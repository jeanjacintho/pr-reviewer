parse_command() {
    printf '%s' "$1" | jq -Rrs -L "${LIB_ROOT:-$ROOT}/lib" --arg prefix "$CMD_PREFIX" '
        include "select"; parse_command($prefix) |
        select(. != null) | .kind + "\t" + .args'
}
