. "$PR_REVIEWER_ROOT/tests/support.sh"

# Replies for every stage, so a whole deep review can run against the fakes.
dt_angle_reply() {
    printf '### H1\nSeverity: %s\nClass: %s\nClaim: claim from %s\nFiles: `file:1`\nFailure path: failure path of %s\n' "$2" "$3" "$1" "$1"
}

dt_verify_reply() {
    printf '### H1\nAnswer: %s\nEvidence: `file:1` — checked\n' "$1"
}

# Clears everything a previous run left, so one test can run several reviews.
dt_reset() {
    : > "$FAKE_LOG"
    : > "$FAKE_POSTS"
    : > "$STATE_DIR/poll.log"
    rm -f "$STATE_DIR/reviewed.json"
    rm -rf "$FAKE_STAGES"
    mkdir -p "$FAKE_STAGES"
    printf 'The author is working towards a visible test goal.\n' > "$FAKE_STAGES/reply.intent"
    dt_angle_reply correctness blocking bug > "$FAKE_STAGES/reply.angle-correctness"
    dt_angle_reply security medium security > "$FAKE_STAGES/reply.angle-security"
    dt_angle_reply contracts medium contract > "$FAKE_STAGES/reply.angle-contracts"
    dt_angle_reply tests low tests > "$FAKE_STAGES/reply.angle-tests"
    dt_angle_reply simplification low simplification > "$FAKE_STAGES/reply.angle-simplification"
    dt_verify_reply yes > "$FAKE_STAGES/reply.verify-correctness"
    dt_verify_reply yes > "$FAKE_STAGES/reply.verify-security"
    dt_verify_reply unknown > "$FAKE_STAGES/reply.verify-contracts"
    dt_verify_reply yes > "$FAKE_STAGES/reply.verify-tests"
    dt_verify_reply no > "$FAKE_STAGES/reply.verify-simplification"
    printf 'DEEP-WRITEUP\nVERDICT: COMMENT\n' > "$FAKE_STAGES/reply.write-up"
}

dt_setup() {
    review_setup
    repos_set depth deep
    export FAKE_STAGES="$ROOT/stages"
    dt_reset
}

dt_run() {
    bash "$REVIEW_SCRIPT" "${1:-full}" o/r 7 command
}

# Number of engine calls the fakes saw.
dt_calls() {
    grep -cE "^$1 (exec|-p)" "$FAKE_LOG" || true
}

dt_overlap() {
    awk '$1 == "start" { running++; if (running > most) most = running } $1 == "end" { running-- } END { print most + 0 }' "$FAKE_STAGES/events"
}

dt_started() {
    if [ ! -e "$FAKE_STAGES/events" ]; then echo 0; return; fi
    grep -c "^start $1 " "$FAKE_STAGES/events" || true
}

test_deep_review_runs_every_stage_once_and_posts_one_comment() {
    dt_setup
    dt_run || fail review
    assert_eq 12 "$(dt_calls codex)"
    assert_one_review_comment
    assert_contains "$(cat "$FAKE_POSTS")" 'DEEP-WRITEUP'
    assert_contains "$(cat "$FAKE_POSTS")" "**Full review** at \`${HEAD_SHA:0:7}\`"
    assert_not_contains "$(cat "$FAKE_POSTS")" 'Partial review'
    assert_eq "$HEAD_SHA" "$(reviewed_get o/r 7)"
    assert_contains "$(cat "$FAKE_LOG")" 'content=HOORAY'
    assert_not_contains "$(cat "$STATE_DIR/poll.log")" 'Invalid DEEP_PARALLEL'
    assert_eq '' "$(ls -A "$WORK_DIR/wt")"
    assert_eq '' "$(pgrep -f "$FAKE_LOG.in" || true)"
}

test_deep_review_hands_only_checked_findings_to_the_write_up() {
    dt_setup
    dt_run || fail review
    local write_up="$(cat "$FAKE_STAGES/prompt.write-up")"
    assert_contains "$write_up" '<data name="verified-findings">'
    assert_contains "$write_up" 'correctness/H1'
    assert_contains "$write_up" 'security/H1'
    assert_contains "$write_up" 'contracts/H1'
    assert_contains "$write_up" 'tests/H1'
    assert_contains "$write_up" 'Verified: open'
    assert_not_contains "$write_up" 'simplification/H1'
    assert_contains "$write_up" 'a visible test goal'
    assert_contains "$(cat "$FAKE_STAGES/prompt.verify-correctness")" 'claim from correctness'
    assert_not_contains "$(cat "$FAKE_STAGES/prompt.verify-correctness")" 'claim from security'
    assert_contains "$(cat "$FAKE_STAGES/prompt.angle-security")" 'a visible test goal'
}

