. "$PR_REVIEWER_ROOT/tests/support.sh"

test_review_full_posts_once() {
    review_setup
    bash "$REVIEW_SCRIPT" full o/r 7 command || fail review
    assert_one_review_comment
    assert_eq "$HEAD_SHA" "$(reviewed_get o/r 7)"
    assert_contains "$(cat "$FAKE_POSTS")" '<sub>Full review at '
    assert_contains "$(cat "$FAKE_LOG")" 'content=EYES'
    assert_contains "$(cat "$FAKE_LOG")" 'content=HOORAY'
    assert_contains "$(cat "$FAKE_LOG")" 'removeReaction(input:'
    assert_not_contains "$(cat "$FAKE_LOG")" '-m '
    assert_not_contains "$(cat "$FAKE_LOG")" '--skip-git-repo-check'
    assert_not_contains "$(cat "$STATE_DIR/poll.log")" 'Could not '
    assert_contains "$(cat "$FAKE_LOG.stdin")" 'Tests not configured'
    assert_contains "$(cat "$FAKE_LOG.stdin")" 'Base instructions'
    perl -0777 -ne '($policy)=split /# Untrusted PR data/; exit($policy =~ /Untrusted head instructions/)' "$FAKE_LOG.stdin" || fail base_rules
    assert_eq '' "$(ls -A "$WORK_DIR/wt")"
}

test_review_update_noop_skips_codex() {
    review_setup
    reviewed_set o/r 7 "$HEAD_SHA"
    bash "$REVIEW_SCRIPT" update o/r 7 command || fail noop
    assert_one_review_comment
    assert_eq 'No new commits since last review.' "$(head -n 1 "$FAKE_POSTS")"
    assert_not_contains "$(cat "$FAKE_LOG")" 'codex '
}

test_review_update_and_fallback() {
    review_setup
    reviewed_set o/r 7 "$PRIOR_SHA"
    bash "$REVIEW_SCRIPT" update o/r 7 command || fail update
    assert_contains "$(cat "$FAKE_LOG.stdin")" "Mode: update (since $PRIOR_SHA)"
    assert_contains "$(cat "$FAKE_POSTS")" '<sub>Update review at '
    perl -0777 -ne '($d)=/<data name="diff">(.*?)<\/data>/s; exit !($d =~ /second change/ && $d !~ /\+first change/)' "$FAKE_LOG.stdin" || fail scope
    reviewed_set o/r 7 deadbeef
    bash "$REVIEW_SCRIPT" update o/r 7 command || fail fallback
    assert_contains "$(cat "$FAKE_LOG.stdin")" 'Mode: full'
    assert_contains "$(cat "$FAKE_POSTS")" 'No usable previous review'
}

test_review_codex_failures() {
    review_setup
    local kind
    for kind in exit invalid timeout; do
        : > "$FAKE_POSTS"
        export FAKE_CODEX_EXIT=0 FAKE_CODEX_SLEEP=0
        case "$kind" in
            exit) FAKE_CODEX_EXIT=1 ;;
            invalid) printf invalid > "$FAKE_CODEX_OUT" ;;
            timeout) FAKE_CODEX_SLEEP=3; printf '\nREVIEW_TIMEOUT_SECS=1\n' >> "$PR_REVIEWER_CONFIG" ;;
        esac
        if bash "$REVIEW_SCRIPT" full o/r 7 command; then fail "$kind"; fi
        assert_one_review_comment
        assert_contains "$(cat "$FAKE_POSTS")" 'Review failed:'
        assert_contains "$(cat "$FAKE_LOG")" 'codex exec'
        assert_contains "$(cat "$FAKE_LOG")" 'content=CONFUSED'
        assert_not_contains "$(cat "$STATE_DIR/poll.log")" 'Could not post failure comment'
        assert_eq '' "$(reviewed_get o/r 7)"
        assert_eq '' "$(ls -A "$WORK_DIR/wt")"
    done
}

test_review_test_author_gate() {
    review_setup
    printf '\nTEST_CMDS=("o/r|echo hi; exit 3")\n' >> "$PR_REVIEWER_CONFIG"
    bash "$REVIEW_SCRIPT" full o/r 7 command || fail trusted
    assert_contains "$(cat "$FAKE_LOG.stdin")" 'exit 3'
    assert_contains "$(cat "$FAKE_LOG.stdin")" hi
    jq '.author.login="mallory"' "$FAKE_GH_META" > "$ROOT/meta.next"
    mv "$ROOT/meta.next" "$FAKE_GH_META"
    printf '\nTEST_CMDS=("o/r|touch %s/should-not-exist")\n' "$ROOT" >> "$PR_REVIEWER_CONFIG"
    bash "$REVIEW_SCRIPT" full o/r 7 command || fail untrusted
    [ ! -e "$ROOT/should-not-exist" ] || fail executed
    assert_contains "$(cat "$FAKE_LOG.stdin")" 'Tests skipped: PR author is not in the trusted list.'
    assert_eq '' "$(ls -A "$WORK_DIR/wt")"
}

