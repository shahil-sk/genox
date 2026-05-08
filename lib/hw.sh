# ==============================================================================
# lib/hw.sh — Hardware-acceleration detection and encoder mapping
# Depends on: terminal.sh (log)
# ==============================================================================

# detect_hw_encoders — prints space-separated list of available hw backends,
# or "none" when nothing is detected.
# Checks: NVIDIA NVENC, Intel/AMD VAAPI, AMD AMF, Apple VideoToolbox
detect_hw_encoders() {
    local available=()
    local encoders
    encoders=$(ffmpeg -hide_banner -encoders 2>/dev/null)

    # NVIDIA NVENC — do a real test encode, not just a grep
    if printf '%s' "$encoders" | grep -q "h264_nvenc"; then
        ffmpeg -hide_banner -f lavfi -i color=black:s=64x64:d=0.1 \
            -c:v h264_nvenc -f null - &>/dev/null 2>&1 && available+=("nvenc") || true
    fi

    # Intel / AMD VAAPI — require the render node to exist
    if printf '%s' "$encoders" | grep -q "h264_vaapi" && [[ -e /dev/dri/renderD128 ]]; then
        available+=("vaapi")
    fi

    # AMD AMF — Windows/Linux with amdgpu-pro or ROCm driver
    if printf '%s' "$encoders" | grep -q "h264_amf"; then
        ffmpeg -hide_banner -f lavfi -i color=black:s=64x64:d=0.1 \
            -c:v h264_amf -f null - &>/dev/null 2>&1 && available+=("amf") || true
    fi

    # Apple VideoToolbox — macOS only
    if [[ "$(uname -s)" == "Darwin" ]] && printf '%s' "$encoders" | grep -q "h264_videotoolbox"; then
        available+=("videotoolbox")
    fi

    [[ ${#available[@]} -gt 0 ]] && printf '%s' "${available[*]}" || printf 'none'
}

# hw_video_enc SW_ENC HW_MODE — returns the best encoder flags.
# If the hw mode doesn't have a mapping for this sw encoder, falls back to sw.
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
        amf)
            case "$sw_enc" in
                *libx264*) printf '%s' "-c:v h264_amf -quality quality -rc cqp -qp_i 20 -qp_p 20 -movflags +faststart" ;;
                *libx265*) printf '%s' "-c:v hevc_amf -quality quality -rc cqp -qp_i 22 -qp_p 22 -movflags +faststart" ;;
                *)         printf '%s' "$sw_enc" ;;
            esac ;;
        videotoolbox)
            case "$sw_enc" in
                *libx264*) printf '%s' "-c:v h264_videotoolbox -q:v 65 -movflags +faststart" ;;
                *libx265*) printf '%s' "-c:v hevc_videotoolbox -q:v 65 -movflags +faststart" ;;
                *)         printf '%s' "$sw_enc" ;;
            esac ;;
        *) printf '%s' "$sw_enc" ;;
    esac
}

# hw_video_enc_with_fallback SW_ENC HW_MODE FILE OUT_FILE LOG
# Attempts hw encode; if ffmpeg exits non-zero, retries with software.
# Prints "ok" or "fail" to stdout. Caller reads the result.
hw_video_enc_with_fallback() {
    local sw_enc="$1" hw="$2" in_file="$3" out_file="$4" logf="$5"
    shift 5
    local extra_args=("$@")   # venc_args already resolved by caller

    local this_enc
    this_enc=$(hw_video_enc "$sw_enc" "$hw")
    local -a venc_args
    IFS=' ' read -r -a venc_args <<< "$this_enc"

    if ffmpeg -hide_banner -loglevel warning \
        -i "$in_file" "${venc_args[@]}" "${extra_args[@]}" \
        "$out_file" 2>>"$logf"; then
        printf 'ok'
        return 0
    fi

    # hw encode failed — warn and retry with pure software flags
    log "WARN" "HW encode failed for $(basename "$in_file"), retrying in software"
    rm -f "$out_file"
    local -a sw_args
    IFS=' ' read -r -a sw_args <<< "$sw_enc"
    if ffmpeg -hide_banner -loglevel warning \
        -i "$in_file" "${sw_args[@]}" "${extra_args[@]}" \
        "$out_file" 2>>"$logf"; then
        printf 'ok'
    else
        printf 'fail'
    fi
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
