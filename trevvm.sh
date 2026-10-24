#!/usr/bin/env bash
#
# TrevVM control script.
#
#   ./trevvm.sh status
#   ./trevvm.sh logs -f
#   ./trevvm.sh backup
#
# Everything it does is a thin wrapper around Docker, so the container can
# still be managed by hand if you prefer.

set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
CONTAINER="${TREVVM_CONTAINER:-TrevVM}"
IMAGE="${TREVVM_IMAGE:-trevvm}"
PORT="${TREVVM_PORT:-3000}"
SAVE_DIR="${TREVVM_SAVE:-$ROOT/Save}"
BACKUP_DIR="${TREVVM_BACKUP_DIR:-$ROOT/backups}"
ASSUME_YES=0
FOLLOW=0
TAIL_LINES=100

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'
    C_GREEN=$'\033[1;32m'
    C_YELLOW=$'\033[1;33m'
    C_RED=$'\033[1;31m'
    C_BLUE=$'\033[1;34m'
else
    C_RESET=""
    C_GREEN=""
    C_YELLOW=""
    C_RED=""
    C_BLUE=""
fi

log()  { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s ok %s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s warn %s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%serror%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

usage() {
    cat <<EOF
TrevVM control

Usage: ./trevvm.sh <command> [options]

  start                 start the container
  stop                  stop the container
  restart               restart the container
  status                container, health, URL and save path
  url                   print the browser URL
  logs [-f] [--tail N]  show container logs (default: last $TAIL_LINES lines)
  shell                 open a root shell inside the container
  update                pull, rebuild and recreate, keeping save data
  backup [FILE]         archive the save directory
  restore FILE          restore a backup (stops the container first)
  reset                 delete save data and restore the defaults
  config                print the options used for the last build
  doctor                diagnose Docker, KVM, port, disk and save state
  clean                 prune build cache and unused images (asks first)
  apps list             list installable apps
  apps install ID       install an app into the running container
  uninstall [--purge]   remove the container (--purge: image + save data)

Environment: TREVVM_CONTAINER, TREVVM_IMAGE, TREVVM_PORT, TREVVM_SAVE.
EOF
}

have() { command -v "$1" >/dev/null 2>&1; }

require_docker() {
    have docker || die "Docker is not installed."
    docker info >/dev/null 2>&1 || die "The Docker daemon is not reachable. Start Docker, then retry."
}

exists() { docker inspect "$CONTAINER" >/dev/null 2>&1; }

running() {
    [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)" = "true" ]
}

access_url() {
    if [ -n "${CODESPACE_NAME:-}" ] && [ -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ]; then
        printf 'https://%s-%s.%s' "$CODESPACE_NAME" "$PORT" "$GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN"
    else
        printf 'http://localhost:%s' "$PORT"
    fi
}

port_in_use() {
    (exec 3<>"/dev/tcp/127.0.0.1/$PORT") >/dev/null 2>&1
}

confirm() {
    local prompt="$1" reply
    [ "$ASSUME_YES" -eq 1 ] && return 0
    [ -t 0 ] || return 1
    printf '%s [y/N] ' "$prompt"
    read -r reply || return 1
    case "$reply" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

wait_healthy() {
    local timeout="${1:-120}"
    local start=$SECONDS
    while [ $((SECONDS - start)) -lt "$timeout" ]; do
        if [ "$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CONTAINER" 2>/dev/null || true)" = "healthy" ]; then
            return 0
        fi
        running || return 1
        port_in_use && return 0
        sleep 2
    done
    return 1
}

require_container() {
    exists || die "No container named $CONTAINER. Run ./install.sh first."
}

require_save_dir() {
    [ -n "$SAVE_DIR" ] || die "TREVVM_SAVE is empty."
    case "$SAVE_DIR" in
        /|"$HOME"|"$HOME/") die "Refusing to use $SAVE_DIR as the save directory." ;;
    esac
}

cmd_start() {
    require_docker
    require_container
    if running; then
        ok "Already running: $(access_url)"
        return 0
    fi
    log "Starting $CONTAINER"
    docker start "$CONTAINER" >/dev/null
    wait_healthy 120 || warn "Started, but not healthy yet. Check: ./trevvm.sh logs"
    ok "Running: $(access_url)"
}

cmd_stop() {
    require_docker
    require_container
    if ! running; then
        ok "Already stopped"
        return 0
    fi
    docker stop "$CONTAINER" >/dev/null
    ok "Stopped"
}

cmd_restart() {
    require_docker
    require_container
    log "Restarting $CONTAINER"
    docker restart "$CONTAINER" >/dev/null
    wait_healthy 120 || warn "Restarted, but not healthy yet. Check: ./trevvm.sh logs"
    ok "Running: $(access_url)"
}

cmd_status() {
    require_docker
    if ! exists; then
        printf 'TrevVM is not installed (no container named %s).\n' "$CONTAINER"
        return 1
    fi
    local state health image save_path
    state="$(docker inspect -f '{{.State.Status}}' "$CONTAINER")"
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CONTAINER")"
    image="$(docker inspect -f '{{.Config.Image}}' "$CONTAINER")"
    save_path="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/config"}}{{.Source}}{{end}}{{end}}' "$CONTAINER" 2>/dev/null || true)"

    printf 'Container  %s (%s, health: %s)\n' "$CONTAINER" "$state" "$health"
    printf 'Image      %s\n' "$image"
    printf 'URL        %s\n' "$(access_url)"
    [ -n "$save_path" ] && printf 'Save       %s\n' "$save_path"
    printf 'Port       %s\n' "$(docker port "$CONTAINER" 3000/tcp 2>/dev/null || printf 'not published')"
    printf 'Uptime     %s\n' "$(docker inspect -f '{{.State.StartedAt}}' "$CONTAINER")"
}

