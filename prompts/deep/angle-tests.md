# Angle: tests

Judge whether the tests would notice if this change were wrong. The supplied
test result tells you what ran.

- If tests failed or timed out, find the cause in the code and report it with
  the failing location.
- For each behavior the change adds or alters, look for a test that would fail
  if that behavior broke. Report the missing ones that matter, with the concrete
  failure that would go unnoticed.
- Look for tests that cannot fail: they assert on a mock they set up, repeat the
  implementation, or never reach the changed branch.
- Look for tests that pass for the wrong reason, such as an assertion on a value
  the test itself supplied.
- Deleted or weakened tests, skipped tests and loosened assertions need a reason
  in the change.

Do not ask for tests of trivial code or of paths that cannot happen. A hypothesis
without a concrete failure that would slip through is not worth listing.
