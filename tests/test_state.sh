state_setup() {
    . "$PR_REVIEWER_ROOT/lib/common.sh"
    . "$ROOT/lib/state.sh"
    STATE_DIR="$(mktmp)"
}

test_seen_roundtrip() {
    state_setup
    if seen_has X; then fail fresh; fi
    seen_add X || fail add
    seen_add X || fail duplicate
    seen_has X || fail missing
    if seen_has Y; then fail other; fi
    assert_eq '["X"]' "$(jq -c . "$STATE_DIR/seen.json")"
}

test_reviewed_roundtrip() {
    state_setup
    assert_eq '' "$(reviewed_get o/r 8)"
    reviewed_set o/r 7 abc || fail set
    assert_eq abc "$(reviewed_get o/r 7)"
    assert_eq '' "$(reviewed_get o/r 8)"
    reviewed_set o/r 7 def || fail replace
    assert_eq def "$(reviewed_get o/r 7)"
    assert_contains "$(jq -r '."o/r#7".at' "$STATE_DIR/reviewed.json")" T
}

test_state_invalid_json_is_not_replaced() {
    state_setup
    printf broken > "$STATE_DIR/seen.json"
    if seen_add X; then fail invalid; fi
    assert_eq broken "$(cat "$STATE_DIR/seen.json")"
}
