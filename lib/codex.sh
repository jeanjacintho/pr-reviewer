codex_safety() {
    local directory="$1" output="$2" project_key feature name
    project_key="$(printf '%s' "$directory" | jq -Rs .)"
    CODEX_SAFETY_ARGS=(-c project_doc_max_bytes=0 -c 'web_search="disabled"' -c 'approval_policy="never"' -c "projects.$project_key.trust_level=\"untrusted\"")
    for feature in apps plugins hooks browser_use browser_use_external image_generation multi_agent multi_agent_v2; do
        CODEX_SAFETY_ARGS+=( --disable "$feature" )
    done
    # Listing configuration is local and never starts a model session.
    run_with_timeout 30 codex "${CODEX_SAFETY_ARGS[@]}" -C "$directory" mcp list --json < /dev/null | jq -r '.[].name | @json' > "$output.servers"
    while IFS= read -r name; do
        CODEX_SAFETY_ARGS+=( -c "mcp_servers.$name.enabled=false" )
    done < "$output.servers"
}

codex_text() {
    local seconds="$1" directory="$2" output="$3" prompt="$4"
    codex_safety "$directory" "$output"
    local args=(exec --sandbox read-only -C "$directory" --output-last-message "$output")
    args+=( "${CODEX_SAFETY_ARGS[@]}" )
    if [ "${5:-}" = text ]; then args+=( --skip-git-repo-check --disable shell_tool --disable view_image ); fi
    if [ -n "$CODEX_MODEL" ]; then args+=( -m "$CODEX_MODEL" ); fi
    run_with_timeout "$seconds" codex "${args[@]}" - < "$prompt" > "$output.log" 2>&1
}
