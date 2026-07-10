# Ephemera

AI chat slideout panel for Wayland, built as a DankMaterialShell daemon plugin (`"type": "daemon"`). In-memory by default; optional persistence via PluginService.

## Setup

Source lives in `src/`. Hot-reload with `dms restart` (full restart required — DMS caches compiled QML in-process; `dms ipc call plugins reload ephemera` does NOT reliably pick up all changes).

Depends on parent config modules: `qs.Common` (Theme), `qs.Widgets` (Dank* components, StyledText), `qs.Services` (PluginService).

Unit tests: `node tests/run_tests.js`
MCP QML lifecycle test: `tests/run_qml_tests.sh` (requires Quickshell)
Live panel geometry test: `tests/run_panel_qml_test.sh` (requires Quickshell and an active Wayland compositor)

## Architecture

EphemeraService.qml is the **coordinator** that owns message state (`messagesModel`, `messageIndexMap`, `variantStore`) and orchestrates child services (KeyringService, StreamingService, OllamaManager, MCPService). Child services communicate via signals; the coordinator applies their outputs to the shared message model. Narrow facade properties expose child state so UI binds to `aiService.*` without receiving executable service objects.

## Gotchas & Landmines

- **Qt textFormat binding bug** — switching `textFormat` between `RichText`/`PlainText` destroys the `text` binding. Must re-establish via `Qt.binding()` in a `Connections` handler. See `MessageBubble.qml`.
- **Provider switch clears chat** — changing providers clears history and index maps to prevent stale `messageIndexMap` lookups. Model changes within the same provider preserve conversation.
- **ListModel limitations** — QML `ListModel` can't store nested arrays or complex objects. Use JS side-channel maps (`variantStore`, `messageIndexMap`) alongside the model.
- **Ollama safety net** — `Component.onDestruction` fires `pkill` as last resort. The `_shuttingDown` flag prevents double-shutdown. External Ollama is never auto-stopped by the idle timer.
- **5MB stdout buffer cap** — exceeding it kills the curl process to prevent memory exhaustion.
- **DMS permissions are silent** — missing permission declarations in `plugin.json` prevent PluginService calls without logging errors. Current permissions: `settings_read`, `settings_write`.
- **pluginData null during init** — use `??` operator; values are `undefined` before first load.
- **DMS auto-injected properties** — `pluginData`, `pluginService`, `pluginId` are injected into the root component. Don't redeclare them.
- **`_keyringCache` clone requirement** — always use `_cloneCache()` when mutating `_keyringCache`. QML `property var` skips change notification when reassigned the same object reference, silently breaking `hasApiKey`/`missingApiKey` bindings via the alias chain.
- **StreamingService signal ordering** — the coordinator must set up the message model entry and index map BEFORE calling `streamingService.launchCurl()`, and every launch/resume must carry the stream's provider and generation identity. Replacement curl launches wait for the previous Process `onExited`; stale output is ignored.
- **MCP bridge gate** — MCP requires native Linux, Node.js >=24.17.0 and <25 with bundled Undici >=7.28.0 and <8, plus the globally installed, reviewed `mcp-remote` 0.1.38 release with a resolved direct Undici in the same range and `open` exactly 10.1.0 or 10.2.0. MCPService captures the exact Node executable and npm-reported package layout through probes, and `src/runtime/McpFetchGuard.cjs` revalidates the loaded packages, installs the checked Fetch implementation, blocks redirects, and terminates secondary concurrent OAuth attempts rather than allowing loopback polling. Never fall back to an unchecked `PATH` bridge command or accept an unreviewed package layout.
- **MCP reconnect ordering** — setting `Process.running = false` only sends SIGTERM. Reconnects must wait for `onExited`; never restart with `Qt.callLater()` while the old process is still running.
- **MCP round state** — `_roundContent`/`_roundThinking` contain only the current model turn. Tool audit text may be displayed through `_streamThinking` but must never be sent back as model-authored thinking.

## Conventions

- **Root IDs** — root items: `id: root`, delegate roots: `id: delegate`.
- **Private properties** — prefix with `_` (e.g., `_streamContent`).
- **JS libraries** — `.js` files in `src/lib/` are `.pragma library` pure-function modules. Import with namespace aliases (`as Providers`). All public functions have JSDoc comments.
- **State centralization** — all mutable state in EphemeraService.qml. Child services own internal state but communicate changes via signals/property aliases.
- **Property grouping** — use `// --- Section name ---` comment headers.
- **Theme** — never hardcode colors/spacing/fonts. Use `Theme` singleton from `qs.Common`.
- **UI signals** — extracted components communicate with parent via signals, not direct property writes.

## Key Design Decisions

- **curl via Process** — `curl -K -` so URL, auth headers, and body never appear in `/proc/cmdline` or `ps` output. `escapeCurlConfig()` handles config format escaping.
- **Deferred markdown** — `markdownToHtml()` runs only after streaming completes, never per-delta. `_lastRenderedText` cache prevents redundant re-renders.
- **Variants, not replacements** — regeneration saves current response into `variantStore[msgId]` and streams a new one. Capped at 10 (FIFO). Cancel preserves partial content as a navigable variant.
- **Three thinking paths** — (1) `<think>` tags in content stream (Ollama), (2) `reasoning_content` fields (DeepSeek API), (3) Anthropic extended thinking with interleaved-thinking header.
- **Settings vs state** — `savePluginData` for user preferences (requires permissions); `savePluginState` for runtime data like chat history (no permissions, debounced 150ms, atomic).
- **Exponential backoff with jitter** — `Backoff.js` handles error cooldown. Resets on successful stream finalization.
- **Bounded MCP discovery** — MCP stdout uses `SplitParser`; tool discovery is capped by message size, total schema size, pages, and tool count. Invalid, duplicate, deeply nested, and task-required tools are ignored.

## Security Invariants

- API keys: system keyring (D-Bus Secret Service) or env vars only. Never persisted by PluginService.
- `secret-tool store` receives keys via stdin — never in `/proc/cmdline`.
- HTML escaped before markdown rendering; link schemes whitelisted to http/https.
- Custom URLs validated: http(s) only, valid hostname, max 2048 chars, no unsafe characters.
- MCP tool access requires exact-contract approval, bounded input-schema validation at the execution boundary, and confirmation of every call. Malformed names, arguments, schemas, and results fail closed.
- Remote MCP uses HTTPS by default. Non-loopback HTTP requires consent bound to the exact endpoint; URL credentials and query strings are rejected. Bridge Fetch redirects fail closed so an approved HTTPS endpoint cannot downgrade to HTTP; external-browser navigation remains browser-controlled. The local Node and global npm installation are trusted rather than cryptographically attested.
- `mcp-remote` versions below 0.1.16 are blocked due to CVE-2025-6514.
- `forceShutdownExternal()` uses `pkill -x` (exact match) to avoid killing unrelated processes.
- Chat persistence opt-in; API keys never stored in PluginService.
