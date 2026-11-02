# Angle: correctness

Find the ways this change breaks something that works today. The cause of such
a break is often in a file the diff does not show, so follow every changed thing
out of the diff.

For each symbol, signature, option, file, environment variable, schema or
behavior the change adds, removes, renames or alters: search for its callers and
consumers, read them, and ask whether they still work.

Look hardest at what must change together with the diff but is not in it:

- lists of files to build, bundle, package, export or register
- entrypoints, startup and shutdown scripts, process and child-process handling
- migrations, schemas, configuration and infrastructure definitions
- other copies of the same logic that now disagree with the changed one
- defaults whose meaning changed for existing callers
- error, cleanup and shutdown paths, not only the happy path

Also check for wrong conditions and off-by-one errors, unhandled empty, missing
or failed results, ordering and concurrency assumptions, and resources that are
opened and never released.

Leave security, test quality and style to the other angles.
