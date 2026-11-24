# 8. Export file publication

Status: accepted. Recorded 2026-11-24 from a comment in `ExportService.qml`.

## Decision

A file export writes a private sibling temporary file and publishes it with
an atomic hard link.

- `link(2)` fails when the destination already exists as a file, FIFO,
  directory, or symlink, and never opens or follows it. Such a path cannot
  be overwritten or used to capture the export.
- The command runs `ln -T`, which always passes the destination itself to
  `link(2)`. Without `-T`, `ln` would create the link inside a destination
  that is a directory or a symlink to one, and report success.
- `chmod` is applied through the open file descriptor. That defeats
  inherited default ACLs and removes the window for a path swap while
  writing.