test_deep_intent_runs_beside_the_tests_and_angles_wait_for_them() {
    dt_setup
    export FAKE_WATCH="$ROOT/tests-done"
    repos_set test_cmd "sleep 1; touch $ROOT/tests-done"
    dt_run || fail review
    assert_contains "$(cat "$FAKE_STAGES/events")" 'start intent watch=no'
    assert_eq 1 "$(grep -c 'watch=no' "$FAKE_STAGES/events")"
    assert_contains "$(cat "$FAKE_STAGES/prompt.write-up")" 'exit 0'
}

test_deep_review_never_exceeds_the_parallel_limit() {
    dt_setup
    printf '0.3\n' > "$FAKE_STAGES/delay"
    printf '\nDEEP_PARALLEL=2\n' >> "$PR_REVIEWER_CONFIG"
    dt_run || fail two
    assert_eq 2 "$(dt_overlap)"
    dt_reset
    printf '0.2\n' > "$FAKE_STAGES/delay"
    printf '\nDEEP_PARALLEL=1\n' >> "$PR_REVIEWER_CONFIG"
    dt_run || fail one
    assert_eq 1 "$(dt_overlap)"
}

test_deep_angle_without_hypotheses_skips_its_verification() {
    dt_setup
    printf 'NO HYPOTHESES\n' > "$FAKE_STAGES/reply.angle-security"
    dt_run || fail review
    assert_eq 11 "$(dt_calls codex)"
    assert_eq 0 "$(dt_started verify-security)"
    assert_not_contains "$(cat "$FAKE_STAGES/prompt.write-up")" 'security/H1'
    assert_not_contains "$(cat "$FAKE_POSTS")" 'Partial review'
}

test_deep_review_survives_one_broken_angle() {
    local kind
    dt_setup
    for kind in fail garbage bad-verification fail-verification; do
        dt_reset
        case "$kind" in
            fail) : > "$FAKE_STAGES/fail.angle-security" ;;
            garbage) printf 'I looked and everything seems fine.\n' > "$FAKE_STAGES/reply.angle-security" ;;
            bad-verification) printf '### H1\nAnswer: yes\n' > "$FAKE_STAGES/reply.verify-security" ;;
            fail-verification) : > "$FAKE_STAGES/fail.verify-security" ;;
        esac
        dt_run || fail "$kind"
        assert_one_review_comment
        assert_contains "$(cat "$FAKE_POSTS")" 'Partial review: the security check did not finish.'
        assert_contains "$(cat "$FAKE_POSTS")" 'DEEP-WRITEUP'
        assert_contains "$(cat "$FAKE_STAGES/prompt.write-up")" 'correctness/H1'
        assert_not_contains "$(cat "$FAKE_STAGES/prompt.write-up")" 'security/H1'
        assert_eq "$HEAD_SHA" "$(reviewed_get o/r 7)"
    done
    assert_contains "$(cat "$STATE_DIR/poll.log")" 'Stage verify-security o/r#7 failed after'
}

test_deep_review_names_every_broken_angle() {
    dt_setup
    : > "$FAKE_STAGES/fail.angle-security"
    : > "$FAKE_STAGES/fail.angle-tests"
    dt_run || fail review
    assert_contains "$(cat "$FAKE_POSTS")" 'Partial review: the security, tests checks did not finish.'
}

test_deep_review_notes_come_before_the_review() {
    dt_setup
    : > "$FAKE_STAGES/fail.angle-security"
    reviewed_set o/r 7 deadbeef
    dt_run update || fail review
    assert_eq 'No usable previous review — doing a full review.' "$(head -n 1 "$FAKE_POSTS")"
    assert_eq 'Partial review: the security check did not finish.' "$(sed -n 3p "$FAKE_POSTS")"
}

test_deep_review_fails_when_every_angle_fails() {
    dt_setup
    local angle
    for angle in correctness security contracts tests simplification; do : > "$FAKE_STAGES/fail.angle-$angle"; done
    dt_run && fail all_angles
    assert_one_review_comment
    assert_contains "$(cat "$FAKE_POSTS")" 'Review failed:'
    assert_eq 0 "$(dt_started write-up)"
    assert_eq '' "$(reviewed_get o/r 7)"
}

test_deep_review_fails_when_the_write_up_fails() {
    local kind
    dt_setup
    for kind in fail invalid; do
        dt_reset
        case "$kind" in
            fail) : > "$FAKE_STAGES/fail.write-up" ;;
            invalid) printf 'A review without a verdict\n' > "$FAKE_STAGES/reply.write-up" ;;
        esac
        dt_run && fail "$kind"
        assert_one_review_comment
        assert_contains "$(cat "$FAKE_POSTS")" 'Review failed:'
        assert_not_contains "$(cat "$FAKE_POSTS")" 'A review without a verdict'
        assert_eq '' "$(reviewed_get o/r 7)"
        assert_eq '' "$(ls -A "$WORK_DIR/wt")"
    done
}

