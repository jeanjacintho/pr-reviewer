# Tests for the test runner itself.

write_suite() {
    local dir="$1"
    cp "$PR_REVIEWER_ROOT/tests/helpers.sh" "$dir/helpers.sh"
    cat > "$dir/test_sample.sh" <<'SUITE'
test_passes() {
    assert_eq 1 1
}

test_fails() {
    assert_eq expected actual
}
SUITE
}

test_runner_reports_pass_and_fail() {
    local dir out rc
    dir="$(mktmp)"
    write_suite "$dir"
    out="$(TESTS_DIR="$dir" bash "$PR_REVIEWER_ROOT/tests/run.sh" 2>&1)" && rc=0 || rc=$?
    assert_eq 1 "$rc"
    assert_contains "$out" "ok   test_passes"
    assert_contains "$out" "FAIL test_fails"
    assert_contains "$out" "expected: expected"
    assert_contains "$out" "1 passed, 1 failed"
}

test_runner_filters_by_name() {
    local dir out rc
    dir="$(mktmp)"
    write_suite "$dir"
    out="$(TESTS_DIR="$dir" bash "$PR_REVIEWER_ROOT/tests/run.sh" passes 2>&1)" && rc=0 || rc=$?
    assert_eq 0 "$rc"
    assert_not_contains "$out" "test_fails"
}

test_runner_filters_by_file() {
    local dir out
    dir="$(mktmp)"
    write_suite "$dir"
    out="$(TESTS_DIR="$dir" bash "$PR_REVIEWER_ROOT/tests/run.sh" sample 2>&1)" || true
    assert_contains "$out" "2 tests: 1 passed, 1 failed"
}
