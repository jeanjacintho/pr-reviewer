. "$PR_REVIEWER_ROOT/tests/helpers.sh"

repos_setup() {
    . "$PR_REVIEWER_ROOT/lib/common.sh"
    . "$PR_REVIEWER_ROOT/lib/repos.sh"
    STATE_DIR="$(mktmp)"
    PR_REVIEWER_REPOS="$STATE_DIR/repos.json"
    printf '%s\n' "$1" > "$PR_REVIEWER_REPOS"
}

REPOS_FIXTURE='{"repos":[
  {"repo":"o/a","enabled":true,"trusted_users":["Alice","bob"],"model":"gpt-x","test_cmd":"npm test"},
  {"repo":"o/b","trusted_users":["carol"]},
  {"repo":"o/off","enabled":false,"trusted_users":["alice"]},
  {"repo":"not a repo","trusted_users":["alice"]},
  {"repo":"o/bad","trusted_users":["al ice","$(touch x)","","Dave"],"model":"bad model;rm"}
]}'

test_repos_enabled_skips_disabled_and_invalid() {
    repos_setup "$REPOS_FIXTURE"
    assert_eq 'o/a
o/b
o/bad' "$(repos_enabled)"
}

test_repos_trust_is_per_repo() {
    repos_setup "$REPOS_FIXTURE"
    repo_is_trusted o/a alice || fail 'alice trusted in o/a'
    repo_is_trusted O/A BOB || fail 'lookup and login ignore case'
    if repo_is_trusted o/b alice; then fail 'alice must not be trusted in o/b'; fi
    if repo_is_trusted o/unknown alice; then fail 'unknown repo trusts nobody'; fi
    if repo_is_trusted o/a ''; then fail 'empty login is never trusted'; fi
    assert_eq 'alice
bob' "$(repo_trusted_users o/a)"
}

test_repos_ignores_malformed_logins() {
    repos_setup "$REPOS_FIXTURE"
    assert_eq 'dave' "$(repo_trusted_users o/bad)"
}

test_repos_model_is_the_repository_own() {
    repos_setup "$REPOS_FIXTURE"
    CODEX_MODEL=global-model
    assert_eq gpt-x "$(repo_model o/a)"
    assert_eq '' "$(repo_model o/b)"
    assert_eq '' "$(repo_model o/bad)"
}

test_repos_test_cmd() {
    repos_setup "$REPOS_FIXTURE"
    assert_eq 'npm test' "$(repo_test_cmd o/a)"
    assert_eq '' "$(repo_test_cmd o/b)"
}

test_repos_missing_file_yields_nothing() {
    repos_setup '{}'
    rm "$PR_REVIEWER_REPOS"
    repos_enabled || fail 'a missing file is not an error'
    assert_eq '' "$(repos_enabled)"
    if repo_is_trusted o/a alice; then fail 'no file trusts nobody'; fi
}

test_repos_trusted_users_must_be_an_array() {
    repos_setup '{"repos":[{"repo":"o/a","trusted_users":{"x":"mallory"}},{"repo":"o/b","trusted_users":"mallory"},{"repo":"o/c"}]}'
    if repo_is_trusted o/a mallory; then fail 'object values must not be trusted'; fi
    if repo_is_trusted o/b mallory; then fail 'a string must not be trusted'; fi
    assert_eq '' "$(repo_trusted_users o/c)"
    assert_eq 'o/a
o/b
o/c' "$(repos_enabled)"
}

test_repos_rejects_path_traversal_names() {
    repos_setup '{"repos":[{"repo":"../r"},{"repo":"o/.."},{"repo":"./r"},{"repo":"o/."},{"repo":"o/.hidden"},{"repo":"o/ok"}]}'
    assert_eq 'o/.hidden
o/ok' "$(repos_enabled)"
}

test_repos_rejects_values_with_a_trailing_newline() {
    repos_setup '{"repos":[{"repo":"o/a\n","trusted_users":["alice"]},{"repo":"o/b","trusted_users":["bob\n","carol"],"model":"m\n"}]}'
    assert_eq 'o/b' "$(repos_enabled)"
    assert_eq 'carol' "$(repo_trusted_users o/b)"
    assert_eq '' "$(repo_model o/b)"
}

test_repos_trailing_garbage_discards_everything() {
    repos_setup '{"repos":[{"repo":"o/a","trusted_users":["alice"]}]} trailing'
    assert_eq '' "$(repos_enabled)"
    if repo_is_trusted o/a alice; then fail 'partially parsed file must trust nobody'; fi
    assert_contains "$(cat "$STATE_DIR/poll.log")" 'Invalid repos file'
}

test_repos_bad_json_is_logged_not_fatal() {
    repos_setup '{not json'
    assert_eq '' "$(repos_enabled)"
    if repo_is_trusted o/a alice; then fail 'bad json trusts nobody'; fi
    assert_contains "$(cat "$STATE_DIR/poll.log")" 'Invalid repos file'
}

test_repos_engine_defaults_to_codex_and_rejects_unknown() {
    repos_setup '{"repos":[{"repo":"o/a"},{"repo":"o/b","engine":"claude"},{"repo":"o/c","engine":"other-cli"},{"repo":"o/d","engine":5}]}'
    assert_eq codex "$(repo_engine o/a)"
    assert_eq claude "$(repo_engine O/B)"
    assert_eq '' "$(repo_engine o/c)"
    assert_eq '' "$(repo_engine o/d)"
}

test_repos_effort_is_a_plain_word() {
    repos_setup '{"repos":[{"repo":"o/a","effort":"high"},{"repo":"o/b"},{"repo":"o/c","effort":"high; rm -rf"},{"repo":"o/d","effort":"low\n"}]}'
    assert_eq high "$(repo_effort o/a)"
    assert_eq '' "$(repo_effort o/b)"
    assert_eq '' "$(repo_effort o/c)"
    assert_eq '' "$(repo_effort o/d)"
}
