# Implementation log

## Baseline and method

- Read AGENTS.md, the design, the implementation plan and the local ub-mode skill before changing code. The initial working tree was clean at `e3eb347`; only development tooling existed.
- Implemented the eight plan tasks in order. Wrote behavioral tests before new implementations, observed the expected failures, and refined the implementation using independent reviews and mutation results.
- Kept later tasks out of each commit using temporary Git stashes. Restored future files without overwriting newer fixes; resolved earlier stash conflicts in favor of the already-tested committed versions. No extra development worktree remains.
- All scripts and prompts were written in this project. Tests use local Git fixtures and fake gh, Codex, launchctl and fault-injection cp commands; no test calls real GitHub or a real model.

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
- Checked the flags locally without starting a real review or changing user configuration. The real GitHub/model smoke test remains a separate operational step.

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

## Operational follow-up

The plan's live smoke test explicitly requires Jean: choose a scratch repository, activate launchd, create a small PR, and publish the full-review, update-review and memorize commands. No launchd job has been activated and no smoke-test PR/comment has been published. This step remains unchecked in the plan pending repository selection and authorization for those GitHub writes.

## Final local status

- All eight implementation tasks have passing gates and independent reviews. The final Bash syntax check and `git diff --check` passed.
- GitHub CLI and Codex CLI authentication checks passed; no login or user configuration was changed.
- Code commits, in order: `391201c`, `4f2ed5b`, `fb3746c`, `f14ac46`, `b8de821`, `738fe35`, `8a71eca`, `9a69753` (the final operations commit can also be identified by `feat(launchd): install and operate the personal reviewer`).
- Temporary Git stashes were removed and only the original `main` worktree remains. The configured publication target is `origin/main` at `https://github.com/jeanjacintho/pr-reviewer.git`.
- Live launchd/GitHub validation remains pending as described above; installation files and test PR comments were not published or activated during local validation.

## Authorized live smoke — in progress

- Jean authorized creating the disposable PR and leaving the Mac service active.
- Created PR [#1](https://github.com/jeanjacintho/pr-reviewer/pull/1) with a documentation-only fixture. The initial launchd job could not read scripts from the Documents checkout (`Operation not permitted`). Unloaded that job and installed a separate checkout at `~/Library/Application Support/pr-reviewer`, preserving configuration and the original installation watermark.
- The relocated job received the review command, prepared separate review/test worktrees, and posted exactly one failure reply. Later polling cycles did not retry the seen command.
- Diagnosed actual CLI configuration loading outside the bot's publication path. Quoted names in dotted override paths created a new MCP entry without transport configuration. Root TOML table values preserve server names and project paths correctly; a real configuration listing and a real read-only Codex diagnostic succeeded with the correction.
- Extended the fake CLI to reject that malformed override and pinned a combined table for two MCP servers, including a name containing a dot. The regression failed before the code fix and passed after it.
