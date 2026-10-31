# Local dashboard Implementation Plan

> **For agentic workers:** follow `AGENTS.md` and the `ub-mode` skill. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Configure repositories, trusted people, review model and test command per repository from a web page served only on the owner's Mac, without breaking the Bash bot.

**Spec:** `docs/superpowers/specs/2026-10-31-pr-reviewer-design.md`, section "Dashboard local". The spec wins on any conflict; stop and ask.

**Architecture:** One data file, `repos.json`, read by the Bash bot with `jq` and written atomically by a zero-dependency Node server. The bot never depends on the server. Migration moves the old `config.sh` arrays into `repos.json` once.

**Tech Stack:** Bash 3.2 + `jq` (bot side); Node `http` + `node --test` (dashboard, no npm packages); launchd.

## Global Constraints

- Bot code stays Bash 3.2 and obeys `AGENTS.md` (functions at column 0, English, gate before commits).
- Node is allowed only under `dashboard/`, with no dependencies and no `package.json` dependencies block. The quality tools do not analyze it, so it stays small and is covered by `node --test`.
- `repos.json` is the single source for repos, trusted users, model and test command. No second copy in `config.sh`.
- Trust is per repository. Commenter must be in that repo's `trusted_users`; tests also need the PR author in it.
- Validate input once, at the dashboard's write boundary and again when the bot reads (a bad entry is skipped and logged, never executed as shell).
- The server listens on `127.0.0.1` only and rejects foreign `Host`/`Origin`.
- `repos.json`, `state/`, `work/`, `config.sh` are gitignored.

## Review Focus

1. A repo with an empty or missing `trusted_users` triggers nothing and runs no tests.
2. A user trusted in repo A must not trigger or run tests in repo B.
3. Malformed `repos.json` (bad JSON, bad repo name) must not crash the poll for other repos or reach a shell.
4. Dashboard write is atomic; a crash mid-write leaves the old file intact.
5. A request with a foreign `Origin` or `Host` changes nothing.

---

### Task 1: `repos.json` reader (Bash)

**Files:** Create `lib/repos.sh`, `repos.example.json`, `tests/test_repos.sh`; modify `.gitignore`, `lib/bootstrap.sh` (load list if needed).

**Interfaces produced** (read `${PR_REVIEWER_REPOS:-$ROOT/repos.json}`):
- `repos_enabled` → prints enabled, valid `owner/name`, one per line.
- `repo_trusted_users repo` → prints logins, one per line.
- `repo_model repo` → repo model, else `$CODEX_MODEL`.
- `repo_test_cmd repo` → command or empty.
- `is_trusted repo login` → 0 if login in that repo's list (case-insensitive).

- [ ] Failing tests: per-repo trust isolation (A vs B), disabled repo omitted, invalid repo name skipped, missing file yields nothing, model fallback to `CODEX_MODEL`.
- [ ] Implement with `jq`; commit `feat(config): read per-repo settings from repos.json`.

### Task 2: Poll uses per-repo trust

**Files:** modify `lib/poll.sh`, `lib/common.sh` (drop global `is_trusted`/`REPOS`), tests.

- [ ] Failing test: user trusted only in A commenting in B is ignored; polling iterates `repos_enabled`.
- [ ] Feed `repo_trusted_users` into `select_triggers`; commit `feat(poll): trust and repos come from repos.json`.

### Task 3: Per-repo model and test command

**Files:** modify `lib/codex.sh`, `lib/review.sh`, `lib/memorize.sh`, `lib/decide.sh`, tests.

- [ ] Failing tests: `codex_text` receives the repo's model (fake `codex` logs argv); test gate uses `repo_test_cmd` and the repo's trusted list for the PR author.
- [ ] Thread `repo` into `codex_text`; commit `feat(review): choose model and tests per repository`.

### Task 4: Migration and installer

**Files:** create `tools/migrate-config` (or `lib/migrate.sh`), modify `install.sh`, `config.example.sh`, `README.md`, tests.

- [ ] Failing test: a legacy `config.sh` with `REPOS`, `TRUSTED_USERS`, `TEST_CMDS`, `CODEX_MODEL` becomes the equivalent `repos.json`; running twice is a no-op; existing `repos.json` is never overwritten.
- [ ] `install.sh` runs the migration; `config.example.sh` keeps only `CMD_PREFIX` and timeouts. Commit `feat(install): migrate legacy config to repos.json`.
- [ ] Verify with `bash tests/run.sh` and a manual `./poll.sh` cycle against the fakes.

### Task 5: Dashboard API (Node)

**Files:** create `dashboard/server.js`, `dashboard/validate.js`, `dashboard/test/*.test.js`.

- [ ] Failing tests (`node --test`): `GET /api/repos`; `PUT /api/repos` validates (repo, logins, model regex) and writes atomically; foreign `Origin`/`Host` returns 403 and writes nothing; invalid body returns 400 and leaves the file unchanged; `GET /api/activity` returns `reviewed.json` and the `poll.log` tail.
- [ ] Implement; bind `127.0.0.1`, port from `DASHBOARD_PORT` (default 4777). Commit `feat(dashboard): local API for repository settings`.

### Task 6: Dashboard UI

**Files:** create `dashboard/public/index.html`, `app.js`, `style.css`.

- [ ] Table of repos with enable toggle, trusted-user chips, model field with suggestions, test command field, add/remove repo, a visible note beside trusted users that trust also lets that person's PR code run the test command, recent reviews and log tail.
- [ ] Verify in the browser (add repo, change model, reload, confirm `repos.json`). Commit `feat(dashboard): repository settings page`.

### Task 7: launchd service and docs

**Files:** modify `install.sh`, `uninstall.sh`, `lib/install.sh`, `README.md`, `docs/implementation-log.md`.

- [ ] Failing test: installer renders a second plist (`com.jeanjacintho.pr-reviewer-dashboard`, `KeepAlive`, PATH with `/opt/homebrew/bin`) and checks `node` on that PATH; uninstall removes it.
- [ ] Document usage and the Node exception; commit `feat(install): run the dashboard as a launchd service`.
- [ ] Final: `tools/gate`, `tools/review`, then a live check that a change made in the page is used by the next poll.
