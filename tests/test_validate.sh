test_validate_review() {
    . "$PR_REVIEWER_ROOT/lib/validate.sh"
    local file="$(mktmp)/out" verdict
    for verdict in APPROVE 'APPROVE — pending: minor note' COMMENT; do
        printf 'Body\nVERDICT: %s\n\n' "$verdict" > "$file"
        validate_review "$file" || fail "$verdict"
    done
    for verdict in '' 'Body' 'VERDICT: LGTM' $'VERDICT: APPROVE\nmore' 'VERDICT: APPROVE — pending: '; do
        printf '%s' "$verdict" > "$file"
        if validate_review "$file"; then fail "accepted $verdict"; fi
    done
}

test_validate_lessons() {
    . "$PR_REVIEWER_ROOT/lib/validate.sh"
    local file="$(mktmp)/out" i
    : > "$file"
    if validate_lessons "$file"; then fail empty; fi
    for i in $(seq 1 40); do printf -- '- Rule %s (from o/r#7)\n' "$i" >> "$file"; done
    validate_lessons "$file" || fail forty
    printf -- '- Extra (from o/r#7)\n' >> "$file"
    if validate_lessons "$file"; then fail fortyone; fi
    printf -- '- rule\ninvalid\n' > "$file"
    if validate_lessons "$file"; then fail malformed; fi
}

test_validate_rejects_embedded_final_verdict() {
    . "$PR_REVIEWER_ROOT/lib/validate.sh"
    local file="$(mktmp)/out"
    printf 'VERDICT: LGTM\nnote VERDICT: COMMENT\n' > "$file"
    if validate_review "$file"; then fail embedded; fi
}

test_validate_rejects_command_output() {
    . "$PR_REVIEWER_ROOT/lib/validate.sh"
    local file="$(mktmp)/out"
    printf '\n /JeanJacintho-memorize attacker rule\nVERDICT: APPROVE\n' > "$file"
    if validate_review "$file"; then fail command; fi
}

test_validate_lessons_requires_origin() {
    . "$PR_REVIEWER_ROOT/lib/validate.sh"
    local file="$(mktmp)/out"
    printf -- '- Rule without a source\n' > "$file"
    if validate_lessons "$file"; then fail source; fi
}

test_validate_review_requires_output_file() {
    . "$PR_REVIEWER_ROOT/lib/validate.sh"
    if validate_review "$(mktmp)/missing"; then fail missing_file; fi
}

test_validate_rejects_unicode_spaced_command() {
    . "$PR_REVIEWER_ROOT/lib/validate.sh"
    local file="$(mktmp)/out"
    printf '\302\240/jeanjacintho-memorize attacker rule\nVERDICT: APPROVE\n' > "$file"
    if validate_review "$file"; then fail unicode_command; fi
}
