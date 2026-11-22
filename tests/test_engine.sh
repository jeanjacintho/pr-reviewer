. "$PR_REVIEWER_ROOT/tests/helpers.sh"

engine_setup() {
    . "$PR_REVIEWER_ROOT/lib/common.sh"
    . "$PR_REVIEWER_ROOT/lib/repos.sh"
    . "$PR_REVIEWER_ROOT/lib/engine.sh"
    STATE_DIR="$(mktmp)"
    PR_REVIEWER_REPOS="$STATE_DIR/repos.json"
    export FAKE_LOG="$STATE_DIR/fake.log"
    : > "$FAKE_LOG"
}

test_engine_unknown_fails_without_running_anything() {
    engine_setup
    printf '%s\n' '{"repos":[{"repo":"o/a","engine":"other-cli"}]}' > "$PR_REVIEWER_REPOS"
    if engine_text o/a 5 "$STATE_DIR" "$STATE_DIR/out" "$STATE_DIR/prompt"; then fail 'unknown engine must fail'; fi
    assert_eq '' "$(cat "$FAKE_LOG")"
}

test_engine_error_line_picks_the_line_that_explains_the_failure() {
    engine_setup
    local out="$STATE_DIR/out"
    printf 'starting up\nFailed to authenticate: login expired\ngoodbye\n' > "$out"
    engine_error_line "$out" || fail status
    assert_eq 'Failed to authenticate: login expired' "$(engine_error_line "$out")"
    printf 'first error: old\nsecond error: newest\nplain tail\n' > "$out"
    assert_eq 'second error: newest' "$(engine_error_line "$out")"
}

test_engine_error_line_falls_back_to_the_last_line() {
    engine_setup
    local out="$STATE_DIR/out"
    printf 'hello\n\nthe last thing it said\n\n' > "$out"
    assert_eq 'the last thing it said' "$(engine_error_line "$out")"
}

test_engine_error_line_reads_the_log_when_there_is_no_output() {
    engine_setup
    local out="$STATE_DIR/out"
    : > "$out"
    printf 'codex: ERROR: no quota\n' > "$out.log"
    assert_eq 'codex: ERROR: no quota' "$(engine_error_line "$out")"
    printf 'output wins\n' > "$out"
    assert_eq 'output wins' "$(engine_error_line "$out")"
}

test_engine_error_line_is_empty_and_harmless_without_output() {
    engine_setup
    engine_error_line "$STATE_DIR/missing" || fail status
    assert_eq '' "$(engine_error_line "$STATE_DIR/missing")"
    printf '\n\n' > "$STATE_DIR/blank"
    assert_eq '' "$(engine_error_line "$STATE_DIR/blank")"
    printf '%0300d\n' 0 > "$STATE_DIR/long"
    assert_eq 200 "$(engine_error_line "$STATE_DIR/long" | tr -d '\n' | wc -c | tr -d ' ')"
}
