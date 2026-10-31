# Tests for tools/gate: one short summary of tests, crapper, dryer, mutator.

gate_fixture() {
    local dir
    dir="$(mktmp)"
    mkdir "$dir/tests"
    cat > "$dir/lib.sh" <<'SRC'
simple() {
    echo simple
}

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
SRC
    cat > "$dir/tests/run.sh" <<'SRC'
. ./lib.sh
[ "$(simple)" = simple ] || { echo "1 tests: 0 passed, 1 failed"; exit 1; }
branchy a >/dev/null; branchy b x >/dev/null; branchy c >/dev/null
echo "1 tests: 1 passed, 0 failed"
SRC
    git -C "$dir" init -q
    git -C "$dir" add -A
    git -C "$dir" -c user.name=t -c user.email=t@t commit -q -m init
    echo "$dir"
}

run_gate() {
    "$PR_REVIEWER_ROOT/tools/gate" "$@" 2>&1
}

test_gate_passes_on_clean_project() {
    local dir out rc
    dir="$(gate_fixture)"
    out="$(run_gate --root "$dir")" && rc=0 || rc=$?
    assert_eq 0 "$rc" "$out"
    assert_contains "$out" "Gate: PASS"
    assert_contains "$out" "Tests: 1/1"
    assert_contains "$out" "Crapper: 0 over threshold"
    assert_contains "$out" "Dryer: 0 regions"
    assert_contains "$out" "Mutator: 0/0 killed"
}

test_gate_lists_function_over_crap_threshold() {
    local dir out rc
    dir="$(gate_fixture)"
    printf '. ./lib.sh\nsimple >/dev/null\necho "1 tests: 1 passed, 0 failed"\n' > "$dir/tests/run.sh"
    out="$(run_gate --root "$dir")" && rc=0 || rc=$?
    assert_eq 1 "$rc"
    assert_contains "$out" "Gate: FAIL"
    assert_contains "$out" "Crapper: 1 over threshold"
    assert_contains "$out" "lib.sh:5 branchy CRAP 42.0"
}

test_gate_stops_when_tests_fail() {
    local dir out rc
    dir="$(gate_fixture)"
    printf 'echo "3 tests: 2 passed, 1 failed"\nexit 1\n' > "$dir/tests/run.sh"
    out="$(run_gate --root "$dir")" && rc=0 || rc=$?
    assert_eq 1 "$rc"
    assert_contains "$out" "Gate: FAIL"
    assert_contains "$out" "Tests: 2/3"
    assert_not_contains "$out" "Crapper:"
}

test_gate_lists_surviving_mutants() {
    local dir out rc
    dir="$(gate_fixture)"
    printf 'is_big() {\n    [ "$1" -gt 10 ]\n}\n' >> "$dir/lib.sh"
    out="$(run_gate --root "$dir" --since HEAD)" && rc=0 || rc=$?
    assert_eq 1 "$rc"
    assert_contains "$out" "Mutator: 0/1 killed"
    assert_contains "$out" "lib.sh:"
    assert_contains "$out" "-gt -> -le"
}
