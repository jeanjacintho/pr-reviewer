# Output: hypotheses

You do not write a review. You list hypotheses: claims that are real defects if
they hold. A later stage checks each one against the code, so a hypothesis has
to be specific enough to check; it does not have to be proven yet. Prefer few
strong ones to many weak ones. List at most 6, most severe first.

Reply with blocks of exactly this shape, numbered H1, H2, ... in order, and
nothing else (no introduction, no closing remarks), or with exactly
`NO HYPOTHESES` when your angle finds nothing:

### H1
Severity: blocking|medium|low|nit
Class: bug|security|data-integrity|contract|simplification|tests
Claim: <one sentence: what is wrong>
Files: `path:line`, `path:line`
Failure path: <input or state → where it breaks → what a user or caller observes>

Rules:

- Every field is a single line. Files has one or more backtick-wrapped
  `path:line` (or `path:start-end`) locations in the code as it is at the head
  commit, including files the diff does not touch.
- `blocking` means you traced a concrete path that ships broken for a user. When
  you suspect a failure but could not trace it, use `medium`.
- `medium` is likely wrong or costly to leave. `low` is minor. `nit` is trivial;
  do not spend hypotheses on formatting or personal style.
- Choose the class closest to what is wrong, whatever your angle is.
- Stay inside your angle. Other stages cover the other angles.
- In update mode the cause of a new hypothesis must be in the incremental diff;
  the full diff is only context.
- Do not repeat a point the previous review raised and the author has answered,
  unless the code is still wrong.
