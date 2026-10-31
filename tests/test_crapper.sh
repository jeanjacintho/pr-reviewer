# Tests for tools/crapper: per-function CRAP from complexity and coverage.

crapper_fixture() {
    local dir
    dir="$(mktmp)"
    cat > "$dir/lib.sh" <<'LIB'
simple() {
    echo simple
}

# branchy has complexity 6: base 1 + if + elif + && + two case arms.
branchy() {
    if [ "$1" = a ]; then
        echo a
    elif [ "$1" = b ] && [ -n "$2" ]; then
        echo b
    fi
    case "$1" in
        c)
            echo c
            ;;
        *)
            echo other
            ;;
    esac
}
LIB
    mkdir "$dir/tests"
    cat > "$dir/tests/helper.sh" <<'LIB'
ignored_test_helper() {
    if true; then echo; fi
}
LIB
    echo "$dir"
}

run_crapper() {
    "$PR_REVIEWER_ROOT/tools/crapper" "$@" 2>&1
}

row_for() {
    printf '%s\n' "$1" | grep " $2 " || true
}

test_crapper_flags_uncovered_complex_function() {
    local dir out rc
    dir="$(crapper_fixture)"
    out="$(run_crapper --root "$dir" --test-cmd '. ./lib.sh; simple')" && rc=0 || rc=$?
    assert_eq 1 "$rc" "$out"
    assert_contains "$(row_for "$out" branchy)" "42.0"
    assert_contains "$(row_for "$out" branchy)" "  0%"
    assert_contains "$(row_for "$out" branchy)" "lib.sh:6"
    assert_contains "$(row_for "$out" simple)" "1.0"
    assert_contains "$(row_for "$out" simple)" "100%"
}

test_crapper_partial_coverage() {
    local dir out
    dir="$(crapper_fixture)"
    out="$(run_crapper --root "$dir" --test-cmd '. ./lib.sh; branchy a')" || true
    # 4 of 7 executable lines run: 36 * (3/7)^3 + 6 = 8.8
    assert_contains "$(row_for "$out" branchy)" "8.8"
    assert_contains "$(row_for "$out" branchy)" " 57%"
}

test_crapper_passes_when_fully_covered() {
    local dir out rc
    dir="$(crapper_fixture)"
    out="$(run_crapper --root "$dir" \
        --test-cmd '. ./lib.sh; simple; branchy a; branchy b x; branchy c')" && rc=0 || rc=$?
    assert_eq 0 "$rc" "$out"
    assert_not_contains "$out" " line "
    assert_contains "$(row_for "$out" branchy)" "6.0"
    assert_not_contains "$out" " line "
    assert_contains "$(row_for "$out" branchy)" "100%"
}

test_crapper_threshold_option() {
    local dir rc
    dir="$(crapper_fixture)"
    run_crapper --root "$dir" --threshold 50 --test-cmd '. ./lib.sh' >/dev/null && rc=0 || rc=$?
    assert_eq 0 "$rc"
}

test_crapper_skips_tests_dir() {
    local dir out
    dir="$(crapper_fixture)"
    out="$(run_crapper --root "$dir" --test-cmd 'true')" || true
    assert_not_contains "$out" "ignored_test_helper"
}

test_crapper_fails_when_tests_fail() {
    local dir out rc
    dir="$(crapper_fixture)"
    out="$(run_crapper --root "$dir" --test-cmd 'exit 3')" && rc=0 || rc=$?
    assert_eq 2 "$rc"
    assert_contains "$out" "test command failed"
}
