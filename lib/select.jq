def trim: gsub("^\\s+|\\s+$"; "");
def parse_command($prefix):
  gsub("\r\n"; "\n") | sub("^\\s*"; "") |
  split("\n") | .[0] as $first |
  ($first | try capture("^/(?<prefix>[^\\s/]+?)-(?<kind>update-review|review|memorize)(?:\\s+(?<args>.*)|$)"; "i") catch null) as $cmd |
  if $cmd == null then null
  elif ($cmd.prefix | ascii_downcase) != ($prefix | ascii_downcase) then null
  else {kind: ($cmd.kind | ascii_downcase), args: ([( $cmd.args // "" )] + .[1:] | join("\n") | trim)} end;

def select_triggers($repo; $prefix; $trusted; $watermark; $seen):
  [$trusted[] | ascii_downcase] as $users |
  [.data.repository.pullRequests.nodes[] | . as $pr | .comments.nodes[] |
    select(.body | contains("<!-- " + $prefix + "-reviewer -->") | not) |
    . as $comment | (.body | parse_command($prefix)) as $cmd |
    select($cmd != null) |
    select(($users | index(($comment.author.login // "" | ascii_downcase))) != null) |
    select(.createdAt > $watermark) |
    select(($seen | index($comment.id)) == null) |
    {repo: $repo, pr: $pr.number, id, kind: $cmd.kind, args: $cmd.args,
     commenter: .author.login, pr_author: $pr.author.login, head_sha: $pr.headRefOid, created_at: .createdAt}]
  | sort_by(.created_at, .id);
