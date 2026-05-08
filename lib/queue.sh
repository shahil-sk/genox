# ==============================================================================
# lib/queue.sh — Queue processor, parallel engine, disk-space guard
# Depends on: config.sh, terminal.sh, tui.sh, notify.sh, hw.sh, codecs.sh
#
# Parallel design:
#   Each file is encoded in a subshell (background job).  Shared state cannot
#   be mutated directly, so every worker writes a small result record to a
#   private temp file under $WORK_DIR.  The coordinator loop (semaphore) caps
#   concurrency at $effective_jobs, waits for each worker, reads its result
#   file, and accumulates counters.  TUI mode shows a multi-slot status board
#   (one line per active slot); headless mode prints progress to stderr.
# ==============================================================================

# ------------------------------------------------------------------------------
# check_disk_space INPUT_DIR OUTPUT_DIR
# ------------------------------------------------------------------------------
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
        avail_hr=$(awk "BEGIN  { printf \"%.1f GB\", $avail_space / 1073741824 }")
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
# _run_hook FILE OUT_FILE — safe hook execution via env vars, no eval
# ------------------------------------------------------------------------------
_run_hook() {
    local in_file="$1" out_file="$2"
    [[ -z "$post_hook" ]] && return 0
    log "INFO" " Hook: $post_hook"
    INPUT="$in_file" OUTPUT="$out_file" \
        env bash -c "$post_hook" 2>>"$log_file" \
        || log "WARN" " Hook exited non-zero"
}

# ------------------------------------------------------------------------------
# _archive_source FILE — move source into a date-stamped archive subfolder
# ------------------------------------------------------------------------------
_archive_source() {
    local file="$1"
    local archive_dir="$media_in/archive/$(date +%Y-%m-%d)"
    mkdir -p "$archive_dir"
    mv "$file" "$archive_dir/"
    log "INFO" " Moved to archive: $archive_dir"
}

