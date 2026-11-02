# Deep review: intent, then the angles (each followed by its verification),
# then the write-up. Stage output travels between stages as files in
# $DEEP_DIR; each stage is one engine call with its own timeout.

positive_or_default() {
    case "$1" in
        ''|*[!0-9]*|0*) printf '%s\n' "$2" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

deep_settings() {
    local parallel timeout
    parallel="$(positive_or_default "$DEEP_PARALLEL" 3)"
    timeout="$(positive_or_default "$STAGE_TIMEOUT_SECS" 600)"
    if [ "$parallel" != "$DEEP_PARALLEL" ] || [ "$timeout" != "$STAGE_TIMEOUT_SECS" ]; then
        log 'Invalid DEEP_PARALLEL or STAGE_TIMEOUT_SECS; using the default for each invalid one'
    fi
    DEEP_PARALLEL="$parallel"
    STAGE_TIMEOUT_SECS="$timeout"
}

# deep_stage <name> <stage> <output>: builds the stage prompt, runs the engine
# and logs how long it took.
deep_stage() {
    local name="$1" started rc=0
    started="$(date +%s)"
    build_stage_prompt "$DEEP_DIR/$name.prompt" "$2" "$MODE"
    engine_text "$REPO" "$STAGE_TIMEOUT_SECS" "$REVIEW_WT" "$3" "$DEEP_DIR/$name.prompt" || rc=$?
    if [ "$rc" -eq 0 ]; then
        log "Stage $name $REPO#$PR took $(($(date +%s) - started))s"
    else
        log "Stage $name $REPO#$PR failed after $(($(date +%s) - started))s"
    fi
    return "$rc"
}

# Runs a stage as a tracked job, so that cancelling the review ends its engine call.
deep_run_stage() {
    ( deep_stage "$@" ) &
    DEEP_PIDS="$!"
    if ! wait "$!"; then DEEP_PIDS=''; return 1; fi
    DEEP_PIDS=''
}

# One angle: its hypotheses, then their verification, then what survives.
deep_angle() {
    local angle="$1" hypotheses="$DEEP_DIR/hypotheses-$1" verification="$DEEP_DIR/verification-$1"
    deep_stage "angle-$angle" "angle-$angle" "$hypotheses"
    if ! validate_hypotheses "$hypotheses"; then
        log "Stage angle-$angle $REPO#$PR returned an invalid format"
        return 1
    fi
    if ! has_hypotheses "$hypotheses"; then
        : > "$DEEP_DIR/verified-$angle"
        return 0
    fi
    HYPOTHESES_FILE="$hypotheses" deep_stage "verify-$angle" verify "$verification"
    if ! validate_verification "$hypotheses" "$verification"; then
        log "Stage verify-$angle $REPO#$PR returned an invalid format"
        return 1
    fi
    merge_verified "$angle" "$hypotheses" "$verification" > "$DEEP_DIR/verified-$angle"
}

deep_wait_slot() {
    while [ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$DEEP_PARALLEL" ]; do sleep 0.2; done
}

deep_angle_jobs() {
    local angle
    for angle in $(deep_angles); do
        deep_wait_slot
        ( deep_angle "$angle"; : > "$DEEP_DIR/done-$angle" ) &
        DEEP_PIDS="$DEEP_PIDS $!"
    done
    wait
    DEEP_PIDS=''
}

# The intent is optional: without it, later stages say so and carry on.
deep_intent_finish() {
    if ! wait "$DEEP_PIDS"; then rm -f "$INTENT_FILE"; fi
    DEEP_PIDS=''
}

# Gathers the verified findings of the angles that finished and names the
# ones that did not. Fails when no angle finished.
deep_collect() {
    local angle finished=0
    DEEP_FAILED=''
    : > "$VERIFIED_FILE"
    for angle in $(deep_angles); do
        if [ -e "$DEEP_DIR/done-$angle" ]; then
            finished=$((finished + 1))
            cat "$DEEP_DIR/verified-$angle" >> "$VERIFIED_FILE"
        else
            DEEP_FAILED="${DEEP_FAILED:+$DEEP_FAILED, }$angle"
        fi
    done
    if [ "$finished" -eq 0 ]; then log "Every review angle failed for $REPO#$PR"; return 1; fi
    case "$DEEP_FAILED" in
        '') ;;
        *,*) PARTIAL_NOTE="Partial review: the $DEEP_FAILED checks did not finish." ;;
        *) PARTIAL_NOTE="Partial review: the $DEEP_FAILED check did not finish." ;;
    esac
}

deep_review() {
    DEEP_DIR="$REVIEW_TMP/deep" DEEP_PIDS='' PARTIAL_NOTE=''
    INTENT_FILE="$DEEP_DIR/intent" VERIFIED_FILE="$DEEP_DIR/verified"
    mkdir "$DEEP_DIR"
    deep_settings
    ( deep_stage intent intent "$INTENT_FILE" ) &
    DEEP_PIDS="$!"
    review_wait_tests
    deep_intent_finish
    deep_angle_jobs
    deep_collect
    deep_run_stage write-up write-up "$REVIEW_TMP/output"
    validate_review "$REVIEW_TMP/output"
    if ! validate_ceiling "$VERIFIED_FILE" "$REVIEW_TMP/output"; then
        log "The review of $REPO#$PR rates a finding above what was verified"
        return 1
    fi
}

deep_descendants() {
    local child
    for child in $(pgrep -P "$1" 2>/dev/null); do
        printf '%s\n' "$child"
        deep_descendants "$child"
    done
}

# Ends the stage jobs still running, with the engine calls they started.
deep_stop() {
    local pid
    for pid in ${DEEP_PIDS:-}; do
        kill "$pid" $(deep_descendants "$pid") 2>/dev/null
    done
    wait ${DEEP_PIDS:-} 2>/dev/null
}
