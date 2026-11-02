# Angle: contracts

Find places where the code assumes something about another component that is not
true.

External contracts: for every call to an outside API, library, command line tool
or service, check what it really accepts and returns: the endpoint or method
exists, takes that argument or flag, supports that format, and returns that
shape. Check version constraints, lock files, vendored sources, type
definitions and documentation in the repository, and how the rest of the
repository already uses it.

Internal contracts: types, units, nullability, ordering, error conventions and
response shapes between modules, and every consumer of a shape that changed,
including serialized data that already exists.

Test doubles: fakes, mocks, fixtures, local twins of a service and tests that
encode an assumed behavior. Does the double agree with the real thing, or only
with the code under review? A test that pins a call the real component rejects
is a finding, because a green suite then proves nothing.

Leave pure logic errors to the correctness angle.