cmd_logs() {
    require_docker
    require_container
    case "$TAIL_LINES" in
        ''|*[!0-9]*) die "--tail must be a number" ;;
    esac
    local args=(logs "--tail" "$TAIL_LINES")
    [ "$FOLLOW" -eq 1 ] && args+=("--follow")
    docker "${args[@]}" "$CONTAINER"
}

cmd_shell() {
    require_docker
    require_container
    running || die "The container is stopped. Run ./trevvm.sh start."
    [ -t 0 ] || die "An interactive terminal is required for the shell."
    docker exec -it "$CONTAINER" bash
}

cmd_update() {
    [ -x "$ROOT/install.sh" ] || die "install.sh is missing from $ROOT."
    local args=()
    [ "$ASSUME_YES" -eq 1 ] && args+=(-y)
    exec "$ROOT/install.sh" --update "${args[@]}" "$@"
}

cmd_backup() {
    local target="${1:-}"
    require_container
    require_save_dir
    [ -d "$SAVE_DIR" ] || die "Save directory not found: $SAVE_DIR"

    mkdir -p "$BACKUP_DIR"
    if [ -z "$target" ]; then
        target="$BACKUP_DIR/trevvm-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    fi

    log "Backing up $SAVE_DIR"
    tar -czf "$target" -C "$(dirname "$SAVE_DIR")" "$(basename "$SAVE_DIR")"
    ok "Backup written to $target ($(du -h "$target" | awk '{print $1}'))"
}

cmd_restore() {
    local archive="${1:-}"
    [ -n "$archive" ] || die "Usage: ./trevvm.sh restore FILE.tar.gz"
    [ -f "$archive" ] || die "Backup not found: $archive"
    tar -tzf "$archive" >/dev/null 2>&1 || die "$archive is not a valid tar.gz"
    require_save_dir
    if tar -tzf "$archive" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
        die "$archive contains absolute or parent paths; refusing to extract it"
    fi

    if ! confirm "Restore $archive over $SAVE_DIR? The current data is moved aside first."; then
        printf 'Cancelled.\n'
        return 0
    fi

    if exists && running; then
        log "Stopping $CONTAINER"
        docker stop "$CONTAINER" >/dev/null
    fi

    local previous=""
    if [ -d "$SAVE_DIR" ] && [ -n "$(ls -A "$SAVE_DIR" 2>/dev/null || true)" ]; then
        previous="$SAVE_DIR.before-restore-$(date +%Y%m%d-%H%M%S)"
        mv "$SAVE_DIR" "$previous"
        log "Previous data moved to $previous"
    fi

    mkdir -p "$SAVE_DIR"
    tar -xzf "$archive" -C "$(dirname "$SAVE_DIR")"
    ok "Restored $archive"
    if exists; then
        cmd_start
    fi
}

cmd_reset() {
    require_docker
    require_save_dir
    if ! confirm "Delete all data in $SAVE_DIR and restore the defaults?"; then
        printf 'Cancelled.\n'
        return 0
    fi
    if exists && running; then
        docker stop "$CONTAINER" >/dev/null
    fi
    rm -rf "$SAVE_DIR"
    mkdir -p "$SAVE_DIR"
    if [ -d "$ROOT/root/config" ]; then
        cp -Rn "$ROOT/root/config/." "$SAVE_DIR/" 2>/dev/null || true
    fi
    ok "Save data reset"
    if exists; then
        cmd_start
    fi
}

cmd_config() {
    local options="$ROOT/options.json"
    [ -f "$options" ] || die "No options.json in $ROOT (it is written by ./install.sh)."
    if command -v python3 >/dev/null 2>&1; then
        ( cd "$ROOT" && python3 -m json.tool options.json ) 2>/dev/null && return
    elif command -v python >/dev/null 2>&1; then
        ( cd "$ROOT" && python -m json.tool options.json ) 2>/dev/null && return
    fi
    cat "$options"
}

