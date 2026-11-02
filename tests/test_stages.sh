stages_setup() {
    . "$PR_REVIEWER_ROOT/lib/common.sh"
    . "$PR_REVIEWER_ROOT/lib/stages.sh"
    STAGE_DIR="$(mktmp)"
}

# hyp_block <id> [severity] [class]: one well-formed hypothesis.
hyp_block() {
    printf '### H%s\nSeverity: %s\nClass: %s\nClaim: claim number %s\nFiles: `src/f%s.ts:%s`, `src/main.ts:3-5`\nFailure path: failure path number %s\n\n' "$1" "${2:-blocking}" "${3:-bug}" "$1" "$1" "$1" "$1"
}

# ver_block <id> <answer> [evidence]
ver_block() {
    printf '### H%s\nAnswer: %s\nEvidence: %s\n\n' "$1" "$2" "${3:-\`src/build.ts:12\` — the source list has no variant.ts}"
}

hyp_accepts() {
    printf '%s' "$1" > "$STAGE_DIR/hyp"
    validate_hypotheses "$STAGE_DIR/hyp"
}

test_stages_accept_well_formed_hypotheses() {
    stages_setup
    hyp_accepts "$(hyp_block 1)" || fail one
    hyp_accepts "$(hyp_block 1 medium contract; hyp_block 2 low tests; hyp_block 3 nit simplification; hyp_block 4 low security; hyp_block 5 low data-integrity; hyp_block 6)" || fail six
    hyp_accepts $'\n\nNO HYPOTHESES\n\n' || fail none
    return 0
}

test_stages_reject_malformed_hypotheses() {
    stages_setup
    local good bad
    good="$(hyp_block 1)"
    for bad in \
        '' \
        'Looks fine to me.' \
        "Here are my findings:
$good" \
        "$good
Thanks!" \
        "$(hyp_block 1 critical)" \
        "$(hyp_block 1 low style)" \
        "$(hyp_block 2)" \
        "$(hyp_block 1; hyp_block 1)" \
        "$(printf '### H1\nSeverity: low\nClass: bug\nClaim: x\nFiles: `a:1`\n')" \
        "$(printf '### H1\nSeverity: low\nClass: bug\n'; hyp_block 2)" \
        "$(hyp_block 1; hyp_block 3)" \
        "$(hyp_block 1; hyp_block 2; hyp_block 3; hyp_block 4; hyp_block 5; hyp_block 6; hyp_block 7)" \
        "$good
NO HYPOTHESES" \
        'NO HYPOTHESES because of reasons' \
        "$(printf '%s' "$good" | grep -v '^Class:')" \
        "$(printf '%s' "$good" | perl -pe 's/^Claim:.*/Claim:/')" \
        "$(printf '%s' "$good" | perl -pe 's/^Files: .*/Files: src\/build.ts/')" \
        "$(printf '%s' "$good" | perl -pe 's/^Files: .*/Files: `src\/build.ts`/')" \
        "$(printf '%s\nExtra: field\n' "$good")" \
        "$(printf '### H1\nClass: bug\nSeverity: low\nClaim: x\nFiles: `a:1`\nFailure path: y\n')" \
        "$(printf '%s' "$good" | perl -pe 's/^### H1/### H1 extra/')"; do
        if hyp_accepts "$bad"; then fail "accepted: $bad"; fi
    done
    if validate_hypotheses "$STAGE_DIR/missing"; then fail missing_file; fi
}

verification_accepts() {
    printf '%s' "$1" > "$STAGE_DIR/ver"
    validate_verification "$STAGE_DIR/hyp" "$STAGE_DIR/ver"
}

test_stages_verification_must_match_the_hypotheses() {
    stages_setup
    hyp_block 1 > "$STAGE_DIR/hyp"; hyp_block 2 medium contract >> "$STAGE_DIR/hyp"
    verification_accepts "$(ver_block 1 yes; ver_block 2 no)" || fail yes_no
    verification_accepts "$(ver_block 1 unknown '`src/build.ts:1` — searched, no build list'; ver_block 2 unknown '`src/main.ts:2` — no callers found')" || fail unknown
    local bad
    for bad in \
        '' \
        "$(ver_block 1 yes)" \
        "$(ver_block 2 yes; ver_block 1 yes)" \
        "$(ver_block 1 yes; ver_block 2 yes; ver_block 3 yes)" \
        "$(ver_block 1 maybe; ver_block 2 yes)" \
        "$(ver_block 1 yes 'looks right to me'; ver_block 2 yes)" \
        "$(ver_block 1 yes; ver_block 2 no 'it is fine')" \
        "$(ver_block 1 yes; ver_block 2 unknown 'could not tell')" \
        "$(ver_block 1 yes; printf '### H2\nAnswer: yes\n')" \
        "$(ver_block 1 yes; printf '### H2\n'; ver_block 3 yes)" \
        "$(printf '### H1\n'; ver_block 2 yes)" \
        "$(ver_block 1 yes ' '; ver_block 2 yes)" \
        "Verdict follows
$(ver_block 1 yes; ver_block 2 yes)" \
        "$(ver_block 1 yes; ver_block 2 yes)
Done." ; do
        if verification_accepts "$bad"; then fail "accepted: $bad"; fi
    done
    if validate_verification "$STAGE_DIR/hyp" "$STAGE_DIR/missing"; then fail missing_file; fi
    if validate_verification "$STAGE_DIR/missing" "$STAGE_DIR/ver"; then fail missing_hypotheses; fi
    printf 'NO HYPOTHESES\n' > "$STAGE_DIR/hyp"
    if verification_accepts "$(ver_block 1 yes)"; then fail verifying_nothing; fi
    if verification_accepts ''; then fail verifying_nothing_with_nothing; fi
}

