post_once() {
    POST_ATTEMPTED=yes
    post_comment "$REPO" "$PR" "$1"
}

finish_reactions() {
    if [ "${HAS_EYES:-no}" = yes ]; then
        unreact "$COMMENT_ID" EYES || log 'Could not remove reaction'
    fi
    add_reaction "$1"
}

command_failed() {
    local rc="$1" message="$2" directory="$3"
    # Only the owning shell publishes; substitutions propagate their exit status.
    if [ "$BASH_SUBSHELL" -gt 0 ]; then exit "$rc"; fi
    trap - ERR
    log "$REPO#$PR: $message"
    if [ "$POST_ATTEMPTED" = no ]; then
        printf '%s\n%s\n' "$message" "$MARKER" > "$directory/comment"
        post_once "$directory/comment" || log 'Could not post failure comment'
    fi
    finish_reactions CONFUSED
    exit "$rc"
}

add_reaction() {
    react "$COMMENT_ID" "$1" || log 'Could not add reaction'
}
