# ==============================================================================
# lib/notify.sh — Desktop notifications (notify-send, silently skipped if absent)
# Depends on: terminal.sh (log)
# ==============================================================================

notify_success() {
    log "INFO" "$1${2:+ — $2}"
    command -v notify-send &>/dev/null &&
        notify-send "$1" "${2:-}" 2>/dev/null || true
}

notify_error() {
    log "ERROR" "$1${2:+ — $2}"
    command -v notify-send &>/dev/null &&
        notify-send -u critical "$1" "${2:-}" 2>/dev/null || true
}
