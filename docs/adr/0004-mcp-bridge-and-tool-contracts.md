# 4. MCP bridge guard and tool contracts

Status: accepted. Recorded 2026-11-24 from comments in `McpFetchGuard.cjs`,
`Mcp.js`, `McpSchema.js`, and `MCPService.qml`.

## Context

MCP runs through `mcp-remote` 0.1.38, a third-party bridge that talks to a
remote server and opens a browser for OAuth. Tool names, schemas, arguments,
and results all come from parties Ephemera does not trust.

## Decisions

### Bridge preload (`McpFetchGuard.cjs`)

- The preload is part of the transport security boundary. The
  version-checked Node executable loads it before `mcp-remote`'s entry point.
- `undici.install()` puts the reviewed Fetch implementation in place for
  transports that use Node's global Fetch. The guard then covers both that
  path and `mcp-remote`'s direct import.
- `mcp-remote` opens OAuth authorization URLs through the ESM `open` package,
  outside Fetch. On Linux `open` delegates to `xdg-open`. The guard hooks
  `child_process.spawn` and applies the same transport policy before a
  browser process starts.
- That hook depends on how `open` 10.1.0 and 10.2.0 behave on Linux: they pass
  the initial OAuth URL to `spawn` as the final argument. The guard gates
  those exact releases and package layouts before relying on it.
- `mcp-remote` 0.1.38 catches an ordinary rejection during OAuth
  coordination, deletes a live peer's lock, and starts a competing flow. The
  guard terminates the process instead. Concurrent OAuth is unsupported, and
  in exchange the lock and the peer doing the authorization stay intact.

### Runtime and version checks (`Mcp.js`)

- `isVersionAtLeast` and `isVersionInRange` reject prerelease builds, because
  the bridge is a security boundary.
- `extractNodeRuntimeInfo` captures the executable path during the probe. The
  checked runtime starts the bridge, never a later `PATH` lookup.
- `mcpUrlSafetyError` rejects endpoint forms that would expose credentials
  through process argv.

### Protocol and tool identity

- `classifyJsonRpcMessage`: client request ids are positive integers that
  Ephemera generates; server request ids may also be bounded strings. An
  invalid response-like envelope keeps a safe numeric `responseId`, so its
  pending request is rejected and does not hang.
- `findTool` matches the exact, case-sensitive advertised name. Tool names
  are authorization identifiers: normalising a model-provided name for
  comparison and then executing the raw value would break the approval.
- `toolApprovalKey` binds an approval to the tool name and a fingerprint of
  its executable contract. `trustKey` binds approvals to one server.
  `pruneApprovedTools` drops approvals whose contract is no longer
  advertised.
- `formatReviewText` escapes invisible and bidirectional controls in any
  server- or model-provided text shown in an approval prompt.

### Schema validation (`McpSchema.js`)

- `JSON.stringify` turns array holes into `null` and ignores named array
  properties. The validator rejects both, so the value the user reviewed is
  exactly the value sent.
- `validateToolResult` supports a bounded structural JSON Schema vocabulary.
  It does not evaluate remote regular expressions or resolve remote
  references.
