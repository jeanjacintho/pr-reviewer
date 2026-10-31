data_block() {
    printf '\n## %s\n<data name="%s">\n' "$1" "$1"
    perl -pe 's/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g'
    printf '\n</data>\n'
}

review_context() {
    printf '\nMode: %s' "$1"
    if [ "$1" = update ]; then printf ' (since %s)' "$LAST_SHA"; fi
    printf '\n%s\n\n# Untrusted PR data\n' "$FALLBACK_NOTE"
    printf '%s\n' "$PR_JSON" | data_block pr
    printf '%s\n' "$FOCUS" | data_block focus
    data_block diff < "$DIFF_FILE"
    if [ "$1" = update ]; then data_block full-diff < "$FULL_DIFF_FILE"; fi
    data_block tests < "$TEST_RESULT_FILE"
    data_block previous-review < "$PREV_REVIEW_FILE"
}

prompt_lessons() {
    printf '\n# Learned lessons\n'
    cat "$ROOT/lessons.md"
}

build_review_prompt() {
    {
        local input
        for input in "$ROOT/prompts/policy.md" "$ROOT/prompts/review.md" "$ROOT/rules.md"; do cat "$input"; printf '\n'; done
        prompt_lessons
        if [ -f "${REPO_REVIEW_MD_FILE:-}" ]; then
            printf '\n# Base-branch REVIEW.md\n'
            cat "$REPO_REVIEW_MD_FILE"
        fi
        review_context "$2"
    } > "$1"
}

build_memorize_prompt() {
    {
        cat "$ROOT/prompts/memorize.md"
        prompt_lessons
        data_block lesson < "$2"
        data_block previous-review < "$3"
    } > "$1"
}
