#!/usr/bin/env bash
#
# TrevVM installer.
#
# Works in two situations:
#   * from a checkout:  ./install.sh
#   * standalone:       bash install.sh   (clones TREVVM_REPO into ./TrevVM)
#
# It is safe to re-run: the save directory is preserved and an existing
# container is reused unless --reinstall or --update is passed.

set -Eeuo pipefail

VERSION="3.1.0"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
SELF="${BASH_SOURCE[0]:-$0}"

REPO_SLUG="${TREVVM_REPO:-TrevorTesch/TrevVM}"
BRANCH="${TREVVM_BRANCH:-main}"
CONTAINER="${TREVVM_CONTAINER:-TrevVM}"
IMAGE="${TREVVM_IMAGE:-trevvm}"
PORT="${TREVVM_PORT:-3000}"
SHM="${TREVVM_SHM:-2gb}"
KVM_MODE="${TREVVM_KVM:-auto}"
WORKDIR="${TREVVM_DIR:-}"
SAVE_DIR="${TREVVM_SAVE:-}"
TZ_VALUE="${TREVVM_TZ:-}"

MODE="install"
ASSUME_YES=0
NO_CACHE=0
DRY_RUN=0
PURGE=0
FORCE=0

REPO_DIR=""
OPTIONS_FILE=""
LOG_FILE=""
PYTHON=""
PY=""
USE_KVM=0

PREREQ_ERRORS=()
PREREQ_WARNINGS=()

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'
    C_BLUE=$'\033[1;34m'
    C_GREEN=$'\033[1;32m'
    C_YELLOW=$'\033[1;33m'
    C_RED=$'\033[1;31m'
    C_DIM=$'\033[2m'
else
    C_RESET=""
    C_BLUE=""
    C_GREEN=""
    C_YELLOW=""
    C_RED=""
    C_DIM=""
fi

log()  { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s ok %s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s warn %s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%serror%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

on_error() {
    local status=$?
    printf '\n%serror%s installation stopped (exit %s)\n' "$C_RED" "$C_RESET" "$status" >&2
    if [ -n "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
        printf '%s--- last 30 log lines (%s) ---%s\n' "$C_DIM" "$LOG_FILE" "$C_RESET" >&2
        tail -n 30 "$LOG_FILE" >&2 || true
    fi
    printf 'See docs/TROUBLESHOOTING.md, or run "%s --status".\n' "$SELF" >&2
    exit "$status"
}
trap on_error ERR

usage() {
    cat <<EOF
TrevVM installer v$VERSION

Usage:
  ./install.sh [options]
  bash install.sh [options]          # standalone; clones the repository

Install:
  -y, --yes              use the default selection (no TUI)
      --de ID            desktop: cinnamon, xfce, kde, i3, gnome, lxqt
      --apps LIST        comma separated package ids (see installer.py --list)
      --all              select every package
      --none             select no optional packages
      --port PORT|auto   host port for the web desktop (default: $PORT)
      --kvm              force KVM acceleration
      --no-kvm           disable KVM acceleration
      --save PATH        config directory (default: <repo>/Save)
      --dir PATH         where to clone when run standalone
      --repo OWNER/NAME  repository to clone (default: $REPO_SLUG)
      --branch NAME      branch to clone (default: $BRANCH)
      --no-cache         rebuild the image without Docker's layer cache

Maintenance:
      --update           pull the latest source, rebuild, keep the save data
      --reinstall        rebuild and recreate the container
      --status           print container, URL and health information
      --uninstall        remove the container (--purge also removes image+save)
      --purge            with --uninstall: delete the image and save directory

Other:
      --dry-run          check the environment and print what would happen
  -h, --help             show this help
  -V, --version          print the version
EOF
}

banner() {
    printf '%s\n' "TrevVM $VERSION - Linux desktop in a container"
    printf '%s\n\n' "------------------------------------------------"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -V|--version) printf '%s\n' "$VERSION"; exit 0 ;;
            -y|--yes|--non-interactive) ASSUME_YES=1; shift ;;
            --de) [ $# -ge 2 ] || die "--de needs a value"; DE_CHOICE="$2"; shift 2 ;;
            --de=*) DE_CHOICE="${1#*=}"; shift ;;
            --apps) [ $# -ge 2 ] || die "--apps needs a value"; APPS_CHOICE="$2"; shift 2 ;;
            --apps=*) APPS_CHOICE="${1#*=}"; shift ;;
            --all) SELECT_ALL=1; shift ;;
            --none) SELECT_NONE=1; shift ;;
            --port) [ $# -ge 2 ] || die "--port needs a value"; PORT="$2"; shift 2 ;;
            --port=*) PORT="${1#*=}"; shift ;;
            --kvm) KVM_MODE="yes"; shift ;;
            --no-kvm) KVM_MODE="no"; shift ;;
            --save) [ $# -ge 2 ] || die "--save needs a value"; SAVE_DIR="$2"; shift 2 ;;
            --save=*) SAVE_DIR="${1#*=}"; shift ;;
            --dir) [ $# -ge 2 ] || die "--dir needs a value"; WORKDIR="$2"; shift 2 ;;
            --dir=*) WORKDIR="${1#*=}"; shift ;;
            --repo) [ $# -ge 2 ] || die "--repo needs a value"; REPO_SLUG="$2"; shift 2 ;;
            --repo=*) REPO_SLUG="${1#*=}"; shift ;;
            --branch) [ $# -ge 2 ] || die "--branch needs a value"; BRANCH="$2"; shift 2 ;;
            --branch=*) BRANCH="${1#*=}"; shift ;;
            --no-cache) NO_CACHE=1; FORCE=1; shift ;;
            --update) MODE="update"; FORCE=1; shift ;;
            --reinstall) MODE="reinstall"; FORCE=1; shift ;;
            --status) MODE="status"; shift ;;
            --uninstall) MODE="uninstall"; shift ;;
            --purge) PURGE=1; shift ;;
            --dry-run) DRY_RUN=1; shift ;;
            *) die "unknown option: $1 (try --help)" ;;
        esac
    done

    if [ "$PORT" = "auto" ]; then
        local candidate
        for candidate in $(seq 3000 3099); do
            if ! port_in_use "$candidate"; then
                PORT="$candidate"
                break
            fi
        done
        [ "$PORT" != "auto" ] || die "no free port in 3000-3099"
    fi

    case "$PORT" in
        ''|*[!0-9]*) die "--port must be a number or 'auto'" ;;
    esac
    if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        die "--port must be between 1 and 65535"
    fi
    if [ "$PURGE" -eq 1 ] && [ "$MODE" != "uninstall" ]; then
        die "--purge only makes sense together with --uninstall"
    fi
    case "$KVM_MODE" in
        auto|yes|no) ;;
        *) die "--kvm mode must be auto, yes or no" ;;
    esac
}

