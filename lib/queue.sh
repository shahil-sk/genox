# ==============================================================================
# lib/queue.sh — Queue processor and disk-space guard
# Depends on: config.sh, terminal.sh, tui.sh, notify.sh, hw.sh, codecs.sh
# ==============================================================================

# check_disk_space INPUT_DIR OUTPUT_DIR
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

# _encode_file FILE FILE_INDEX TOTAL EFFECTIVE_HW
# Handles per-file probing, skipping, and encoding (real or dry-run).
# Appends to caller's results_log; increments converted/skipped/failed.
_encode_file() {
    local file="$1" file_index="$2" total="$3" effective_hw="$4"
    local file_name
    file_name=$(basename "$file")

    local overall_pct
    overall_pct=$(awk "BEGIN { printf \"%d\", $file_index * 100 / $total }") || overall_pct=0
    ! $no_tui && tui_progress_update "$overall_pct" "Probing [$file_index/$total]: $file_name"

    # ---- Probe ---------------------------------------------------------------
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

    # ---- Skip guards ---------------------------------------------------------
    if [[ -z "$file_ext" ]]; then
        log "WARN" "Skip $file_name — unrecognized container"
        results_log+=" SKIP $file_name (unrecognized format)\n"
        (( skipped++ )) || true
        return 0
    fi
    if [[ ! " ${input_codecs[*]} " =~ " ${video_codec} " ]]; then
        log "INFO" "Skip $file_name — codec '$video_codec' not in list"
        results_log+=" SKIP $file_name (codec: $video_codec)\n"
        (( skipped++ )) || true
        return 0
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
        (( skipped++ )) || true
        return 0
    fi

    # ---- Encode --------------------------------------------------------------
    (( file_index++ )) || true
    local pct2
    pct2=$(awk "BEGIN { printf \"%d\", ($file_index-1)*100/$total }") || pct2=0
    ! $no_tui && tui_progress_update "$pct2" "Encoding [$file_index/$total]: $file_name"
    log "INFO" "[$file_index/$total] $file_name -> $(basename "$out_file")"

    if $dry_run; then
        results_log+=" DRY $file_name -> $(basename "$out_file")\n"
        log "INFO" " [DRY RUN]"; sleep 0.2
        return 0
    fi

    local -a venc_args aenc_args
    IFS=' ' read -r -a venc_args <<< "$this_video_enc"
    IFS=' ' read -r -a aenc_args <<< "$this_audio_enc"

    # Real per-file progress via -progress pipe
    local total_frames encode_ok=true
    total_frames=$(get_total_frames "$file" 2>/dev/null || echo 0)

    if ! $no_tui && [[ "$total_frames" -gt 0 ]]; then
        local progress_fifo
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
        notify_success "Done $file_index/$total)" "$file_name"
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
}

# process_queue — discovers video files, confirms with user, calls _encode_file
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

    # ---- Hardware detection --------------------------------------------------
    local effective_hw="$hw_accel"
    if [[ "$hw_accel" == "auto" ]]; then
        local detected
        detected=$(detect_hw_encoders 2>/dev/null || echo "none")
        if   [[ "$detected" == *"nvenc"* ]]; then effective_hw="nvenc"
        elif [[ "$detected" == *"vaapi"* ]]; then effective_hw="vaapi"
        else effective_hw="none"; fi
        log "INFO" "HW auto-detect: $effective_hw"
    fi
    local hw_label="Software (CPU)"
    [[ "$effective_hw" != "none" ]] && hw_label="Hardware ($effective_hw)"

    # ---- Confirmation --------------------------------------------------------
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
        _encode_file "$file" "$file_index" "$total" "$effective_hw"
        (( file_index++ )) || true
    done

    ! $no_tui && { tui_progress_update 100 "All done!"; sleep 0.5; tui_progress_done; }

    local summary
    summary="Converted : $converted\nSkipped : $skipped\nFailed : $failed\n"
    $dry_run && summary+="\n(DRY RUN -- nothing encoded)\n"
    summary+="\n${results_log}\nLog: $log_file"

    if $no_tui; then
        printf '%b\n' "$summary"
    else
        tui_info "Conversion Complete" "$summary"
    fi

    notify_success "Done" "Converted: $converted / Skip: $skipped / Failed: $failed"
    log "INFO" "Done -- Converted: $converted, Skipped: $skipped, Failed: $failed"
}

# view_log — show the tail of the current session log
view_log() {
    [[ ! -f "$log_file" ]] && { tui_info "No Log" "No log file yet."; return; }
    tui_scroll "Session Log" "$(tail -n 300 "$log_file")"
}
