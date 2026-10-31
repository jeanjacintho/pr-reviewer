# Tests for tools/review: one reviewer prompt, run by codex or claude.

# Fake engine CLIs on a private PATH; each logs argv and stdin.
review_bin() {
    local bin
    bin="$(mktmp)"
    for cli in codex claude; do
        cat > "$bin/$cli" <<FAKE
#!/bin/bash
echo "$cli \$*" >> "\$FAKE_LOG"
cat > "\$FAKE_LOG.stdin.$cli"
out=""
while [ \$# -gt 0 ]; do
    [ "\$1" = --output-last-message ] && out="\$2"
    shift
done
if [ -n "\$out" ]; then echo "Verdict: OK" > "\$out"; else echo "Verdict: OK"; fi
FAKE
        chmod +x "$bin/$cli"
    done
    echo "$bin"
}

run_review() {
    local bin="$1"
    shift
    FAKE_LOG="$bin/log" PATH="$bin:/usr/bin:/bin" "$PR_REVIEWER_ROOT/tools/review" "$@" 2>&1
}

test_review_defaults_to_codex_read_only() {
    local bin out
    bin="$(review_bin)"
    out="$(run_review "$bin")"
    assert_contains "$out" "Verdict: OK"
    assert_contains "$(cat "$bin/log")" "codex exec --sandbox read-only"
    assert_contains "$(cat "$bin/log.stdin.codex")" "You review changes"
    assert_contains "$(cat "$bin/log.stdin.codex")" "git diff HEAD"
}

test_review_runs_claude_with_read_only_tools() {
    local bin out
    bin="$(review_bin)"
    out="$(run_review "$bin" --engine claude)"
    assert_contains "$out" "Verdict: OK"
    assert_contains "$(cat "$bin/log")" "claude -p --allowedTools"
    assert_not_contains "$(cat "$bin/log")" "codex"
    assert_not_contains "$(cat "$bin/log")" "Edit"
    assert_not_contains "$(cat "$bin/log")" "Write"
    assert_contains "$(cat "$bin/log.stdin.claude")" "You review changes"
}

test_review_range_and_focus_reach_the_prompt() {
    local bin
    bin="$(review_bin)"
    run_review "$bin" --range main..HEAD "focus on auth" >/dev/null
    assert_contains "$(cat "$bin/log.stdin.codex")" "git diff main..HEAD"
    assert_contains "$(cat "$bin/log.stdin.codex")" "focus on auth"
}

test_review_passes_model_to_each_engine() {
    local bin
    bin="$(review_bin)"
    run_review "$bin" --model m1 >/dev/null
    run_review "$bin" --engine claude --model m2 >/dev/null
    assert_contains "$(cat "$bin/log")" "-m m1"
    assert_contains "$(cat "$bin/log")" "--model m2"
}

test_review_engine_from_environment() {
    local bin
    bin="$(review_bin)"
    REVIEW_ENGINE=claude run_review "$bin" >/dev/null
    assert_contains "$(cat "$bin/log")" "claude -p"
}

test_review_rejects_unknown_engine() {
    local bin out rc
    bin="$(review_bin)"
    out="$(run_review "$bin" --engine gemini)" && rc=0 || rc=$?
    assert_eq 2 "$rc"
    assert_contains "$out" "unknown engine"
}

test_review_reports_missing_cli() {
    local bin out rc
    bin="$(mktmp)"
    out="$(FAKE_LOG="$bin/log" PATH="$bin:/usr/bin:/bin" "$PR_REVIEWER_ROOT/tools/review" --engine claude 2>&1)" && rc=0 || rc=$?
    assert_eq 2 "$rc"
    assert_contains "$out" "claude not found"
}
