# One line saying why an engine call failed, taken from its own output: the
# last line that sounds like an error, else the last line at all.
engine_error_line() {
    local file line
    for file in "$1" "$1.log"; do
        [ -s "$file" ] || continue
        line="$({ grep -Ei 'error|fail|denied|limit|login|auth|usage|quota' "$file" || true; } | tail -n 1)"
        if [ -z "$line" ]; then line="$({ grep -v '^[[:space:]]*$' "$file" || true; } | tail -n 1)"; fi
        printf '%.200s\n' "$line"
        return 0
    done
}

# Runs the review engine chosen for the repository. Never falls back to
# another engine: an unknown one fails the command visibly. A failing engine
# leaves its own error line in the log.
engine_text() {
    local rc=0
    case "$(repo_engine "$1")" in
        codex) codex_text "$@" || rc=$? ;;
        claude) claude_text "$@" || rc=$? ;;
        *) log "Unknown review engine for $1"; return 1 ;;
    esac
    if [ "$rc" -ne 0 ]; then log "Engine failed for $1: $(engine_error_line "$4")"; fi
    return "$rc"
}
