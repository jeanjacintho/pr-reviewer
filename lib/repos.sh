# Per-repository settings read from repos.json. A missing or invalid file
# yields no repositories and trusts nobody.
repos_query() {
    local file="${PR_REVIEWER_REPOS:-$ROOT/repos.json}" filter="$1" output
    shift
    [ -f "$file" ] || return 0
    # Print only after jq read the whole file, so a damaged file yields nothing.
    if output="$(jq -r -L "${LIB_ROOT:-$ROOT}/lib" "$@" "include \"repos\"; $filter" "$file")"; then
        [ -z "$output" ] || printf '%s\n' "$output"
    else
        log "Invalid repos file: $file"
    fi
}

repos_enabled() {
    repos_query 'enabled_repos'
}

repo_trusted_users() {
    repos_query 'trusted_logins($r)[]' --arg r "$1"
}

repo_is_trusted() {
    [ "$(repos_query 'trusted_logins($r) | index($u | ascii_downcase) != null' --arg r "$1" --arg u "$2")" = true ]
}

repo_model() {
    local model
    model="$(repos_query 'model_of($r)' --arg r "$1")"
    printf '%s\n' "${model:-$CODEX_MODEL}"
}

repo_test_cmd() {
    repos_query 'test_cmd_of($r)' --arg r "$1"
}