test_deep_stage_timeout_drops_only_that_angle() {
    dt_setup
    printf '\nSTAGE_TIMEOUT_SECS=2\n' >> "$PR_REVIEWER_CONFIG"
    printf '6\n' > "$FAKE_STAGES/slow.angle-tests"
    dt_run || fail review
    assert_contains "$(cat "$FAKE_POSTS")" 'Partial review: the tests check did not finish.'
    assert_eq 0 "$(dt_started verify-tests)"
    assert_eq '' "$(pgrep -f "$FAKE_LOG.in" || true)"
}

test_deep_review_goes_on_without_the_intent() {
    local kind
    dt_setup
    for kind in fail empty; do
        dt_reset
        if [ "$kind" = fail ]; then : > "$FAKE_STAGES/fail.intent"; else : > "$FAKE_STAGES/reply.intent"; fi
        dt_run || fail "$kind"
        assert_not_contains "$(cat "$FAKE_POSTS")" 'Partial review'
        assert_contains "$(cat "$FAKE_STAGES/prompt.angle-correctness")" 'Not available: the intent stage did not finish.'
        assert_contains "$(cat "$FAKE_STAGES/prompt.write-up")" 'Not available: the intent stage did not finish.'
    done
}

test_quick_depth_makes_a_single_engine_call() {
    review_setup
    repos_set depth quick
    bash "$REVIEW_SCRIPT" full o/r 7 command || fail review
    assert_eq 1 "$(dt_calls codex)"
    assert_not_contains "$(cat "$STATE_DIR/poll.log")" 'Stage '
}

test_unknown_depth_fails_visibly_without_running_anything() {
    review_setup
    repos_set depth thorough
    bash "$REVIEW_SCRIPT" full o/r 7 command && fail unknown_depth
    assert_one_review_comment
    assert_contains "$(cat "$FAKE_POSTS")" 'Review failed: The review engine failed'
    assert_eq 0 "$(dt_calls codex)"
    assert_contains "$(cat "$STATE_DIR/poll.log")" 'Unknown review depth for o/r'
}

test_deep_review_logs_how_long_each_stage_took() {
    dt_setup
    dt_run || fail review
    local stage
    for stage in intent angle-correctness verify-correctness angle-simplification verify-simplification write-up; do
        assert_contains "$(cat "$STATE_DIR/poll.log")" "Stage $stage o/r#7 took "
    done
}

test_deep_update_review_scopes_the_angles_to_the_new_commits() {
    dt_setup
    reviewed_set o/r 7 "$PRIOR_SHA"
    dt_run update || fail review
    assert_contains "$(cat "$FAKE_POSTS")" '**Update review** at '
    assert_contains "$(cat "$FAKE_STAGES/prompt.angle-correctness")" "Mode: update (since $PRIOR_SHA)"
    assert_contains "$(cat "$FAKE_STAGES/prompt.angle-correctness")" '<data name="full-diff">'
    perl -0777 -ne '($d)=/<data name="diff">(.*?)<\/data>/s; exit !($d =~ /second change/ && $d !~ /\+first change/)' "$FAKE_STAGES/prompt.angle-correctness" || fail scope
}

test_deep_review_runs_with_claude_code() {
    dt_setup
    repos_set engine claude
    dt_run || fail review
    assert_eq 12 "$(dt_calls claude)"
    assert_eq 0 "$(dt_calls codex)"
    assert_contains "$(cat "$FAKE_POSTS")" 'DEEP-WRITEUP'
    assert_eq "$WORK_DIR/wt/o+r-7-review" "$(cat "$FAKE_LOG.claude-pwd")"
}

test_invalid_deep_settings_fall_back_to_the_defaults() {
    dt_setup
    printf '\nDEEP_PARALLEL=0\n' >> "$PR_REVIEWER_CONFIG"
    run_with_timeout 90 bash "$REVIEW_SCRIPT" full o/r 7 command || fail parallel
    assert_contains "$(cat "$STATE_DIR/poll.log")" 'Invalid DEEP_PARALLEL or STAGE_TIMEOUT_SECS'
    assert_eq 12 "$(dt_calls codex)"
    dt_reset
    printf '\nDEEP_PARALLEL=2\nSTAGE_TIMEOUT_SECS=soon\n' >> "$PR_REVIEWER_CONFIG"
    run_with_timeout 90 bash "$REVIEW_SCRIPT" full o/r 7 command || fail timeout
    assert_contains "$(cat "$STATE_DIR/poll.log")" 'Invalid DEEP_PARALLEL or STAGE_TIMEOUT_SECS'
    assert_eq 12 "$(dt_calls codex)"
}