DE_CHOICE=""
APPS_CHOICE=""
SELECT_ALL=0
SELECT_NONE=0

setup_logging() {
    if [ -n "${TREVVM_LOG:-}" ]; then
        LOG_FILE="$TREVVM_LOG"
    elif [ -w "$PWD" ]; then
        LOG_FILE="$PWD/trevvm-install.log"
    fi
    if [ "$DRY_RUN" -eq 0 ] && [ -n "$LOG_FILE" ] && command -v tee >/dev/null 2>&1; then
        : >"$LOG_FILE"
        exec > >(tee -a "$LOG_FILE") 2>&1
    fi
}

# ---------------------------------------------------------------------------
# Environment checks
# ---------------------------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

port_in_use() {
    local port="$1"
    (exec 3<>"/dev/tcp/127.0.0.1/$port") >/dev/null 2>&1
}

container_exists() {
    docker inspect "$CONTAINER" >/dev/null 2>&1
}

container_running() {
    [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)" = "true" ]
}

kvm_available() {
    [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]
}

detect_tz() {
    if [ -n "$TZ_VALUE" ]; then
        printf '%s' "$TZ_VALUE"
        return
    fi
    if [ -f /etc/timezone ]; then
        local value
        value="$(head -n 1 /etc/timezone 2>/dev/null || true)"
        if [ -n "$value" ]; then
            printf '%s' "$value"
            return
        fi
    fi
    if [ -L /etc/localtime ]; then
        local value
        value="$(readlink /etc/localtime 2>/dev/null | sed 's#.*/zoneinfo/##' || true)"
        if [ -n "$value" ]; then
            printf '%s' "$value"
            return
        fi
    fi
    printf 'Etc/UTC'
}

