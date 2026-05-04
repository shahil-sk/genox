#!/usr/bin/env bash
# ==============================================================================
# video-convert.sh — FFmpeg batch video transcoder
# Pure-bash TUI (no whiptail, no extra installs required)
# Dependencies: ffmpeg, ffprobe, file, awk, tput — all ship with any Linux distro
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Config defaults
# ------------------------------------------------------------------------------
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

# ==============================================================================
# ANSI colours & terminal helpers (pure bash, zero deps beyond tput)
# ==============================================================================
if [[ -t 1 ]] && command -v tput &>/dev/null && tput colors &>/dev/null; then
C_RESET=$(tput sgr0)
C_BOLD=$(tput bold)
C_REV=$(tput rev)
C_BLACK=$(tput setaf 0)
C_RED=$(tput setaf 1)
C_GREEN=$(tput setaf 2)
C_YELLOW=$(tput setaf 3)
C_BLUE=$(tput setaf 4)
C_CYAN=$(tput setaf 6)
C_WHITE=$(tput setaf 7)
TW=$(tput cols)
TH=$(tput lines)
else
C_RESET="" C_BOLD="" C_REV="" C_BLACK="" C_RED=""
C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN="" C_WHITE=""
TW=80; TH=24
fi

hide_cursor() { printf '\033[?25l'; }
show_cursor() { printf '\033[?25h'; }
clear_screen() { printf '\033[2J\033[H'; }
move_to() { printf '\033[%d;%dH' "$1" "$2"; } # row col

# Ensure cursor is restored on exit
trap 'show_cursor; tput rmcup 2>/dev/null || true' EXIT
trap 'show_cursor; exit 130' INT TERM

# ==============================================================================
# Logging
# ==============================================================================
log() {
local level="$1"; shift
[[ -n "$log_file" ]] && printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "$log_file"
$no_tui && printf '[%s] %s\n' "$level" "$*" >&2 || true
}

# ==============================================================================
# Pure-bash TUI primitives
# ==============================================================================

# Draw a box: tui_box ROW COL WIDTH HEIGHT TITLE
tui_box() {
local row=$1 col=$2 w=$3 h=$4 title="${5:-}"
local inner=$(( w - 2 ))
local hline
hline=$(printf '─%.0s' $(seq 1 "$inner"))

hide_cursor
# Top border
move_to "$row" "$col"
printf '%s┌%s┐%s' "$C_BOLD$C_CYAN" "$hline" "$C_RESET"

# Title centred in top border
if [[ -n "$title" ]]; then
local tlen=${#title}
local tpos=$(( col + (w - tlen) / 2 ))
move_to "$row" "$tpos"
printf '%s %s %s' "$C_BOLD$C_WHITE" "$title" "$C_RESET"
fi

# Side borders + blank fill
local r
for (( r=1; r<h-1; r++ )); do
move_to $(( row + r )) "$col"
printf '%s│%*s│%s' "$C_BOLD$C_CYAN" "$inner" "" "$C_RESET"
done

# Bottom border
move_to $(( row + h - 1 )) "$col"
printf '%s└%s┘%s' "$C_BOLD$C_CYAN" "$hline" "$C_RESET"
}

# tui_menu TITLE PROMPT ITEM... -> sets MENU_RESULT (1-based choice string)
# Returns 0 on select, 1 on cancel/back
tui_menu() {
local title="$1" prompt="$2"
shift 2
local -a items=("$@")
local count=${#items[@]}

local bw=$(( TW * 3 / 4 ))
(( bw < 60 )) && bw=60
(( bw > 90 )) && bw=90
local bh=$(( count + 8 ))
(( bh > TH - 2 )) && bh=$(( TH - 2 ))
local br=$(( (TH - bh) / 2 ))
local bc=$(( (TW - bw) / 2 ))

local selected=0

tput smcup 2>/dev/null || clear_screen

while true; do
clear_screen
tui_box "$br" "$bc" "$bw" "$bh" "$title"

# Prompt line
move_to $(( br + 2 )) $(( bc + 2 ))
printf '%s%s%s' "$C_YELLOW" "$prompt" "$C_RESET"

# Menu items
local i
for (( i=0; i<count; i++ )); do
move_to $(( br + 4 + i )) $(( bc + 2 ))
if (( i == selected )); then
printf '%s▶ %s%s' "$C_GREEN$C_BOLD" "${items[$i]}" "$C_RESET"
else
printf '%s  %s%s' "$C_WHITE" "${items[$i]}" "$C_RESET"
fi
done

# Footer
move_to $(( br + bh - 2 )) $(( bc + 2 ))
printf '%s↑↓ navigate  Enter select  Q back%s' "$C_YELLOW" "$C_RESET"

# Read key
local key
IFS= read -rsn1 key 2>/dev/null || true
if [[ $key == $'\033' ]]; then
read -rsn2 -t 0.1 key 2>/dev/null || true
case "$key" in
'[A') (( selected > 0 )) && (( selected-- )) || true ;; # Up
'[B') (( selected < count - 1 )) && (( selected++ )) || true ;; # Down
esac
elif [[ $key == $'\n' || $key == '' ]]; then
MENU_RESULT=$(( selected + 1 ))
tput rmcup 2>/dev/null || clear_screen
show_cursor
return 0
elif [[ $key =~ ^[1-9]$ ]] && (( key >= 1 && key <= count )); then
MENU_RESULT=$key
tput rmcup 2>/dev/null || clear_screen
show_cursor
return 0
elif [[ $key == 'q' || $key == 'Q' ]]; then
tput rmcup 2>/dev/null || clear_screen
show_cursor
return 1
fi
done
}

