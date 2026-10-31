. "$PR_REVIEWER_ROOT/tests/support.sh"

memorize_setup() {
    review_setup
    MEMORIZE_SCRIPT="${REVIEW_SCRIPT%review.sh}memorize.sh"
    export FAKE_GH_BODY="/jeanjacintho-memorize Don't flag X"
    printf -- '- Existing rule (from o/r#1)\n' > "$ROOT/lessons.md"
}

test_memorize_saves_lesson() {
    memorize_setup
    cp "$ROOT/lessons.md" "$ROOT/old-lessons"
    printf -- '- Existing rule (from o/r#1)\n- Do not flag X (from o/r#7)\n' > "$FAKE_CODEX_OUT"
    bash "$MEMORIZE_SCRIPT" o/r 7 command || fail memorize
    assert_eq "$(cat "$FAKE_CODEX_OUT")" "$(cat "$ROOT/lessons.md")"
    assert_eq "$(cat "$ROOT/old-lessons")" "$(cat "$STATE_DIR/lessons.bak")"
    assert_contains "$(cat "$FAKE_POSTS")" 'Learned: - Do not flag X'
    assert_contains "$(cat "$FAKE_LOG.stdin")" 'o/r#7'
    assert_one_review_comment
}

test_memorize_empty_lesson() {
    memorize_setup
    FAKE_GH_BODY=/jeanjacintho-memorize
    bash "$MEMORIZE_SCRIPT" o/r 7 command || fail empty
    assert_contains "$(cat "$FAKE_POSTS")" 'Please include the lesson'
    assert_not_contains "$(cat "$FAKE_LOG")" 'codex '
}

test_memorize_invalid_keeps_lessons() {
    memorize_setup
    local before="$(cat "$ROOT/lessons.md")" i
    : > "$FAKE_CODEX_OUT"
    for i in $(seq 1 41); do printf -- '- Rule %s (from o/r#7)\n' "$i" >> "$FAKE_CODEX_OUT"; done
    if bash "$MEMORIZE_SCRIPT" o/r 7 command; then fail invalid; fi
    assert_eq "$before" "$(cat "$ROOT/lessons.md")"
    assert_contains "$(cat "$FAKE_POSTS")" "Couldn't save that lesson:"
    assert_one_review_comment
}

test_memorize_confirms_normalized_rule_when_already_known() {
    memorize_setup
    FAKE_GH_BODY='/jeanjacintho-memorize Não sinalize isso novamente'
    cp "$ROOT/lessons.md" "$FAKE_CODEX_OUT"
    bash "$MEMORIZE_SCRIPT" o/r 7 command || fail existing_rule
    assert_contains "$(cat "$FAKE_POSTS")" 'Learned: - Existing rule (from o/r#1)'
    assert_not_contains "$(cat "$FAKE_POSTS")" 'Não sinalize'
    assert_contains "$(cat "$FAKE_LOG")" '--skip-git-repo-check'
    assert_contains "$(cat "$FAKE_LOG")" '--disable shell_tool'
    assert_contains "$(cat "$FAKE_LOG")" '--disable view_image'
    assert_not_contains "$(cat "$FAKE_LOG")" 'content=EYES'
}

test_memorize_confirmation_failure_keeps_saved_lesson() {
    memorize_setup
    printf -- '- Normalized rule (from o/r#7)\n' > "$FAKE_CODEX_OUT"
    FAKE_GH_POST_EXIT=1 bash "$MEMORIZE_SCRIPT" o/r 7 command && fail confirmation_failure
    assert_eq "$(cat "$FAKE_CODEX_OUT")" "$(cat "$ROOT/lessons.md")"
    assert_contains "$(cat "$STATE_DIR/poll.log")" 'Lesson saved, but confirmation failed'
    assert_not_contains "$(cat "$STATE_DIR/poll.log")" "Couldn't save that lesson"
    assert_one_review_comment
}

test_memorize_failed_replacement_cleans_temporary_file() {
    memorize_setup
    local before="$(cat "$ROOT/lessons.md")"
    printf -- '- Normalized rule (from o/r#7)\n' > "$FAKE_CODEX_OUT"
    FAKE_CP_FAIL_DEST_MATCH='.lessons.' bash "$MEMORIZE_SCRIPT" o/r 7 command && fail replacement_failure
    assert_eq "$before" "$(cat "$ROOT/lessons.md")"
    if compgen -G "$ROOT/.lessons.*" > /dev/null; then fail temporary_file; fi
    assert_one_review_comment
}
