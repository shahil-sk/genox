# ==============================================================================
# lib/settings.sh — Interactive settings screen
# Depends on: config.sh, tui.sh
# ==============================================================================

handle_settings() {
    while true; do
        tui_menu "Settings" "Select a setting to change:" \
            "Input directory  : $media_in" \
            "Output directory : $media_out" \
            "HW acceleration  : $hw_accel" \
            "Move after encode: $move_after" \
            "Post-conv hook   : ${post_hook:-none}" \
            "Toggle dry-run   : $dry_run" \
            "Back" || return 0

        case "$MENU_RESULT" in
            1)  tui_input "Input Directory" "Enter input (queue) directory:" "$media_in"
                [[ -n "$INPUT_RESULT" ]] && media_in="$INPUT_RESULT"
                ;;
            2)  tui_input "Output Directory" "Enter output directory:" "$media_out"
                [[ -n "$INPUT_RESULT" ]] && media_out="$INPUT_RESULT"
                ;;
            3)  tui_menu "Hardware Acceleration" "Select HW encoder mode:" \
                    "auto  — Auto-detect best available" \
                    "nvenc — NVIDIA NVENC" \
                    "vaapi — Intel/AMD VAAPI" \
                    "none  — CPU only (software)" || continue
                case "$MENU_RESULT" in
                    1) hw_accel="auto"  ;;
                    2) hw_accel="nvenc" ;;
                    3) hw_accel="vaapi" ;;
                    4) hw_accel="none"  ;;
                esac
                ;;
            4)  $move_after && move_after=false || move_after=true ;;
            5)  tui_input "Post-Conversion Hook" \
                    "Shell cmd after each file. Use \$INPUT and \$OUTPUT. Leave blank to disable:" \
                    "$post_hook"
                post_hook="$INPUT_RESULT"
                ;;
            6)  $dry_run && dry_run=false || dry_run=true ;;
            7)  break ;;
        esac
        save_config
    done
}
