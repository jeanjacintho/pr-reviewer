#!/bin/bash
# Runs every test_* function from tests/test_*.sh, each in its own subshell.
# Usage: tests/run.sh [filter]  (filter matches a test name or a file name)
set -uo pipefail

TESTS_DIR="${TESTS_DIR:-$(cd "$(dirname "$0")" && pwd)}"
export PR_REVIEWER_ROOT="${PR_REVIEWER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
FILTER="${1:-}"
TEST_TMP_ROOT="$(mktemp -d)"
export TEST_TMP_ROOT
export PR_REVIEWER_CONFIG="$TEST_TMP_ROOT/config-absent"
export PATH="$TESTS_DIR/fakes:$PATH"
trap 'rm -rf "$TEST_TMP_ROOT"' EXIT

. "$TESTS_DIR/helpers.sh"

# Names of the test_* functions a file defines, read from bash itself so
# heredoc text that looks like a definition is not picked up.
list_tests() {
    ( . "$1"; declare -F | awk "{print \$3}" | grep "^test_" )
}

passed=0
failed=0
for file in "$TESTS_DIR"/test_*.sh; do
    [ -e "$file" ] || continue
    for name in $(list_tests "$file"); do
        case "$name $(basename "$file")" in
            *"$FILTER"*) ;;
            *) continue ;;
        esac
        log="$TEST_TMP_ROOT/$name.log"
        ( . "$file"; "$name" ) >"$log" 2>&1
        if [ $? -eq 0 ]; then
            passed=$((passed + 1))
            echo "ok   $name"
        else
            failed=$((failed + 1))
            echo "FAIL $name"
            sed 's/^/     /' "$log"
        fi
    done
done

echo "$((passed + failed)) tests: $passed passed, $failed failed"
[ "$failed" -eq 0 ]
