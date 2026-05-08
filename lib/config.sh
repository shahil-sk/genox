# ==============================================================================
# lib/config.sh — Global config defaults, load/save, log rotation
# ==============================================================================

CONFIG_VERSION=3

media_in="${MEDIA_IN:-$HOME/Videos/convert_queue}"
media_out="${MEDIA_OUT:-$HOME/Videos/converted}"
log_dir="${LOG_DIR:-$HOME/Videos}"
log_file=""
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/video-convert"
config_file="$config_dir/config"
post_hook=""
dry_run=false
no_tui=false
hw_accel="auto"
move_after=false
log_keep=10          # number of past log files to retain
parallel_jobs=1      # concurrent ffmpeg workers (1 = sequential, 0 = auto = nproc/2)

# Codec state (set by menu selections or --preset CLI flag)
audio_enc_default="-c:a copy"
out_format="mp4"
input_codecs=()
video_enc=""

# ------------------------------------------------------------------------------
save_config() {
    mkdir -p "$config_dir"
    cat > "$config_file" <<EOF
# video-convert config — $(date)
config_version=$CONFIG_VERSION
media_in=$media_in
media_out=$media_out
log_dir=$log_dir
hw_accel=$hw_accel
move_after=$move_after
post_hook=$post_hook
log_keep=$log_keep
parallel_jobs=$parallel_jobs
EOF
    log "INFO" "Config saved: $config_file"
}

load_config() {
    [[ -f "$config_file" ]] || return 0
    while IFS='=' read -r key val; do
        [[ "$key" =~ ^# || -z "$key" ]] && continue
        key="${key// /}"; val="${val// /}"
        case "$key" in
            media_in)        media_in="$val"        ;;
            media_out)       media_out="$val"        ;;
            log_dir)         log_dir="$val"          ;;
            hw_accel)        hw_accel="$val"         ;;
            move_after)      move_after="$val"       ;;
            post_hook)       post_hook="$val"        ;;
            log_keep)        log_keep="$val"         ;;
            parallel_jobs)   parallel_jobs="$val"    ;;
            config_version)  true                    ;;
        esac
    done < "$config_file"
    log "INFO" "Config loaded"
}

# resolve_parallel_jobs — returns the effective job count (resolves 0 → nproc/2)
resolve_parallel_jobs() {
    local j="$parallel_jobs"
    if [[ "$j" == "0" ]]; then
        local cpus
        cpus=$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 2)
        j=$(( cpus / 2 ))
        (( j < 1 )) && j=1
    fi
    printf '%d' "$j"
}

# rotate_logs — keep only the $log_keep most recent log files in $log_dir
rotate_logs() {
    local pattern="$log_dir/convert_log_*.log"
    local count
    # shellcheck disable=SC2086
    count=$(ls -1 $pattern 2>/dev/null | wc -l) || return 0
    if (( count > log_keep )); then
        # shellcheck disable=SC2086
        ls -1t $pattern 2>/dev/null | tail -n +"$(( log_keep + 1 ))" | xargs rm -f --
        log "INFO" "Log rotation: kept $log_keep, removed $(( count - log_keep )) old log(s)"
    fi
}