merge_fixture() {
    { hyp_block 1 blocking bug; hyp_block 2 medium contract; hyp_block 3 medium tests; hyp_block 4 low simplification; hyp_block 5 blocking security; hyp_block 6 nit tests; } > "$STAGE_DIR/hyp"
    { ver_block 1 yes; ver_block 2 unknown '`src/a.ts:9` — no consumer found'; ver_block 3 no; ver_block 4 unknown '`src/b.ts:1` — unclear'; ver_block 5 unknown '`src/c.ts:2` — handler not reachable'; ver_block 6 unknown '`src/d.ts:3` — unclear'; } > "$STAGE_DIR/ver"
}

# merged_block <angle> <id> <severity> <class> <state> <evidence>
merged_block() {
    printf '### %s/H%s\nSeverity: %s\nClass: %s\nClaim: claim number %s\nFiles: `src/f%s.ts:%s`, `src/main.ts:3-5`\nFailure path: failure path number %s\nVerified: %s\nEvidence: %s\n\n' "$1" "$2" "$3" "$4" "$2" "$2" "$2" "$2" "$5" "$6"
}

test_stages_merge_keeps_confirmed_and_open_findings_only() {
    stages_setup
    merge_fixture
    local expected
    expected="$(merged_block correctness 1 blocking bug yes '`src/build.ts:12` — the source list has no variant.ts'
        merged_block correctness 2 medium contract open '`src/a.ts:9` — no consumer found'
        merged_block correctness 5 blocking security open '`src/c.ts:2` — handler not reachable')"
    assert_eq "$expected" "$(merge_verified correctness "$STAGE_DIR/hyp" "$STAGE_DIR/ver")"
}

test_stages_merge_tags_findings_with_the_angle() {
    stages_setup
    merge_fixture
    assert_contains "$(merge_verified security "$STAGE_DIR/hyp" "$STAGE_DIR/ver")" '### security/H5'
}

test_stages_merge_with_nothing_confirmed_is_empty() {
    stages_setup
    printf 'NO HYPOTHESES\n' > "$STAGE_DIR/hyp"
    : > "$STAGE_DIR/ver"
    assert_eq '' "$(merge_verified tests "$STAGE_DIR/hyp" "$STAGE_DIR/ver")"
    merge_verified tests "$STAGE_DIR/hyp" "$STAGE_DIR/ver" || fail none_is_ok
    { hyp_block 1 low bug; hyp_block 2 medium bug; } > "$STAGE_DIR/hyp"
    { ver_block 1 yes; ver_block 2 no; } > "$STAGE_DIR/ver"
    assert_eq '1' "$(merge_verified tests "$STAGE_DIR/hyp" "$STAGE_DIR/ver" | grep -c '^### ')"
    { ver_block 1 no; ver_block 2 no; } > "$STAGE_DIR/ver"
    assert_eq '' "$(merge_verified tests "$STAGE_DIR/hyp" "$STAGE_DIR/ver")"
}

test_stages_merge_refuses_invalid_input_and_prints_nothing() {
    stages_setup
    merge_fixture
    local out
    if out="$(merge_verified 'Bad Angle' "$STAGE_DIR/hyp" "$STAGE_DIR/ver")"; then fail bad_angle; fi
    assert_eq '' "$out"
    if out="$(merge_verified correctness "$STAGE_DIR/hyp" "$STAGE_DIR/missing")"; then fail missing; fi
    assert_eq '' "$out"
    printf '%s' "$(ver_block 1 yes)" > "$STAGE_DIR/ver"
    if out="$(merge_verified correctness "$STAGE_DIR/hyp" "$STAGE_DIR/ver")"; then fail short_verification; fi
    assert_eq '' "$out"
}
