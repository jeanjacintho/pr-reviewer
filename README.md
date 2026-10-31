# Personal PR reviewer

A Bash 3.2 bot for macOS that watches configured GitHub repositories every two
minutes. A trusted person's command starts one Codex review and posts one English
comment with ranked findings and a verdict. Polling uses gh and jq, without Codex.

Requirements: macOS with a signed-in graphical session, Git, Perl, jq, GitHub CLI
(`gh auth login`) and Codex CLI signed in to your account. The implementation was validated with Codex CLI 0.166.0. The CLI must
support `codex exec --sandbox read-only --output-last-message` and the
`project_doc_max_bytes` setting, feature toggles and `codex mcp list --json`. No Node, Python, Docker or public server
is needed to run the bot.

Use an installed checkout outside macOS-protected Documents/Desktop folders.
The live smoke test found that launchd could not read this project from Documents.
Keep the development checkout separate from the active installation.
Run operational commands and edit config.sh, rules.md and lessons.md in that
installed checkout; it owns the active state and repository caches.

To configure and start:

```bash
git clone https://github.com/jeanjacintho/pr-reviewer.git "$HOME/Library/Application Support/pr-reviewer"
cd "$HOME/Library/Application Support/pr-reviewer"
cp config.example.sh config.sh
# Edit config.sh: choose repositories, trusted people and optional test commands.
./install.sh
```

Install is idempotent: it preserves configuration and the first-install watermark.
It registers `~/Library/LaunchAgents/com.jeanjacintho.pr-reviewer.plist` with a
120-second interval. Keep this checkout in place while installed. Its path may
contain spaces. Launchd's PATH includes Homebrew and `~/.local/bin`; put CLI
binaries there, or set `PR_REVIEWER_PATH` when installing to use a custom PATH.
The installer checks dependencies using the same PATH that launchd will use.

`./uninstall.sh` unloads the service and removes its plist, preserving local data.
Uninstall checks the final launchd state. An already-absent service succeeds;
a still-loaded service produces a nonzero exit and a retry command after the
saved plist is removed.
Run `./poll.sh` manually for a single cycle after installing. No command created
before the first installation is acted on, including after a reinstall.

Write these as the first nonblank line of a **top-level PR conversation comment**:

- `/jeanjacintho-review [optional focus]`: review the entire PR again, even at the same SHA.
- `/jeanjacintho-update-review [optional focus]`: review changes since the previous successful review. With no new commits it replies without invoking Codex. With no usable prior SHA it announces a full review.
- `/jeanjacintho-memorize <lesson>`: teach a global rule, with optional further lines.

Commands are case-insensitive. Inline comments, submitted review bodies, quoted
examples after prose and code fences do not trigger the bot. Untrusted commenters
are ignored. A failed command is not retried automatically: comment again.
The script attempts at most one comment publication per command; if GitHub's
response is ambiguous, it does not retry and risk a duplicate. Check local logs.

Configuration (`config.sh`, ignored by Git):

| Setting | Meaning |
| --- | --- |
| `CMD_PREFIX` | Command namespace; defaults to `jeanjacintho` |
| `REPOS` | Explicit `owner/repo` Bash array; only these repositories are watched |
| `TRUSTED_USERS` | Case-insensitive GitHub login array for commenters and test authors |
| `REVIEW_TIMEOUT_SECS` | Codex review limit; default 1200 seconds |
| `TEST_TIMEOUT_SECS` | Configured test command limit; default 900 seconds |
| `TEST_CMDS` | Optional array of `owner/repo\|command` strings; may be empty |
| `CODEX_MODEL` | Optional model override; empty uses Codex's configured default |

The commenter controls authorization to review. Tests additionally require the
**PR author** to be trusted and an explicit command in `TEST_CMDS`. Test commands
come from local config, never from PR text. They run in a separate disposable
worktree at the same SHA, with a timeout. Their exit code and last 200 log lines
are supplied to Codex; Codex does not execute tests itself. An untrusted author's
code is inspected without executing its tests. Only configure commands and
trusted people whose code you are willing to execute locally.

Codex reads a detached review worktree with the read-only sandbox. Automatic repository instructions, project config,
hooks, apps, plugins, browser and image generation, web search, extra agents and
configured MCP servers are disabled for that session. A local `codex mcp list`
reads configuration without starting a model session; only `codex exec` starts
inference. Lesson sessions also disable shell commands and image reading. PR text, diffs,
logs and previous comments are delimited as data. Standing rules are in
`rules.md`; taught lessons are in `lessons.md` (English bullets, at most 40, with
source PRs). The previous lessons file is saved to `state/lessons.bak`. Per-repo
rules belong in that repository's `REVIEW.md`, read from the **base branch**.
No GitHub approval is submitted; the verdict lives in the comment.

Progress reactions: 👀 started, 🎉 succeeded, 😕 failed, 👍 no changes or lesson
learned. GitHub has no ✅ reaction, so the design's success check maps to HOORAY
(🎉). Successful reviews include the reviewed SHA and a hidden marker.

State is under `state/`: `started-at`, `seen.json`, `reviewed.json`, `poll.log`
(rotated at 1 MiB), and launchd stdout/stderr in `launchd.log`. Repository caches
and disposable worktrees live under `work/`. A directory lock serializes polling;
a stale lock is reclaimed when its owner is no longer alive. Do not delete state
to retry a failed command; submit a new command instead.

The v1 poll reads the 50 most recently updated open PRs and the last 30 conversation
comments on each. A command outside that window can be missed; reissue it.
Large diffs are currently included in full; context-limit errors are reported as
failures and need a narrower PR. The Mac must be awake for launchd to poll.

Development:

```bash
bash tests/run.sh
bash tests/run.sh review_command
tools/gate
tools/review --engine claude
```

Tests use local Git fixtures and fake gh/Codex/launchctl commands, never real
GitHub or Codex. The gate includes complexity, duplication and mutation checks.
The implementation record is in [docs/implementation-log.md](docs/implementation-log.md).
A real GitHub smoke test and launchd activation are separate operational steps;
they require selecting a scratch repository and publishing test PR comments.
