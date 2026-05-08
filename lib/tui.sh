# ==============================================================================
# lib/tui.sh — Pure-bash TUI primitives
# Depends on: terminal.sh (colours, cursor helpers)
# ==============================================================================

# ------------------------------------------------------------------------------
# tui_box ROW COL WIDTH HEIGHT TITLE
# ------------------------------------------------------------------------------
tui_box() {
    local row=$1 col=$2 w=$3 h=$4 title="${5:-}"
    local inner=$(( w - 2 ))
    local hline
    hline=$(printf '─%.0s' $(seq 1 "$inner"))

    hide_cursor
    move_to "$row" "$col"
    printf '%s┌%s┐%s' "$C_BOLD$C_CYAN" "$hline" "$C_RESET"

    if [[ -n "$title" ]]; then
        local tlen=${#title}
        local tpos=$(( col + (w - tlen) / 2 ))
        move_to "$row" "$tpos"
        printf '%s %s %s' "$C_BOLD$C_WHITE" "$title" "$C_RESET"
    fi

    local r
    for (( r=1; r<h-1; r++ )); do
        move_to $(( row + r )) "$col"
        printf '%s│%*s│%s' "$C_BOLD$C_CYAN" "$inner" "" "$C_RESET"
    done

    move_to $(( row + h - 1 )) "$col"
    printf '%s└%s┘%s' "$C_BOLD$C_CYAN" "$hline" "$C_RESET"
}

# ------------------------------------------------------------------------------
# tui_menu TITLE PROMPT ITEM... -> sets MENU_RESULT (1-based)
# Returns 0 on select, 1 on cancel/back
# ------------------------------------------------------------------------------
tui_menu() {
    local title="$1" prompt="$2"
    shift 2
    local -a items=("$@")
    local count=${#items[@]}

    local bw=$TW
    (( bw < 60 )) && bw=60
    local bh=$(( count + 8 ))
    (( bh > TH - 2 )) && bh=$(( TH - 2 ))
    local br=1
    local bc=1

    local selected=0

    tput smcup 2>/dev/null || clear_screen

    while true; do
        clear_screen
        tui_box "$br" "$bc" "$bw" "$bh" "$title"

        move_to $(( br + 2 )) $(( bc + 2 ))
        printf '%s%s%s' "$C_YELLOW" "$prompt" "$C_RESET"

        local i
        for (( i=0; i<count; i++ )); do
            move_to $(( br + 4 + i )) $(( bc + 2 ))
            if (( i == selected )); then
                printf '%s▶ %s%s' "$C_GREEN$C_BOLD" "${items[$i]}" "$C_RESET"
            else
                printf '%s  %s%s' "$C_WHITE" "${items[$i]}" "$C_RESET"
            fi
        done

        move_to $(( br + bh - 2 )) $(( bc + 2 ))
        printf '%s↑↓ navigate  Enter select  Q back%s' "$C_YELLOW" "$C_RESET"

        local key
        IFS= read -rsn1 key 2>/dev/null || true
        if [[ $key == $'\033' ]]; then
            read -rsn2 -t 0.1 key 2>/dev/null || true
            case "$key" in
                '[A') (( selected > 0 ))           && (( selected-- )) || true ;;
                '[B') (( selected < count - 1 ))   && (( selected++ )) || true ;;
            esac
        elif [[ $key == $'\n' || $key == '' ]]; then
            MENU_RESULT=$(( selected + 1 ))
            tput rmcup 2>/dev/null || clear_screen
            show_cursor
            return 0
        elif [[ $key =~ ^[1-9]$ ]] && (( key >= 1 && key <= count )); then
            MENU_RESULT=$key
            tput rmcup 2>/dev/null || clear_screen
            show_cursor
            return 0
        elif [[ $key == 'q' || $key == 'Q' ]]; then
            tput rmcup 2>/dev/null || clear_screen
            show_cursor
            return 1
        fi
    done
}

# ------------------------------------------------------------------------------
# tui_confirm TITLE MESSAGE -> 0=yes 1=no
# ------------------------------------------------------------------------------
tui_confirm() {
    local title="$1" msg="$2"
    tui_menu "$title" "$msg" "Yes — proceed" "No — go back"
    [[ "$MENU_RESULT" == "1" ]]
}

# ------------------------------------------------------------------------------
# tui_info TITLE MESSAGE
# ------------------------------------------------------------------------------
tui_info() {
    tui_menu "$1" "$2" "OK"
    return 0
}

# ------------------------------------------------------------------------------
# tui_error TITLE MESSAGE
# ------------------------------------------------------------------------------
tui_error() {
    local old_cyan="$C_CYAN"
    C_CYAN="$C_RED"
    tui_menu "! $1" "$2" "OK"
    C_CYAN="$old_cyan"
    return 0
}

