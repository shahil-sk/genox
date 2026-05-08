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
            "Parallel jobs    : $parallel_jobs  (0=auto, 1=sequential)" \
            "Move after encode: $move_after" \
            "Post-conv hook   : ${post_hook:-none}" \
            "Toggle dry-run   : $dry_run" \
            "Log retention    : keep $log_keep log(s)" \
            "Back" || return 0

        case "$MENU_RESULT" in
            1)  tui_input "Input Directory" "Enter input (queue) directory:" "$media_in"
                [[ -n "$INPUT_RESULT" ]] && media_in="$INPUT_RESULT"
                ;;
            2)  tui_input "Output Directory" "Enter output directory:" "$media_out"
                [[ -n "$INPUT_RESULT" ]] && media_out="$INPUT_RESULT"
                ;;
            3)  tui_menu "Hardware Acceleration" "Select HW encoder mode:" \
                    "auto         — Auto-detect best available" \
                    "nvenc        — NVIDIA NVENC" \
                    "vaapi        — Intel / AMD VAAPI" \
                    "amf          — AMD AMF (amdgpu-pro / ROCm)" \
                    "videotoolbox — Apple VideoToolbox (macOS)" \
                    "none         — CPU only (software)" || continue
                case "$MENU_RESULT" in
                    1) hw_accel="auto"          ;;
                    2) hw_accel="nvenc"         ;;
                    3) hw_accel="vaapi"         ;;
                    4) hw_accel="amf"           ;;
                    5) hw_accel="videotoolbox"  ;;
                    6) hw_accel="none"          ;;
                esac
                ;;
            4)  local cpu_count
                cpu_count=$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo "?")
                tui_input "Parallel Jobs" \
                    "Number of simultaneous encodes.\n0 = auto (nproc/2, currently ~$(( ${cpu_count} / 2 )) on this machine)\n1 = sequential (default, safe for HW encoders)\n2-N = manual\n\nEnter value:" \
                    "$parallel_jobs"
                if [[ "$INPUT_RESULT" =~ ^[0-9]+$ ]]; then
                    parallel_jobs="$INPUT_RESULT"
                fi
                ;;
            5)  $move_after && move_after=false || move_after=true ;;
            6)  tui_input "Post-Conversion Hook" \
                    "Shell cmd after each file. \$INPUT and \$OUTPUT are set as env vars. Leave blank to disable:" \
                    "$post_hook"
                post_hook="$INPUT_RESULT"
                ;;
            7)  $dry_run && dry_run=false || dry_run=true ;;
            8)  tui_input "Log Retention" \
                    "Number of log files to keep (oldest are deleted automatically):" \
                    "$log_keep"
                if [[ "$INPUT_RESULT" =~ ^[0-9]+$ && "$INPUT_RESULT" -gt 0 ]]; then
                    log_keep="$INPUT_RESULT"
                fi
                ;;
            9)  break ;;
        esac
        save_config
    done
}
