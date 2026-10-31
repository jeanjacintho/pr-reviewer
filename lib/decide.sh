resolve_mode() {
    if [ "$1" = review ]; then
        echo full
    elif [ -z "$3" ] || [ "$4" = no ]; then
        echo fallback
    elif [ "$2" = "$3" ]; then
        echo noop
    else
        echo update
    fi
}

test_decision() {
    local cmd
    cmd="$(repo_test_cmd "$1")"
    if [ -z "$cmd" ]; then
        echo not-configured
    elif repo_is_trusted "$1" "$2"; then
        printf 'run\t%s\n' "$cmd"
    else
        echo skip-untrusted
    fi
}
