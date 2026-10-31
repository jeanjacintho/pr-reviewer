# Implementation log

## Baseline and method

- Read AGENTS.md, the design, the implementation plan and the local ub-mode skill before changing code. The initial working tree was clean at `e3eb347`; only development tooling existed.
- Implemented the eight plan tasks in order. Wrote behavioral tests before new implementations, observed the expected failures, and refined the implementation using independent reviews and mutation results.
- Kept later tasks out of each commit using temporary Git stashes. Restored future files without overwriting newer fixes; resolved earlier stash conflicts in favor of the already-tested committed versions. No extra development worktree remains.
- All scripts and prompts were written in this project. The automated suite uses local Git fixtures and fake gh, Codex, launchctl and fault-injection cp commands; only the separately authorized live smoke calls real GitHub and Codex.

## Changes and reasons

1. **Common foundation:** added configuration, paths, rotating logs and case-insensitive trust checks. A supervising Perl process owns a separate process group so timeout or cancellation can terminate ordinary child processes. Fixed empty-array expansion for Bash 3.2 and isolated tests from real local configuration.
2. **Commands:** added first-nonblank-line parsing, CRLF/case normalization, chronological trusted-trigger selection, watermark and seen filters. Marked bot output is always excluded, including command-shaped output, to prevent self-triggering loops.
3. **State and decisions:** added atomic JSON stores, full/update/noop decisions, trusted-author test gating, strict final verdict validation and sourced lesson-list validation. Added missing-file and Unicode-whitespace regressions.
4. **GitHub and polling:** added API helpers, a directory lock with stale-owner recovery, mark-before-dispatch semantics and per-repo failure isolation. Detached dispatch stdin so handlers cannot consume other triggers. Previous-review lookup checks the authenticated author, footer and verdict, excluding status replies and forged markers. Polling never invokes Codex.
5. **Workspaces and prompts:** added cached clones, fork pull-ref fetches, collision-free disposable paths, missing-registration pruning, SHA-pinned test worktrees and base-branch REVIEW.md. Prompts label trusted inputs and entity-escape untrusted data; tests check ordering, block ownership and closing-tag escaping.
6. **Review lifecycle:** added full and incremental review, no-op replies without inference, configured tests in a separate checkout, bounded Codex execution, output validation and one publication attempt. The reviewed SHA follows the fetched checkout. An ancestry check rejects old objects retained after force-push; the caller prefixes fallback notices. Removed redundant existence checks and pinned full/update footer labels after mutation testing. State advances only after publication succeeds, so an unpublished review never becomes a baseline.
7. **Learning:** added lesson normalization, a 40-rule cap, provenance, backup and same-filesystem atomic replacement. The taught rule is placed last in model output so even an already-known non-English lesson receives an English confirmation. Failed replacement cleans its temporary file. Failure messages distinguish invalid generation, persistence failure and a lesson saved before confirmation failure; publication is never retried automatically.
8. **Operations:** added launchd install/uninstall, dependency diagnostics, XML escaping, an explicit shared installation/service PATH and an optional PR_REVIEWER_PATH override. Reinstallation preserves configuration and the watermark. Source files and isolated state roots remain distinct. Uninstall checks the final loaded state instead of inferring it from bootout status. Added README configuration and operating instructions.

## Codex verification

- Inspected installed CLI help and feature flags; the installed version is `codex-cli 0.166.0`.
- Applied the OpenAI Docs skill and read the [official configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference). App/connector traffic is outside command sandbox network controls, so the bot explicitly disables apps, plugins, hooks, browser/image generation, web search, extra agents and every configured MCP server.
- A local `codex mcp list --json` reads configuration without inference. Session-specific flags keep project configuration untrusted and disable automatic AGENTS.md loading while retaining account authentication and model preferences. Text-only learning sessions also disable shell and image-reading tools.
- Initial flag checks were local and did not change user configuration. Subsequent authorized live reviews and learning are documented below.

## Verification and commits

Every code commit received an independent `tools/review --engine claude` review and a passing `tools/gate`. Reviews were static; the local runner and gate performed execution. Medium/blocking findings were fixed and re-reviewed. Relevant initial gate failures were resolved before committing.