check_prereqs() {
    if ! have docker; then
        PREREQ_ERRORS+=("Docker is not installed. See https://docs.docker.com/engine/install/")
    elif ! docker info >/dev/null 2>&1; then
        PREREQ_ERRORS+=("The Docker daemon is not reachable. Start Docker, then retry.")
    fi

    if ! have curl && ! have wget; then
        PREREQ_WARNINGS+=("Neither curl nor wget was found; some app installs may fail.")
    fi

    if [ -r /proc/meminfo ]; then
        local mem_mb
        mem_mb="$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)"
        if [ "${mem_mb:-0}" -lt 3072 ]; then
            PREREQ_WARNINGS+=("Only ${mem_mb} MB of RAM detected; the desktop may be slow (4 GB+ recommended).")
        fi
    fi

    local free_kb
    free_kb="$(df -Pk "$PWD" 2>/dev/null | awk 'NR==2 {print $4}' || true)"
    if [ -n "${free_kb:-}" ] && [ "$free_kb" -lt 5242880 ]; then
        PREREQ_WARNINGS+=("Less than 5 GB of free disk space in $PWD.")
    fi

    if [ "$MODE" = "install" ] && [ "$DRY_RUN" -eq 0 ] && [ "$FORCE" -eq 0 ]; then
        if container_running; then
            ok "TrevVM is already running."
            print_access_short
            exit 0
        fi
        if container_exists; then
            ok "Container $CONTAINER exists but is stopped."
            log "Starting it instead of reinstalling. Use --reinstall to rebuild."
            docker start "$CONTAINER" >/dev/null
            wait_healthy 120 || true
            print_access_short
            exit 0
        fi
    fi

    if [ "$MODE" != "status" ] && [ "$MODE" != "uninstall" ]; then
        if port_in_use "$PORT"; then
            if container_exists; then
                PREREQ_WARNINGS+=("Port $PORT is already used by the existing $CONTAINER container.")
            else
                PREREQ_ERRORS+=("Port $PORT is already in use. Pick another with --port <number>.")
            fi
        fi
    fi

    local message
    for message in "${PREREQ_ERRORS[@]:-}"; do
        [ -n "$message" ] || continue
        if [ "$DRY_RUN" -eq 1 ]; then
            warn "$message"
        else
            printf '%serror%s %s\n' "$C_RED" "$C_RESET" "$message" >&2
        fi
    done
    for message in "${PREREQ_WARNINGS[@]:-}"; do
        [ -n "$message" ] || continue
        warn "$message"
    done

    if [ "${#PREREQ_ERRORS[@]}" -gt 0 ] && [ "$DRY_RUN" -eq 0 ]; then
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Source and Python
# ---------------------------------------------------------------------------

pull_source() {
    local directory="$1"
    if [ "$MODE" != "update" ]; then
        return 0
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        log "Would pull the latest changes in $directory"
        return 0
    fi
    if [ -d "$directory/.git" ]; then
        git -C "$directory" pull --ff-only
    else
        warn "$directory is not a git checkout; skipping git pull"
    fi
}

resolve_source() {
    if [ -f "$SCRIPT_DIR/installer.py" ] && [ -f "$SCRIPT_DIR/Dockerfile" ]; then
        REPO_DIR="$SCRIPT_DIR"
        log "Using checkout: $REPO_DIR"
        pull_source "$REPO_DIR"
        return
    fi

    REPO_DIR="${WORKDIR:-$PWD/TrevVM}"

    if [ "$DRY_RUN" -eq 1 ] && [ ! -d "$REPO_DIR" ]; then
        log "Would clone https://github.com/$REPO_SLUG.git ($BRANCH) into $REPO_DIR"
        return
    fi

    have git || die "git is required to download TrevVM (or run install.sh from a checkout)."

    if [ -d "$REPO_DIR/.git" ]; then
        log "Using existing checkout: $REPO_DIR"
        pull_source "$REPO_DIR"
    elif [ -e "$REPO_DIR" ]; then
        die "$REPO_DIR exists but is not a git checkout. Remove it or pass --dir."
    else
        log "Cloning https://github.com/$REPO_SLUG.git ($BRANCH)"
        git clone --depth 1 --branch "$BRANCH" "https://github.com/$REPO_SLUG.git" "$REPO_DIR"
    fi

    [ -f "$REPO_DIR/installer.py" ] || die "$REPO_DIR does not look like a TrevVM checkout."
}

find_python() {
    local candidate
    for candidate in python3 python; do
        if have "$candidate"; then
            PYTHON="$candidate"
            return
        fi
    done
    die "Python 3 is required. Install python3 and python3-venv, then retry."
}

setup_python() {
    find_python
    local venv="$REPO_DIR/.venv"

    if [ ! -x "$venv/bin/python" ]; then
        log "Creating a virtual environment in .venv"
        if ! "$PYTHON" -m venv "$venv" >/dev/null 2>&1; then
            warn "python3 -m venv failed; trying to install python3-venv"
            if have sudo && [ "$(id -u)" -ne 0 ]; then
                sudo apt-get update -qq && sudo apt-get install -y -qq python3-venv || true
            fi
            if ! "$PYTHON" -m venv "$venv" >/dev/null 2>&1; then
                warn "Falling back to the system Python (dependencies may conflict)."
                venv=""
            fi
        fi
    fi

    if [ -n "$venv" ] && [ -x "$venv/bin/python" ]; then
        PY="$venv/bin/python"
        "$PY" -m pip install --quiet --disable-pip-version-check --upgrade pip >/dev/null 2>&1 || true
    else
        PY="$PYTHON"
    fi

    log "Installing Python dependencies"
    if ! "$PY" -m pip install --quiet --disable-pip-version-check -r "$REPO_DIR/requirements.txt"; then
        die "Could not install Python dependencies. Install python3-venv and retry."
    fi
}

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

installer_args() {
    local args=(--output "$OPTIONS_FILE")
    case "$KVM_MODE" in
        yes) args+=(--kvm) ;;
        no) args+=(--no-kvm) ;;
        auto)
            if [ "$USE_KVM" -eq 1 ]; then args+=(--kvm); else args+=(--no-kvm); fi
            ;;
    esac
    if [ -n "$DE_CHOICE" ]; then args+=(--de "$DE_CHOICE"); fi
    if [ -n "$APPS_CHOICE" ]; then args+=(--apps "$APPS_CHOICE"); fi
    if [ "$SELECT_ALL" -eq 1 ]; then args+=(--all); fi
    if [ "$SELECT_NONE" -eq 1 ]; then args+=(--none); fi
    printf '%s\n' "${args[@]}"
}

