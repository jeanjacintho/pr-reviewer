workspace_setup() {
    . "$PR_REVIEWER_ROOT/tests/support.sh"
    . "$PR_REVIEWER_ROOT/lib/common.sh"
    . "$PR_REVIEWER_ROOT/lib/workspace.sh"
    WORK_DIR="$(mktmp)"
    local_origin
}

test_worktree_from_pull_ref() {
    workspace_setup
    local path
    path="$(prepare_worktree o/r 7 review)" || fail prepare
    assert_eq "$HEAD_SHA" "$(git -C "$path" rev-parse HEAD)"
    sha_exists o/r "$HEAD_SHA" || fail exists
    if sha_exists o/r deadbeef; then fail missing; fi
    assert_eq 'Base instructions' "$(base_file o/r main REVIEW.md)"
    assert_eq '' "$(base_file o/r main missing.md)"
    cleanup_worktree "$path" || fail cleanup
    [ ! -d "$path" ] || fail left
}

test_worktree_first_clone_and_pinned_tests() {
    workspace_setup
    export FAKE_LOG="$FIXTURE_DIR/gh.log" FAKE_GH_ORIGIN="$FIXTURE_DIR/origin.git"
    rm -rf "$WORK_DIR/o/r"
    local path tests_path
    path="$(prepare_worktree o/r 7 review)" || fail clone
    assert_eq "$HEAD_SHA" "$(git -C "$path" rev-parse HEAD)"
    assert_contains "$(cat "$FAKE_LOG")" 'gh repo clone o/r'
    path="$(prepare_worktree o/r 7 review)" || fail stale_worktree
    tests_path="$(prepare_worktree o/r 7 tests "$PRIOR_SHA")" || fail tests_worktree
    assert_eq "$PRIOR_SHA" "$(git -C "$tests_path" rev-parse HEAD)"
    cleanup_worktree "$path" || fail review_cleanup
    cleanup_worktree "$tests_path" || fail tests_cleanup
    base_file o/r main missing.md > "$FIXTURE_DIR/missing" || fail missing_base_file
    assert_eq '' "$(cat "$FIXTURE_DIR/missing")"
}

test_worktree_recovers_missing_registered_directory() {
    workspace_setup
    local path
    path="$(prepare_worktree o/r 7 review)" || fail prepare
    rm -rf "$path"
    path="$(prepare_worktree o/r 7 review)" || fail stale_registration
    assert_eq "$HEAD_SHA" "$(git -C "$path" rev-parse HEAD)"
    cleanup_worktree "$path" || fail cleanup
}
