# 2. Process lifecycle and output bounds

Status: accepted. Recorded 2026-11-24 from comments in
`StreamingService.qml`, `OllamaManager.qml`, and `Providers.js`.

## Context

Every network call and every managed server is a Quickshell `Process`.
Quickshell's process signals have gaps, and output from a remote peer is
untrusted in size.

## Decisions

### Response transport (`StreamingService`)

- `Process.running = false` only requests termination. `launchCurl` keeps
  exactly one identity-bound launch in `_pendingLaunch` until `onExited`.
- `SplitParser` delivers every line, including an unterminated tail, before
  `Process` emits `exited`. Exit alone therefore completes the transport in
  `_finishCurlProcess`.
- `_finishCurlProcess` clears `_processActive` before emitting any completion
  signal, so an observer can launch the next process or read idle state from
  inside its handler.
- When a replacement launch is queued, it owns the active identity. The old
  process drains without its result or exit status touching the new request.
- Process exit is authoritative. A syntactically complete partial body is
  rejected when curl reports a timeout, truncation, or any other transport
  failure after stdout has drained.
- Quickshell emits `runningChanged` but not `exited` when `QProcess` fails to
  start. `onRunningChanged` calls `_finishCurlProcess(-1, true)` so later
  launches cannot queue behind a process that never existed.
- stdout is split on the newline byte. That keeps multi-byte UTF-8 sequences
  whole; decoding arbitrary pipe reads would corrupt characters split across
  reads.
- `_handleFetchLine` counts received length for the process even after its
  stream identity is cancelled. Stale output stays inert but cannot grow
  without bound while termination drains. The cap is 5,242,880 code units.
- curl also carries `--max-filesize 5242880`, which bounds an unterminated
  line before it reaches the line parser.

### Ollama server (`OllamaManager`)

- Probe responses are capped at 64 KiB by curl, against transferred bytes,
  before `StdioCollector` retains them. QML string lengths count UTF-16 code
  units and cannot enforce a raw byte limit on multi-byte output.
- An external Ollama is stopped with `pkill -x -U $USER ollama`. `-x` matches
  the exact process name; `-f` would kill any process with "ollama" in its
  command line.
- An owned Ollama is stopped through `Process.running = false`, which targets
  the exact child. Ownership stays set until `onExited` confirms termination.
- `_kill` uses `kill` only with the captured PID. With no PID there is no
  `pkill` fallback: losing the identity means killing nothing.
- `QProcess` may omit `exited` when the launch itself fails, so
  `onRunningChanged` schedules `_finishOwnedProcessExit`. Normal owned
  shutdowns finish only in `onExited`.
- `_handleIdleTimeout` defers shutdown by a full idle interval while a stream
  is active, including one paused on MCP tool approval. It never cancels the
  stream.

## Consequences

Any new `Process` needs the same three answers: who finishes it when it fails
to start, who owns its identity while it drains, and what bounds its output.
