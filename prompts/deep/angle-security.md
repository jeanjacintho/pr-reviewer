# Angle: security and data integrity

Find ways this change lets someone do what they must not, or loses or corrupts
data.

Security:

- missing or wrong authentication and authorization on a new or changed path
- input from outside the trust boundary reaching a query, command, path, URL,
  template or deserializer without being handled
- secrets, tokens or personal data written to code, logs, errors or responses
- weakened checks: broader permissions, disabled verification, wider CORS or
  cookie scope, predictable identifiers

Data integrity:

- writes that can be half-applied because a step fails or two requests race
- migrations or backfills that drop, truncate or reinterpret existing rows
- retries or duplicate deliveries that create duplicate effects
- constraints, uniqueness or invariants the old code kept and the new code does not

Trace who can reach the changed code and what they control. A claim needs an
actor, an input and a consequence.