# ==============================================================================
# _worker  FILE SLOT TOTAL EFFECTIVE_HW WORK_DIR
#
# Runs entirely in a subshell.  Does NOT touch any parent-scope variables.
# On completion writes one line to $WORK_DIR/result.$SLOT:
#   STATUS|file_name|out_basename|in_size|out_size|duration_s|log_line
# STATUS ∈ { OK SKIP FAIL DRY }
# ==============================================================================
_worker() {
    local file="$1" slot="$2" total="$3" effective_hw="$4" work_dir="$5"
    local file_name result_file slot_file
    file_name=$(basename "$file")
    result_file="$work_dir/result.$slot"
    slot_file="$work_dir/slot.$slot"   # live status written here for the TUI board

    _wslot() { printf '%s' "$*" > "$slot_file"; }
    _wresult() { printf '%s\n' "$*" > "$result_file"; }

    _wslot "Probing: $file_name"

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

    local resolve_project
    resolve_project=$(probe_resolve_project "$file" 2>/dev/null || true)

    local container_format file_ext
    container_format=$(file -b --mime-type "$file" 2>/dev/null || echo "video/unknown")
    container_format="${container_format#*/}"
    file_ext=$(get_file_ext "$container_format")

    # ---- Skip guards ---------------------------------------------------------
    if [[ -z "$file_ext" ]]; then
        log "WARN" "Skip $file_name — unrecognized container"
        _wresult "SKIP|$file_name||||| SKIP  $file_name (unrecognized format)"
        _wslot "Done (skipped)"
        return 0
    fi
    if [[ ! " ${input_codecs[*]} " =~ " ${video_codec} " ]]; then
        log "INFO" "Skip $file_name — codec '$video_codec' not in list"
        _wresult "SKIP|$file_name||||| SKIP  $file_name (codec: $video_codec)"
        _wslot "Done (skipped)"
        return 0
    fi

    # ---- Build encoder args --------------------------------------------------
    local this_audio_enc this_video_enc
    this_audio_enc=$(get_audio_enc "$audio_codec" "$audio_enc_default")
    this_video_enc=$(hw_video_enc "$video_enc" "$effective_hw")
    [[ "$out_format" == "mp4" && "$this_video_enc" == *"libsvtav1"* ]] &&
        this_video_enc="$this_video_enc -g $keyframe_interval"
    [[ -n "$force_sample_rate" ]] && this_audio_enc="$this_audio_enc $force_sample_rate"

    local base_name out_file
    base_name=$(basename "$file_name" "$file_ext")
    out_file="$media_out/${base_name}.${out_format}"

    if [[ -f "$out_file" ]]; then
        log "INFO" "Skip $file_name — output exists"
        _wresult "SKIP|$file_name||||| SKIP  $file_name (output exists)"
        _wslot "Done (skipped)"
        return 0
    fi

    local project_note=""
    [[ -n "$resolve_project" ]] && project_note=" [project: $resolve_project]"
    log "INFO" "$file_name -> $(basename "$out_file")$project_note | workflow: ${workflow_label:-unknown}"

    # ---- Dry run -------------------------------------------------------------
    if $dry_run; then
        _wresult "DRY|$file_name|$(basename "$out_file")||| DRY   $file_name -> $(basename "$out_file")"
        _wslot "Done (dry run)"
        return 0
    fi

    # ---- Encode --------------------------------------------------------------
    local -a venc_args aenc_args map_args
    IFS=' ' read -r -a venc_args <<< "$this_video_enc"
    IFS=' ' read -r -a aenc_args <<< "$this_audio_enc"
    IFS=' ' read -r -a map_args  <<< "$pass_streams"

    local encode_start=$SECONDS
    local total_frames encode_ok=true
    total_frames=$(get_total_frames "$file" 2>/dev/null || echo 0)

    _wslot "0% $file_name"

    # Per-file progress via -progress pipe (only when there is a single job,
    # i.e. the TUI is driving one file at a time; with multiple parallel jobs
    # we use simple blocking ffmpeg and update the slot file from the fifo).
    local progress_fifo
    progress_fifo=$(mktemp -u /tmp/vc_prog_XXXXXX)
    mkfifo "$progress_fifo" 2>/dev/null || true

    ffmpeg -hide_banner -loglevel error \
        -i "$file" "${venc_args[@]}" "${aenc_args[@]}" \
        "${map_args[@]}" -progress "$progress_fifo" \
        "$out_file" 2>>"$log_file" &
    local ffmpeg_pid=$!

    if [[ -p "$progress_fifo" && "$total_frames" -gt 0 ]]; then
        local frame=0 fpct=0 elapsed eta_str start_ts=$SECONDS
        while IFS='=' read -r -t 5 key val <&7 || true; do
            [[ "$key" == "frame" ]] && frame="$val"
            [[ "$key" == "progress" && "$val" == "end" ]] && break
            fpct=$(awk "BEGIN { p=int($frame*100/$total_frames); print (p>100?100:p) }")
            elapsed=$(( SECONDS - start_ts ))
            if (( fpct > 0 && elapsed > 0 )); then
                eta_str=$(awk "BEGIN {
                    rem=int($elapsed*(100-$fpct)/$fpct);
                    printf \"%02d:%02d\", int(rem/60), rem%60
                }")
                _wslot "${fpct}% $file_name  ETA ${eta_str}"
            else
                _wslot "${fpct}% $file_name"
            fi
        done 7<"$progress_fifo"
    fi

    wait "$ffmpeg_pid" 2>/dev/null || encode_ok=false
    rm -f "$progress_fifo"

    # hw fallback
    if ! $encode_ok && [[ "$effective_hw" != "none" ]]; then
        log "WARN" "HW encode failed for $file_name, retrying in software"
        _wslot "SW retry: $file_name"
        rm -f "$out_file"
        encode_ok=true
        local -a sw_args
        IFS=' ' read -r -a sw_args <<< "$video_enc"
        ffmpeg -hide_banner -loglevel warning \
            -i "$file" "${sw_args[@]}" "${aenc_args[@]}" \
            "${map_args[@]}" "$out_file" 2>>"$log_file" || encode_ok=false
    fi

    local encode_dur=$(( SECONDS - encode_start ))

    # ---- Post-encode ---------------------------------------------------------
    if $encode_ok; then
        local in_sz out_sz
        in_sz=$(du -sh "$file"      2>/dev/null | awk '{print $1}' || echo "?")
        out_sz=$(du -sh "$out_file" 2>/dev/null | awk '{print $1}' || echo "?")
        log "INFO" " Done: $(basename "$out_file") | ${in_sz} → ${out_sz} | ${encode_dur}s"
        notify_success "Converted" "$file_name"
        $move_after && _archive_source "$file" || true
        _run_hook "$file" "$out_file"
        _wresult "OK|$file_name|$(basename "$out_file")|$in_sz|$out_sz|${encode_dur}s| OK    $file_name -> $(basename "$out_file")  [${in_sz} → ${out_sz}, ${encode_dur}s]"
        _wslot "Done ✓ $file_name"
    else
        log "ERROR" " Failed: $file_name"
        rm -f "$out_file"
        notify_error "Encode failed" "$file_name"
        _wresult "FAIL|$file_name||||| FAIL  $file_name"
        _wslot "FAILED $file_name"
    fi
}

