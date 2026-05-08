# ==============================================================================
# lib/codecs.sh — Codec profiles (import / render / presets) and helpers
# Sets global: input_codecs, video_enc, audio_enc_default, out_format
# ==============================================================================

# apply_import_codec N — configure for editorial-friendly output
apply_import_codec() {
    case "$1" in
        1)  input_codecs=("h264" "hevc" "av1" "vp9")
            video_enc="-c:v dnxhd -profile:v 4 -pix_fmt yuv422p10le"
            audio_enc_default="-c:a pcm_s16le"; out_format="mov" ;;
        2)  input_codecs=("h264" "hevc" "vp9")
            video_enc="-c:v libsvtav1 -preset 6 -crf 23 -pix_fmt yuv420p10le"
            audio_enc_default="-c:a pcm_s16le"; out_format="mp4" ;;
        3)  input_codecs=("h264" "hevc" "av1" "vp9")
            video_enc="-c:v mpeg4 -q:v 2"
            audio_enc_default="-c:a copy"; out_format="mov" ;;
        *)  return 1 ;;
    esac
    return 0
}

# apply_render_codec N — configure for delivery-ready output
apply_render_codec() {
    case "$1" in
        1)  input_codecs=("dnxhd" "prores")
            video_enc="-c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -movflags +faststart"
            audio_enc_default="-c:a aac -b:a 192k"; out_format="mp4" ;;
        2)  input_codecs=("dnxhd" "prores")
            video_enc="-c:v libx265 -preset slow -crf 20 -movflags +faststart"
            audio_enc_default="-c:a aac -b:a 192k"; out_format="mov" ;;
        3)  input_codecs=("dnxhd" "prores")
            video_enc="-c:v libsvtav1 -preset 3 -crf 25 -pix_fmt yuv420p10le -svtav1-params tune=0:fast-decode=1 -movflags +faststart"
            audio_enc_default="-c:a libopus -b:a 128k"; out_format="mp4" ;;
        *)  return 1 ;;
    esac
    return 0
}

# apply_preset N — quick one-click profiles
apply_preset() {
    case "$1" in
        1)  input_codecs=("h264" "hevc" "av1" "vp9" "dnxhd" "prores")
            video_enc="-c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -movflags +faststart"
            audio_enc_default="-c:a aac -b:a 192k"; out_format="mp4" ;;
        2)  input_codecs=("h264" "hevc" "av1" "vp9")
            video_enc="-c:v dnxhd -profile:v 4 -pix_fmt yuv422p10le"
            audio_enc_default="-c:a pcm_s16le"; out_format="mov" ;;
        3)  input_codecs=("h264" "hevc" "av1" "vp9" "dnxhd" "prores")
            video_enc="-c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p -movflags +faststart"
            audio_enc_default="-c:a aac -b:a 128k"; out_format="mp4" ;;
        4)  input_codecs=("h264" "hevc" "av1" "vp9" "dnxhd" "prores")
            video_enc="-c:v libsvtav1 -preset 5 -crf 30 -pix_fmt yuv420p10le -movflags +faststart"
            audio_enc_default="-c:a libopus -b:a 96k"; out_format="webm" ;;
        *)  return 1 ;;
    esac
    return 0
}

# get_audio_enc CODEC DEFAULT — pass-through PCM, otherwise use DEFAULT
get_audio_enc() {
    case "$1" in
        pcm_s16le|pcm_s24le|pcm_f32le) printf '%s' "-c:a copy" ;;
        *) printf '%s' "$2" ;;
    esac
}

# get_file_ext MIME_SUBTYPE — map mime subtype to file extension (with dot)
get_file_ext() {
    case "$1" in
        "mp4"|"x-m4v")   printf '.mp4' ;;
        "quicktime")      printf '.mov' ;;
        "x-matroska")     printf '.mkv' ;;
        "webm")           printf '.webm' ;;
        "avi")            printf '.avi' ;;
        "x-flv")          printf '.flv' ;;
        "x-ms-wmv")       printf '.wmv' ;;
        *)                printf '' ;;
    esac
}

# get_total_frames FILE — estimate total frame count via ffprobe
get_total_frames() {
    local file="$1"
    local duration fps
    duration=$(ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo 0)
    fps=$(ffprobe -v error -show_entries stream=avg_frame_rate \
        -select_streams v:0 -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "30/1")
    awk "BEGIN { printf \"%d\", ($duration + 0) * ($fps + 0) }" 2>/dev/null || echo 0
}