# tui_confirm TITLE MESSAGE -> 0=yes 1=no
tui_confirm() {
local title="$1" msg="$2"
tui_menu "$title" "$msg" "Yes — proceed" "No — go back"
[[ "$MENU_RESULT" == "1" ]]
}

# tui_info TITLE MESSAGE
tui_info() {
tui_menu "$1" "$2" "OK"
return 0
}

# tui_error TITLE MESSAGE
tui_error() {
local old_cyan="$C_CYAN"
C_CYAN="$C_RED"
tui_menu "! $1" "$2" "OK"
C_CYAN="$old_cyan"
return 0
}

# tui_input TITLE PROMPT DEFAULT -> sets INPUT_RESULT
tui_input() {
local title="$1" prompt="$2" default="$3"
local bw=$(( TW * 3 / 4 ))
(( bw < 60 )) && bw=60
local bh=8
local br=$(( (TH - bh) / 2 ))
local bc=$(( (TW - bw) / 2 ))
local inner=$(( bw - 4 ))

tput smcup 2>/dev/null || clear_screen
clear_screen
tui_box "$br" "$bc" "$bw" "$bh" "$title"
move_to $(( br + 2 )) $(( bc + 2 ))
printf '%s%s%s' "$C_YELLOW" "$prompt" "$C_RESET"
move_to $(( br + 4 )) $(( bc + 2 ))
printf '%s' "$C_WHITE"

# Use readline-enabled read for editing
INPUT_RESULT=""
show_cursor
read -rei "$default" -p "" INPUT_RESULT 2>/dev/null || INPUT_RESULT="$default"
printf '%s' "$C_RESET"
tput rmcup 2>/dev/null || clear_screen
}

# tui_progress TITLE PCT MESSAGE (call repeatedly to update)
# Uses a simple in-place bar drawn with printf
_PROG_TITLE=""
tui_progress_init() {
_PROG_TITLE="$1"
tput smcup 2>/dev/null || clear_screen
clear_screen
}

