# ==============================================================================
# lib/main.sh — Entry point: initialisation + interactive main menu loop
# Depends on: all other lib modules
# ==============================================================================

main() {
    parse_args "$@"
    load_config
    log_file="$log_dir/convert_log_$(date +%Y%m%d_%H%M%S).log"
    mkdir -p "$log_dir"
    log "INFO" "video-convert started (bash $BASH_VERSION)"
    check_dependencies
    rotate_logs

    # ---- Headless / cron mode ------------------------------------------------
    if $no_tui; then
        printf 'Headless | Input: %s | Output: %s | HW: %s\n' "$media_in" "$media_out" "$hw_accel"

        if [[ -n "$cli_preset" ]]; then
            apply_cli_preset "$cli_preset"
        else
            # Default headless profile (H.264 CRF20, broad compatibility)
            apply_render_codec 1
        fi

        apply_cli_overrides
        log "INFO" "Workflow: ${workflow_label:-custom (headless default)}"
        process_queue || true
        exit 0
    fi

    # ---- Interactive TUI mode ------------------------------------------------
    # draw_splash

    while true; do
        tui_menu "Genox" \
            "HW: $hw_accel | Move: $move_after | Dry: $dry_run" \
            "Import -- editing codec (DNxHR / ProRes / AV1 / MPEG-4)" \
            "Render -- delivery codec (H.264 / H.265 / AV1)" \
            "Presets -- quick profiles" \
            "Settings" \
            "View Log" \
            "Exit" || { log "INFO" "Exited via Escape"; exit 0; }

        case "$MENU_RESULT" in
            1)
                tui_menu "Import Codec" "Select output codec (Resolve-safe):" \
                    "DNxHR HQX   -- 10-bit YUV422, .mov  [recommended]" \
                    "ProRes 422 HQ -- 10-bit YUV422, .mov" \
                    "AV1         -- 10-bit YUV422, .mp4" \
                    "MPEG-4 pt2  -- lossy, .mov (legacy)" \
                    "Back" || continue
                [[ "$MENU_RESULT" == "5" ]] && continue
                apply_import_codec "$MENU_RESULT" && process_queue || true
                ;;
            2)
                tui_menu "Render Codec" "Select output codec:" \
                    "H.264 -- CRF 20, slow preset, .mp4" \
                    "H.265 -- CRF 20, slow preset, .mov" \
                    "AV1   -- CRF 25, preset 3, .webm" \
                    "Back" || continue
                [[ "$MENU_RESULT" == "4" ]] && continue
                apply_render_codec "$MENU_RESULT" && process_queue || true
                ;;
            3)
                tui_menu "Quick Presets" "Select a profile:" \
                    "YouTube Upload  -- H.264 CRF18, AAC 192k" \
                    "Archive Master  -- DNxHR HQX 10-bit, PCM 48kHz" \
                    "Proxy Edit      -- H.264 CRF28 ultrafast" \
                    "Web Streaming   -- AV1 CRF30, Opus (.webm)" \
                    "Back" || continue
                [[ "$MENU_RESULT" == "5" ]] && continue
                apply_preset "$MENU_RESULT" && process_queue || true
                ;;
            4) handle_settings ;;
            5) view_log ;;
            6) log "INFO" "User exited."
               tui_info "Goodbye" "Log saved to:\n$log_file"
               exit 0 ;;
        esac
    done
}
