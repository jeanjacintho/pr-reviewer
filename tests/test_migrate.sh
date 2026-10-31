migrate_setup() {
    . "$PR_REVIEWER_ROOT/lib/migrate.sh"
    MIGRATE_DIR="$(mktmp)"
}

test_migrate_legacy_arrays_become_per_repo_settings() {
    migrate_setup
    cat > "$MIGRATE_DIR/config.sh" <<'CONFIG'
REPOS=(o/a o/b)
TRUSTED_USERS=(alice bob)
TEST_CMDS=("o/b|npm ci && npm test" "x/y|make")
CODEX_MODEL="global"
CONFIG
    local expected='{"repos":[
      {"repo":"o/a","enabled":true,"trusted_users":["alice","bob"],"model":"","test_cmd":""},
      {"repo":"o/b","enabled":true,"trusted_users":["alice","bob"],"model":"","test_cmd":"npm ci && npm test"}]}'
    assert_eq "$(printf '%s' "$expected" | jq -S .)" "$(migrate_legacy_config "$MIGRATE_DIR/config.sh" | jq -S .)"
}

test_migrate_empty_arrays_yield_no_repos() {
    migrate_setup
    printf 'CMD_PREFIX=foo\n' > "$MIGRATE_DIR/config.sh"
    assert_eq '{"repos":[]}' "$(migrate_legacy_config "$MIGRATE_DIR/config.sh" | jq -c .)"
}

test_migrate_keeps_commands_with_quotes_and_pipes() {
    migrate_setup
    cat > "$MIGRATE_DIR/config.sh" <<'CONFIG'
REPOS=(o/a)
TEST_CMDS=("o/a|echo \"hi\" | cat; exit 3")
CONFIG
    assert_eq 'echo "hi" | cat; exit 3' "$(migrate_legacy_config "$MIGRATE_DIR/config.sh" | jq -r '.repos[0].test_cmd')"
}