tui_progress_update() {
local pct=$1 msg="$2"
local bw=$(( TW * 3 / 4 ))
(( bw < 60 )) && bw=60
local bh=9
local br=$(( (TH - bh) / 2 ))
local bc=$(( (TW - bw) / 2 ))
local bar_inner=$(( bw - 6 ))
local filled=$(( pct * bar_inner / 100 ))
local empty=$(( bar_inner - filled ))

clear_screen
tui_box "$br" "$bc" "$bw" "$bh" "$_PROG_TITLE"
move_to $(( br + 2 )) $(( bc + 2 ))
printf '%s%s%s' "$C_YELLOW" "$msg" "$C_RESET"
# Progress bar
move_to $(( br + 4 )) $(( bc + 2 ))
printf '%s[%s%s%s%s%s]%s' \
"$C_CYAN" \
"$C_GREEN$C_BOLD" "$(printf '█%.0s' $(seq 1 "$filled") 2>/dev/null || printf '%*s' "$filled" | tr ' ' '█')" \
"$C_RESET$C_CYAN" "$(printf '░%.0s' $(seq 1 "$empty") 2>/dev/null || printf '%*s' "$empty" | tr ' ' '░')" \
"$C_RESET$C_CYAN" "$C_RESET"
move_to $(( br + 5 )) $(( bc + 2 ))
printf '%s%d%%%s' "$C_WHITE$C_BOLD" "$pct" "$C_RESET"
}

tui_progress_done() {
tput rmcup 2>/dev/null || clear_screen
}

# tui_scroll TITLE CONTENT (paged view of long text)
tui_scroll() {
local title="$1"
local -a lines=()
while IFS= read -r line; do
lines+=("$line")
done <<< "$2"

local total=${#lines[@]}
local bw=$(( TW - 4 ))
local bh=$(( TH - 4 ))
local visible=$(( bh - 4 ))
local offset=0

tput smcup 2>/dev/null || clear_screen

while true; do
clear_screen
tui_box 2 2 "$bw" "$bh" "$title"
local i
for (( i=0; i<visible && offset+i<total; i++ )); do
move_to $(( 4 + i )) 4
printf '%s%s%s' "$C_WHITE" "${lines[$((offset+i))]}" "$C_RESET"
done
move_to $(( TH - 3 )) 4
printf '%s[%d/%d] ↑↓ scroll  Q/Enter quit%s' "$C_YELLOW" "$(( offset+1 ))" "$total" "$C_RESET"

local key
IFS= read -rsn1 key 2>/dev/null || true
if [[ $key == $'\033' ]]; then
read -rsn2 -t 0.1 key 2>/dev/null || true
case "$key" in
'[A') (( offset > 0 )) && (( offset-- )) || true ;;
'[B') (( offset + visible < total )) && (( offset++ )) || true ;;
esac
elif [[ $key == 'q' || $key == 'Q' || $key == $'\n' ]]; then
break
fi
done

tput rmcup 2>/dev/null || clear_screen
}

# ==============================================================================
# Splash / header (drawn once at launch)
# ==============================================================================
draw_splash() {
tput smcup 2>/dev/null || true
clear_screen
local title=" VIDEO BATCH CONVERTER "
local sub=" FFmpeg-powered | No extra installs required "
local col=$(( (TW - ${#title}) / 2 ))

move_to 2 "$col"
printf '%s%s%s\n' "$C_BOLD$C_CYAN" "$title" "$C_RESET"
move_to 3 $(( (TW - ${#sub}) / 2 ))
printf '%s%s%s' "$C_YELLOW" "$sub" "$C_RESET"

sleep 0.6
tput rmcup 2>/dev/null || clear_screen
}

# ==============================================================================
# Notification (optional notify-send — silently skipped if absent)
# ==============================================================================
notify_success() {
log "INFO" "$1${2:+ — $2}"
command -v notify-send &>/dev/null &&
notify-send "$1" "${2:-}" 2>/dev/null || true
}

notify_error() {
log "ERROR" "$1${2:+ — $2}"
command -v notify-send &>/dev/null &&
notify-send -u critical "$1" "${2:-}" 2>/dev/null || true
}

# ==============================================================================
# Config file
# ==============================================================================
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
media_in) media_in="$val" ;;
media_out) media_out="$val" ;;
log_dir) log_dir="$val" ;;
hw_accel) hw_accel="$val" ;;
move_after) move_after="$val" ;;
post_hook) post_hook="$val" ;;
esac
done < "$config_file"
log "INFO" "Config loaded"
}

# ==============================================================================
# Dependency check — only truly needed tools
# ==============================================================================
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

# ==============================================================================
# Hardware acceleration detection
# ==============================================================================
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

hw_video_enc() {
local sw_enc="$1" hw="$2"
case "$hw" in
nvenc)
case "$sw_enc" in
*libx264*) printf '%s' "-c:v h264_nvenc -preset p4 -rc vbr -cq 20 -pix_fmt yuv420p -movflags +faststart" ;;
*libx265*) printf '%s' "-c:v hevc_nvenc -preset p4 -rc vbr -cq 22 -movflags +faststart" ;;
*) printf '%s' "$sw_enc" ;;
esac ;;
vaapi)
case "$sw_enc" in
*libx264*) printf '%s' "-vaapi_device /dev/dri/renderD128 -vf format=nv12,hwupload -c:v h264_vaapi -qp 20 -movflags +faststart" ;;
*libx265*) printf '%s' "-vaapi_device /dev/dri/renderD128 -vf format=nv12,hwupload -c:v hevc_vaapi -qp 22 -movflags +faststart" ;;
*) printf '%s' "$sw_enc" ;;
esac ;;
*) printf '%s' "$sw_enc" ;;
esac
}

