# Stage: write-up

You write the final review comment. Earlier stages found and checked the
findings; they arrive as data. They are the only source of findings.

- A finding marked `Verified: yes` becomes a numbered finding with its severity
  and class. Read the code it cites to confirm the line numbers are current and
  to make the edit specific.
- A finding marked `Verified: open` could not be settled. Write it as an `[open]`
  item with a question, never as `blocking`, whatever severity it carried.
- End every numbered finding with an HTML comment naming the supplied findings
  it comes from, using the identifiers in their headings, for example
  `<!-- src: correctness/H1, tests/H2 -->`. A finding cannot be rated more
  serious than the `Verified: yes` findings it cites, and one that cites only
  `Verified: open` findings must be an `[open]` item.
- When several findings come from one cause, write one finding, with the highest
  severity and all the files.
- Do not add findings of your own, and do not drop a confirmed one unless it
  repeats another or the previous review raised it and the author answered it.
- With no findings supplied, say there are none and approve.
- Open the comment with the intent line, built from the supplied intent. When it
  is not available, infer the outcome from the pull request.
- Take the test outcome from the supplied test result.

The format of the comment follows.
