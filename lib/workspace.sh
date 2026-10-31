prepare_worktree() {
    local cache="$WORK_DIR/$1" path="$WORK_DIR/wt/${1%/*}+${1#*/}-$2-$3"
    mkdir -p "$(dirname "$cache")" "$WORK_DIR/wt"
    if [ ! -d "$cache/.git" ]; then gh repo clone "$1" "$cache" -- --no-checkout >&2 || return; fi
    git -C "$cache" fetch origin >&2 || return
    git -C "$cache" fetch origin "+refs/pull/$2/head:refs/pr/$2" >&2 || return
    git -C "$cache" worktree prune --expire now >&2 || return
    # Clean only the dedicated disposable worktree left by an interrupted command.
    if [ -d "$path" ]; then cleanup_worktree "$path" || return; fi
    git -C "$cache" -c core.hooksPath=/dev/null worktree add --detach "$path" "${4:-refs/pr/$2}" >&2 || return
    printf '%s\n' "$path"
}

cleanup_worktree() {
    git -C "$1" -c core.hooksPath=/dev/null worktree remove --force "$1"
}

sha_exists() {
    git -C "$WORK_DIR/$1" cat-file -e "$2^{commit}" 2>/dev/null
}

base_file() {
    git -C "$WORK_DIR/$1" show "origin/$2:$3" 2>/dev/null || :
}
