def repo_re: "^[A-Za-z0-9-]+/[A-Za-z0-9_.-]+\\z";
def repo_name_ok: test(repo_re) and (split("/")[1] | IN(".", "..") | not);
def login_re: "^[A-Za-z0-9-]{1,39}\\z";
def model_re: "^[A-Za-z0-9._:-]{0,64}\\z";

def entries:
  .repos[]?
  | select(type == "object" and (.repo | type) == "string" and (.repo | repo_name_ok));

def of($repo): entries | select((.repo | ascii_downcase) == ($repo | ascii_downcase));

def enabled_repos: entries | select(.enabled != false) | .repo;

def trusted_logins($repo):
  [of($repo) | .trusted_users | arrays | .[] | strings | select(test(login_re)) | ascii_downcase];

def model_of($repo): [of($repo) | .model? | strings | select(test(model_re))][0] // "";

def test_cmd_of($repo): [of($repo) | .test_cmd? | strings][0] // "";
