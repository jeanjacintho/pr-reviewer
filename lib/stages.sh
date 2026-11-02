# Checks and joins the text that the deep review stages hand to each other.
# The format rules live in stages.pl, next to this file; these wrappers give
# them Bash names.
STAGES_PL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/stages.pl"

validate_hypotheses() {
    perl "$STAGES_PL" hypotheses "$1"
}

validate_verification() {
    perl "$STAGES_PL" verification "$1" "$2"
}

# merge_verified <angle> <hypotheses> <verification>: prints the findings worth
# writing up, each tagged with the angle and with how well it was verified.
merge_verified() {
    perl "$STAGES_PL" merge "$1" "$2" "$3"
}

# True when the angle listed at least one valid hypothesis.
has_hypotheses() {
    perl "$STAGES_PL" present "$1"
}

# validate_ceiling <verified findings> <review>: the review may not rate a
# finding above what the checks confirmed (open findings stay [open]).
validate_ceiling() {
    perl "$STAGES_PL" ceiling "$1" "$2"
}
