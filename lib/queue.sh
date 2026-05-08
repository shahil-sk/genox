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

# ------------------------------------------------------------------------------
# _encode_file FILE FILE_INDEX TOTAL EFFECTIVE_HW RESULT_FILE
# Runs in a subshell (called via & for parallel mode).
# Writes one line to RESULT_FILE: OK|SKIP|FAIL|DRY <filename> [-> outfile]
# Never touches shared parent variables.
# ------------------------------------------------------------------------------
_encode_file() {
    local file="$1" file_index="$2" total="$3" effective_hw="$4" result_file="$5"
    local file_name
    file_name=$(basename "$file")

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
        printf 'SKIP %s (unrecognized format)\n' "$file_name" >> "$result_file"
        return 0
    fi
    if [[ ! " ${input_codecs[*]} " =~ " ${video_codec} " ]]; then
        log "INFO" "Skip $file_name — codec '$video_codec' not in list"
        printf 'SKIP %s (codec: %s)\n' "$file_name" "$video_codec" >> "$result_file"
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
        printf 'SKIP %s (output exists)\n' "$file_name" >> "$result_file"
        return 0
    fi

    # ---- Encode --------------------------------------------------------------
    log "INFO" "[$file_index/$total] $file_name -> $(basename "$out_file")"

    if $dry_run; then
        printf 'DRY %s -> %s\n' "$file_name" "$(basename "$out_file")" >> "$result_file"
        log "INFO" " [DRY RUN]"; sleep 0.2
        return 0
    fi

    local -a venc_args aenc_args
    IFS=' ' read -r -a venc_args <<< "$this_video_enc"
    IFS=' ' read -r -a aenc_args <<< "$this_audio_enc"

    local encode_ok=true
    ffmpeg -hide_banner -loglevel warning \
        -i "$file" "${venc_args[@]}" "${aenc_args[@]}" \
        -map_metadata 0 "$out_file" 2>>"$log_file" || encode_ok=false

    if $encode_ok; then
        printf 'OK %s -> %s\n' "$file_name" "$(basename "$out_file")" >> "$result_file"
        log "INFO" " Done: $(basename "$out_file")"
        notify_success "Done $file_index/$total" "$file_name"

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
        printf 'FAIL %s\n' "$file_name" >> "$result_file"
        log "ERROR" " Failed: $file_name"
        rm -f "$out_file"
        notify_error "Encode failed" "$file_name"
    fi
}

# ------------------------------------------------------------------------------
# _tui_status_board SLOT_FILE TOTAL DONE_FILE
# Draws a multi-slot live status board for parallel mode.
# Reads slot state from SLOT_FILE (one line per slot: SLOT_N=<label>).
# Reads completed count from DONE_FILE (single integer).
# Runs in a background subshell; killed by parent when encoding done.
# ------------------------------------------------------------------------------
_tui_status_board() {
    local slot_file="$1" total="$2" done_file="$3"
    local jobs="$parallel_jobs"

    while true; do
        clear_screen
        move_to 1 1
        printf '%s  Parallel Encoding — %s jobs%s\n' "$C_BOLD$C_CYAN" "$jobs" "$C_RESET"
        printf '%s  Total: %s%s\n\n' "$C_YELLOW" "$total" "$C_RESET"

        local done_count=0
        [[ -f "$done_file" ]] && done_count=$(cat "$done_file" 2>/dev/null || echo 0)
        local pct=0
        (( total > 0 )) && pct=$(( done_count * 100 / total ))

        local slot
        for (( slot=0; slot<jobs; slot++ )); do
            local label="idle"
            if [[ -f "$slot_file.$slot" ]]; then
                label=$(cat "$slot_file.$slot" 2>/dev/null || echo "idle")
            fi
            printf '%s  [slot %d] %s%s\n' "$C_WHITE" "$slot" "$label" "$C_RESET"
        done

        printf '\n%s  Progress: %d/%d (%d%%)%s\n' "$C_GREEN" "$done_count" "$total" "$pct" "$C_RESET"
        sleep 0.5
    done
}

