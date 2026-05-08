# ==============================================================================
# lib/codecs.sh — Codec profiles (import / render / presets) and helpers
# Sets globals: input_codecs, video_enc, audio_enc_default, out_format,
#               force_sample_rate, pass_streams, workflow_label
# ==============================================================================

# force_sample_rate — injected into ffmpeg args for Import modes (Resolve needs 48 kHz)
# pass_streams      — -map flags controlling subtitle/chapter passthrough
# workflow_label    — human-readable description logged per run
force_sample_rate=""
pass_streams="-map_metadata 0"
workflow_label=""

# ------------------------------------------------------------------------------
# apply_import_codec N — editorial-friendly (Resolve-safe) output
# ------------------------------------------------------------------------------
apply_import_codec() {
    # All Import modes: force 48 kHz (Resolve rejects 44.1 kHz audio)
    # and preserve every stream including subtitles and chapters.
    force_sample_rate="-ar 48000"
    pass_streams="-map 0 -map_metadata 0"

    case "$1" in
        1)  # DNxHR HQX — 10-bit YUV422, primary Resolve editing codec
            input_codecs=("h264" "hevc" "av1" "vp9" "mjpeg" "mpeg4")
            video_enc="-c:v dnxhd -profile:v 4 -pix_fmt yuv422p10le -movflags +faststart"
            audio_enc_default="-c:a pcm_s16le"
            out_format="mov"
            workflow_label="Import › DNxHR HQX" ;;
        2)  # ProRes 422 HQ — Resolve-native alternative to DNxHR
            input_codecs=("h264" "hevc" "av1" "vp9" "mjpeg" "mpeg4")
            video_enc="-c:v prores_ks -profile:v 3 -pix_fmt yuv422p10le -movflags +faststart"
            audio_enc_default="-c:a pcm_s16le"
            out_format="mov"
            workflow_label="Import › ProRes 422 HQ" ;;
        3)  # AV1 — 10-bit YUV422 (matches DNxHR chroma subsampling, not 420)
            input_codecs=("h264" "hevc" "vp9" "mjpeg" "mpeg4")
            video_enc="-c:v libsvtav1 -preset 6 -crf 23 -pix_fmt yuv422p10le"
            audio_enc_default="-c:a pcm_s16le"
            out_format="mp4"
            workflow_label="Import › AV1 10-bit YUV422" ;;
        4)  # MPEG-4 Part 2 — legacy; audio forced to PCM so Resolve accepts the .mov
            input_codecs=("h264" "hevc" "av1" "vp9" "mjpeg")
            video_enc="-c:v mpeg4 -q:v 2"
            audio_enc_default="-c:a pcm_s16le"
            out_format="mov"
            workflow_label="Import › MPEG-4 Part 2 (legacy)" ;;
        *)  return 1 ;;
    esac
    return 0
}

# ------------------------------------------------------------------------------
# apply_render_codec N — delivery-ready output after Resolve export
# ------------------------------------------------------------------------------
apply_render_codec() {
    force_sample_rate=""
    # Delivery: keep video + all audio tracks + subtitles + chapters
    pass_streams="-map 0:v:0 -map 0:a? -map 0:s? -map 0:t? -map_metadata 0"

    case "$1" in
        1)  # H.264 CRF 20 — maximum device compatibility
            input_codecs=("dnxhd" "prores")
            video_enc="-c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -movflags +faststart"
            audio_enc_default="-c:a aac -b:a 192k"
            out_format="mp4"
            workflow_label="Render › H.264 CRF20" ;;
        2)  # H.265 CRF 20 — smaller file, Vimeo / client delivery
            input_codecs=("dnxhd" "prores")
            video_enc="-c:v libx265 -preset slow -crf 20 -movflags +faststart"
            audio_enc_default="-c:a aac -b:a 192k"
            out_format="mov"
            workflow_label="Render › H.265 CRF20" ;;
        3)  # AV1 CRF 25 in webm — Opus audio is valid in webm; mp4+Opus has poor support
            input_codecs=("dnxhd" "prores")
            video_enc="-c:v libsvtav1 -preset 3 -crf 25 -pix_fmt yuv420p10le -svtav1-params tune=0:fast-decode=1"
            audio_enc_default="-c:a libopus -b:a 128k"
            out_format="webm"
            workflow_label="Render › AV1 CRF25 (.webm)" ;;
        *)  return 1 ;;
    esac
    return 0
}