# ==============================================================================
# Disk space check
# ==============================================================================
check_disk_space() {
local input_dir="$1" output_dir="$2"
local input_size avail_space
input_size=$(du -sb "$input_dir" 2>/dev/null | awk '{print $1}' || echo 0)
avail_space=$(df -B1 "$output_dir" 2>/dev/null | awk 'NR==2 {print $4}' || echo 999999999999)
local needed
needed=$(awk "BEGIN { printf \"%d\", $input_size * 1.2 }")
if awk "BEGIN { exit ($avail_space < $needed) ? 0 : 1 }"; then
local needed_hr avail_hr
needed_hr=$(awk "BEGIN { printf \"%.1f GB\", $needed / 1073741824 }")
avail_hr=$(awk "BEGIN { printf \"%.1f GB\", $avail_space / 1073741824 }")
if $no_tui; then
printf 'WARNING: Low disk space. Needed ~%s, available %s\n' "$needed_hr" "$avail_hr" >&2
else
tui_confirm "Low Disk Space" \
"Estimated needed : $needed_hr\nAvailable : $avail_hr\n\nContinue anyway?" || return 1
fi
fi
return 0
}

# ==============================================================================
# Codec config
# ==============================================================================
apply_import_codec() {
case "$1" in
1) input_codecs=("h264" "hevc" "av1" "vp9")
video_enc="-c:v dnxhd -profile:v 4 -pix_fmt yuv422p10le"
audio_enc_default="-c:a pcm_s16le"; out_format="mov" ;;
2) input_codecs=("h264" "hevc" "vp9")
video_enc="-c:v libsvtav1 -preset 6 -crf 23 -pix_fmt yuv420p10le"
audio_enc_default="-c:a pcm_s16le"; out_format="mp4" ;;
3) input_codecs=("h264" "hevc" "av1" "vp9")
video_enc="-c:v mpeg4 -q:v 2"
audio_enc_default="-c:a copy"; out_format="mov" ;;
*) return 1 ;;
esac; return 0
}

apply_render_codec() {
case "$1" in
1) input_codecs=("dnxhd" "prores")
video_enc="-c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -movflags +faststart"
audio_enc_default="-c:a aac -b:a 192k"; out_format="mp4" ;;
2) input_codecs=("dnxhd" "prores")
video_enc="-c:v libx265 -preset slow -crf 20 -movflags +faststart"
audio_enc_default="-c:a aac -b:a 192k"; out_format="mov" ;;
3) input_codecs=("dnxhd" "prores")
video_enc="-c:v libsvtav1 -preset 3 -crf 25 -pix_fmt yuv420p10le -svtav1-params tune=0:fast-decode=1 -movflags +faststart"
audio_enc_default="-c:a libopus -b:a 128k"; out_format="mp4" ;;
*) return 1 ;;
esac; return 0
}

