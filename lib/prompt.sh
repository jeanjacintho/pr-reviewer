data_block() {
    printf '\n## %s\n<data name="%s">\n' "$1" "$1"
    perl -pe 's/&/&amp;/g; s/</&lt;/g; s/>/&gt;/g'
    printf '\n</data>\n'
}

context_head() {
    printf '\nMode: %s' "$1"
    if [ "$1" = update ]; then printf ' (since %s)' "$LAST_SHA"; fi
    printf '\n%s\n\n# Untrusted PR data\n' "$FALLBACK_NOTE"
}

# The diff to review, plus the whole-PR diff as reading context when updating.
diff_blocks() {
    data_block diff < "$DIFF_FILE"
    if [ "$1" = update ]; then data_block full-diff < "$FULL_DIFF_FILE"; fi
}

review_context() {
    local block
    context_head "$1"
    for block in pr focus diff tests previous-review; do emit_block "$block" "$1"; done
}

prompt_lessons() {
    printf '\n# Learned lessons\n'
    cat "$ROOT/lessons.md"
}

# Prints each file named on stdin, one per line, followed by a blank line.
cat_each() {
    local file
    while IFS= read -r file; do
        cat "$file"
        printf '\n'
    done
}

# Lessons and the base branch's own REVIEW.md, which every prompt carries.
prompt_standing() {
    prompt_lessons
    if [ -f "${REPO_REVIEW_MD_FILE:-}" ]; then
        printf '\n# Base-branch REVIEW.md\n'
        cat "$REPO_REVIEW_MD_FILE"
    fi
}

build_review_prompt() {
    {
        printf '%s\n' "$ROOT/prompts/policy.md" "$ROOT/prompts/review.md" "$ROOT/rules.md" | cat_each
        prompt_standing
        review_context "$2"
    } > "$1"
}

deep_angles() {
    printf '%s\n' correctness security contracts tests simplification
}

# The prompt files that make up a deep review stage, in order, or failure.
stage_task_files() {
    local dir="$ROOT/prompts/deep"
    case "$1" in
        intent|verify) printf '%s\n' "$dir/$1.md" ;;
        write-up) printf '%s\n' "$dir/write-up.md" "$ROOT/prompts/review.md" ;;
        angle-*)
            deep_angles | grep -Fxq -- "${1#angle-}" || return 1
            printf '%s\n' "$dir/$1.md" "$dir/hypotheses.md" ;;
        *) return 1 ;;
    esac
}

# The intent is the one stage output a later stage can do without.
intent_block() {
    if [ -s "${INTENT_FILE:-}" ]; then
        data_block intent < "$INTENT_FILE"
    else
        printf 'Not available: the intent stage did not finish.\n' | data_block intent
    fi
}

# The data blocks of each stage, in prompt order.
stage_blocks() {
    case "$1" in
        intent) echo 'pr diff' ;;
        verify) echo 'pr hypotheses diff' ;;
        write-up) echo 'pr focus intent verified-findings diff tests previous-review' ;;
        angle-tests) echo 'pr focus intent diff tests previous-review' ;;
        *) echo 'pr focus intent diff previous-review' ;;
    esac
}

block_file() {
    case "$1" in
        hypotheses) printf '%s\n' "$HYPOTHESES_FILE" ;;
        verified-findings) printf '%s\n' "$VERIFIED_FILE" ;;
        tests) printf '%s\n' "$TEST_RESULT_FILE" ;;
        previous-review) printf '%s\n' "$PREV_REVIEW_FILE" ;;
    esac
}

emit_block() {
    case "$1" in
        pr) printf '%s\n' "$PR_JSON" | data_block pr ;;
        focus) printf '%s\n' "$FOCUS" | data_block focus ;;
        intent) intent_block ;;
        diff) diff_blocks "$2" ;;
        *) data_block "$1" < "$(block_file "$1")" ;;
    esac
}

stage_context() {
    local block
    context_head "$2"
    for block in $(stage_blocks "$1"); do emit_block "$block" "$2"; done
}

# build_stage_prompt <out> <stage> <mode>. Stages: intent, angle-<name>,
# verify and write-up. Earlier stage output arrives through INTENT_FILE,
# HYPOTHESES_FILE and VERIFIED_FILE, and is escaped like any other data.
build_stage_prompt() {
    local tasks
    tasks="$(stage_task_files "$2")" || return 1
    {
        printf '%s\n' "$ROOT/prompts/policy.md" | cat_each
        printf '%s\n' "$tasks" | cat_each
        printf '%s\n' "$ROOT/rules.md" | cat_each
        prompt_standing
        stage_context "$2" "$3"
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
