acquire_poll_lock() {
    local lock="$STATE_DIR/poll.lock"
    mkdir -p "$STATE_DIR"
    if mkdir "$lock" 2>/dev/null; then return 0; fi
    local stale
    stale="$(perl -e 'print time - (stat $ARGV[0])[9] > $ARGV[1] ? "yes" : "no"' "$lock" "$((REVIEW_TIMEOUT_SECS + 600))")"
    if [ "$stale" = yes ]; then
        # A living poll may be processing several commands; age alone is insufficient.
        if [ -f "$lock/pid" ] && kill -0 "$(cat "$lock/pid")" 2>/dev/null; then return 1; fi
        rm -rf "$lock"
        mkdir "$lock" 2>/dev/null
    else
        return 1
    fi
}

dispatch_trigger() {
    local repo pr id kind
    repo="$(printf '%s' "$1" | jq -r .repo)"
    pr="$(printf '%s' "$1" | jq -r .pr)"
    id="$(printf '%s' "$1" | jq -r .id)"
    kind="$(printf '%s' "$1" | jq -r .kind)"
    seen_add "$id" || return
    log "Dispatch $repo#$pr $kind $id"
    case "$kind" in
        review) "${REVIEW_SH:-$ROOT/review.sh}" full "$repo" "$pr" "$id" ;;
        update-review) "${REVIEW_SH:-$ROOT/review.sh}" update "$repo" "$pr" "$id" ;;
        memorize) "${MEMORIZE_SH:-$ROOT/memorize.sh}" "$repo" "$pr" "$id" ;;
    esac
}

# Calls "$1" once per nonblank line of "$2", with stdin closed.
for_each_line() {
    local line
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        "$1" "$line" < /dev/null
    done <<< "$2"
}

dispatch_or_log() {
    dispatch_trigger "$1" || log "Dispatch failed: $1"
}

poll_repo() {
    local response triggers trusted seen
    response="$(fetch_open_prs "$1")" || { log "Fetch failed: $1"; return; }
    trusted="$(repo_trusted_users "$1" | jq -Rsc 'split("\n") | map(select(length > 0))')"
    state_init seen '[]'
    seen="$(cat "$STATE_DIR/seen.json")"
    triggers="$(printf '%s' "$response" | jq -c -L "${LIB_ROOT:-$ROOT}/lib" --arg repo "$1" --arg prefix "$CMD_PREFIX" --arg watermark "$(cat "$STATE_DIR/started-at")" --argjson trusted "$trusted" --argjson seen "$seen" '
        include "select"; select_triggers($repo; $prefix; $trusted; $watermark; $seen)[]')" || { log "Invalid response: $1"; return; }
    for_each_line dispatch_or_log "$triggers"
}

poll_main() {
    acquire_poll_lock || { log 'Poll already running'; return 0; }
    printf '%s\n' "$$" > "$STATE_DIR/poll.lock/pid"
    trap 'rm -rf "$STATE_DIR/poll.lock"' EXIT
    [ -s "$STATE_DIR/started-at" ] || { log 'Missing state/started-at; run install.sh'; return 1; }
    for_each_line poll_repo "$(repos_enabled)"
}
