# Checks and joins the text that the deep review stages hand to each other.
# The format rules live in stages.pl; these wrappers give them Bash names.
validate_hypotheses() {
    perl "$ROOT/lib/stages.pl" hypotheses "$1"
}

validate_verification() {
    perl "$ROOT/lib/stages.pl" verification "$1" "$2"
}

# merge_verified <angle> <hypotheses> <verification>: prints the findings worth
# writing up, each tagged with the angle and with how well it was verified.
merge_verified() {
    perl "$ROOT/lib/stages.pl" merge "$1" "$2" "$3"
}
