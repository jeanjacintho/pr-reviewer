memorize_generate() {
    printf '%s\nSource: %s#%s\n' "$LESSON" "$REPO" "$PR" > "$MEMORY_TMP/lesson"
    prev_review "$REPO" "$PR" > "$MEMORY_TMP/previous"
    build_memorize_prompt "$MEMORY_TMP/prompt" "$MEMORY_TMP/lesson" "$MEMORY_TMP/previous"
    mkdir "$MEMORY_TMP/empty"
    MEMORY_FAILURE="Couldn't save that lesson: the review engine failed or timed out."
    engine_text "$REPO" 300 "$MEMORY_TMP/empty" "$MEMORY_TMP/output" "$MEMORY_TMP/prompt" text
    MEMORY_FAILURE="Couldn't save that lesson: the review engine returned an invalid lessons list."
    validate_lessons "$MEMORY_TMP/output"
}

memorize_save() {
    local rule
    MEMORY_FAILURE="Couldn't save that lesson: could not persist normalized rules."
    mkdir -p "$STATE_DIR"
    cp "$ROOT/lessons.md" "$STATE_DIR/lessons.bak"
    MEMORY_REPLACEMENT="$(mktemp "$ROOT/.lessons.XXXXXX")"
    cp "$MEMORY_TMP/output" "$MEMORY_REPLACEMENT"
    mv "$MEMORY_REPLACEMENT" "$ROOT/lessons.md"
    MEMORY_FAILURE="Lesson saved, but confirmation failed. Check lessons.md before retrying."
    rule="$(perl -ne '$last=$_ if /^- /; END { print $last }' "$ROOT/lessons.md")"
    printf 'Learned: %s\n%s\n' "$rule" "$MARKER" > "$MEMORY_TMP/comment"
    post_once "$MEMORY_TMP/comment"
    finish_reactions THUMBS_UP
    log "Learned lesson from $REPO#$PR"
}

memorize_main() {
    REPO="$1" PR="$2" COMMENT_ID="$3"
    MEMORY_TMP="$(mktemp -d)" POST_ATTEMPTED=no
    MEMORY_REPLACEMENT="$MEMORY_TMP/replacement"
    MEMORY_FAILURE="Couldn't save that lesson: could not read the command."
    trap 'rm -rf "$MEMORY_TMP"; rm -f "$MEMORY_REPLACEMENT"' EXIT
    trap 'command_failed "$?" "$MEMORY_FAILURE" "$MEMORY_TMP"' ERR
    local body parsed
    body="$(comment_body "$COMMENT_ID")"
    parsed="$(parse_command "$body")"
    LESSON="${parsed#*$'\t'}"
    if [ -z "$LESSON" ]; then
        printf 'Please include the lesson after the command, e.g. `/%s-memorize Do not flag X because Y`.\n%s\n' "$CMD_PREFIX" "$MARKER" > "$MEMORY_TMP/comment"
        post_once "$MEMORY_TMP/comment"
        return
    fi
    memorize_generate
    memorize_save
}
