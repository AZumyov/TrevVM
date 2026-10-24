#!/usr/bin/env bash
#
# Install one or more apps from the TrevVM catalog.
#
# Build time:  bash install-app.sh                (reads /options.json packages)
# Runtime:     bash install-app.sh --id wine
# Inspection:  bash install-app.sh --list

set -uo pipefail

APPS_DIR=/opt/trevvm/apps
MANIFEST=/opt/trevvm/apps.json
OPTIONS_FILE=/options.json
LOG=/config/trevvm-apps.log
STRICT="${TREVVM_STRICT_APPS:-0}"

if ! touch "$LOG" 2>/dev/null; then
    LOG=/tmp/trevvm-apps.log
    touch "$LOG"
fi

log()  { printf '[trevvm-apps] %s\n' "$*"; }
warn() { printf '[trevvm-apps] warning: %s\n' "$*" >&2; }

require_manifest() {
    if [ ! -r "$MANIFEST" ]; then
        printf 'error: %s is missing\n' "$MANIFEST" >&2
        exit 1
    fi
}

script_for() {
    jq -r --arg id "$1" '.groups[].packages[] | select(.id == $id) | .script' "$MANIFEST" 2>/dev/null | head -n 1
}

legacy_script_for() {
    local key="$1" index="$2"
    jq -r --arg key "$key" --argjson index "$index" \
        '.groups[] | select(.key == $key) | .packages[$index].script // empty' "$MANIFEST" 2>/dev/null
}

install_one() {
    local id="$1" script rc=0
    script="$(script_for "$id")"
    if [ -z "$script" ] || [ "$script" = "null" ]; then
        warn "unknown package: $id"
        return 2
    fi
    if [ ! -f "$APPS_DIR/$script" ]; then
        warn "missing script: $APPS_DIR/$script"
        return 1
    fi
    log "installing $id"
    if bash "$APPS_DIR/$script" >>"$LOG" 2>&1; then
        log "installed $id"
        return 0
    fi
    rc=$?
    warn "$id failed (exit $rc); last lines of $LOG:"
    tail -n 15 "$LOG" >&2 || true
    return "$rc"
}

collect_build_selection() {
    if [ ! -r "$OPTIONS_FILE" ]; then
        warn "$OPTIONS_FILE is missing; nothing to install"
        return 0
    fi

    if jq -e '.packages | type == "array"' "$OPTIONS_FILE" >/dev/null 2>&1; then
        jq -r '.packages[]' "$OPTIONS_FILE"
        return 0
    fi

    # Legacy options.json stored integer indexes per group.
    local key index
    for key in defaultapps programming apps; do
        while IFS= read -r index; do
            [ -n "$index" ] || continue
            legacy_script_for "$key" "$index"
        done < <(jq -r --arg key "$key" '.[$key] // [] | .[]' "$OPTIONS_FILE" 2>/dev/null)
    done | sed 's/\.sh$//'
}

list_catalog() {
    jq -r '.groups[] | .title as $title | .packages[] | "\(.id)\t\(.label)"' "$MANIFEST"
}

main() {
    require_manifest

    local mode=build id=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --id) mode=one; [ $# -ge 2 ] || { printf 'error: --id needs a value\n' >&2; exit 2; }; id="$2"; shift 2 ;;
            --id=*) mode=one; id="${1#*=}"; shift ;;
            --list) list_catalog; return 0 ;;
            *) printf 'error: unknown option: %s\n' "$1" >&2; exit 2 ;;
        esac
    done

    if [ "$mode" = one ]; then
        install_one "$id"
        return $?
    fi

    local selected=() id_value seen=" "
    while IFS= read -r id_value; do
        [ -n "$id_value" ] || continue
        id_value="${id_value%.sh}"
        case "$seen" in *" $id_value "*) continue ;; esac
        seen="$seen$id_value "
        selected+=("$id_value")
    done < <(collect_build_selection)

    if [ "${#selected[@]}" -eq 0 ]; then
        log "no optional apps selected"
        return 0
    fi

    log "selected apps: ${selected[*]}"
    local failed=0 installed=0
    for id_value in "${selected[@]}"; do
        if install_one "$id_value"; then
            installed=$((installed + 1))
        else
            failed=$((failed + 1))
        fi
    done

    log "summary: $installed installed, $failed failed"
    if [ "$failed" -gt 0 ] && [ "$STRICT" = "1" ]; then
        return 1
    fi
    return 0
}

main "$@"