write_options() {
    OPTIONS_FILE="$REPO_DIR/options.json"

    if [ "$MODE" = "update" ] && [ -s "$OPTIONS_FILE" ]; then
        log "Keeping existing options.json"
        return
    fi

    local args=()
    while IFS= read -r line; do args+=("$line"); done < <(installer_args)

    if [ "$ASSUME_YES" -eq 1 ] || [ ! -t 0 ]; then
        args+=(--defaults)
        log "Writing the default selection"
        "$PY" "$REPO_DIR/installer.py" "${args[@]}"
    else
        log "Starting the installer UI"
        local status=0
        "$PY" "$REPO_DIR/installer.py" "${args[@]}" || status=$?
        if [ "$status" -eq 130 ]; then
            printf '\nCancelled.\n'
            exit 130
        fi
        [ "$status" -eq 0 ] || exit "$status"
    fi

    [ -s "$OPTIONS_FILE" ] || die "The installer did not write options.json."
    "$PY" - "$OPTIONS_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
if not data.get("DE"):
    raise SystemExit("options.json has no DE")
if not isinstance(data.get("packages"), list):
    raise SystemExit("options.json has no packages list")
PY
}

read_runtime_options() {
    local kvm="false"
    kvm="$("$PY" -c 'import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    print("true" if data.get("enablekvm", False) else "false")
except Exception:
    print("false")' "$OPTIONS_FILE" 2>/dev/null || printf 'false')"
    if [ "$kvm" = "true" ]; then
        if kvm_available; then
            USE_KVM=1
        else
            warn "options.json requests KVM but /dev/kvm is not available; continuing without it."
            USE_KVM=0
        fi
    else
        USE_KVM=0
    fi
}

# ---------------------------------------------------------------------------
# Docker
# ---------------------------------------------------------------------------

build_image() {
    local args=(build --pull --tag "$IMAGE" --file "$REPO_DIR/Dockerfile"
        --build-arg "VERSION=$VERSION"
        --build-arg "BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)")
    if [ -s "$OPTIONS_FILE" ]; then
        local options_json
        options_json="$("$PY" -c 'import json, sys
print(json.dumps(json.load(open(sys.argv[1], encoding="utf-8")), separators=(",", ":")))' "$OPTIONS_FILE")"
        args+=(--build-arg "OPTIONS_JSON=$options_json")
    fi
    if [ "$NO_CACHE" -eq 1 ]; then
        args+=(--no-cache)
    fi
    args+=("$REPO_DIR")

    log "Building the image (first build can take 10-30 minutes)"
    if ! docker "${args[@]}"; then
        return 1
    fi
    ok "Image $IMAGE built"
}

