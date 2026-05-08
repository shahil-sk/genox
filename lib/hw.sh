# ==============================================================================
# lib/hw.sh — Hardware-acceleration detection and encoder mapping
# Depends on: terminal.sh (log)
# ==============================================================================

# detect_hw_encoders — prints space-separated list of available hw backends,
# or "none" when nothing is found.
detect_hw_encoders() {
    local available=()
    if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "h264_nvenc"; then
        ffmpeg -hide_banner -f lavfi -i color=black:s=64x64:d=0.1 \
            -c:v h264_nvenc -f null - &>/dev/null 2>&1 && available+=("nvenc") || true
    fi
    if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "h264_vaapi" && [[ -e /dev/dri/renderD128 ]]; then
        available+=("vaapi")
    fi
    [[ ${#available[@]} -gt 0 ]] && printf '%s' "${available[*]}" || printf 'none'
}

# hw_video_enc SW_ENC HW_MODE — prints the best encoder flags for the given
# software encoder + hardware mode combination.
hw_video_enc() {
    local sw_enc="$1" hw="$2"
    case "$hw" in
        nvenc)
            case "$sw_enc" in
                *libx264*) printf '%s' "-c:v h264_nvenc -preset p4 -rc vbr -cq 20 -pix_fmt yuv420p -movflags +faststart" ;;
                *libx265*) printf '%s' "-c:v hevc_nvenc -preset p4 -rc vbr -cq 22 -movflags +faststart" ;;
                *)         printf '%s' "$sw_enc" ;;
            esac ;;
        vaapi)
            case "$sw_enc" in
                *libx264*) printf '%s' "-vaapi_device /dev/dri/renderD128 -vf format=nv12,hwupload -c:v h264_vaapi -qp 20 -movflags +faststart" ;;
                *libx265*) printf '%s' "-vaapi_device /dev/dri/renderD128 -vf format=nv12,hwupload -c:v hevc_vaapi -qp 22 -movflags +faststart" ;;
                *)         printf '%s' "$sw_enc" ;;
            esac ;;
        *) printf '%s' "$sw_enc" ;;
    esac
}

# check_dependencies — exits with code 2 if any required binary is missing.
check_dependencies() {
    local missing=()
    for cmd in ffmpeg ffprobe file awk; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        printf '\nERROR: Missing required tools: %s\n' "${missing[*]}" >&2
        printf 'Install them and re-run the script.\n\n' >&2
        exit 2
    fi
}
