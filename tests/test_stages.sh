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

test_stages_has_hypotheses_follows_the_parser() {
    stages_setup
    printf '%s' "$(hyp_block 1)" > "$STAGE_DIR/hyp"
    has_hypotheses "$STAGE_DIR/hyp" || fail block
    printf '### H1 \r\nSeverity: low\r\nClass: bug\r\nClaim: x\r\nFiles: `a:1`\r\nFailure path: y\r\n' > "$STAGE_DIR/hyp"
    has_hypotheses "$STAGE_DIR/hyp" || fail whitespace_and_crlf
    printf 'NO HYPOTHESES\n' > "$STAGE_DIR/hyp"
    if has_hypotheses "$STAGE_DIR/hyp"; then fail none; fi
    printf 'prose\n' > "$STAGE_DIR/hyp"
    if has_hypotheses "$STAGE_DIR/hyp"; then fail invalid; fi
    if has_hypotheses "$STAGE_DIR/missing"; then fail missing; fi
}

# ceiling_check <review items...>: validates a write-up made of these lines
# against four verified findings: correctness/H1 (blocking), security/H1
# (medium) and tests/H1 (low) confirmed, contracts/H1 (blocking) still open.
ceiling_check() {
    printf '%s\n' "$@" > "$STAGE_DIR/review"
    validate_ceiling "$STAGE_DIR/verified" "$STAGE_DIR/review"
}