prepare_save() {
    if [ -z "$SAVE_DIR" ]; then
        SAVE_DIR="$REPO_DIR/Save"
    fi
    mkdir -p "$SAVE_DIR"
    SAVE_DIR="$(cd "$SAVE_DIR" && pwd -P)"
    if [ -d "$REPO_DIR/root/config" ]; then
        cp -Rn "$REPO_DIR/root/config/." "$SAVE_DIR/" 2>/dev/null || true
    fi
}

run_container() {
    if container_exists; then
        log "Replacing the existing container (save data is kept)"
        docker rm -f "$CONTAINER" >/dev/null
    fi

    local args=(run --detach
        --name "$CONTAINER"
        --restart unless-stopped
        --env "PUID=$(id -u)"
        --env "PGID=$(id -g)"
        --env "TZ=$(detect_tz)"
        --env "SUBFOLDER=/"
        --env "TITLE=TrevVM"
        --publish "${PORT}:3000"
        --shm-size "$SHM"
        --security-opt seccomp=unconfined
        --volume "${SAVE_DIR}:/config")

    if [ -n "${TREVVM_USER:-}" ]; then
        args+=(--env "CUSTOM_USER=${TREVVM_USER}")
    fi
    if [ -n "${TREVVM_PASSWORD:-}" ]; then
        args+=(--env "PASSWORD=${TREVVM_PASSWORD}")
    fi

    if [ "$USE_KVM" -eq 1 ]; then
        args+=(--device /dev/kvm)
    fi

    log "Starting the container"
    docker "${args[@]}" "$IMAGE" >/dev/null
}

wait_healthy() {
    local timeout="${1:-180}"
    local start=$SECONDS
    local status=""

    log "Waiting for the desktop to start (up to ${timeout}s)"
    while [ $((SECONDS - start)) -lt "$timeout" ]; do
        status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CONTAINER" 2>/dev/null || true)"
        case "$status" in
            healthy) ok "Desktop is healthy"; return 0 ;;
            unhealthy) break ;;
        esac
        if ! container_running; then break; fi
        if port_in_use "$PORT"; then ok "Desktop is listening on port $PORT"; return 0; fi
        sleep 3
    done

    warn "The desktop did not become healthy in time."
    docker logs --tail 40 "$CONTAINER" 2>&1 || true
    return 1
}

container_port() {
    docker inspect -f '{{range $p, $conf := .NetworkSettings.Ports}}{{if eq $p "3000/tcp"}}{{(index $conf 0).HostPort}}{{end}}{{end}}' "$CONTAINER" 2>/dev/null || true
}

effective_port() {
    local mapped=""
    if container_exists; then
        mapped="$(container_port)"
    fi
    printf '%s' "${mapped:-$PORT}"
}

access_url() {
    local port
    port="$(effective_port)"
    if [ -n "${CODESPACE_NAME:-}" ] && [ -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ]; then
        printf 'https://%s-%s.%s' "$CODESPACE_NAME" "$port" "$GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN"
    else
        printf 'http://localhost:%s' "$port"
    fi
}

print_access() {
    local url
    url="$(access_url)"
    printf '\n%sTrevVM is ready%s\n' "$C_GREEN" "$C_RESET"
    printf '  URL      %s\n' "$url"
    printf '  Port     %s (open the Ports tab if the preview is private)\n' "$(effective_port)"
    printf '  Logs     docker logs -f %s\n' "$CONTAINER"
    printf '  Stop     %s\n' "$(manage_hint stop)"
    printf '  Update   %s\n' "$(manage_hint update)"
    printf '  Apps     %s\n' "$(manage_hint apps)"
    if [ -n "$SAVE_DIR" ]; then
        printf '  Save     %s\n' "$SAVE_DIR"
    fi
    printf '\n'
}

print_access_short() {
    printf '  URL   %s\n' "$(access_url)"
    printf '  Stop  %s\n' "$(manage_hint stop)"
}

manage_hint() {
    if [ -x "$SCRIPT_DIR/trevvm.sh" ]; then
        printf '%s %s' "$SCRIPT_DIR/trevvm.sh" "$1"
        return
    fi
    case "$1" in
        stop) printf 'docker stop %s' "$CONTAINER" ;;
        update) printf '%s --update' "$SELF" ;;
        apps) printf 'docker exec %s bash /opt/trevvm/install-app.sh --list' "$CONTAINER" ;;
        *) printf '%s --status' "$SELF" ;;
    esac
}

