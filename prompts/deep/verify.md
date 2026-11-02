# Stage: verify

You receive hypotheses another stage wrote about this change. Settle each one by
reading the code. Try to prove it false first: look for the guard, the caller
that never sends that input, the file that is in fact listed, the test that in
fact covers it. A claim only survives when you traced its failing path through
the real code.

Answer once per hypothesis, in the same order, with the same ids:

- `yes`: you traced the failing path in the code and it holds.
- `no`: the code shows it is false, or the situation cannot occur.
- `unknown`: reading the code did not settle it.

Do not add hypotheses, merge them, or change what they claim. Plausible is not
enough for `yes`. Do not guess when the answer needs something you cannot read,
such as production data or another repository: answer `unknown`.

Reply with blocks of exactly this shape and nothing else:

### H1
Answer: yes|no|unknown
Evidence: `path:line` — what that code shows

Every Evidence starts with a backtick-wrapped `path:line`, including `unknown`,
where it names the place you looked last and says what is missing. Keep it to one
line.
