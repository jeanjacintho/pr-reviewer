fetch_open_prs() {
    gh api graphql -f query='query($owner:String!,$name:String!){repository(owner:$owner,name:$name){pullRequests(states:OPEN,first:50,orderBy:{field:UPDATED_AT,direction:DESC}){nodes{number headRefOid baseRefName author{login} comments(last:30){nodes{id body createdAt author{login}}}}}}}' -f owner="${1%/*}" -f name="${1#*/}"
}

reaction() {
    gh api graphql -f query="mutation(\$id:ID!,\$content:ReactionContent!){$1(input:{subjectId:\$id,content:\$content}){subject{id}}}" -f id="$2" -f content="$3" > /dev/null
}

react() {
    reaction addReaction "$@"
}

unreact() {
    reaction removeReaction "$@"
}

post_comment() {
    gh pr comment "$2" -R "$1" --body-file "$3"
}

prev_review() {
    local login
    login="$(gh api user --jq .login)" || return
    gh api --paginate "repos/$1/issues/$2/comments" | jq -rs --arg marker "$MARKER" --arg login "$login" '
        [ .[][] | select(.user.login == $login) | select(.body | contains($marker) and test("(^|\\n)<sub>(Full|Update) review at ") and test("(^|\\n)VERDICT: (APPROVE( — pending: .+)?|COMMENT)(\\n|$)")) ] | sort_by(.created_at, .id) | last | .body // empty'
}

pr_meta() {
    gh pr view "$2" -R "$1" --json title,body,author,baseRefName,headRefOid,commits,files | jq '
        .author = .author.login | .commits |= map(.messageHeadline) | .files |= map(.path)'
}

comment_body() {
    gh api graphql -f query='query($id:ID!){node(id:$id){... on IssueComment{body}}}' -f id="$1" | jq -er '.data.node.body'
}
