# Assertions and helpers shared by every test file. A failed assertion
# prints what differed and exits the test's subshell with status 1.

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

assert_eq() {
    [ "$1" = "$2" ] || fail "expected: $1" "
  actual: $2${3:+
 message: $3}"
}

assert_contains() {
    case "$1" in
        *"$2"*) ;;
        *) fail "expected to contain: $2
  actual: $1" ;;
    esac
}

assert_not_contains() {
    case "$1" in
        *"$2"*) fail "expected not to contain: $2
  actual: $1" ;;
    esac
}

# Prints a fresh directory that the runner removes after the run.
mktmp() {
    mktemp -d "$TEST_TMP_ROOT/t.XXXXXX"
}
