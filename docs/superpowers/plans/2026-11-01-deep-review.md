# Deep staged review — Implementation Plan

> Follow `AGENTS.md` and the `ub-mode` skill. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A repository set to `depth: deep` is reviewed by a pipeline (intent → five angles → verification per angle → write-up) that follows changed code outside the diff and posts only findings it could check against the code. `quick` stays the one-call review of today.

**Spec:** section "Revisão profunda em etapas" of `docs/superpowers/specs/2026-10-31-pr-reviewer-design.md`.

## Review Focus

1. `quick` and entries without `depth` behave exactly as before: same prompt, one engine call, same comment.
2. Every stage is read-only like today's review: same engine flags, no files written in the worktree, stage outputs passed on only through the next prompt as escaped data.
3. A verifier `no` never reaches the comment, and an `unknown` reaches it only as an `[open]` item. This is enforced in Bash, not just asked of the model.
4. A failing angle degrades the review with the `Partial review:` note. A failing write-up, or all angles failing, fails the review with one error comment, never a half-written one.
5. At most `DEEP_PARALLEL` engine calls in flight. No background job outlives the review (cleanup waits for or kills them on every exit path).
6. Bash (`lib/repos.jq`) and Node (`dashboard/validate.js`) accept the same `depth` values.

## Stage contract

Hypothesis block (angle output), repeated, or exactly `NO HYPOTHESES`:

```
### H<n>
Severity: blocking|medium|low|nit
Class: bug|security|data-integrity|contract|simplification|tests
Claim: <one sentence>
Files: `path:line`[, `path:line`…]
Failure path: <input → where it breaks → observable result>
```

Verification block, one per input id, same order:

```
### H<n>
Answer: yes|no|unknown
Evidence: `path:line` — <what the code shows>
```

`lib/stages.sh` validates both with perl, joins them by id, drops `no`, drops `unknown` below `medium`, marks the remaining `unknown` as open, and prefixes each kept block with its angle. The write-up receives only that merged file.

### Task 1: data — `depth`
- [ ] Tests first: `repo_depth` (missing → quick, invalid → empty, which fails the review visibly like an unknown engine), validate.js enum, the Bash/Node cross-check test, `repos.example.json`.
- [ ] Implement in `lib/repos.jq`, `lib/repos.sh`, `dashboard/validate.js`.

### Task 2: stage formats
- [ ] Tests first with fixture files: valid and invalid hypotheses (missing field, bad severity, more than 6, mixed with prose), `NO HYPOTHESES`, a verification that skips or reorders an id, the filter (yes kept, no dropped, unknown medium kept as open, unknown low dropped).
- [ ] Implement `validate_hypotheses`, `validate_verification`, `merge_verified` in `lib/stages.sh`.

### Task 3: prompts
- [ ] Write from scratch: `prompts/deep/intent.md`, `angle-correctness.md`, `angle-security.md`, `angle-contracts.md`, `angle-tests.md`, `angle-simplification.md`, `verify.md`, `write-up.md`. The write-up reuses the output format of `prompts/review.md` (shared, not copied).
- [ ] `lib/prompt.sh` builds each stage prompt from `policy.md` + the stage file + rules, lessons and base `REVIEW.md` + the data blocks that stage needs. Tests assert which blocks each stage gets and that earlier stage output arrives escaped.

### Task 4: pipeline
- [ ] Tests first with the fake engines (outputs chosen per stage by a marker in the prompt): the happy path calls the engine 12 times and posts one comment; `NO HYPOTHESES` skips that angle's verification; a failed angle → `Partial review:` note; all angles failed → one error comment; a failed write-up → one error comment; never more than `DEEP_PARALLEL` concurrent calls (the fake records start/end); a timed-out stage is killed; `quick` still makes one call.
- [ ] Implement `lib/deep.sh`: the intent runs alongside the tests; after the tests, each angle runs as one job (angle, then its verification) under a concurrency limit built from `jobs`/`wait` (Bash 3.2, no `wait -n`); then the merge and the write-up. `review_run` dispatches on `repo_depth`. One `Stage <name> <repo>#<pr> took <n>s` log line per stage.
- [ ] `config.example.sh` / `lib/common.sh`: `DEEP_PARALLEL=3`, `STAGE_TIMEOUT_SECS=600`. `lib/poll.sh` keeps its lock rule: a lock is only taken from a dead poll, so a live deep review never loses it by age.

### Task 5: try-review
- [ ] Tests first: `tools/try-review` prints the comment and makes no GitHub write (the fake `gh` fails on any write verb).
- [ ] Implement it on top of the same functions, with the `quick|deep` argument overriding the repository's depth.

### Task 6: dashboard
- [ ] Depth control (Quick / Deep, with a cost hint) in the repository card, new repositories default to `deep`, stage timings shown in the repository's activity.
- [ ] Verify in the browser (light, dark, phone).

### Task 7: ship and measure
- [ ] Gate, independent review, commit; pull into the installed checkout; restart the dashboard job only if server code changed.
- [ ] With Jean's PRs whose bugs the bot missed: run `tools/try-review` in `quick` and `deep`, and record in `docs/implementation-log.md` which known bugs each one caught, the time taken, and the call count.
- [ ] Switch repositories to `deep` only if Jean agrees after seeing that comparison.