# process_queue — discovers video files, confirms with user, runs encode loop
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
    local jobs=$parallel_jobs
    (( jobs < 1 )) && jobs=1

    if ! $no_tui; then
        local dry_note=""
        $dry_run && dry_note="\nDRY RUN -- nothing will be encoded."
        local parallel_note=""
        (( jobs > 1 )) && parallel_note="\nParallel jobs: $jobs"
        tui_confirm "Confirm Conversion" \
            "Found $total video file(s)\nEncoder : $hw_label${parallel_note}${dry_note}\n\nStart?" || return 0
    fi

    log "INFO" "Starting: $total files, hw=$effective_hw, dry_run=$dry_run, jobs=$jobs"

    # ---- Temp dir for inter-process communication ----------------------------
    local tmp_dir
    tmp_dir=$(mktemp -d /tmp/genox_XXXXXX)
    local result_file="$tmp_dir/results"
    local slot_base="$tmp_dir/slot"
    local done_file="$tmp_dir/done"
    printf '0' > "$done_file"
    touch "$result_file"

    # ---- TUI init ------------------------------------------------------------
    if ! $no_tui; then
        if (( jobs > 1 )); then
            tput smcup 2>/dev/null || clear_screen
            _tui_status_board "$slot_base" "$total" "$done_file" &
            local board_pid=$!
        else
            tui_progress_init "Converting Videos — $hw_label"
        fi
    fi

    # ---- Semaphore encode loop -----------------------------------------------
    local file_index=0
    local -a pids=()
    local -a pid_slots=()

    for file in "${files[@]}"; do
        # Wait for a free slot when at capacity
        while (( ${#pids[@]} >= jobs )); do
            local new_pids=() new_slots=()
            local p s
            for (( i=0; i<${#pids[@]}; i++ )); do
                p=${pids[$i]}; s=${pid_slots[$i]}
                if kill -0 "$p" 2>/dev/null; then
                    new_pids+=("$p"); new_slots+=("$s")
                else
                    wait "$p" 2>/dev/null || true
                    rm -f "$slot_base.$s"
                    local done_count
                    done_count=$(cat "$done_file" 2>/dev/null || echo 0)
                    printf '%d' $(( done_count + 1 )) > "$done_file"
                fi
            done
            pids=("${new_pids[@]}"); pid_slots=("${new_slots[@]}")
            (( ${#pids[@]} >= jobs )) && sleep 0.1
        done

        # Find free slot index
        local slot=0
        while printf '%s' "${pid_slots[*]}" | grep -qw "$slot" 2>/dev/null; do
            (( slot++ ))
        done

        (( file_index++ )) || true
        local file_name
        file_name=$(basename "$file")

        # Serial TUI progress
        if ! $no_tui && (( jobs == 1 )); then
            local pct=$(( (file_index - 1) * 100 / total ))
            tui_progress_update "$pct" "Encoding [$file_index/$total]: $file_name"
        fi

        # Update slot label for status board
        printf '%s' "[$file_index/$total] $file_name" > "$slot_base.$slot"

        # Launch subshell
        ( _encode_file "$file" "$file_index" "$total" "$effective_hw" "$result_file" ) &
        pids+=("$!"); pid_slots+=("$slot")
    done

    # Drain remaining jobs
    for (( i=0; i<${#pids[@]}; i++ )); do
        wait "${pids[$i]}" 2>/dev/null || true
        rm -f "$slot_base.${pid_slots[$i]}"
        local done_count
        done_count=$(cat "$done_file" 2>/dev/null || echo 0)
        printf '%d' $(( done_count + 1 )) > "$done_file"
    done

    # ---- TUI teardown --------------------------------------------------------
    if ! $no_tui; then
        if (( jobs > 1 )); then
            kill "$board_pid" 2>/dev/null || true
            wait "$board_pid" 2>/dev/null || true
            tput rmcup 2>/dev/null || clear_screen
        else
            tui_progress_update 100 "All done!"; sleep 0.5; tui_progress_done
        fi
    fi

    # ---- Tally results -------------------------------------------------------
    local converted=0 skipped=0 failed=0 results_log=""
    while IFS= read -r line; do
        case "$line" in
            OK*)   (( converted++ )); results_log+=" OK   ${line#OK }\n" ;;
            SKIP*) (( skipped++  )); results_log+=" SKIP ${line#SKIP }\n" ;;
            FAIL*) (( failed++   )); results_log+=" FAIL ${line#FAIL }\n" ;;
            DRY*)  (( converted++)); results_log+=" DRY  ${line#DRY }\n" ;;
        esac
    done < "$result_file"

    rm -rf "$tmp_dir"

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
