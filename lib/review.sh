review_cleanup() {
    trap - ERR
    set +e
    if [ -n "$TEST_PID" ]; then wait "$TEST_PID" 2>/dev/null; fi
    if [ -n "$TEST_WT" ]; then cleanup_worktree "$TEST_WT" >/dev/null 2>&1; fi
    if [ -n "$REVIEW_WT" ]; then cleanup_worktree "$REVIEW_WT" >/dev/null 2>&1; fi
    rm -rf "$REVIEW_TMP"
}

review_mode() {
    local requested="$1" exists=no
    LAST_SHA="$(reviewed_get "$REPO" "$PR")"
    if git -C "$REVIEW_WT" merge-base --is-ancestor "$LAST_SHA" "$HEAD_SHA" 2>/dev/null; then exists=yes; fi
    case "$requested" in full) requested=review ;; update) requested=update-review ;; *) return 1 ;; esac
    MODE="$(resolve_mode "$requested" "$HEAD_SHA" "$LAST_SHA" "$exists")"
    FALLBACK_NOTE=''
    if [ "$MODE" = fallback ]; then
        MODE=full
        FALLBACK_NOTE='No usable previous review — doing a full review.'
    fi
}

review_noop() {
    printf 'No new commits since last review.\n%s\n' "$MARKER" > "$REVIEW_TMP/comment"
    post_once "$REVIEW_TMP/comment"
    finish_reactions THUMBS_UP
}

execute_tests() {
    local rc=0
    (cd "$TEST_WT" && run_with_timeout "$TEST_TIMEOUT_SECS" bash -c "$1") > "$REVIEW_TMP/test.log" 2>&1 || rc=$?
    if [ "$rc" -eq 124 ]; then
        printf 'timed out after %ss\n' "$TEST_TIMEOUT_SECS"
    else
        printf 'exit %s\n' "$rc"
    fi
    tail -n 200 "$REVIEW_TMP/test.log"
}

review_tests_start() {
    local decision
    decision="$(test_decision "$REPO" "$(printf '%s' "$PR_JSON" | jq -r .author)")"
    case "$decision" in
        run*)
            TEST_WT="$(prepare_worktree "$REPO" "$PR" tests "$HEAD_SHA")"
            execute_tests "${decision#*$'\t'}" > "$TEST_RESULT_FILE" &
            TEST_PID=$! ;;
        skip-untrusted) printf 'Tests skipped: PR author is not in the trusted list.\n' > "$TEST_RESULT_FILE" ;;
        not-configured) printf 'Tests not configured for this repo.\n' > "$TEST_RESULT_FILE" ;;
    esac
}

review_data() {
    local base merge_base body
    base="$(printf '%s' "$PR_JSON" | jq -r .baseRefName)"
    merge_base="$(git -C "$REVIEW_WT" merge-base "origin/$base" "$HEAD_SHA")"
    git -C "$REVIEW_WT" diff --no-ext-diff --no-textconv "$merge_base" "$HEAD_SHA" > "$FULL_DIFF_FILE"
    if [ "$MODE" = update ]; then
        git -C "$REVIEW_WT" diff --no-ext-diff --no-textconv "$LAST_SHA" "$HEAD_SHA" > "$DIFF_FILE"
    else
        cp "$FULL_DIFF_FILE" "$DIFF_FILE"
    fi
    base_file "$REPO" "$base" REVIEW.md > "$REPO_REVIEW_MD_FILE"
    prev_review "$REPO" "$PR" > "$PREV_REVIEW_FILE"
    body="$(comment_body "$COMMENT_ID")"
    FOCUS="$(parse_command "$body")"
    FOCUS="${FOCUS#*$'\t'}"
    if [ -n "$TEST_PID" ]; then wait "$TEST_PID"; TEST_PID=''; fi
    build_review_prompt "$REVIEW_TMP/prompt" "$MODE"
}

review_run() {
    engine_text "$REPO" "$REVIEW_TIMEOUT_SECS" "$REVIEW_WT" "$REVIEW_TMP/output" "$REVIEW_TMP/prompt"
    validate_review "$REVIEW_TMP/output"
}

review_publish() {
    local label='Full review'
    if [ "$MODE" = update ]; then label='Update review'; fi
    {
        if [ -n "$FALLBACK_NOTE" ]; then printf '%s\n\n' "$FALLBACK_NOTE"; fi
        cat "$REVIEW_TMP/output"
        printf '\n\n<sub>%s at %s · `/%s-update-review` after your next push · `/%s-memorize <lesson>` to teach me</sub>\n%s\n' "$label" "${HEAD_SHA:0:7}" "$CMD_PREFIX" "$CMD_PREFIX" "$MARKER"
    } > "$REVIEW_TMP/comment"
    post_once "$REVIEW_TMP/comment"
    reviewed_set "$REPO" "$PR" "$HEAD_SHA"
    finish_reactions HOORAY
    log "Reviewed $REPO#$PR $HEAD_SHA ($MODE)"
}

review_main() {
    local requested="$1"
    REPO="$2" PR="$3" COMMENT_ID="$4"
    REVIEW_TMP="$(mktemp -d)"
    REVIEW_WT='' TEST_WT='' TEST_PID='' POST_ATTEMPTED=no HAS_EYES=yes
    trap review_cleanup EXIT
    trap 'command_failed "$?" "Review failed: $PHASE. Comment the command again to retry." "$REVIEW_TMP"' ERR
    PHASE='could not prepare PR'
    add_reaction EYES
    PR_JSON="$(pr_meta "$REPO" "$PR")"
    REVIEW_WT="$(prepare_worktree "$REPO" "$PR" review)"
    HEAD_SHA="$(git -C "$REVIEW_WT" rev-parse HEAD)"
    PR_JSON="$(printf '%s' "$PR_JSON" | jq --arg sha "$HEAD_SHA" '.headRefOid = $sha')"
    review_mode "$requested"
    if [ "$MODE" = noop ]; then review_noop; return; fi
    DIFF_FILE="$REVIEW_TMP/diff" FULL_DIFF_FILE="$REVIEW_TMP/full-diff"
    TEST_RESULT_FILE="$REVIEW_TMP/tests" PREV_REVIEW_FILE="$REVIEW_TMP/previous"
    REPO_REVIEW_MD_FILE="$REVIEW_TMP/base-rules"
    PHASE='could not prepare review context'
    review_tests_start
    review_data
    PHASE='The review engine failed, timed out, or returned an invalid review'
    review_run
    PHASE='could not publish review'
    review_publish
}