apply_preset() {
case "$1" in
1) input_codecs=("h264" "hevc" "av1" "vp9" "dnxhd" "prores")
video_enc="-c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -movflags +faststart"
audio_enc_default="-c:a aac -b:a 192k"; out_format="mp4" ;;
2) input_codecs=("h264" "hevc" "av1" "vp9")
video_enc="-c:v dnxhd -profile:v 4 -pix_fmt yuv422p10le"
audio_enc_default="-c:a pcm_s16le"; out_format="mov" ;;
3) input_codecs=("h264" "hevc" "av1" "vp9" "dnxhd" "prores")
video_enc="-c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p -movflags +faststart"
audio_enc_default="-c:a aac -b:a 128k"; out_format="mp4" ;;
4) input_codecs=("h264" "hevc" "av1" "vp9" "dnxhd" "prores")
video_enc="-c:v libsvtav1 -preset 5 -crf 30 -pix_fmt yuv420p10le -movflags +faststart"
audio_enc_default="-c:a libopus -b:a 96k"; out_format="webm" ;;
*) return 1 ;;
esac; return 0
}

get_audio_enc() {
case "$1" in
pcm_s16le|pcm_s24le|pcm_f32le) printf '%s' "-c:a copy" ;;
*) printf '%s' "$2" ;;
esac
}

get_file_ext() {
case "$1" in
"mp4"|"x-m4v") printf '.mp4' ;;
"quicktime") printf '.mov' ;;
"x-matroska") printf '.mkv' ;;
"webm") printf '.webm' ;;
"avi") printf '.avi' ;;
"x-flv") printf '.flv' ;;
"x-ms-wmv") printf '.wmv' ;;
*) printf '' ;;
esac
}

# ==============================================================================
# Real ffmpeg progress using -progress
# ==============================================================================
get_total_frames() {
local file="$1"
local duration fps
duration=$(ffprobe -v error -show_entries format=duration \
-of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo 0)
fps=$(ffprobe -v error -show_entries stream=avg_frame_rate \
-select_streams v:0 -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "30/1")
awk "BEGIN { printf \"%d\", ($duration + 0) * ($fps + 0) }" 2>/dev/null || echo 0
}

# ==============================================================================
# Settings screen
# ==============================================================================
handle_settings() {
while true; do
tui_menu "Settings" "Select a setting to change:" \
"Input directory : $media_in" \
"Output directory : $media_out" \
"HW acceleration : $hw_accel" \
"Move after encode: $move_after" \
"Post-conv hook : ${post_hook:-none}" \
"Toggle dry-run : $dry_run" \
"Back" || return 0

case "$MENU_RESULT" in
1)
tui_input "Input Directory" "Enter input (queue) directory:" "$media_in"
[[ -n "$INPUT_RESULT" ]] && media_in="$INPUT_RESULT"
;;
2)
tui_input "Output Directory" "Enter output directory:" "$media_out"
[[ -n "$INPUT_RESULT" ]] && media_out="$INPUT_RESULT"
;;
3)
tui_menu "Hardware Acceleration" "Select HW encoder mode:" \
"auto — Auto-detect best available" \
"nvenc — NVIDIA NVENC" \
"vaapi — Intel/AMD VAAPI" \
"none — CPU only (software)" || continue
case "$MENU_RESULT" in
1) hw_accel="auto" ;;
2) hw_accel="nvenc" ;;
3) hw_accel="vaapi" ;;
4) hw_accel="none" ;;
esac
;;
4) $move_after && move_after=false || move_after=true ;;
5)
tui_input "Post-Conversion Hook" \
"Shell cmd after each file. Use \$INPUT and \$OUTPUT. Leave blank to disable:" \
"$post_hook"
post_hook="$INPUT_RESULT"
;;
6) $dry_run && dry_run=false || dry_run=true ;;
7) break ;;
esac
save_config
done
}

