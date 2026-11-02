# Failures worth another try: GitHub outages and network errors, never 4xx.
transient_gh_error() {
    grep -Eiq 'Something went wrong while executing your query|HTTP 5[0-9][0-9]|Bad Gateway|Service Unavailable|Gateway Time-?out|timed? ?out|connection (reset|refused)|dial tcp|unexpected EOF|could not resolve host|secondary rate limit|HTTP 429' "$1"
}

# Runs a command, retrying transient failures with a growing delay. The command
# can read GH_ATTEMPT. The final error's first line goes to poll.log.
gh_retry() {
    local errors output rc n=1
    errors="$(mktemp)" output="$(mktemp)"
    while :; do
        GH_ATTEMPT=$n
        rc=0
        "$@" > "$output" 2> "$errors" || rc=$?
        if [ "$rc" -eq 0 ]; then cat "$output"; rm -f "$errors" "$output"; return 0; fi
        if [ "$n" -ge "$GH_RETRY_ATTEMPTS" ] || ! transient_gh_error "$errors"; then break; fi
        sleep $((GH_RETRY_DELAY * n))
        n=$((n + 1))
    done
    log "GitHub call failed after $n attempt(s): $(head -n 1 "$errors")"
    cat "$errors" >&2
    rm -f "$errors" "$output"
    return "$rc"
}

fetch_open_prs() {
    gh_retry gh api graphql -f query='query($owner:String!,$name:String!){repository(owner:$owner,name:$name){pullRequests(states:OPEN,first:50,orderBy:{field:UPDATED_AT,direction:DESC}){nodes{number headRefOid baseRefName author{login} comments(last:30){nodes{id body createdAt author{login}}}}}}}' -f owner="${1%/*}" -f name="${1#*/}"
}

reaction() {
    gh_retry gh api graphql -f query="mutation(\$id:ID!,\$content:ReactionContent!){$1(input:{subjectId:\$id,content:\$content}){subject{id}}}" -f id="$2" -f content="$3" > /dev/null
}

react() {
    reaction addReaction "$@"
}

unreact() {
    reaction removeReaction "$@"
}

# Exit 0: the bot already published this exact text in the last minutes.
# 1: it did not. 2: the lookup itself failed, so nothing is known.
comment_already_posted() {
    local login since comments found
    login="$(bot_login)" || return 2
    since="$(date -u -v-5M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"
    comments="$(gh_retry gh api --paginate "repos/$1/issues/$2/comments")" || return 2
    found="$(printf '%s' "$comments" | jq -rs --arg login "$login" --arg since "$since" --rawfile body "$3" '
        [ .[][] | select(.user.login == $login and .created_at >= $since and (.body | rtrimstr("\n")) == ($body | rtrimstr("\n"))) ] | length > 0')" || return 2
    [ "$found" = true ]
}

# A retry first makes sure the previous attempt did not reach GitHub; when that
# cannot be established the attempt fails rather than risk a second comment.
post_attempt() {
    local rc=0
    if [ "$GH_ATTEMPT" -gt 1 ]; then
        comment_already_posted "$@" || rc=$?
        case "$rc" in
            0) return 0 ;;
            2) return 1 ;;
        esac
    fi
    gh pr comment "$2" -R "$1" --body-file "$3"
}

post_comment() {
    gh_retry post_attempt "$@"
}

# The GitHub account the bot posts as.
bot_login() {
    gh_retry gh api user --jq .login
}

# Recognizes the current footer and the older small-print one.
prev_review() {
    local login
    login="$(bot_login)" || return
    gh_retry gh api --paginate "repos/$1/issues/$2/comments" | jq -rs --arg marker "$MARKER" --arg login "$login" '
        [ .[][] | select(.user.login == $login) | select(.body | contains($marker) and test("(^|\\n)(<sub>|\\*\\*)?(Full|Update) review(\\*\\*)? at ") and test("(^|\\n)VERDICT: (APPROVE( — pending: .+)?|COMMENT)(\\n|$)")) ] | sort_by(.created_at, .id) | last | .body // empty'
}

pr_meta() {
    gh_retry gh pr view "$2" -R "$1" --json title,body,author,baseRefName,headRefOid,commits,files | jq '
        .author = .author.login | .commits |= map(.messageHeadline) | .files |= map(.path)'
}

comment_body() {
    gh_retry gh api graphql -f query='query($id:ID!){node(id:$id){... on IssueComment{body}}}' -f id="$1" | jq -er '.data.node.body'
}
