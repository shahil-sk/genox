# ==============================================================================
# lib/terminal.sh — ANSI colours, terminal helpers, logging
# ==============================================================================

if [[ -t 1 ]] && command -v tput &>/dev/null && tput colors &>/dev/null; then
    C_RESET=$(tput sgr0)
    C_BOLD=$(tput bold)
    C_REV=$(tput rev)
    C_BLACK=$(tput setaf 0)
    C_RED=$(tput setaf 1)
    C_GREEN=$(tput setaf 2)
    C_YELLOW=$(tput setaf 3)
    C_BLUE=$(tput setaf 4)
    C_CYAN=$(tput setaf 6)
    C_WHITE=$(tput setaf 7)
    TW=$(tput cols)
    TH=$(tput lines)
else
    C_RESET="" C_BOLD="" C_REV="" C_BLACK="" C_RED=""
    C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN="" C_WHITE=""
    TW=80; TH=24
fi

hide_cursor()  { printf '\033[?25l'; }
show_cursor()  { printf '\033[?25h'; }
clear_screen() { printf '\033[2J\033[H'; }
move_to()      { printf '\033[%d;%dH' "$1" "$2"; }  # row col

# Ensure cursor is restored on exit
trap 'show_cursor; tput rmcup 2>/dev/null || true' EXIT
trap 'show_cursor; exit 130' INT TERM

# ------------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------------
log() {
    local level="$1"; shift
    [[ -n "$log_file" ]] && printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "$log_file"
    $no_tui && printf '[%s] %s\n' "$level" "$*" >&2 || true
}
