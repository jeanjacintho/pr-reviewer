# One-time conversion of the legacy global config arrays to repos.json.
json_array() {
    if [ "$#" -eq 0 ]; then echo '[]'; return; fi
    printf '%s\0' "$@" | jq -Rsc 'split("\u0000") | .[:-1]'
}

migrate_legacy_config() {
    (
        . "$1"
        jq -n \
            --argjson repos "$(json_array ${REPOS[@]+"${REPOS[@]}"})" \
            --argjson trusted "$(json_array ${TRUSTED_USERS[@]+"${TRUSTED_USERS[@]}"})" \
            --argjson commands "$(json_array ${TEST_CMDS[@]+"${TEST_CMDS[@]}"})" \
            '{repos: [$repos[] as $repo | {
                repo: $repo,
                enabled: true,
                trusted_users: $trusted,
                model: "",
                test_cmd: ([$commands[] | select(startswith($repo + "|")) | .[($repo | length) + 1:]][0] // "")
            }]}'
    )
}