| Task | Tests at gate | Mutants killed | Gate | Independent review |
| --- | --- | --- | --- | --- |
| 1: common | 35/35 | 8/8 | PASS | OK |
| 2: commands | 39/39 | 6/6 | PASS | OK |
| 3: state/decisions | 51/51 | 15/15 | PASS | OK |
| 4: polling | 58/58 | 19/19 | PASS | OK |
| 5: workspace/prompts | 64/64 | 12/12 | PASS | OK |
| 6: review | 76/76 | 31/31 | PASS | OK |
| 7: learning | 82/82 | 2/2 | PASS | OK |
| 8: operations | 86/86 | 8/8 | PASS | OK |

The installer tests explicitly require a valid first-install timestamp and preserve an older timestamp on reinstall, so the assertion does not depend on clock timing. A focused mutation run killed all eight installation/uninstallation mutants. The final full gate passed all 86 tests, with no complexity or duplication violations and all eight changed-line operation mutants killed.

## Operational status

The authorized live smoke passed on PR [#1](https://github.com/jeanjacintho/pr-reviewer/pull/1), which was closed without merging. The active installation is `~/Library/Application Support/pr-reviewer`; its config watches only `jeanjacintho/pr-reviewer`, trusts `jeanjacintho`, and runs the configured Bash test suite for trusted PR authors. Launchd remains loaded with a 120-second interval.

## Initial local delivery

- All eight implementation tasks have passing gates and independent reviews. The final Bash syntax check and `git diff --check` passed.
- GitHub CLI and Codex CLI authentication checks passed; no login or user configuration was changed.
- Code commits, in order: `391201c`, `4f2ed5b`, `fb3746c`, `f14ac46`, `b8de821`, `738fe35`, `8a71eca`, `9a69753` (the final operations commit can also be identified by `feat(launchd): install and operate the personal reviewer`).
- Temporary Git stashes were removed and only the original `main` worktree remains. The configured publication target is `origin/main` at `https://github.com/jeanjacintho/pr-reviewer.git`.
- At the initial local delivery, live activation was intentionally pending. Jean subsequently authorized it; the completed live result is recorded below.

## Authorized live smoke — completed

- Jean authorized creating the disposable PR and leaving the Mac service active.
- Created PR [#1](https://github.com/jeanjacintho/pr-reviewer/pull/1) with a documentation-only fixture. The initial launchd job could not read scripts from the Documents checkout (`Operation not permitted`). Unloaded that job and installed a separate checkout at `~/Library/Application Support/pr-reviewer`, preserving configuration and the original installation watermark.
- The relocated job received the review command, prepared separate review/test worktrees, and posted exactly one failure reply. Later polling cycles did not retry the seen command.
- Diagnosed actual CLI configuration loading outside the bot's publication path. Quoted names in dotted override paths created a new MCP entry without transport configuration. Root TOML table values preserve server names and project paths correctly; a real configuration listing and a real read-only Codex diagnostic succeeded with the correction.
- Extended the fake CLI to reject that malformed override and pinned a combined table for two MCP servers, including a name containing a dot. The regression failed before the code fix and passed after it.

The live compatibility fix was committed as `b8e1ae0`, independently reviewed with an OK verdict, and passed the full 86-test gate with 1/1 changed-line mutants killed. The inactive Documents configuration was archived under the development checkout's ignored state directory; the installed copy owns the active configuration and learned rules.

| Live check | Evidence | Result |
| --- | --- | --- |
| Full review | [Command](https://github.com/jeanjacintho/pr-reviewer/pull/1#issuecomment-6546769913), [reply](https://github.com/jeanjacintho/pr-reviewer/pull/1#issuecomment-6546788127) | APPROVE at `183fe0f`; 86 tests passed; HOORAY reaction |
| Incremental review | [Command](https://github.com/jeanjacintho/pr-reviewer/pull/1#issuecomment-6546816441), [reply](https://github.com/jeanjacintho/pr-reviewer/pull/1#issuecomment-6546840378) | Since `183fe0f → 6aa2108`; APPROVE; 86 tests passed; HOORAY reaction |
| Unchanged update | [Reply](https://github.com/jeanjacintho/pr-reviewer/pull/1#issuecomment-6546886755) | Exact no-new-commits reply, unchanged baseline, THUMBS_UP reaction |
| Explicit learning | [Reply](https://github.com/jeanjacintho/pr-reviewer/pull/1#issuecomment-6546888460) | English rule persisted with `jeanjacintho/pr-reviewer#1` provenance, original empty file backed up, THUMBS_UP reaction |
| At-most-once handling | Snapshot in ignored `state/smoke-comments.json`; installed `state/seen.json` | Five commands, five replies including the initial CLI failure; no extra comments after a quiet poll |
| Cleanup and operation | PR CLOSED; temporary local/remote branch and development worktree removed; installed worktree directory empty | Service remains loaded, last exit code 0, interval 120 seconds |

Automatic dispatch latency for the successful commands was within 120 seconds: full review 59 seconds, incremental review 88 seconds, unchanged update 108 seconds, and lesson learning 111 seconds. Reviews and learning then completed in their normal processing time.

The installed lesson is:

> Report correctness bugs only when you can identify a concrete failing path and cite current file:line references; exclude style-only changes. (from jeanjacintho/pr-reviewer#1)

The installed checkout intentionally retains the learned `lessons.md` as local operational data. Its ignored `config.sh`, state, logs and repository cache were preserved. The development checkout remains separate and clean after committing this record.

## Local dashboard and per-repository settings

Planned in `docs/superpowers/plans/2026-10-31-dashboard.md`; implemented in seven small commits on `main`, each passing `tools/gate` and an independent Codex review.

- Settings moved from global arrays in `config.sh` to `repos.json`: per repository `enabled`, `trusted_users`, `model`, `test_cmd`. Trust is per repository; the global `CODEX_MODEL` stays the default. `install.sh` converts an old configuration once and never overwrites an existing `repos.json`.
- Review findings that changed the code: a trusted list of the wrong type must trust nobody; repository names such as `../r` are rejected; a damaged file yields no partial result; a trailing newline in a repo, login or model is rejected (jq's `$` matches before it, so the patterns end with `\z`); migration is written through a temporary file; the page edits nothing until the settings loaded and while saving.
- The dashboard is Node with no packages, bound to `127.0.0.1`, refusing foreign `Host`/`Origin`, with a strict content security policy. It runs as a second launchd job; the installer skips it, and says so, when Node is missing.
- Live check (2026-10-31): the active installation was backed up to `state/backup-before-dashboard/`, fast-forwarded to `55e4b1e` and re-installed; `install.sh` converted `config.sh` into an equivalent `repos.json`, and both launchd jobs loaded. A disposable documentation PR, [#2](https://github.com/jeanjacintho/pr-reviewer/pull/2), got `/jeanjacintho-review`; the poll dispatched it within two minutes, the bot posted exactly one review (no findings, test results included, HOORAY reaction), recorded the SHA in `reviewed.json` and marked the comment seen. The PR was then closed and its branch and worktree removed. The dashboard answered on `127.0.0.1:4777` and refused a foreign `Origin` with 403. One earlier `Fetch failed` at 19:40Z was a transient network error before the update.


## Review engine per repository — live check

Implemented per `docs/superpowers/plans/2026-10-31-engines.md` in commits `6a26c29`, `c5362ea`, `a2fa457`, `e7f388d` and `860c4c9`, each passing `tools/gate` and an independent Codex review. The installed checkout was fast-forwarded and only the dashboard job was restarted; `/api/engines` reported Codex 0.166 (eight models, default `gpt-6.1-sol`) and Claude Code 2.1.

- Live check (2026-10-31): `jeanjacintho/pr-reviewer` was switched through the dashboard API to Claude Code (`sonnet`, effort `low`). On the disposable PR [#3](https://github.com/jeanjacintho/pr-reviewer/pull/3) the command was dispatched within a poll cycle, a `claude -p --restricted …` run was observed, and exactly one review was posted (APPROVE, tests 122/122 included, HOORAY reaction) about 35 seconds after dispatch. The PR was closed, its branch and worktree removed, and the repository set back to Codex with defaults.
- Before implementing, Claude Code with these flags was checked by hand: it could not create a file, run a shell command, read outside the working directory or fetch a URL.