# Ends a review with SIGTERM while <stage> runs and checks nothing is left over.
dt_kill_during() {
    dt_reset
    printf '27\n' > "$FAKE_STAGES/slow.$1"
    bash "$REVIEW_SCRIPT" full o/r 7 command > /dev/null 2>&1 &
    local review=$! tries=0
    until grep -q "^start $1 " "$FAKE_STAGES/events" 2>/dev/null; do
        tries=$((tries + 1))
        [ "$tries" -lt 300 ] || { kill "$review"; fail "$1 never started"; }
        sleep 0.1
    done
    kill -TERM "$review"
    wait "$review" 2>/dev/null || true
    sleep 1
    assert_eq '' "$(pgrep -f "$FAKE_LOG.in" || true)" "left over after $1"
    assert_eq '' "$(pgrep -f 'sleep 27' || true)" "sleep left over after $1"
    assert_eq '' "$(ls -A "$WORK_DIR/wt")"
}

test_a_killed_deep_review_leaves_no_engine_running_in_any_stage() {
    dt_setup
    local stage
    for stage in intent angle-correctness verify-correctness write-up; do dt_kill_during "$stage"; done
    repos_set engine claude
    for stage in intent write-up; do dt_kill_during "$stage"; done
}

test_deep_review_does_not_start_without_the_mcp_lock_down() {
    dt_setup
    FAKE_CODEX_MCP_LIST=invalid dt_run && fail invalid_mcp
    assert_one_review_comment
    assert_contains "$(cat "$FAKE_POSTS")" 'Review failed:'
    assert_eq 0 "$(dt_calls codex)"
    assert_eq 0 "$(dt_started intent)"
    assert_contains "$(cat "$STATE_DIR/poll.log")" 'Stage intent o/r#7 failed after'
    assert_not_contains "$(cat "$STATE_DIR/poll.log")" 'Stage intent o/r#7 took'
}

test_deep_review_does_not_publish_what_a_failed_write_up_left_behind() {
    dt_setup
    : > "$FAKE_STAGES/failafter.write-up"
    dt_run && fail failed_write_up
    assert_one_review_comment
    assert_contains "$(cat "$FAKE_POSTS")" 'Review failed:'
    assert_not_contains "$(cat "$FAKE_POSTS")" 'DEEP-WRITEUP'
    assert_eq '' "$(reviewed_get o/r 7)"
}

test_deep_review_verifies_hypotheses_with_untidy_headers() {
    dt_setup
    printf '### H1 \r\nSeverity: medium\r\nClass: bug\r\nClaim: claim from security\r\nFiles: `file:1`\r\nFailure path: failure path of security\r\n' > "$FAKE_STAGES/reply.angle-security"
    dt_run || fail review
    assert_eq 1 "$(dt_started verify-security)"
    assert_contains "$(cat "$FAKE_STAGES/prompt.write-up")" 'security/H1'
}

test_deep_review_rejects_a_write_up_that_promotes_an_unverified_finding() {
    dt_setup
    local faithful bad
    faithful='1. [blocking] [bug] real <!-- src: correctness/H1 -->
2. [medium] [security] real <!-- src: security/H1 -->
3. [open] [contract] **Q: still unknown?** <!-- src: contracts/H1 -->
4. [low] [tests] real <!-- src: tests/H1 -->'
    for bad in \
        '1. [blocking] [bug] real <!-- src: correctness/H1 -->
2. [blocking] [contract] promoted from unknown <!-- src: contracts/H1 -->' \
        '1. [blocking] [contract] promoted from unknown <!-- src: contracts/H1 -->' \
        '1. [blocking] [bug] promoted from unknown and uncited'; do
        dt_reset
        printf '%s\nVERDICT: COMMENT\n' "$bad" > "$FAKE_STAGES/reply.write-up"
        dt_run && fail "published: $bad"
        assert_one_review_comment
        assert_contains "$(cat "$FAKE_POSTS")" 'Review failed:'
        assert_not_contains "$(cat "$FAKE_POSTS")" 'promoted from unknown'
        assert_contains "$(cat "$STATE_DIR/poll.log")" 'above what was verified'
    done
    dt_reset
    printf '%s\nVERDICT: COMMENT\n' "$faithful" > "$FAKE_STAGES/reply.write-up"
    dt_run || fail faithful
    assert_contains "$(cat "$FAKE_POSTS")" 'still unknown?'
}
