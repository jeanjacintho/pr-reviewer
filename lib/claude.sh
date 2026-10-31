# Claude Code in print mode, read-only: --restricted drops shell, code and
# network tools and ignores user and project settings; only file reading
# tools stay, and none at all for text-only tasks.
claude_text() {
    local repo="$1" seconds="$2" directory="$3" output="$4" prompt="$5" tools='Read,Grep,Glob' model effort
    if [ "${6:-}" = text ]; then tools=''; fi
    model="$(repo_model "$repo")"
    effort="$(repo_effort "$repo")"
    local args=(-p --restricted --tools "$tools" --permission-mode dontAsk --strict-mcp-config --disable-slash-commands --no-session-persistence --output-format text)
    if [ -n "$model" ]; then args+=( --model "$model" ); fi
    if [ -n "$effort" ]; then args+=( --effort "$effort" ); fi
    (cd "$directory" && run_with_timeout "$seconds" claude "${args[@]}" < "$prompt" > "$output" 2> "$output.log")
}
