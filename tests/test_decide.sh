test_decision_modes() {
    . "$PR_REVIEWER_ROOT/lib/decide.sh"
    assert_eq full "$(resolve_mode review a a yes)"
    assert_eq update "$(resolve_mode update-review b a yes)"
    assert_eq noop "$(resolve_mode update-review a a yes)"
    assert_eq fallback "$(resolve_mode update-review b '' yes)"
    assert_eq fallback "$(resolve_mode update-review b a no)"
}

test_decision_tests() {
    . "$PR_REVIEWER_ROOT/lib/common.sh"
    . "$ROOT/lib/repos.sh"
    . "$ROOT/lib/decide.sh"
    STATE_DIR="$(mktmp)"
    PR_REVIEWER_REPOS="$STATE_DIR/repos.json"
    printf '%s\n' '{"repos":[{"repo":"o/r","trusted_users":["alice"],"test_cmd":"npm test"},{"repo":"o/other","trusted_users":["bob"],"test_cmd":"make"},{"repo":"x/y","trusted_users":["alice"]}]}' > "$PR_REVIEWER_REPOS"
    assert_eq $'run\tnpm test' "$(test_decision o/r ALICE)"
    assert_eq skip-untrusted "$(test_decision o/r mallory)"
    assert_eq skip-untrusted "$(test_decision o/other alice)"
    assert_eq not-configured "$(test_decision x/y alice)"
    assert_eq not-configured "$(test_decision unknown/repo alice)"
}