# ------------------------------------------------------------------------------
# tui_input TITLE PROMPT DEFAULT -> sets INPUT_RESULT
# Avoids read -e/-i (readline) which breaks inside TUI contexts.
# Shows default in prompt; Enter keeps it, any other input replaces it.
# ------------------------------------------------------------------------------
tui_input() {
    local title="$1" prompt="$2" default="$3"
    local _raw

    clear_screen
    printf '\n'
    printf '%s  [ %s ]%s\n\n' "$C_BOLD$C_CYAN" "$title" "$C_RESET"
    printf '%s  %s%s\n' "$C_YELLOW" "$prompt" "$C_RESET"
    [[ -n "$default" ]] && printf '%s  Current: %s%s\n' "$C_WHITE" "$default" "$C_RESET"
    printf '%s  New value (Enter to keep current): %s' "$C_GREEN" "$C_RESET"

    show_cursor
    IFS= read -r _raw
    if [[ -z "$_raw" ]]; then
        INPUT_RESULT="$default"
    else
        INPUT_RESULT="$_raw"
    fi
}

# ------------------------------------------------------------------------------
# tui_progress_init TITLE — call once before a batch
# tui_progress_update PCT MESSAGE — call repeatedly
# tui_progress_done — call after batch completes
# ------------------------------------------------------------------------------
_PROG_TITLE=""

tui_progress_init() {
    _PROG_TITLE="$1"
    tput smcup 2>/dev/null || clear_screen
    clear_screen
}

tui_progress_update() {
    local pct=$1 msg="$2"
    local bw=$TW
    (( bw < 60 )) && bw=60
    local bh=9
    local br=1
    local bc=1
    local bar_inner=$(( bw - 6 ))
    local filled=$(( pct * bar_inner / 100 ))
    local empty=$(( bar_inner - filled ))

    clear_screen
    tui_box "$br" "$bc" "$bw" "$bh" "$_PROG_TITLE"
    move_to $(( br + 2 )) $(( bc + 2 ))
    printf '%s%s%s' "$C_YELLOW" "$msg" "$C_RESET"
    move_to $(( br + 4 )) $(( bc + 2 ))
    printf '%s[%s%s%s%s%s]%s' \
        "$C_CYAN" \
        "$C_GREEN$C_BOLD" "$(printf '█%.0s' $(seq 1 "$filled") 2>/dev/null || printf '%*s' "$filled" | tr ' ' '█')" \
        "$C_RESET$C_CYAN" "$(printf '░%.0s' $(seq 1 "$empty")  2>/dev/null || printf '%*s' "$empty"  | tr ' ' '░')" \
        "$C_RESET$C_CYAN" "$C_RESET"
    move_to $(( br + 5 )) $(( bc + 2 ))
    printf '%s%d%%%s' "$C_WHITE$C_BOLD" "$pct" "$C_RESET"
}

tui_progress_done() {
    tput rmcup 2>/dev/null || clear_screen
}

# ------------------------------------------------------------------------------
# tui_scroll TITLE CONTENT — paged view of long text
# ------------------------------------------------------------------------------
tui_scroll() {
    local title="$1"
    local -a lines=()
    while IFS= read -r line; do
        lines+=("$line")
    done <<< "$2"

    local total=${#lines[@]}
    local bw=$(( TW - 2 ))
    local bh=$(( TH - 2 ))
    local visible=$(( bh - 4 ))
    local offset=0

    tput smcup 2>/dev/null || clear_screen

    while true; do
        clear_screen
        tui_box 1 1 "$bw" "$bh" "$title"
        local i
        for (( i=0; i<visible && offset+i<total; i++ )); do
            move_to $(( 3 + i )) 3
            printf '%s%s%s' "$C_WHITE" "${lines[$((offset+i))]}" "$C_RESET"
        done
        move_to $(( TH - 3 )) 3
        printf '%s[%d/%d] ↑↓ scroll  Q/Enter quit%s' "$C_YELLOW" "$(( offset+1 ))" "$total" "$C_RESET"

        local key
        IFS= read -rsn1 key 2>/dev/null || true
        if [[ $key == $'\033' ]]; then
            read -rsn2 -t 0.1 key 2>/dev/null || true
            case "$key" in
                '[A') (( offset > 0 ))                   && (( offset-- )) || true ;;
                '[B') (( offset + visible < total ))      && (( offset++ )) || true ;;
            esac
        elif [[ $key == 'q' || $key == 'Q' || $key == $'\n' ]]; then
            break
        fi
    done

    tput rmcup 2>/dev/null || clear_screen
}

# ------------------------------------------------------------------------------
# draw_splash — shown once at launch
# ------------------------------------------------------------------------------
draw_splash() {
    tput smcup 2>/dev/null || true
    clear_screen
    local title=" VIDEO BATCH CONVERTER "
    local sub=" FFmpeg-powered | No extra installs required "

    move_to 2 2
    printf '%s%s%s\n' "$C_BOLD$C_CYAN" "$title" "$C_RESET"
    move_to 3 2
    printf '%s%s%s' "$C_YELLOW" "$sub" "$C_RESET"

    sleep 0.6
    tput rmcup 2>/dev/null || clear_screen
}