# ==============================================================================
# _draw_parallel_board WORK_DIR SLOTS DONE TOTAL
# Redraws the multi-slot status board in-place (TUI parallel mode).
# ==============================================================================
_draw_parallel_board() {
    local work_dir="$1" slots="$2" done="$3" total="$4"
    local bw=$(( TW * 3 / 4 )); (( bw < 70 )) && bw=70
    local bh=$(( slots + 6 ))
    local br=$(( (TH - bh) / 2 ))
    local bc=$(( (TW - bw) / 2 ))

    clear_screen
    tui_box "$br" "$bc" "$bw" "$bh" "Parallel Encode — $done/$total done"

    move_to $(( br + 2 )) $(( bc + 2 ))
    printf '%sJobs: %d  |  Queue: %d/%d%s' "$C_YELLOW" "$slots" "$done" "$total" "$C_RESET"

    local s status_text
    for (( s=0; s<slots; s++ )); do
        local slot_file="$work_dir/slot.$s"
        status_text="idle"
        [[ -f "$slot_file" ]] && status_text=$(cat "$slot_file" 2>/dev/null || echo "idle")
        move_to $(( br + 4 + s )) $(( bc + 2 ))
        printf '%s[%d]%s %s%-*s%s' \
            "$C_CYAN$C_BOLD" "$(( s+1 ))" "$C_RESET" \
            "$C_WHITE" "$(( bw - 8 ))" "${status_text:0:$(( bw - 8 ))}" "$C_RESET"
    done

    move_to $(( br + bh - 2 )) $(( bc + 2 ))
    printf '%sCtrl+C to cancel%s' "$C_YELLOW" "$C_RESET"
}

