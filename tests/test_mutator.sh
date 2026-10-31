# Tests for tools/mutator: mutants that the test command fails to kill.

mutator_fixture() {
    local dir
    dir="$(mktmp)"
    cat > "$dir/lib.sh" <<'SRC'
is_big() {
    [ "$1" -gt 10 ]
}

is_small() {
    [ "$1" -lt 3 ]
}

label() {
    echo "a == b"  # x == y
}
SRC
    mkdir "$dir/tests"
    cat > "$dir/tests/check.sh" <<'SRC'
. ./lib.sh
is_big 11 || exit 1
is_big 3 && exit 1
exit 0
SRC
    git -C "$dir" init -q
    git -C "$dir" add -A
    git -C "$dir" -c user.name=t -c user.email=t@t commit -q -m init
    echo "$dir"
}

run_mutator() {
    "$PR_REVIEWER_ROOT/tools/mutator" --test-cmd 'bash tests/check.sh' "$@" 2>&1
}

test_mutator_reports_survivors_only() {
    local dir out rc
    dir="$(mutator_fixture)"
    cp "$dir/lib.sh" "$dir/lib.orig"
    out="$(run_mutator --root "$dir")" && rc=0 || rc=$?
    assert_eq 1 "$rc" "$out"
    assert_contains "$out" "SURVIVED lib.sh:6  -lt -> -ge"
    assert_not_contains "$out" "lib.sh:2"
    assert_not_contains "$out" "lib.sh:10"
    assert_contains "$out" "mutants: 2  killed: 1  survived: 1"
    assert_eq "" "$(cmp "$dir/lib.sh" "$dir/lib.orig")" "source left mutated"
}

test_mutator_passes_when_all_killed() {
    local dir out rc
    dir="$(mutator_fixture)"
    printf '. ./lib.sh\nis_small 2 || exit 1\nis_small 5 && exit 1\nexit 0\n' > "$dir/tests/extra.sh"
    out="$("$PR_REVIEWER_ROOT/tools/mutator" --root "$dir" \
        --test-cmd 'bash tests/check.sh && bash tests/extra.sh' 2>&1)" && rc=0 || rc=$?
    assert_eq 0 "$rc" "$out"
    assert_contains "$out" "survived: 0"
}

test_mutator_since_limits_to_changed_lines() {
    local dir out
    dir="$(mutator_fixture)"
    sed -i '' 's/-lt 3/-lt 4/' "$dir/lib.sh"
    out="$(run_mutator --root "$dir" --since HEAD)" || true
    assert_contains "$out" "mutants: 1  killed: 0  survived: 1"
}

test_mutator_times_out_endless_mutant() {
    local dir out
    dir="$(mutator_fixture)"
    cat > "$dir/loop.sh" <<'SRC'
count_to_three() {
    i=0
    while [ "$i" -lt 3 ] && true; do
        i=$((i + 1))
    done
    echo "$i"
}
SRC
    printf '. ./loop.sh\n[ "$(count_to_three)" = 3 ] || exit 1\nexit 0\n' > "$dir/tests/loop.sh"
    out="$("$PR_REVIEWER_ROOT/tools/mutator" --root "$dir" --timeout 2 \
        --test-cmd 'bash tests/loop.sh' loop.sh 2>&1)" || true
    assert_contains "$out" "timed out: 1"
    assert_not_contains "$out" "SURVIVED loop.sh:3  && -> ||"
}

test_mutator_mutates_jq() {
    local dir out
    dir="$(mutator_fixture)"
    printf 'def is_ok: . == "ok" and true;\n' > "$dir/f.jq"
    printf '[ "$(jq -n -L . '"'"'include "f"; "ok" | is_ok'"'"')" = true ] || exit 1\n' > "$dir/tests/jq.sh"
    out="$("$PR_REVIEWER_ROOT/tools/mutator" --root "$dir" --test-cmd 'bash tests/jq.sh' f.jq 2>&1)" || true
    assert_contains "$out" "SURVIVED f.jq:1  and -> or"
    assert_not_contains "$out" "== -> !="
}

test_mutator_fails_when_baseline_fails() {
    local dir out rc
    dir="$(mutator_fixture)"
    out="$("$PR_REVIEWER_ROOT/tools/mutator" --root "$dir" --test-cmd 'exit 1' 2>&1)" && rc=0 || rc=$?
    assert_eq 2 "$rc"
    assert_contains "$out" "tests fail before mutation"
}
