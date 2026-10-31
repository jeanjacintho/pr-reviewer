# Runs the review engine chosen for the repository. Never falls back to
# another engine: an unknown one fails the command visibly.
engine_text() {
    case "$(repo_engine "$1")" in
        codex) codex_text "$@" ;;
        claude) claude_text "$@" ;;
        *) log "Unknown review engine for $1"; return 1 ;;
    esac
}
