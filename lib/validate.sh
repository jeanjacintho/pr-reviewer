validate_review() {
    [ -s "$1" ] || return 1
    REVIEW_VALIDATE_PREFIX="${CMD_PREFIX:-jeanjacintho}" perl -CSD -Mutf8 -0777 -ne 's/\s+\z//; exit 1 if /\A\s*\/\Q$ENV{REVIEW_VALIDATE_PREFIX}\E-(?:review|update-review|memorize)(?:\s|$)/i; exit !/(?:\A|\n)VERDICT: (?:APPROVE|APPROVE — pending: \S[^\n]*|COMMENT)\z/' "$1"
}

validate_lessons() {
    perl -ne 'next if /^\s*$/; $n++; $bad++ unless m{^- .+ \(from [^/\s()]+/[^#\s()]+#[1-9][0-9]*\)\s*$}; END { exit !($n && $n <= 40 && !$bad) }' "$1"
}
