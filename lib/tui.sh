# ==============================================================================
# lib/tui.sh — Pure-bash TUI primitives
# Depends on: terminal.sh (colours, cursor helpers: hide_cursor, show_cursor,
#             clear_screen, move_to, TW, TH, C_* colour vars)
# ==============================================================================
#
# Layout contract (all functions follow this):
#   • Boxes are centred both horizontally and vertically.
#   • Standard widths: dialog=75% TW (min 62, max 92), progress/scroll=TW-4.
#   • hide_cursor / show_cursor are managed at function entry/exit only —
#     never inside drawing helpers like tui_box.
#   • smcup/rmcup are always paired; fallback is always clear_screen for both.
#   • Every exit path (select, cancel, ESC) restores cursor + alt-screen.

# ------------------------------------------------------------------------------
# _tui_smcup / _tui_rmcup — paired alt-screen wrappers with consistent fallback
# ------------------------------------------------------------------------------
_tui_smcup() { tput smcup 2>/dev/null || clear_screen; }
_tui_rmcup() { tput rmcup 2>/dev/null || clear_screen; }

# _tui_dialog_dims — compute centred box dimensions into caller's locals
# Usage: _tui_dialog_dims BW BH  (sets br bc after computing from BW/BH)
_tui_dialog_dims() {
    local _bw="$1" _bh="$2"
    br=$(( (TH - _bh) / 2 ))
    bc=$(( (TW - _bw) / 2 ))
    (( br < 1 )) && br=1
    (( bc < 1 )) && bc=1
}

# _tui_std_width — standard dialog box width (75% TW, clamped 62–92)
_tui_std_width() {
    local w=$(( TW * 3 / 4 ))
    (( w < 62 )) && w=62
    (( w > 92 )) && w=92
    printf '%d' "$w"
}