test_review_codex_isolation_and_model_override() {
    review_setup
    printf '\nCODEX_MODEL=fake-model\n' >> "$PR_REVIEWER_CONFIG"
    export FAKE_CODEX_MCP_LIST='[{"name":"dangerous.server","enabled":true},{"name":"other","enabled":true}]'
    bash "$REVIEW_SCRIPT" full o/r 7 command || fail isolated_review
    local calls="$(cat "$FAKE_LOG")"
    assert_contains "$calls" '--sandbox read-only'
    assert_contains "$calls" '--disable apps'
    assert_contains "$calls" '--disable plugins'
    assert_contains "$calls" '--disable hooks'
    assert_contains "$calls" '--disable browser_use'
    assert_contains "$calls" '--disable image_generation'
    assert_contains "$calls" '--disable multi_agent'
    assert_contains "$calls" 'web_search="disabled"'
    assert_contains "$calls" 'trust_level="untrusted"'
    assert_contains "$calls" 'mcp_servers={"dangerous.server"={enabled=false},"other"={enabled=false}}'
    assert_contains "$calls" "projects={\"$WORK_DIR/wt/o+r-7-review\"={trust_level=\"untrusted\"}}"
    assert_not_contains "$calls" 'projects."'
    assert_contains "$calls" '-m fake-model'
    assert_not_contains "$calls" '--skip-git-repo-check'
}

test_review_github_failure_does_not_publish_twice() {
    review_setup
    FAKE_GH_FAIL_MATCH='pr view' bash "$REVIEW_SCRIPT" full o/r 7 command && fail metadata_failure
    assert_one_review_comment
    assert_contains "$(cat "$FAKE_POSTS")" 'Review failed:'
    assert_not_contains "$(cat "$FAKE_LOG")" 'codex '
    : > "$FAKE_POSTS"
    FAKE_GH_POST_EXIT=1 bash "$REVIEW_SCRIPT" full o/r 7 command && fail post_failure
    assert_one_review_comment
    assert_eq '' "$(reviewed_get o/r 7)"
}

test_review_waits_for_tests_before_error_cleanup() {
    review_setup
    printf '\nTEST_CMDS=("o/r|sleep 1; touch %s/test-completed")\n' "$ROOT" >> "$PR_REVIEWER_CONFIG"
    FAKE_GH_FAIL_MATCH='/comments' bash "$REVIEW_SCRIPT" full o/r 7 command && fail context_failure
    [ -e "$ROOT/test-completed" ] || fail pending_tests
    assert_eq '' "$(ls -A "$WORK_DIR/wt")"
    assert_one_review_comment
}

test_review_reaction_failure_is_logged() {
    review_setup
    FAKE_GH_FAIL_MATCH=content=EYES bash "$REVIEW_SCRIPT" full o/r 7 command || fail reaction_failure
    assert_contains "$(cat "$STATE_DIR/poll.log")" 'Could not add reaction'
    assert_eq "$HEAD_SHA" "$(reviewed_get o/r 7)"
    FAKE_GH_FAIL_MATCH=removeReaction bash "$REVIEW_SCRIPT" full o/r 7 command || fail remove_failure
    assert_contains "$(cat "$STATE_DIR/poll.log")" 'Could not remove reaction'
}

test_review_empty_or_invalid_mcp_configuration() {
    review_setup
    export FAKE_CODEX_MCP_LIST='[]'
    run_with_timeout 10 bash "$REVIEW_SCRIPT" full o/r 7 command || fail empty_mcp
    assert_one_review_comment
    : > "$FAKE_LOG"
    : > "$FAKE_POSTS"
    FAKE_CODEX_MCP_LIST=invalid bash "$REVIEW_SCRIPT" full o/r 7 command && fail invalid_mcp
    assert_one_review_comment
    assert_not_contains "$(cat "$FAKE_LOG")" 'codex exec'
}

test_review_force_push_with_cached_old_sha_falls_back() {
    review_setup
    reviewed_set o/r 7 "$PRIOR_SHA"
    git -C "$FIXTURE_DIR/seed" checkout -qb rewritten "$BASE_SHA"
    printf 'rewritten change\n' >> "$FIXTURE_DIR/seed/file"
    git -C "$FIXTURE_DIR/seed" commit -qam rewritten
    local rewritten="$(git -C "$FIXTURE_DIR/seed" rev-parse HEAD)"
    git -C "$FIXTURE_DIR/seed" push -q --force origin HEAD:refs/pull/7/head
    git -C "$WORK_DIR/o/r" cat-file -e "$PRIOR_SHA^{commit}" || fail cached_sha
    bash "$REVIEW_SCRIPT" update o/r 7 command || fail force_push
    assert_eq 'No usable previous review — doing a full review.' "$(head -n 1 "$FAKE_POSTS")"
    assert_contains "$(cat "$FAKE_LOG.stdin")" 'Mode: full'
    assert_eq "$rewritten" "$(reviewed_get o/r 7)"
}

test_review_invalid_mode_posts_error_without_codex() {
    review_setup
    bash "$REVIEW_SCRIPT" invalid o/r 7 command && fail invalid_mode
    assert_one_review_comment
    assert_contains "$(cat "$FAKE_POSTS")" 'Review failed:'
    assert_not_contains "$(cat "$FAKE_LOG")" 'codex '
}
