. "$PR_REVIEWER_ROOT/tests/helpers.sh"

common_setup() {
    . "$PR_REVIEWER_ROOT/lib/common.sh"
    STATE_DIR="$(mktmp)"
}

test_common_marker_from_prefix() {
    common_setup
    CMD_PREFIX=foo
    . "$PR_REVIEWER_ROOT/lib/common.sh"
    assert_eq '<!-- foo-reviewer -->' "$MARKER"
}

test_common_timeout() {
    common_setup
    local rc=0
    run_with_timeout 1 sleep 3 || rc=$?
    assert_eq 124 "$rc"
    run_with_timeout 5 true || fail success
    run_with_timeout 5 sh -c 'exit 7' || rc=$?
    assert_eq 7 "$rc"
}

test_common_log_rotation() {
    common_setup
    log hello
    assert_contains "$(cat "$STATE_DIR/poll.log")" hello
    dd if=/dev/zero of="$STATE_DIR/poll.log" bs=1024 count=1025 2>/dev/null
    log rotated
    [ -f "$STATE_DIR/poll.log.1" ] || fail rotation
    assert_contains "$(cat "$STATE_DIR/poll.log")" rotated
}

test_common_loads_config_override() {
    local dir="$(mktmp)"
    printf 'CMD_PREFIX=custom\nREVIEW_TIMEOUT_SECS=5\n' > "$dir/settings"
    PR_REVIEWER_CONFIG="$dir/settings"
    . "$PR_REVIEWER_ROOT/lib/common.sh"
    assert_eq custom "$CMD_PREFIX"
    assert_eq 5 "$REVIEW_TIMEOUT_SECS"
}