# ==============================================================================
# Queue processor
# ==============================================================================
process_queue() {
mkdir -p "$media_in" "$media_out"

local files=()
while IFS= read -r -d '' f; do
local mime
mime=$(file -b --mime-type "$f" 2>/dev/null || true)
[[ "$mime" == video/* ]] && files+=("$f")
done < <(find "$media_in" -maxdepth 1 -type f -print0 2>/dev/null || true)

local total="${#files[@]}"

if [[ "$total" -eq 0 ]]; then
$no_tui \
&& printf 'ERROR: No video files found in %s\n' "$media_in" >&2 \
|| tui_error "Queue Empty" "No video files found in:\n$media_in\n\nAdd videos and try again."
log "WARN" "Queue is empty"
return 0
fi

check_disk_space "$media_in" "$media_out" || return 0

# HW detection
local effective_hw="$hw_accel"
if [[ "$hw_accel" == "auto" ]]; then
local detected
detected=$(detect_hw_encoders 2>/dev/null || echo "none")
if [[ "$detected" == *"nvenc"* ]]; then effective_hw="nvenc"
elif [[ "$detected" == *"vaapi"* ]]; then effective_hw="vaapi"
else effective_hw="none"; fi
log "INFO" "HW auto-detect: $effective_hw"
fi
local hw_label="Software (CPU)"
[[ "$effective_hw" != "none" ]] && hw_label="Hardware ($effective_hw)"

if ! $no_tui; then
local dry_note=""
$dry_run && dry_note="\nDRY RUN -- nothing will be encoded."
tui_confirm "Confirm Conversion" \
"Found $total video file(s)\nEncoder : $hw_label$dry_note\n\nStart?" || return 0
fi

log "INFO" "Starting: $total files, hw=$effective_hw, dry_run=$dry_run"

local file_index=0 skipped=0 failed=0 converted=0
local results_log=""

! $no_tui && tui_progress_init "Converting Videos -- $hw_label"

for file in "${files[@]}"; do
local file_name
file_name=$(basename "$file")

local overall_pct
overall_pct=$(awk "BEGIN { printf \"%d\", $file_index * 100 / $total }") || overall_pct=0
! $no_tui && tui_progress_update "$overall_pct" "Probing [$file_index/$total]: $file_name"

# Probe
local video_codec audio_codec frame_rate_raw frame_rate keyframe_interval
video_codec=$(ffprobe -v error -show_entries stream=codec_name \
-select_streams v:0 -of default=noprint_wrappers=1:nokey=1 "$file" 2>>"$log_file" || echo "unknown")
audio_codec=$(ffprobe -v error -show_entries stream=codec_name \
-select_streams a:0 -of default=noprint_wrappers=1:nokey=1 "$file" 2>>"$log_file" || echo "unknown")
frame_rate_raw=$(ffprobe -v error -show_entries stream=avg_frame_rate \
-select_streams v:0 -of default=noprint_wrappers=1:nokey=1 "$file" 2>>"$log_file" || echo "30/1")
frame_rate=$(awk "BEGIN { printf \"%d\", $frame_rate_raw }" 2>/dev/null || echo 30)
keyframe_interval=$(( frame_rate * 10 )) || keyframe_interval=300

local container_format file_ext
container_format=$(file -b --mime-type "$file" 2>/dev/null || echo "video/unknown")
container_format="${container_format#*/}"
file_ext=$(get_file_ext "$container_format")

if [[ -z "$file_ext" ]]; then
log "WARN" "Skip $file_name — unrecognized container"
results_log+=" SKIP $file_name (unrecognized format)\n"
(( skipped++ )) || true; continue
fi
if [[ ! " ${input_codecs[*]} " =~ " ${video_codec} " ]]; then
log "INFO" "Skip $file_name — codec '$video_codec' not in list"
results_log+=" SKIP $file_name (codec: $video_codec)\n"
(( skipped++ )) || true; continue
fi

local this_audio_enc this_video_enc
this_audio_enc=$(get_audio_enc "$audio_codec" "$audio_enc_default")
this_video_enc=$(hw_video_enc "$video_enc" "$effective_hw")
[[ "$out_format" == "mp4" && "$this_video_enc" == *"libsvtav1"* ]] &&
this_video_enc="$this_video_enc -g $keyframe_interval"

local base_name out_file
base_name=$(basename "$file_name" "$file_ext")
out_file="$media_out/${base_name}.${out_format}"

if [[ -f "$out_file" ]]; then
log "INFO" "Skip $file_name — output exists"
results_log+=" SKIP $file_name (output exists)\n"
(( skipped++ )) || true; continue
fi

(( file_index++ )) || true
local pct2
pct2=$(awk "BEGIN { printf \"%d\", ($file_index-1)*100/$total }") || pct2=0
! $no_tui && tui_progress_update "$pct2" "Encoding [$file_index/$total]: $file_name"
log "INFO" "[$file_index/$total] $file_name -> $(basename "$out_file")"

if $dry_run; then
results_log+=" DRY $file_name -> $(basename "$out_file")\n"
log "INFO" " [DRY RUN]"; sleep 0.2; continue
fi

local -a venc_args aenc_args
IFS=' ' read -r -a venc_args <<< "$this_video_enc"
IFS=' ' read -r -a aenc_args <<< "$this_audio_enc"

# Real per-file progress via -progress pipe
local total_frames progress_fifo encode_ok=true
total_frames=$(get_total_frames "$file" 2>/dev/null || echo 0)

if ! $no_tui && [[ "$total_frames" -gt 0 ]]; then
progress_fifo=$(mktemp -u /tmp/vc_prog_XXXXXX)
mkfifo "$progress_fifo"

ffmpeg -hide_banner -loglevel error \
-i "$file" "${venc_args[@]}" "${aenc_args[@]}" \
-map_metadata 0 -progress "$progress_fifo" \
"$out_file" 2>>"$log_file" &
local ffmpeg_pid=$!

local frame=0 fpct=0
while IFS='=' read -r -t 5 key val <&5 || true; do
[[ "$key" == "frame" ]] && frame="$val"
[[ "$key" == "progress" && "$val" == "end" ]] && break
fpct=$(awk "BEGIN { p=int($frame*100/$total_frames); print (p>100?100:p) }")
tui_progress_update "$fpct" "Encoding [$file_index/$total] frame $frame/$total_frames"
done 5<"$progress_fifo"

wait "$ffmpeg_pid" 2>/dev/null || encode_ok=false
rm -f "$progress_fifo"
else
ffmpeg -hide_banner -loglevel warning \
-i "$file" "${venc_args[@]}" "${aenc_args[@]}" \
-map_metadata 0 "$out_file" 2>>"$log_file" || encode_ok=false
fi

if $encode_ok; then
results_log+=" OK $file_name -> $(basename "$out_file")\n"
log "INFO" " Done: $(basename "$out_file")"
notify_success "Converted [$file_index/$total]" "$file_name"
(( converted++ )) || true

$move_after && {
mkdir -p "$media_in/archive"
mv "$file" "$media_in/archive/"
log "INFO" " Moved to archive"
} || true

if [[ -n "$post_hook" ]]; then
local hook_cmd="${post_hook//\$INPUT/$file}"
hook_cmd="${hook_cmd//\$OUTPUT/$out_file}"
log "INFO" " Hook: $hook_cmd"
eval "$hook_cmd" 2>>"$log_file" || log "WARN" " Hook non-zero"
fi
else
results_log+=" FAIL $file_name\n"
log "ERROR" " Failed: $file_name"
rm -f "$out_file"
notify_error "Encode failed" "$file_name"
(( failed++ )) || true
fi
done

! $no_tui && { tui_progress_update 100 "All done!"; sleep 0.5; tui_progress_done; }

local summary
summary="Converted : $converted\nSkipped : $skipped\nFailed : $failed\n"
$dry_run && summary+="\n(DRY RUN -- nothing encoded)\n"
summary+="\n${results_log}\nLog: $log_file"

if $no_tui; then printf '%b\n' "$summary"
else tui_info "Conversion Complete" "$summary"; fi

notify_success "Done" "Converted: $converted | Skipped: $skipped | Failed: $failed"
log "INFO" "Done -- Converted: $converted, Skipped: $skipped, Failed: $failed"
}

# ==============================================================================
# Log viewer
# ==============================================================================
view_log() {
[[ ! -f "$log_file" ]] && { tui_info "No Log" "No log file yet."; return; }
tui_scroll "Session Log" "$(tail -n 300 "$log_file")"
}

# ==============================================================================
# CLI args
# ==============================================================================
parse_args() {
while [[ $# -gt 0 ]]; do
case "$1" in
--input|-i) media_in="$2"; shift 2 ;;
--output|-o) media_out="$2"; shift 2 ;;
--hw) hw_accel="$2"; shift 2 ;;
--dry-run) dry_run=true; shift ;;
--no-tui) no_tui=true; shift ;;
--move) move_after=true; shift ;;
--hook) post_hook="$2"; shift 2 ;;
--help|-h)
printf 'Usage: %s [OPTIONS]\n\n' "$(basename "$0")"
printf ' -i, --input DIR Input queue directory\n'
printf ' -o, --output DIR Output directory\n'
printf ' --hw MODE auto|nvenc|vaapi|none\n'
printf ' --dry-run Simulate without encoding\n'
printf ' --no-tui Headless / cron mode\n'
printf ' --move Move source to archive/ after success\n'
printf ' --hook CMD Post-encode hook ($INPUT $OUTPUT)\n'
printf ' -h, --help This help\n\n'
printf 'Required tools (no extra installs): ffmpeg ffprobe file awk\n\n'
exit 0 ;;
*) printf 'Unknown option: %s (try --help)\n' "$1" >&2; exit 1 ;;
esac
done
}

