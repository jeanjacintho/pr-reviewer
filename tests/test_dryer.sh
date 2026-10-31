# Tests for tools/dryer: ranked near-duplicate regions across files.

dryer_fixture() {
    local dir
    dir="$(mktmp)"
    cat > "$dir/a.sh" <<'SRC'
load_config() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "missing $file" >&2
        return 1
    fi
    while IFS='=' read -r key value; do
        export "$key=$value"
    done < "$file"
}
SRC
    cat > "$dir/b.sh" <<'SRC'
read_settings() {
    local path="$1"
    if [ ! -f "$path" ]; then
        echo "no such $path" >&2
        return 1
    fi
    while IFS='=' read -r name val; do
        export "$name=$val"
    done < "$path"
}
SRC
    cat > "$dir/c.sh" <<'SRC'
render() {
    printf '%s\n' "$1" | sed 's/a/b/'
    for x in 1 2 3; do
        echo "$x"
    done
    curl -fsS https://example.com | jq '.items[] | .name'
    git log --oneline -n 5 | awk '{print $2}'
}
SRC
    echo "$dir"
}

run_dryer() {
    "$PR_REVIEWER_ROOT/tools/dryer" "$@" 2>&1
}

test_dryer_flags_renamed_duplicate() {
    local dir out rc row rank
    dir="$(dryer_fixture)"
    out="$(run_dryer --root "$dir")" && rc=0 || rc=$?
    assert_eq 1 "$rc" "$out"
    row="$(printf '%s\n' "$out" | grep 'a.sh:' | grep 'b.sh:' || true)"
    assert_contains "$row" "~"
    rank="$(printf '%s\n' "$row" | awk 'NR==1 {print $1}')"
    assert_eq 1 "$(awk -v r="$rank" 'BEGIN {print (r >= 0.8) ? 1 : 0}')" "rank $rank"
    assert_not_contains "$out" "c.sh"
    assert_contains "$out" "1 duplicated regions at or above 0.8"
}

test_dryer_clean_when_distinct() {
    local dir out rc
    dir="$(dryer_fixture)"
    rm "$dir/b.sh"
    out="$(run_dryer --root "$dir")" && rc=0 || rc=$?
    assert_eq 0 "$rc" "$out"
    assert_contains "$out" "no duplication at or above 0.8"
}

test_dryer_finds_repeat_within_one_file() {
    local dir out rc
    dir="$(dryer_fixture)"
    cat "$dir/b.sh" >> "$dir/a.sh"
    rm "$dir/b.sh"
    out="$(run_dryer --root "$dir" a.sh)" && rc=0 || rc=$?
    assert_eq 1 "$rc" "$out"
    assert_contains "$out" "a.sh:1-"
    assert_contains "$out" "a.sh:11-"
}

test_dryer_threshold_option() {
    local dir rc
    dir="$(dryer_fixture)"
    run_dryer --root "$dir" --threshold 1.01 >/dev/null && rc=0 || rc=$?
    assert_eq 0 "$rc"
}
