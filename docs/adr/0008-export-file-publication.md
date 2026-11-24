# 8. Export file publication

Status: accepted. Recorded 2026-11-24 from a comment in `ExportService.qml`.

## Decision

A file export writes a private sibling temporary file and publishes it with
an atomic hard link.

- `link(2)` fails for every pre-existing inode type, FIFOs included, and
  never opens the destination. An existing path cannot be overwritten or
  used to capture the export.
- `chmod` is applied through the open file descriptor. That defeats
  inherited default ACLs and removes the window for a path swap while
  writing.
