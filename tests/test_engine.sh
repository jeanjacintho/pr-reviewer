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
