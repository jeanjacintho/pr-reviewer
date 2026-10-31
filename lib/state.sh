state_init() {
    mkdir -p "$STATE_DIR"
    [ -f "$STATE_DIR/$1.json" ] || printf '%s\n' "$2" > "$STATE_DIR/$1.json"
}

seen_has() {
    state_init seen '[]'
    jq -e --arg id "$1" 'index($id) != null' "$STATE_DIR/seen.json" > /dev/null
}

state_write() {
    local store="$1" filter="$2" tmp
    shift 2
    tmp="$(mktemp "$STATE_DIR/$store.XXXXXX")"
    jq "$@" "$filter" "$STATE_DIR/$store.json" > "$tmp" || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$STATE_DIR/$store.json"
}

seen_add() {
    state_init seen '[]'
    state_write seen '. + [$id] | unique' --arg id "$1"
}

reviewed_get() {
    state_init reviewed '{}'
    jq -r --arg key "$1#$2" '.[$key].sha // empty' "$STATE_DIR/reviewed.json"
}

reviewed_set() {
    state_init reviewed '{}'
    state_write reviewed '.[$key] = {sha: $sha, at: $at}' --arg key "$1#$2" --arg sha "$3" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