# ------------------------------------------------------------------------------
# tui_box ROW COL WIDTH HEIGHT [TITLE]
# Pure drawing primitive — does NOT touch cursor visibility.
# ------------------------------------------------------------------------------
tui_box() {
    local row=$1 col=$2 w=$3 h=$4 title="${5:-}"
    local inner=$(( w - 2 ))
    local hline
    hline=$(printf '─%.0s' $(seq 1 "$inner"))

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
# tui_menu TITLE PROMPT ITEM... -> sets MENU_RESULT (1-based index)
# Returns 0 on selection, 1 on Q/back.
# ------------------------------------------------------------------------------
tui_menu() {
    local title="$1" prompt="$2"
    shift 2
    local -a items=("$@")
    local count=${#items[@]}

    local bw
    bw=$(_tui_std_width)
    local bh=$(( count + 8 ))
    (( bh > TH - 2 )) && bh=$(( TH - 2 ))
    local br bc
    _tui_dialog_dims "$bw" "$bh"

    local selected=0

    hide_cursor
    _tui_smcup

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
        # printf '%s↑↓ navigate   Enter select   Q back%s' "$C_YELLOW" "$C_RESET"

        local key
        IFS= read -rsn1 key 2>/dev/null || true
        if [[ $key == $'\033' ]]; then
            read -rsn2 -t 0.1 key 2>/dev/null || true
            case "$key" in
                '[A') (( selected > 0 ))          && (( selected-- )) || true ;;
                '[B') (( selected < count - 1 ))  && (( selected++ )) || true ;;
            esac
        elif [[ $key == $'\n' || $key == '' ]]; then
            MENU_RESULT=$(( selected + 1 ))
            _tui_rmcup; show_cursor
            return 0
        elif [[ $key =~ ^[1-9]$ ]] && (( key >= 1 && key <= count )); then
            MENU_RESULT=$key
            _tui_rmcup; show_cursor
            return 0
        elif [[ $key == 'q' || $key == 'Q' ]]; then
            _tui_rmcup; show_cursor
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
# tui_error TITLE MESSAGE  (box border turns red)
# ------------------------------------------------------------------------------
tui_error() {
    local _save="$C_CYAN"
    C_CYAN="$C_RED"
    tui_menu "⚠  $1" "$2" "OK"
    C_CYAN="$_save"
    return 0
}

# ------------------------------------------------------------------------------
# tui_input TITLE PROMPT DEFAULT -> sets INPUT_RESULT
# Renders a centred box (matching all other dialogs), then prompts inline.
# Does NOT use read -e/-i (readline) — safe in all TUI contexts.
# ------------------------------------------------------------------------------
tui_input() {
    local title="$1" prompt="$2" default="${3:-}"

    local bw
    bw=$(_tui_std_width)
    local bh=9
    local br bc
    _tui_dialog_dims "$bw" "$bh"

    hide_cursor
    _tui_smcup
    clear_screen
    tui_box "$br" "$bc" "$bw" "$bh" "$title"

    move_to $(( br + 2 )) $(( bc + 2 ))
    printf '%s%s%s' "$C_YELLOW" "$prompt" "$C_RESET"

    if [[ -n "$default" ]]; then
        move_to $(( br + 4 )) $(( bc + 2 ))
        printf '%sCurrent: %s%s%s' "$C_WHITE" "$C_BOLD" "$default" "$C_RESET"
    fi

    move_to $(( br + 6 )) $(( bc + 2 ))
    printf '%sNew value (Enter to keep current): %s' "$C_GREEN" "$C_RESET"

    show_cursor
    local _raw
    IFS= read -r _raw
    hide_cursor

    _tui_rmcup
    show_cursor

    if [[ -z "$_raw" ]]; then
        INPUT_RESULT="$default"
    else
        INPUT_RESULT="$_raw"
    fi
}

# ------------------------------------------------------------------------------
# tui_progress_init TITLE  — call once before a batch
# tui_progress_update PCT MESSAGE  — call repeatedly during encoding
# tui_progress_done  — call when batch completes
# ------------------------------------------------------------------------------
_PROG_TITLE=""
_PROG_SMCUP=false   # tracks whether smcup succeeded so rmcup matches

tui_progress_init() {
    _PROG_TITLE="$1"
    hide_cursor
    _tui_smcup
    _PROG_SMCUP=true
    clear_screen
}

tui_progress_update() {
    local pct=$1 msg="$2"
    local bw=$(( TW - 4 ))
    (( bw < 62 )) && bw=62
    local bh=9
    local br bc
    _tui_dialog_dims "$bw" "$bh"
    local bar_inner=$(( bw - 6 ))
    local filled=$(( pct * bar_inner / 100 ))
    local empty=$(( bar_inner - filled ))

    clear_screen
    tui_box "$br" "$bc" "$bw" "$bh" "$_PROG_TITLE"

    move_to $(( br + 2 )) $(( bc + 2 ))
    printf '%s%s%s' "$C_YELLOW" "$msg" "$C_RESET"

    move_to $(( br + 4 )) $(( bc + 2 ))
    local bar_filled bar_empty
    bar_filled=$(printf '█%.0s' $(seq 1 "$filled") 2>/dev/null || printf '%*s' "$filled" "" | tr ' ' '█')
    bar_empty=$(printf  '░%.0s' $(seq 1 "$empty")  2>/dev/null || printf '%*s' "$empty"  "" | tr ' ' '░')
    printf '%s[%s%s%s%s%s]%s' \
        "$C_CYAN" \
        "$C_GREEN$C_BOLD" "$bar_filled" \
        "$C_RESET$C_CYAN" "$bar_empty" \
        "$C_RESET$C_CYAN" "$C_RESET"

    move_to $(( br + 5 )) $(( bc + 2 ))
    printf '%s%d%%%s' "$C_WHITE$C_BOLD" "$pct" "$C_RESET"
}

tui_progress_done() {
    _tui_rmcup
    show_cursor
    _PROG_SMCUP=false
}

# ------------------------------------------------------------------------------
# tui_scroll TITLE CONTENT — paginated view of long text
# ------------------------------------------------------------------------------
tui_scroll() {
    local title="$1"
    local -a lines=()
    while IFS= read -r line; do
        lines+=("$line")
    done <<< "$2"

    local total=${#lines[@]}
    local bw=$(( TW - 4 ))
    (( bw < 62 )) && bw=62
    local bh=$(( TH - 4 ))
    (( bh < 10 )) && bh=10
    local br bc
    _tui_dialog_dims "$bw" "$bh"

    # Content rows: inside border (br+1) + header gap (1) = br+2 … br+bh-3
    # Status line: br+bh-2 (one row above bottom border)
    local visible=$(( bh - 4 ))
    local offset=0

    hide_cursor
    _tui_smcup

    while true; do
        clear_screen
        tui_box "$br" "$bc" "$bw" "$bh" "$title"

        local i
        for (( i=0; i<visible && offset+i<total; i++ )); do
            move_to $(( br + 2 + i )) $(( bc + 2 ))
            # Truncate line to fit inside box
            local line="${lines[$((offset+i))]}"
            printf '%s%-*s%s' "$C_WHITE" "$(( bw - 4 ))" "${line:0:$(( bw - 4 ))}" "$C_RESET"
        done

        move_to $(( br + bh - 2 )) $(( bc + 2 ))
        printf '%s[%d/%d]  ↑↓ scroll   Q / Enter quit%s' \
            "$C_YELLOW" "$(( offset + 1 ))" "$total" "$C_RESET"

        local key
        IFS= read -rsn1 key 2>/dev/null || true
        if [[ $key == $'\033' ]]; then
            read -rsn2 -t 0.1 key 2>/dev/null || true
            case "$key" in
                '[A') (( offset > 0 ))                  && (( offset-- )) || true ;;
                '[B') (( offset + visible < total ))     && (( offset++ )) || true ;;
            esac
        elif [[ $key == 'q' || $key == 'Q' || $key == $'\n' || $key == '' ]]; then
            break
        fi
    done

    _tui_rmcup
    show_cursor
}

# ------------------------------------------------------------------------------
# draw_splash — shown once at launch
# ------------------------------------------------------------------------------
draw_splash() {
    local title="  VIDEO BATCH CONVERTER  "
    local sub="  FFmpeg-powered · DaVinci Resolve workflows · No extra installs  "
    local tlen=${#title} slen=${#sub}
    local trow=$(( TH / 2 - 1 ))
    local tcol=$(( (TW - tlen) / 2 ))
    local scol=$(( (TW - slen) / 2 ))

    hide_cursor
    _tui_smcup
    clear_screen

    move_to "$trow" "$tcol"
    printf '%s%s%s' "$C_BOLD$C_CYAN" "$title" "$C_RESET"
    move_to $(( trow + 1 )) "$scol"
    printf '%s%s%s' "$C_YELLOW" "$sub" "$C_RESET"

    sleep 0.6
    _tui_rmcup
    show_cursor
}