cmd_doctor() {
    local failures=0
    printf 'TrevVM doctor\n-------------\n'

    if have docker; then
        printf '%-14s %s\n' "docker" "$(docker --version 2>/dev/null | cut -d, -f1)"
    else
        printf '%-14s %s\n' "docker" "missing"
        failures=$((failures + 1))
    fi

    if have docker && docker info >/dev/null 2>&1; then
        printf '%-14s %s\n' "daemon" "reachable"
    else
        printf '%-14s %s\n' "daemon" "not reachable"
        failures=$((failures + 1))
    fi

    if exists; then
        printf '%-14s %s\n' "container" "$(docker inspect -f '{{.State.Status}}' "$CONTAINER")"
    else
        printf '%-14s %s\n' "container" "missing"
    fi

    if docker image inspect "$IMAGE" >/dev/null 2>&1; then
        printf '%-14s %s\n' "image" "$IMAGE"
    else
        printf '%-14s %s\n' "image" "missing"
    fi

    if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        printf '%-14s %s\n' "kvm" "available"
    else
        printf '%-14s %s\n' "kvm" "not available (the VM runs in software mode)"
    fi

    if port_in_use; then
        printf '%-14s %s\n' "port $PORT" "in use"
    else
        printf '%-14s %s\n' "port $PORT" "free"
    fi

    if [ -d "$SAVE_DIR" ]; then
        printf '%-14s %s\n' "save" "$SAVE_DIR (exists)"
    else
        printf '%-14s %s\n' "save" "$SAVE_DIR (missing)"
    fi
    printf '%-14s %s\n' "disk" "$(df -Pk "$ROOT" 2>/dev/null | awk 'NR==2 {printf "%.1f GB free", $4/1048576}')"
    if have docker-compose || docker compose version >/dev/null 2>&1; then
        printf '%-14s %s\n' "compose" "available"
    else
        printf '%-14s %s\n' "compose" "not installed (optional)"
    fi

    if [ "$failures" -gt 0 ]; then
        printf '\n%s%d check(s) failed.%s\n' "$C_RED" "$failures" "$C_RESET"
        return 1
    fi
    printf '\nAll required checks passed.\n'
}

cmd_clean() {
    require_docker
    log "Current disk usage"
    docker system df || true
    if ! confirm "Prune the build cache and unused images?"; then
        printf 'Cancelled.\n'
        return 0
    fi
    docker builder prune -f
    docker image prune -f
    ok "Cleanup finished"
}

cmd_apps() {
    local action="${1:-list}" id="${2:-}" py=""
    case "$action" in
        list)
            [ -f "$ROOT/apps.json" ] || die "apps.json is missing from $ROOT."
            for candidate in python3 python; do
                if have "$candidate"; then
                    py="$candidate"
                    break
                fi
            done
            [ -n "$py" ] || die "Python 3 is required to read apps.json."
            (
                cd "$ROOT" || exit 1
                "$py" - apps.json <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
for group in data["groups"]:
    print(group["title"] + ":")
    for package in group["packages"]:
        marker = " (default)" if package.get("default") else ""
        print(f"  {package['id']:<16} {package['label']}{marker}")
PY
            )
            ;;
        install)
            [ -n "$id" ] || die "Usage: ./trevvm.sh apps install ID"
            require_docker
            require_container
            running || die "The container is stopped. Run ./trevvm.sh start."
            docker exec "$CONTAINER" bash /opt/trevvm/install-app.sh --id "$id"
            ;;
        *)
            die "unknown apps action: $action (use: list, install)"
            ;;
    esac
}

cmd_uninstall() {
    [ -x "$ROOT/install.sh" ] || die "install.sh is missing from $ROOT."
    TREVVM_SAVE="$SAVE_DIR" exec "$ROOT/install.sh" --uninstall "$@"
}

parse_common() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -y|--yes) ASSUME_YES=1; shift ;;
            -f|--follow) FOLLOW=1; shift ;;
            --tail) [ $# -ge 2 ] || die "--tail needs a number"; TAIL_LINES="$2"; shift 2 ;;
            --tail=*) TAIL_LINES="${1#*=}"; shift ;;
            --purge) PURGE=1; shift ;;
            *) break ;;
        esac
    done
}

PURGE=0
command="${1:-}"
[ $# -gt 0 ] && shift
parse_common "$@"

case "$command" in
    ""|-h|--help|help) usage ;;
    start) cmd_start ;;
    stop) cmd_stop ;;
    restart) cmd_restart ;;
    status) cmd_status ;;
    url) access_url; printf '\n' ;;
    logs) cmd_logs ;;
    shell) cmd_shell ;;
    update) cmd_update "$@" ;;
    backup) cmd_backup "${1:-}" ;;
    restore) cmd_restore "${1:-}" ;;
    reset) cmd_reset ;;
    config) cmd_config ;;
    doctor) cmd_doctor ;;
    clean) cmd_clean ;;
    apps) cmd_apps "$@" ;;
    uninstall)
        args=()
        [ "$ASSUME_YES" -eq 1 ] && args+=(-y)
        [ "$PURGE" -eq 1 ] && args+=(--purge)
        cmd_uninstall "${args[@]}"
        ;;
    *) die "unknown command: $command (try ./trevvm.sh --help)" ;;
esac