test_stages_ceiling_ties_every_item_to_findings_that_justify_it() {
    stages_setup
    { merged_block correctness 1 blocking bug yes '`a:1` — x'; merged_block security 1 medium security yes '`a:1` — x'; merged_block tests 1 low tests yes '`a:1` — x'; merged_block contracts 1 blocking contract open '`a:1` — x'; } > "$STAGE_DIR/verified"
    ceiling_check '1. [blocking] [bug] a <!-- src: correctness/H1 -->' '2. [medium] [security] b <!-- src: security/H1 -->' '3. [open] [contract] **Q: c** <!-- src: contracts/H1 -->' '4. [low] [tests] d <!-- src:tests/H1 -->' || fail as_verified
    ceiling_check '1. [medium] [bug] a <!-- src: correctness/H1 -->' '2. [low] [security] b <!-- src: security/H1 -->' || fail downgraded
    ceiling_check '1. [blocking] [bug] merged <!-- src: correctness/H1, contracts/H1 -->' || fail merged_with_an_open_one
    ceiling_check '1. [open] [bug] cautious <!-- src: correctness/H1 -->' || fail open_is_always_allowed
    ceiling_check '1. [medium] [bug] wrapped over' '   two lines <!-- src: correctness/H1 -->' || fail wrapped
    ceiling_check '- [blocking] [bug] bullet <!-- src: correctness/H1 -->' || fail bullets
    ceiling_check '1. [open] [contract]' '**Q: Does this caller need the old behavior?** <!-- src: contracts/H1 -->' || fail wrapped_bold_continuation
    ceiling_check '1) [blocking] [bug] paren <!-- src: correctness/H1 -->' '2. **[medium]** [security] bold <!-- src: security/H1 -->' '+ [low] [tests] plus <!-- src: tests/H1 -->' || fail other_list_shapes
    ceiling_check '1. [BLOCKING] [bug] shouting <!-- src: correctness/H1 -->' '2. [NIT] [tests] small <!-- src: tests/H1 -->' '3. [OPEN] [contract] q <!-- src: contracts/H1 -->' || fail upper_case
    ceiling_check '**For AI authors** — Answer each [open] item directly.' '1. [open] [contract] q <!-- src: contracts/H1 -->' || fail open_in_prose
    ceiling_check 'None — no load-bearing issues found.' '' '**Security** — None' || fail nothing_listed
    ceiling_check '1. [blocking] [contract] promoted <!-- src: contracts/H1 -->' && fail promoted_open
    ceiling_check '1. [medium] [contract] promoted <!-- src: contracts/H1 -->' && fail promoted_open_to_medium
    ceiling_check '1. [blocking] [security] too high <!-- src: security/H1 -->' && fail above_its_source
    ceiling_check '1. [medium] [tests] too high <!-- src: tests/H1 -->' && fail above_a_low_source
    ceiling_check '1. [open] [blocking] [contract] smuggled <!-- src: contracts/H1 -->' && fail second_tag_on_an_open_item
    ceiling_check '1. [blocking] [bug] a [medium] <!-- src: correctness/H1 -->' && fail second_tag_after_a_confirmed_one
    ceiling_check '1. [open] [contract] q <!-- src: contracts/H1 -->' '   and it is [blocking] really' && fail tag_on_a_wrapped_line
    ceiling_check '1. [open] [contract] no citation of its own' '**Security** — None <!-- src: contracts/H1 -->' && fail citation_borrowed_from_a_section
    ceiling_check '1. [open] [contract] no citation of its own' 'VERDICT: COMMENT <!-- src: contracts/H1 -->' && fail citation_borrowed_from_the_verdict
    ceiling_check '1. [blocking] [bug] Uncited claim.' '**Security**' 'None <!-- src: correctness/H1 -->' 'VERDICT: COMMENT' && fail citation_after_a_section_heading
    ceiling_check '1. [blocking] [bug] Uncited claim.' 'VERDICT: COMMENT' '<!-- src: correctness/H1 -->' && fail citation_after_the_verdict
    ceiling_check '1. [blocking] [bug] Uncited claim.' '' '  **Security** — None <!-- src: correctness/H1 -->' && fail citation_after_an_indented_section
    ceiling_check '1. [blocking] [bug] Uncited claim.' '   **Security** — None <!-- src: correctness/H1 -->' && fail citation_in_an_indented_section_without_a_gap
    ceiling_check '1. [blocking] [bug] Uncited claim.' '' 'Some later paragraph <!-- src: correctness/H1 -->' && fail citation_after_a_blank_line
    ceiling_check '1. [blocking] [bug] a <!-- src: correctness/H1 -->' '' '2. [open] [contract] q <!-- src: contracts/H1 -->' || fail items_separated_by_blank_lines
    ceiling_check '1. [blocking] [bug] ok <!-- src: correctness/H1 -->' '**Security** — None' 'VERDICT: COMMENT' || fail citation_before_a_section
    ceiling_check '1) [blocking] [contract] promoted <!-- src: contracts/H1 -->' && fail promoted_paren_alone
    ceiling_check '1. **[blocking]** [contract] promoted <!-- src: contracts/H1 -->' && fail promoted_bold_alone
    ceiling_check '1. [blocking] [bug] a <!-- src: correctness/H1 -->' '2) [blocking] [contract] promoted <!-- src: contracts/H1 -->' && fail promoted_paren_after_a_good_one
    ceiling_check '1. [blocking] [bug] a <!-- src: correctness/H1 -->' '2. **[blocking]** [contract] promoted <!-- src: contracts/H1 -->' && fail promoted_bold_after_a_good_one
    ceiling_check '1. [BLOCKING] [contract] promoted <!-- src: contracts/H1 -->' && fail promoted_upper_case
    ceiling_check 'This is the [blocking] problem <!-- src: contracts/H1 -->' && fail severity_tag_in_prose
    ceiling_check '1. [blocking] [bug] a' && fail no_source
    ceiling_check '1. [low] [bug] a <!-- src: -->' && fail empty_source
    ceiling_check '1. [open] [bug] a <!-- src: -->' && fail empty_source_on_an_open_item
    ceiling_check '1. [open] [bug] invented <!-- src: nope/H9 -->' && fail unknown_source_on_an_open_item
    ceiling_check '- [blocking] [contract] promoted bullet <!-- src: contracts/H1 -->' && fail promoted_bullet
    ceiling_check '1. [low] [bug] invented <!-- src: nope/H9 -->' && fail unknown_source
    ceiling_check '1. [blocking] [bug] a <!-- src: correctness/H1 -->' '2. [blocking] [contract] promoted <!-- src: contracts/H1 -->' && fail one_bad_item_among_good
    if validate_ceiling "$STAGE_DIR/verified" "$STAGE_DIR/missing"; then fail missing_review; fi
    if validate_ceiling "$STAGE_DIR/missing" "$STAGE_DIR/review"; then fail missing_findings; fi
    return 0
}
