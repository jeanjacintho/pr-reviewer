# Integration fixtures use only local git repositories and fake services.
local_origin() {
    FIXTURE_DIR="$(mktmp)"
    git init -q --bare "$FIXTURE_DIR/origin.git"
    git init -q -b main "$FIXTURE_DIR/seed"
    git -C "$FIXTURE_DIR/seed" config user.name Test
    git -C "$FIXTURE_DIR/seed" config user.email test@example.invalid
    printf 'Base instructions\n' > "$FIXTURE_DIR/seed/REVIEW.md"
    printf 'base\n' > "$FIXTURE_DIR/seed/file"
    git -C "$FIXTURE_DIR/seed" add .
    git -C "$FIXTURE_DIR/seed" commit -qm base
    BASE_SHA="$(git -C "$FIXTURE_DIR/seed" rev-parse HEAD)"
    git -C "$FIXTURE_DIR/seed" remote add origin "$FIXTURE_DIR/origin.git"
    git -C "$FIXTURE_DIR/seed" push -q origin main
    printf 'first change\n' >> "$FIXTURE_DIR/seed/file"
    printf 'Untrusted head instructions\n' > "$FIXTURE_DIR/seed/REVIEW.md"
    git -C "$FIXTURE_DIR/seed" commit -qam first
    PRIOR_SHA="$(git -C "$FIXTURE_DIR/seed" rev-parse HEAD)"
    printf 'second change\n' >> "$FIXTURE_DIR/seed/file"
    git -C "$FIXTURE_DIR/seed" commit -qam second
    HEAD_SHA="$(git -C "$FIXTURE_DIR/seed" rev-parse HEAD)"
    git -C "$FIXTURE_DIR/seed" push -q origin HEAD:refs/pull/7/head
    mkdir -p "$WORK_DIR/o"
    git clone -q --no-checkout "$FIXTURE_DIR/origin.git" "$WORK_DIR/o/r"
}

# Sets one field of the first repository in the fixture's repos.json.
repos_set() {
    jq --arg key "$1" --arg value "$2" '.repos[0][$key] = $value' "$ROOT/repos.json" > "$ROOT/repos.next"
    mv "$ROOT/repos.next" "$ROOT/repos.json"
}

review_setup() {
    local source_root="$PR_REVIEWER_ROOT"
    . "$source_root/tests/support.sh"
    . "$source_root/lib/common.sh"
    . "$source_root/lib/state.sh"
    export PR_REVIEWER_ROOT="$(mktmp)"
    ROOT="$PR_REVIEWER_ROOT" STATE_DIR="$PR_REVIEWER_ROOT/state" WORK_DIR="$PR_REVIEWER_ROOT/work"
    export PR_REVIEWER_CONFIG="$ROOT/config.sh"
    mkdir -p "$STATE_DIR"
    cp -R "$source_root/prompts" "$ROOT/prompts"
    cp "$source_root/rules.md" "$source_root/lessons.md" "$ROOT/"
    : > "$PR_REVIEWER_CONFIG"
    printf '{"repos":[{"repo":"o/r","trusted_users":["alice"]}]}\n' > "$ROOT/repos.json"
    export PATH="$source_root/tests/fakes:$PATH"
    export FAKE_LOG="$ROOT/fake.log" FAKE_POSTS="$ROOT/posts" FAKE_CODEX_OUT="$ROOT/output" FAKE_GH_META="$ROOT/meta" FAKE_GH_COMMENTS="$ROOT/comments"
    export FAKE_CODEX_MCP_LIST='[{"name":"local"}]'
    printf '[]' > "$FAKE_GH_COMMENTS"
    printf 'A valid review\nVERDICT: APPROVE\n' > "$FAKE_CODEX_OUT"
    : > "$FAKE_LOG"
    : > "$FAKE_POSTS"
    local_origin
    jq -n --arg sha "$HEAD_SHA" '{title:"A goal",body:"Description",author:{login:"alice"},baseRefName:"main",headRefOid:$sha,commits:[{messageHeadline:"first"},{messageHeadline:"second"}],files:[{path:"file"}]}' > "$FAKE_GH_META"
    REVIEW_SCRIPT="$source_root/review.sh"
}

assert_one_review_comment() {
    assert_eq 1 "$(grep -c '^===COMMENT===$' "$FAKE_POSTS")"
    assert_contains "$(cat "$FAKE_POSTS")" '<!-- jeanjacintho-reviewer -->'
}
