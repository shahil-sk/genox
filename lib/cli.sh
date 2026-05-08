# ==============================================================================
# lib/cli.sh — Command-line argument parser
# ==============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --input|-i)   media_in="$2";   shift 2 ;;
            --output|-o)  media_out="$2";  shift 2 ;;
            --hw)         hw_accel="$2";   shift 2 ;;
            --dry-run)    dry_run=true;    shift   ;;
            --no-tui)     no_tui=true;     shift   ;;
            --move)       move_after=true; shift   ;;
            --hook)       post_hook="$2";  shift 2 ;;
            --help|-h)
                printf 'Usage: %s [OPTIONS]\n\n' "$(basename "$0")"
                printf '  -i, --input  DIR   Input queue directory\n'
                printf '  -o, --output DIR   Output directory\n'
                printf '  --hw         MODE  auto|nvenc|vaapi|none\n'
                printf '  --dry-run          Simulate without encoding\n'
                printf '  --no-tui           Headless / cron mode\n'
                printf '  --move             Move source to archive/ after success\n'
                printf '  --hook       CMD   Post-encode hook ($INPUT $OUTPUT)\n'
                printf '  -h, --help         This help\n\n'
                printf 'Required tools (no extra installs): ffmpeg ffprobe file awk\n\n'
                exit 0 ;;
            *)
                printf 'Unknown option: %s (try --help)\n' "$1" >&2
                exit 1 ;;
        esac
    done
}
