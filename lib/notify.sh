# ==============================================================================
# lib/notify.sh — Desktop notifications (notify-send, silently skipped if absent)
# Depends on: terminal.sh (log)
# ==============================================================================

# Absolute path to this library directory
_NOTIFY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Icon path (expects: lib/genox.svg)
_NOTIFY_ICON="$_NOTIFY_DIR/genox.svg"

notify_success() {
    log "INFO" "$1${2:+ — $2}"

    command -v notify-send &>/dev/null &&
        notify-send \
            -a "genox" \
            -i "$_NOTIFY_ICON" \
            "$1" "${2:-}" \
            2>/dev/null || true
}

notify_error() {
    log "ERROR" "$1${2:+ — $2}"

    command -v notify-send &>/dev/null &&
        notify-send \
            -a "genox" \
            -i "$_NOTIFY_ICON" \
            -u critical \
            "$1" "${2:-}" \
            2>/dev/null || true
}