# ------------------------------------------------------------------------------
# apply_preset N — quick one-click profiles
# ------------------------------------------------------------------------------
apply_preset() {
    force_sample_rate=""
    pass_streams="-map 0:v:0 -map 0:a? -map 0:s? -map 0:t? -map_metadata 0"

    case "$1" in
        1)  # YouTube Upload — medium preset; platform re-encodes so slow buys nothing
            input_codecs=("h264" "hevc" "av1" "vp9" "dnxhd" "prores" "mjpeg" "mpeg4")
            video_enc="-c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p -movflags +faststart"
            audio_enc_default="-c:a aac -b:a 192k"
            out_format="mp4"
            workflow_label="Preset › YouTube Upload" ;;
        2)  # Archive Master — DNxHR HQX + 48 kHz PCM; preserve all streams
            input_codecs=("h264" "hevc" "av1" "vp9" "mjpeg" "mpeg4")
            video_enc="-c:v dnxhd -profile:v 4 -pix_fmt yuv422p10le -movflags +faststart"
            audio_enc_default="-c:a pcm_s16le"
            force_sample_rate="-ar 48000"
            pass_streams="-map 0 -map_metadata 0"
            out_format="mov"
            workflow_label="Preset › Archive Master" ;;
        3)  # Proxy Edit — ultrafast H.264 for offline editing proxies
            input_codecs=("h264" "hevc" "av1" "vp9" "dnxhd" "prores" "mjpeg" "mpeg4")
            video_enc="-c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p -movflags +faststart"
            audio_enc_default="-c:a aac -b:a 128k"
            out_format="mp4"
            workflow_label="Preset › Proxy Edit" ;;
        4)  # Web Streaming — AV1 + Opus in webm (valid container for Opus)
            input_codecs=("h264" "hevc" "av1" "vp9" "dnxhd" "prores" "mjpeg" "mpeg4")
            video_enc="-c:v libsvtav1 -preset 5 -crf 30 -pix_fmt yuv420p10le"
            audio_enc_default="-c:a libopus -b:a 96k"
            out_format="webm"
            workflow_label="Preset › Web Streaming" ;;
        *)  return 1 ;;
    esac
    return 0
}

# get_audio_enc CODEC DEFAULT — pass-through any PCM variant unmodified
get_audio_enc() {
    case "$1" in
        pcm_s16le|pcm_s24le|pcm_f32le|pcm_s32le) printf '%s' "-c:a copy" ;;
        *) printf '%s' "$2" ;;
    esac
}

# get_file_ext MIME_SUBTYPE — map mime subtype → file extension (with dot)
get_file_ext() {
    case "$1" in
        "mp4"|"x-m4v")   printf '.mp4'  ;;
        "quicktime")      printf '.mov'  ;;
        "x-matroska")     printf '.mkv'  ;;
        "webm")           printf '.webm' ;;
        "avi"|"x-msvideo") printf '.avi' ;;
        "x-flv")          printf '.flv'  ;;
        "x-ms-wmv")       printf '.wmv'  ;;
        "mxf")            printf '.mxf'  ;;
        *)                printf ''      ;;
    esac
}

# get_total_frames FILE — estimate frame count via ffprobe duration × fps
get_total_frames() {
    local file="$1"
    local duration fps
    duration=$(ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo 0)
    fps=$(ffprobe -v error -show_entries stream=avg_frame_rate \
        -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "30/1")
    awk "BEGIN { printf \"%d\", ($duration + 0) * ($fps + 0) }" 2>/dev/null || echo 0
}

# probe_resolve_project FILE — try to extract the originating Resolve project name
# from DNxHR/ProRes metadata tags; returns empty string if nothing found.
probe_resolve_project() {
    local file="$1"
    ffprobe -v error \
        -show_entries format_tags=com.apple.proapps.studio.projectname,title \
        -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null \
        | grep -v '^$' | head -1 || true
}
