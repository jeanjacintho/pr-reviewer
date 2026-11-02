. "$PR_REVIEWER_ROOT/tests/helpers.sh"

test_dashboard_node_suite() {
    node --test "$PR_REVIEWER_ROOT/dashboard/test" > "$TEST_TMP_ROOT/node-suite.log" 2>&1 || { cat "$TEST_TMP_ROOT/node-suite.log"; fail 'node --test failed'; }
}

# What the dashboard writes must be exactly what the bot's reader accepts.
test_dashboard_output_is_read_by_the_bot() {
    . "$PR_REVIEWER_ROOT/lib/common.sh"
    . "$PR_REVIEWER_ROOT/lib/repos.sh"
    STATE_DIR="$(mktmp)"
    PR_REVIEWER_REPOS="$STATE_DIR/repos.json"
    node -e '
        const { validateRepos } = require(process.argv[1] + "/dashboard/validate");
        const result = validateRepos({ repos: [
            { repo: "o/a", trusted_users: ["Alice", "bob"], engine: "claude", model: "gpt-x", effort: "high", depth: "deep", test_cmd: "npm ci && npm test" },
            { repo: "o/off", enabled: false, trusted_users: ["carol"] } ] });
        process.stdout.write(JSON.stringify(result.value));
    ' "$PR_REVIEWER_ROOT" > "$PR_REVIEWER_REPOS"
    assert_eq 'o/a' "$(repos_enabled)"
    repo_is_trusted o/a ALICE || fail 'alice trusted'
    assert_eq gpt-x "$(repo_model o/a)"
    assert_eq claude "$(repo_engine o/a)"
    assert_eq high "$(repo_effort o/a)"
    assert_eq deep "$(repo_depth o/a)"
    assert_eq quick "$(repo_depth o/off)"
    assert_eq codex "$(repo_engine o/off)"
    assert_eq 'npm ci && npm test' "$(repo_test_cmd o/a)"
}
