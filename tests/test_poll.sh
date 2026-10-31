poll_setup() {
    local source_root="$PR_REVIEWER_ROOT"
    export PR_REVIEWER_ROOT="$(mktmp)"
    export PATH="$source_root/tests/fakes:$PATH"
    export FAKE_LOG="$PR_REVIEWER_ROOT/fake.log" FAKE_POSTS="$PR_REVIEWER_ROOT/posts"
    export FAKE_GH_PRS="$PR_REVIEWER_ROOT/prs.json"
    export PR_REVIEWER_CONFIG="$PR_REVIEWER_ROOT/config.sh"
    mkdir -p "$PR_REVIEWER_ROOT/state"
    printf '2026-01-01T00:00:00Z\n' > "$PR_REVIEWER_ROOT/state/started-at"
    printf 'REPOS=(o/r)\nTRUSTED_USERS=(alice)\n' > "$PR_REVIEWER_CONFIG"
    cp "$source_root/tests/fixtures/prs.json" "$FAKE_GH_PRS"
    : > "$FAKE_LOG"
    export REVIEW_SH="$PR_REVIEWER_ROOT/dispatch" MEMORIZE_SH="$PR_REVIEWER_ROOT/dispatch"
    cat > "$REVIEW_SH" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$PR_REVIEWER_ROOT/dispatched"
cat > "$PR_REVIEWER_ROOT/dispatch.stdin"
jq -e --arg id "${!#}" 'index($id) != null' "$PR_REVIEWER_ROOT/state/seen.json" >/dev/null || { touch "$PR_REVIEWER_ROOT/missing-seen"; exit 1; }
case "$*" in *first*) exit 1 ;; esac
STUB
    chmod +x "$REVIEW_SH"
    POLL_SCRIPT="$source_root/poll.sh"
}

test_poll_dispatches_once_and_continues() {
    poll_setup
    bash "$POLL_SCRIPT" || fail poll
    local dispatched="$(cat "$PR_REVIEWER_ROOT/dispatched")"
    assert_contains "$dispatched" 'update o/r 7 first'
    assert_contains "$dispatched" 'full o/r 7 last'
    assert_contains "$dispatched" 'full o/r 7 seen'
    bash "$POLL_SCRIPT" || fail repeat
    assert_eq "$dispatched" "$(cat "$PR_REVIEWER_ROOT/dispatched")"
    assert_eq 3 "$(jq length "$PR_REVIEWER_ROOT/state/seen.json")"
    assert_contains "$(cat "$PR_REVIEWER_ROOT/state/poll.log")" 'Dispatch failed: {"repo":"o/r","pr":7,"id":"first"'
    [ ! -e "$PR_REVIEWER_ROOT/missing-seen" ] || fail seen_order
    [ ! -s "$PR_REVIEWER_ROOT/dispatch.stdin" ] || fail stdin
    assert_not_contains "$(cat "$FAKE_LOG")" codex
}

test_poll_lock_and_watermark() {
    poll_setup
    mkdir "$PR_REVIEWER_ROOT/state/poll.lock"
    bash "$POLL_SCRIPT" || fail fresh
    assert_eq '' "$(cat "$FAKE_LOG")"
    touch -t 202001010000 "$PR_REVIEWER_ROOT/state/poll.lock"
    bash "$POLL_SCRIPT" || fail stale
    [ ! -d "$PR_REVIEWER_ROOT/state/poll.lock" ] || fail cleanup
    rm "$PR_REVIEWER_ROOT/state/started-at"
    if bash "$POLL_SCRIPT"; then fail watermark; fi
}

test_poll_no_triggers_and_fetch_failure() {
    poll_setup
    printf '{"data":{"repository":{"pullRequests":{"nodes":[]}}}}' > "$FAKE_GH_PRS"
    bash "$POLL_SCRIPT" || fail empty
    [ ! -e "$PR_REVIEWER_ROOT/dispatched" ] || fail dispatched
    assert_not_contains "$(cat "$FAKE_LOG")" codex
    FAKE_GH_EXIT=1 bash "$POLL_SCRIPT" || fail fetch
    assert_contains "$(cat "$PR_REVIEWER_ROOT/state/poll.log")" 'Fetch failed'
}

test_poll_stale_live_owner_and_dead_owner() {
    poll_setup
    mkdir "$PR_REVIEWER_ROOT/state/poll.lock"
    printf '%s\n' "$$" > "$PR_REVIEWER_ROOT/state/poll.lock/pid"
    touch -t 202001010000 "$PR_REVIEWER_ROOT/state/poll.lock"
    bash "$POLL_SCRIPT" || fail live
    assert_eq '' "$(cat "$FAKE_LOG")"
    printf '99999999\n' > "$PR_REVIEWER_ROOT/state/poll.lock/pid"
    touch -t 202001010000 "$PR_REVIEWER_ROOT/state/poll.lock"
    bash "$POLL_SCRIPT" || fail dead
    [ ! -d "$PR_REVIEWER_ROOT/state/poll.lock" ] || fail cleanup
}

test_poll_invalid_response_logs_error() {
    poll_setup
    printf 'invalid json' > "$FAKE_GH_PRS"
    bash "$POLL_SCRIPT" || fail invalid
    assert_contains "$(cat "$PR_REVIEWER_ROOT/state/poll.log")" 'Invalid response'
}