# ==============================================================================
# Entry point
# ==============================================================================
main() {
parse_args "$@"
load_config
log_file="$log_dir/convert_log_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$log_dir"
log "INFO" "video-convert started (bash $BASH_VERSION)"
check_dependencies

if $no_tui; then
printf 'Headless | Input: %s | Output: %s | HW: %s\n' "$media_in" "$media_out" "$hw_accel"
input_codecs=("h264" "hevc" "av1" "vp9" "dnxhd" "prores")
video_enc="-c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -movflags +faststart"
audio_enc_default="-c:a aac -b:a 192k"
out_format="mp4"
process_queue || true
exit 0
fi

draw_splash

while true; do
tui_menu "Video Batch Converter" \
"Input : $media_in\nOutput: $media_out\nHW: $hw_accel | Move: $move_after | Dry: $dry_run" \
"Import -- editing codec (DNxHR / AV1 / MPEG-4)" \
"Render -- delivery codec (H.264 / H.265 / AV1)" \
"Presets -- quick profiles" \
"Settings" \
"View Log" \
"Exit" || { log "INFO" "Exited via Escape"; exit 0; }

case "$MENU_RESULT" in
1)
tui_menu "Import Codec" "Select output codec:" \
"DNxHR HQX -- 10-bit YUV422, .mov" \
"AV1 -- 10-bit YUV420, .mp4" \
"MPEG-4 pt2 -- lossy, .mov (legacy)" \
"Back" || continue
[[ "$MENU_RESULT" == "4" ]] && continue
apply_import_codec "$MENU_RESULT" && process_queue || true
;;
2)
tui_menu "Render Codec" "Select output codec:" \
"H.264 -- CRF 20, slow preset, .mp4" \
"H.265 -- CRF 20, slow preset, .mov" \
"AV1 -- CRF 25, preset 3, .mp4" \
"Back" || continue
[[ "$MENU_RESULT" == "4" ]] && continue
apply_render_codec "$MENU_RESULT" && process_queue || true
;;
3)
tui_menu "Quick Presets" "Select a profile:" \
"YouTube Upload -- H.264 CRF18, AAC 192k" \
"Archive Master -- DNxHR HQX 10-bit, PCM" \
"Proxy Edit -- H.264 CRF28 ultrafast" \
"Web Streaming -- AV1 CRF30, Opus" \
"Back" || continue
[[ "$MENU_RESULT" == "5" ]] && continue
apply_preset "$MENU_RESULT" && process_queue || true
;;
4) handle_settings ;;
5) view_log ;;
6) log "INFO" "User exited."; tui_info "Goodbye" "Log saved to:\n$log_file"; exit 0 ;;
esac
done
}

main "$@"
