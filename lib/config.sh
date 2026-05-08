# ==============================================================================
# lib/config.sh — Global config defaults, load/save
# ==============================================================================

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

# Codec state (set by menu selections)
audio_enc_default="-c:a copy"
out_format="mp4"
input_codecs=()
video_enc=""

# ------------------------------------------------------------------------------
save_config() {
    mkdir -p "$config_dir"
    printf '# video-convert config — %s\nmedia_in=%s\nmedia_out=%s\nlog_dir=%s\nhw_accel=%s\nmove_after=%s\npost_hook=%s\n' \
        "$(date)" "$media_in" "$media_out" "$log_dir" "$hw_accel" "$move_after" "$post_hook" > "$config_file"
    log "INFO" "Config saved: $config_file"
}

load_config() {
    [[ -f "$config_file" ]] || return 0
    while IFS='=' read -r key val; do
        [[ "$key" =~ ^# || -z "$key" ]] && continue
        key="${key// /}"; val="${val// /}"
        case "$key" in
            media_in)   media_in="$val"   ;;
            media_out)  media_out="$val"  ;;
            log_dir)    log_dir="$val"    ;;
            hw_accel)   hw_accel="$val"   ;;
            move_after) move_after="$val" ;;
            post_hook)  post_hook="$val"  ;;
        esac
    done < "$config_file"
    log "INFO" "Config loaded"
}
