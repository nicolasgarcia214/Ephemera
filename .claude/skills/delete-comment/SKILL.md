---
name: delete-comment
description: >-
  Audit the code comments in this repository, sort each into tautology, stale,
  excuse, or decision record, move decisions into ADRs, file excuses as GitHub
  issues, delete the comments, and tighten the comment-lint ratchet. Use when
  the user asks to "delete comments", "run the comment audit", "clear the
  comment baseline", or names /delete-comment. Do not use it to review code
  quality in general or to write documentation.
argument-hint: "[optional: paths to limit the audit to]"
allowed-tools: Read, Grep, Glob, Bash, Edit, Write, Agent
---

# Delete Comment

Source files in this repository carry no comments
(`docs/adr/0001-ban-code-comments.md`). This skill empties whatever has
accumulated. The order is fixed: record first, delete second, so no decision
is lost between the two.

## Categories

Judge each comment against the code under it, never from its wording alone.
Consecutive `//` or `#` lines are one comment.

| Category | Test | Action |
|---|---|---|
| Tautology | The code already says it: banners, labels, signature-restating doc blocks | delete |
| Stale | It describes history, or an implementation the code no longer has | delete |
| Excuse | It explains a shortcut, and you can name a concrete fix that is feasible here: a hand-synchronised copy, a weak type, a legacy path, regex-munging, a guard built from a timer | issue, then delete |
| Decision record | A deliberate, non-obvious choice that is correct as implemented | ADR, then delete |

A workaround for an upstream bug with no cleaner alternative is a decision
record. A comment whose claim is half true is split: the true half is judged
on its own and the false half is stale.

## Steps

1. **Inventory.** Run `node tests/lint_comments.js --list`, filtered to the
   argument paths when given. Done when every entry has one category. If a
   tool reads a listed comment (a new linter directive, a release marker), it
   is not a comment: add its prefix to `DIRECTIVE` in
   `tests/lint_comments.js` with a test case in `tests/run_tests.js`.
2. **Validate.** Give two fresh, read-only reviewers the inventory without
   your verdicts and ask each for the excuse and stale lists with `file:line`
   evidence. Done when every excuse and stale verdict has agreement from both
   reviewers and your own reading of the code. An excuse without consensus is
   recorded as a decision.
3. **Record decisions.** Add each decision to the ADR in `docs/adr/` that
   owns its topic, or to a new numbered ADR when none does. Anchor every
   statement to a symbol name; line numbers rot. Check each claim against the
   code and write what the code does. Done when every decision-record comment
   maps to a sentence in an ADR.
4. **File excuses.** Search open issues for each one
   (`gh issue list --search`). Draft one issue per remaining shortcut: what
   the code does, a permalink pinned to a commit, and the fix. Show the user
   the full batch and wait for approval before `gh issue create`. Done when
   every excuse comment has an issue number.
5. **Delete.** `node tests/lint_comments.js --strip <file>...` removes every
   comment in the named files along with the blank lines they leave. Use Edit
   for a file where some comments stay. Done when `git diff` shows no removed
   line other than comments, their blank lines, and trailing-comment tails.
6. **Tighten and prove.** Run `node tests/lint_comments.js --tighten`, then
   `node tests/lint_comments.js`, `node tests/run_tests.js`, and
   `tests/run_qml_tests.sh`. Done when all pass, or a failure is shown to
   exist on the base commit too.

## Final Response

Lead with the comment-line count before and after. Then give the count per
category, the ADRs touched, the issue numbers, what remains in
`tests/comment-baseline.json` and why, and any test that failed.
