# 1. Ban code comments

Status: accepted, 2026-11-24

## Context

The codebase carried 504 comments on 1,013 lines. An audit sorted every one
into four kinds:

| Kind | Meaning | Share |
|---|---|---|
| Tautology | Repeats what the code shows: section banners, `// Header`, JSDoc that restates a signature | most |
| Stale | Describes history or an implementation that is gone | a handful |
| Excuse | Explains a shortcut that should be fixed | five |
| Decision record | States a non-obvious, deliberate choice | the rest |

Only the last kind is worth keeping, and a comment is a poor home for it. It
sits beside one line while the decision spans files, nothing checks it against
the code, and agents copy the pattern of an excuse comment into new code.

## Decision

Source files carry no comments. This covers `.js`, `.cjs`, `.mjs`, `.qml`, and
shell scripts, tests and fixtures included.

- A decision goes in an ADR in this directory, anchored to symbol names.
- A shortcut goes in a GitHub issue, and the code gets fixed.
- A behaviour worth stating goes in a test name or assertion message.
- Everything else goes in a better identifier, or nowhere.

Machine-read directives are not comments under this rule: a shebang on the
first line, `# shellcheck <key>=`, `// qmllint disable|enable`, Quickshell's
`//@ pragma`, and release-please's `// x-release-please-*` markers. A comment
that only borrows one of those prefixes is still a comment. YAML, JSON, and Markdown are out of scope; the pinned-action
`# v4` annotations in the workflows stay.

`node tests/lint_comments.js` enforces the rule in CI as a ratchet. It counts
comment lines per file and compares them with `tests/comment-baseline.json`. A
file may never exceed its baseline, a file absent from the baseline allows
zero, and a baseline looser than reality fails until
`node tests/lint_comments.js --tighten` lowers it. The tool never raises a
baseline, so a raise can only be a hand edit that shows up in review. A
missing baseline file means zero everywhere, which is the state this ADR
landed in.

The scanner is a hand-written lexer, not a parser. It reads files with a
`.js`, `.cjs`, `.mjs`, `.qml`, or `.sh` extension and extensionless scripts
whose shebang names `node` or a POSIX shell. A new source language is
unlinted until it is added to `scannerFor`. A `/` directly after `)` or `}`
is read as division, so a regex literal in that position can be misread;
`--strip` output is always reviewed as a diff for that reason.

## Consequences

- The conventions "all public functions have JSDoc comments" and
  "`// --- Section name ---` headers" are retired.
- Parameter and return shapes are read from the function body and its tests.
- The `/delete-comment` skill repeats the audit when comments arrive through
  a baseline entry or a newly scanned file type.
