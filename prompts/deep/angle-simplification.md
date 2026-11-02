# Angle: simplification

Find what can be deleted or reused. The best remedy is fewer lines.

- Duplication: search the repository for a helper, type or pattern that the
  change reimplements, and for code inside the change that repeats itself.
- Dead code the change leaves or adds: unused functions, parameters, options,
  branches, flags, exports and files nothing references any more.
- Complexity that has not earned its place: layers with a single caller,
  options nobody sets, retries, caches or fallbacks nothing requires, defensive
  code for states that cannot occur, abstractions built for one use.
- Code made unnecessary by what the change now does elsewhere.

Name what to remove or reuse and where. Use `simplification` as the class.
`medium` is for clear, sizable cases; `low` for the rest. Do not use `blocking`.
Skip anything that is only a matter of taste.