print_status() {
    if ! have docker; then
        die "Docker is not installed."
    fi
    if ! container_exists; then
        printf 'TrevVM is not installed (no container named %s).\n' "$CONTAINER"
        exit 1
    fi
    local state health image
    state="$(docker inspect -f '{{.State.Status}}' "$CONTAINER")"
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CONTAINER")"
    image="$(docker inspect -f '{{.Config.Image}}' "$CONTAINER")"
    printf 'Container  %s (%s, health: %s)\n' "$CONTAINER" "$state" "$health"
    printf 'Image      %s\n' "$image"
    printf 'URL        %s\n' "$(access_url)"
    local save_path
    save_path="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/config"}}{{.Source}}{{end}}{{end}}' "$CONTAINER" 2>/dev/null || true)"
    if [ -n "$save_path" ]; then
        printf 'Save       %s\n' "$save_path"
    fi
}

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------

do_uninstall() {
    if ! have docker; then
        die "Docker is not installed."
    fi
    local save_path=""

    if container_exists; then
        save_path="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/config"}}{{.Source}}{{end}}{{end}}' "$CONTAINER" 2>/dev/null || true)"
        if ! confirm "Remove the TrevVM container?"; then
            printf 'Cancelled.\n'
            return 0
        fi
        docker rm -f "$CONTAINER" >/dev/null
        ok "Container removed"
    else
        printf 'No container named %s.\n' "$CONTAINER"
    fi

    if [ "$PURGE" -eq 1 ]; then
        [ -n "$save_path" ] || save_path="${SAVE_DIR:-}"
        if [ -z "$save_path" ]; then
            warn "Could not determine the save directory. Pass --save PATH to purge it."
            return 0
        fi
        if confirm "Also delete the image and all save data in $save_path?"; then
            docker image rm "$IMAGE" >/dev/null 2>&1 || true
            rm -rf "$save_path"
            ok "Image and save data removed"
        fi
    fi
}

confirm() {
    local prompt="$1" reply
    if [ "$ASSUME_YES" -eq 1 ]; then
        return 0
    fi
    if [ ! -t 0 ]; then
        return 1
    fi
    printf '%s [y/N] ' "$prompt"
    read -r reply || return 1
    case "$reply" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

print_plan() {
    printf '\n%sDry run%s - nothing was changed.\n' "$C_YELLOW" "$C_RESET"
    printf '  repo        %s\n' "${REPO_DIR:-$PWD/TrevVM}"
    printf '  image       %s\n' "$IMAGE"
    printf '  container   %s\n' "$CONTAINER"
    printf '  port        %s\n' "$PORT"
    printf '  save        %s\n' "${SAVE_DIR:-${REPO_DIR:-$PWD/TrevVM}/Save}"
    printf '  kvm         %s\n' "$( [ "$USE_KVM" -eq 1 ] && printf enabled || printf disabled )"
    printf '  timezone    %s\n' "$(detect_tz)"
    printf '  options     %s\n' "${REPO_DIR:-$PWD/TrevVM}/options.json"
    printf '\nRun without --dry-run to install.\n'
}

main() {
    parse_args "$@"
    setup_logging
    banner

    check_prereqs

    if [ "$MODE" = "status" ]; then
        print_status
        return 0
    fi

    if [ "$MODE" = "uninstall" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            printf '\nDry run - would remove container %s' "$CONTAINER"
            if [ "$PURGE" -eq 1 ]; then
                printf ' and its image/save data'
            fi
            printf '.\n'
            return 0
        fi
        do_uninstall
        return 0
    fi

    resolve_source

    if [ "$DRY_RUN" -eq 1 ]; then
        if [ "$KVM_MODE" = "yes" ]; then USE_KVM=1
        elif [ "$KVM_MODE" = "no" ]; then USE_KVM=0
        elif kvm_available; then USE_KVM=1
        fi
        print_plan
        return 0
    fi

    setup_python

    write_options
    read_runtime_options

    log "Preparing save data"
    prepare_save

    if ! container_exists || [ "$FORCE" -eq 1 ]; then
        build_image
    fi

    run_container
    if ! wait_healthy 180; then
        die "The container started but did not become ready. Check: docker logs $CONTAINER"
    fi
    print_access
}

main "$@"