# ==============================================================================
# process_queue — discovers files, runs parallel encode loop, reports summary
# ==============================================================================
process_queue() {
    mkdir -p "$media_in" "$media_out"

    # ---- Discover files ------------------------------------------------------
    local find_depth=(-maxdepth 1)
    ${recursive:-false} && find_depth=()

    local files=()
    while IFS= read -r -d '' f; do
        local mime
        mime=$(file -b --mime-type "$f" 2>/dev/null || true)
        [[ "$mime" == video/* ]] && files+=("$f")
    done < <(find "$media_in" "${find_depth[@]}" -type f -print0 2>/dev/null || true)

    local total="${#files[@]}"

    if [[ "$total" -eq 0 ]]; then
        $no_tui \
            && printf 'ERROR: No video files found in %s\n' "$media_in" >&2 \
            || tui_error "Queue Empty" "No video files found in:\n$media_in\n\nAdd videos and try again."
        log "WARN" "Queue is empty"
        return 0
    fi

    check_disk_space "$media_in" "$media_out" || return 0

    # ---- Queue preview (TUI only) --------------------------------------------
    if ! $no_tui; then
        local preview="" i=0
        for f in "${files[@]}"; do
            preview+="  $(basename "$f")\n"
            (( ++i >= 20 )) && { preview+="  … and $(( total - 20 )) more\n"; break; }
        done
        tui_confirm "Queue Preview" \
            "Found $total file(s), Proceed?" || return 0
    fi

    # ---- Hardware detection --------------------------------------------------
    local effective_hw="$hw_accel"
    if [[ "$hw_accel" == "auto" ]]; then
        local detected
        detected=$(detect_hw_encoders 2>/dev/null || echo "none")
        if   [[ "$detected" == *"nvenc"* ]];        then effective_hw="nvenc"
        elif [[ "$detected" == *"vaapi"* ]];        then effective_hw="vaapi"
        elif [[ "$detected" == *"amf"* ]];          then effective_hw="amf"
        elif [[ "$detected" == *"videotoolbox"* ]]; then effective_hw="videotoolbox"
        else effective_hw="none"; fi
        log "INFO" "HW auto-detect: $effective_hw"
    fi
    local hw_label="Software (CPU)"
    [[ "$effective_hw" != "none" ]] && hw_label="HW ($effective_hw)"

    # ---- Resolve effective job count -----------------------------------------
    local effective_jobs
    effective_jobs=$(resolve_parallel_jobs)
    # Safety: never run more jobs than files
    (( effective_jobs > total )) && effective_jobs=$total

    # ---- Confirmation (TUI mode) ---------------------------------------------
    if ! $no_tui; then
        local dry_note="" par_note=""
        $dry_run && dry_note="Nothing will be encoded!"
        (( effective_jobs > 1 )) && par_note="\nParallel jobs : $effective_jobs"
        tui_confirm "Confirm Conversion (DRY RUN)" \
            "Workflow : ${workflow_label:-custom} Encoder  : $hw_label${par_note} ${dry_note} Start?" \
            || return 0
    fi

    log "INFO" "Starting: $total files | workflow=${workflow_label:-custom} | hw=$effective_hw | jobs=$effective_jobs | dry_run=$dry_run"

    # ---- Temp workspace for worker result files ------------------------------
    local work_dir
    work_dir=$(mktemp -d /tmp/genox_XXXXXX)
    trap 'rm -rf "$work_dir"' RETURN

    # Initialise slot status files
    local s
    for (( s=0; s<effective_jobs; s++ )); do
        printf 'idle' > "$work_dir/slot.$s"
    done

    # ---- Parallel semaphore loop ---------------------------------------------
    local -a pids=()          # pid → slot index (pids[slot]=pid)
    local -a slot_file_idx=() # which file_index is running in each slot
    for (( s=0; s<effective_jobs; s++ )); do
        pids[$s]=0
        slot_file_idx[$s]=-1
    done

    local queue_idx=0         # next file to dispatch
    local done_count=0        # files fully processed (any status)
    local converted=0 skipped=0 failed=0
    local results_log=""

    # TUI: switch to parallel board; headless: nothing special
    if ! $no_tui; then
        tput smcup 2>/dev/null || clear_screen
        _draw_parallel_board "$work_dir" "$effective_jobs" "$done_count" "$total"
    fi

    # Helper: collect one finished worker
    _collect() {
        local slot="$1"
        local result_file="$work_dir/result.$slot"
        if [[ -f "$result_file" ]]; then
            local line status fname
            line=$(cat "$result_file" 2>/dev/null || true)
            status="${line%%|*}"
            local rest="${line#*|}"
            # rest format: fname|outbase|in_sz|out_sz|dur|log_line
            local log_line="${line##*|}"
            results_log+="$log_line\n"
            case "$status" in
                OK)   (( converted++ )) || true ;;
                SKIP) (( skipped++   )) || true ;;
                FAIL) (( failed++    )) || true ;;
                DRY)  (( converted++ )) || true ;;
            esac
            rm -f "$result_file"
        fi
        pids[$slot]=0
        slot_file_idx[$slot]=-1
        printf 'idle' > "$work_dir/slot.$slot"
        (( done_count++ )) || true
    }

    # Main dispatch loop
    while (( queue_idx < total || done_count < total )); do

        # Redraw board every iteration (TUI mode)
        if ! $no_tui; then
            _draw_parallel_board "$work_dir" "$effective_jobs" "$done_count" "$total"
        fi

        # ---- Try to fill idle slots with new work ----------------------------
        for (( s=0; s<effective_jobs; s++ )); do
            if (( pids[s] == 0 && queue_idx < total )); then
                local dispatch_file="${files[$queue_idx]}"
                slot_file_idx[$s]=$queue_idx

                if $no_tui; then
                    printf '[%d/%d] Dispatching (job %d): %s\n' \
                        "$(( queue_idx+1 ))" "$total" "$(( s+1 ))" \
                        "$(basename "$dispatch_file")" >&2
                fi

                # Launch worker subshell; export all globals it needs
                (
                    export log_file media_in media_out dry_run move_after post_hook
                    export no_tui force_sample_rate pass_streams workflow_label
                    export out_format audio_enc_default video_enc
                    export -f _worker _run_hook _archive_source probe_resolve_project \
                               get_audio_enc get_file_ext get_total_frames hw_video_enc \
                               log notify_success notify_error
                    # input_codecs is an array — pass as serialised string
                    export _INPUT_CODECS="${input_codecs[*]}"
                    # Re-hydrate array inside subshell
                    read -r -a input_codecs <<< "$_INPUT_CODECS"
                    _worker "$dispatch_file" "$s" "$total" "$effective_hw" "$work_dir"
                ) &
                pids[$s]=$!
                (( queue_idx++ )) || true
            fi
        done

        # ---- Check for finished workers -------------------------------------
        local any_finished=false
        for (( s=0; s<effective_jobs; s++ )); do
            if (( pids[s] != 0 )); then
                if ! kill -0 "${pids[$s]}" 2>/dev/null; then
                    wait "${pids[$s]}" 2>/dev/null || true
                    _collect "$s"
                    any_finished=true
                fi
            fi
        done

        # Avoid busy-spin: if no slot freed and queue is full, sleep briefly
        if ! $any_finished; then
            sleep 0.2
        fi
    done

    # ---- Teardown TUI --------------------------------------------------------
    if ! $no_tui; then
        _draw_parallel_board "$work_dir" "$effective_jobs" "$done_count" "$total"
        sleep 0.5
        tput rmcup 2>/dev/null || clear_screen
    fi

    # ---- Summary -------------------------------------------------------------
    local summary
    summary="Converted: $converted | Skipped: $skipped | Failed: $failed "
    # $dry_run && summary+="\n(DRY RUN -- nothing encoded)\n"
    log_summary="Log: $log_file"

    if $no_tui; then
        printf '%b\n' "$summary"
    else
        tui_info "$summary" "$log_summary"
    fi

    notify_success "Done" "Converted: $converted | Skipped: $skipped | Failed: $failed"
    log "INFO" "Done -- Converted: $converted, Skipped: $skipped, Failed: $failed, Jobs: $effective_jobs"
}

# ------------------------------------------------------------------------------
# view_log — show the tail of the current session log
# ------------------------------------------------------------------------------
view_log() {
    [[ ! -f "$log_file" ]] && { tui_info "No Log" "No log file yet."; return; }
    tui_scroll "Session Log" "$(tail -n 300 "$log_file")"
}
