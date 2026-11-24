# 8. Export file publication

Status: accepted. Recorded 2026-11-24 from a comment in `ExportService.qml`.

## Decision

A file export writes a private sibling temporary file and publishes it with
an atomic hard link.

- `link(2)` fails when the destination already exists as a file, FIFO, or
  symlink, and never opens it. Such a path cannot be overwritten or used to
  capture the export.
- A directory at the destination is the exception. The command runs `ln`
  without `-T`, so the link is created inside the directory and the export
  reports success. Issue #21 tracks adding `-T`.
- `chmod` is applied through the open file descriptor. That defeats
  inherited default ACLs and removes the window for a path swap while
  writing.
