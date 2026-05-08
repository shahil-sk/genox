# ==============================================================================
# lib/cli.sh — Command-line argument parser
# ==============================================================================

# cli_preset / cli_format / cli_crf / cli_audio_bitrate — set by CLI flags,
# applied in main() after load_config so they override saved config.
cli_preset=""
cli_format=""
cli_crf=""
cli_audio_bitrate=""
recursive=false

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --input|-i)         media_in="$2";          shift 2 ;;
            --output|-o)        media_out="$2";         shift 2 ;;
            --hw)               hw_accel="$2";          shift 2 ;;
            --dry-run)          dry_run=true;           shift   ;;
            --no-tui)           no_tui=true;            shift   ;;
            --move)             move_after=true;        shift   ;;
            --hook)             post_hook="$2";         shift 2 ;;
            --recursive|-r)     recursive=true;         shift   ;;
            --preset)           cli_preset="$2";        shift 2 ;;
            --format)           cli_format="$2";        shift 2 ;;
            --crf)              cli_crf="$2";           shift 2 ;;
            --audio-bitrate)    cli_audio_bitrate="$2"; shift 2 ;;
            --jobs|-j)          parallel_jobs="$2";     shift 2 ;;
            --help|-h)
                printf 'Usage: %s [OPTIONS]\n\n' "$(basename "$0")"
                printf '  -i, --input       DIR    Input queue directory\n'
                printf '  -o, --output      DIR    Output directory\n'
                printf '  --hw              MODE   auto|nvenc|vaapi|amf|videotoolbox|none\n'
                printf '  --dry-run                Simulate without encoding\n'
                printf '  --no-tui                 Headless / cron mode\n'
                printf '  --move                   Move source to archive/ after success\n'
                printf '  --hook            CMD    Post-encode hook ($INPUT $OUTPUT)\n'
                printf '  -r, --recursive          Walk subdirectories of input folder\n'
                printf '  --preset          NAME   Headless codec preset:\n'
                printf '                             import-dnxhr | import-prores | import-av1 |\n'
                printf '                             render-h264  | render-h265  | render-av1  |\n'
                printf '                             youtube | archive | proxy | web\n'
                printf '  --format          EXT    Override output container (mp4|mov|mkv|webm)\n'
                printf '  --crf             N      Override CRF quality value\n'
                printf '  --audio-bitrate   RATE   Override audio bitrate (e.g. 320k)\n'
                printf '  -j, --jobs        N      Parallel encode workers (0=auto=nproc/2, 1=sequential)\n'
                printf '  -h, --help               This help\n\n'
                printf 'Required tools (no extra installs): ffmpeg ffprobe file awk\n\n'
                exit 0 ;;
            *)
                printf 'Unknown option: %s (try --help)\n' "$1" >&2
                exit 1 ;;
        esac
    done
}

# apply_cli_preset NAME — maps --preset string to codec profile functions
apply_cli_preset() {
    case "$1" in
        import-dnxhr)  apply_import_codec 1 ;;
        import-prores) apply_import_codec 2 ;;
        import-av1)    apply_import_codec 3 ;;
        render-h264)   apply_render_codec 1 ;;
        render-h265)   apply_render_codec 2 ;;
        render-av1)    apply_render_codec 3 ;;
        youtube)       apply_preset 1 ;;
        archive)       apply_preset 2 ;;
        proxy)         apply_preset 3 ;;
        web)           apply_preset 4 ;;
        *)
            printf 'Unknown preset: %s\nSee --help for valid preset names.\n' "$1" >&2
            exit 1 ;;
    esac
}

# apply_cli_overrides — apply --crf, --format, --audio-bitrate on top of any preset
apply_cli_overrides() {
    if [[ -n "$cli_crf" ]]; then
        video_enc="${video_enc//-crf [0-9]*/}"
        video_enc="$video_enc -crf $cli_crf"
        log "INFO" "CLI override: CRF=$cli_crf"
    fi
    if [[ -n "$cli_format" ]]; then
        out_format="$cli_format"
        log "INFO" "CLI override: format=$cli_format"
    fi
    if [[ -n "$cli_audio_bitrate" ]]; then
        audio_enc_default="${audio_enc_default//-b:a [0-9]*[k|K|m|M]*/}"
        audio_enc_default="$audio_enc_default -b:a $cli_audio_bitrate"
        log "INFO" "CLI override: audio-bitrate=$cli_audio_bitrate"
    fi
}
