# Contributing to Ephemera

This guide covers everything you need to know to work on Ephemera — a DankMaterialShell daemon plugin, built with Quickshell, that provides an ephemeral AI chat slideout for Wayland desktops.

## Prerequisites

- A running [DankMaterialShell (DMS)](https://danklinux.com) installation (provides Quickshell + `qs.Common`, `qs.Widgets`, `qs.Services`)
- `curl`, `wl-copy` (from wl-clipboard), GNU `install`, and optionally [Ollama](https://ollama.com) and `secret-tool`
- Node.js for the JS suite; the MCP lifecycle suite's production gate is Node.js >=24.17.0 and <25 with bundled Undici >=7.28.0 and <8
- Quickshell for QML lifecycle tests; an active Wayland compositor is required for the live panel geometry test
- Basic familiarity with QML and JavaScript

## Project structure

```
ephemera/
├── plugin.json                          # Plugin manifest (id, type, capabilities, entry point)
├── EphemeraDaemon.qml                   # Entry point — service init, per-screen panels, IPC handler
├── src/
│   ├── services/
│   │   ├── EphemeraService.qml          # Coordinator — messages, variants, orchestrates child services
│   │   ├── StreamingService.qml         # Curl process, SSE parsing, stream state, error backoff
│   │   ├── KeyringService.qml           # System keyring (D-Bus Secret Service) and env var key resolution
│   │   ├── OllamaManager.qml            # Ollama lifecycle — auto-start, probes, shutdown, model discovery
│   │   └── MCPService.qml               # Version-gated MCP bridge, JSON-RPC, discovery, tool execution
│   ├── components/
│   │   ├── EphemeraPanel.qml            # Wayland layer-shell PanelWindow — slide/expand animations
│   │   ├── EphemeraChat.qml             # Main UI — header, message area, composer, overlays
│   │   ├── ChatComposer.qml             # Auto-growing text input with guarded send/stop/clear
│   │   ├── ChatHeader.qml               # Model selector, exports, placement, expansion, overflow menu
│   │   ├── ChatToast.qml                # Ephemeral notification overlay
│   │   ├── ClearChatDialog.qml          # Clear chat confirmation dialog
│   │   ├── EphemeraSettings.qml         # Settings shell — delegates to card components below
│   │   ├── ProviderSettingsCard.qml     # Provider/model selection with URL validation
│   │   ├── ModelParametersCard.qml      # Temperature, max tokens, system prompt, timeout sliders
│   │   ├── ApiKeysCard.qml              # API key status from provider registry
│   │   ├── ChatHistoryCard.qml          # Persistence toggle
│   │   ├── McpSettingsCard.qml          # MCP endpoint, transport consent, and tool contracts
│   │   ├── McpToolContractCard.qml      # Exact-contract review UI
│   │   ├── McpToolApprovalPrompt.qml    # Per-invocation confirmation UI
│   │   ├── EphemeraActionButton.qml     # Tooltip-safe header action wrapper
│   │   ├── AccordionSection.qml         # Reusable animated show/hide container
│   │   ├── SettingsCard.qml             # Reusable themed card with icon and title
│   │   ├── MessageList.qml              # ListView wrapper with auto-scroll and entry animations
│   │   └── MessageBubble.qml            # Message rendering (markdown, variants, copy, regenerate, timer)
│   ├── lib/
│   │   ├── Providers.js                 # Provider registry + curl command builders + URL validation
│   │   ├── Markdown.js                  # Markdown-to-HTML converter with security hardening
│   │   ├── StreamParser.js              # SSE stream parsing — parseDelta() per provider format
│   │   ├── ChatExport.js                # Chat export to markdown format
│   │   ├── ChatPersistence.js           # Bounded, validated, atomic chat snapshots
│   │   ├── Mcp.js                       # MCP transport/tool normalization helpers
│   │   ├── McpSchema.js                 # Bounded JSON Schema validation
│   │   ├── Submission.js                # Shared submission-readiness contract
│   │   ├── VariantStore.js              # Pure-function variant store operations (save, get, evict)
│   │   ├── ErrorHints.js                # Contextual error hints for HTTP/curl error codes
│   │   └── Backoff.js                   # Exponential error cooldown with jitter
│   └── runtime/
│       └── McpFetchGuard.cjs             # Revalidates and constrains the reviewed bridge at runtime
├── tests/
│   ├── run_tests.js                     # JS, source-contract, and geometry unit tests
│   ├── run_qml_tests.sh                 # MCP guard plus QML lifecycle/compile harnesses
│   ├── run_panel_qml_test.sh            # Live Wayland panel geometry harness
│   ├── *Harness.qml                     # Focused lifecycle and integration harnesses
│   └── fixtures/                        # Hermetic process, package, and parent-module fixtures
├── CLAUDE.md -> AGENTS.md               # AI assistant context file
├── CONTRIBUTING.md                      # Developer guide
└── README.md                            # User-facing documentation
```

## Architecture

```
EphemeraDaemon (entry point)
│
├─ EphemeraService (coordinator, src/services/)
│  ├─ Message ListModel (in-memory by default, optionally persisted)
│  ├─ messageIndexMap (O(1) message lookups by ID)
│  ├─ VariantStore.js (pure-function variant ops: save, get, evict)
│  ├─ Provider/request settings (snapshotted at stream start, persisted via PluginService)
│  ├─ ChatPersistence.js (bounded state, trim disclosure, 150ms debounce, atomic savePluginState)
│  └─ Narrow facades for child state and user-triggered operations
│
├─ StreamingService (child service, src/services/)
│  ├─ Curl process (stdin config via -K -, SSE streaming, 5MB buffer cap)
│  ├─ Stream buffers (_streamContent, _streamThinking, _streamVariantIndex)
│  ├─ Provider/generation identity checks and replacement-launch queue
│  ├─ MCP tool-round state and per-call confirmation
│  └─ Managed clipboard and mode-0600 file export processes
│
├─ KeyringService (child service, src/services/)
│  └─ Serialized keyring operations and key resolution (secret-tool → env var fallback)
│
├─ OllamaManager (child service, src/services/)
│  └─ Bounded readiness/model/GPU probes and owned-process lifecycle
│
├─ MCPService (child service, src/services/)
│  ├─ Exact Node/mcp-remote/Undici/open version and layout gate
│  ├─ Guarded bridge process, reconnect ordering, and JSON-RPC lifecycle
│  └─ Bounded tool discovery, schemas, calls, and results
│
└─ Variants (one per screen)
   └─ EphemeraPanel (bounded PanelWindow with side/slide/expand animations)
      └─ EphemeraChat
         ├─ MessageList → MessageBubble (uses Markdown.js, streaming timer)
         ├─ Composer (auto-growing text input)
         └─ EphemeraSettings (overlay)
            ├─ ProviderSettingsCard
            ├─ ModelParametersCard
            ├─ ApiKeysCard
            ├─ ChatHistoryCard
            └─ McpSettingsCard → McpToolContractCard
```

**Data flow:** User types → `EphemeraChat.sendCurrentMessage()` → `EphemeraService.sendMessage()` checks the shared submission contract → the coordinator appends indexed user/assistant entries → snapshots provider, credential, model, parameters, tools, and context → `Providers.buildCurlCommand()` produces a secret-free argv plus stdin curl config → `StreamingService.launchCurl()` binds the launch to provider/generation identity → `handleStreamChunk()` and `StreamParser.parseDelta()` update child-owned buffers → signals call the coordinator's `_applyStreamContent()`/`_applyStreamThinking()` methods → the coordinator conditionally updates the visible ListModel variant.

**Regeneration flow:** User clicks Regenerate → `regenerate()` saves current `{content, thinking, modelName}` into `variantStore[msgId]` → increments `variantCount`, snapshots the new request identity, and starts the replacement stream without appending messages → `StreamingService` writes its buffers → the coordinator saves the finalized or cancelled variant at `_streamVariantIndex` → `switchVariant()` loads content, thinking, and model identity from the side-channel store. Variants are capped at 10 with FIFO eviction.

**MCP flow:** The Ollama-only MCP service validates the configured transport and reviewed local runtime → starts the guarded bridge → negotiates a supported protocol and bounded tool list → the user approves exact tool contracts and separately enables model tool requests → Ollama receives only approved schemas → each proposed call is revalidated against the approved contract and pauses for explicit confirmation → bounded results are returned through native Ollama tool-round messages. Tool audit text is display-only and is never sent back as model-authored thinking.

## Setup for development

1. Symlink or copy this directory into your DMS plugin path:
   ```sh
   ln -s /path/to/ephemera ~/.config/DankMaterialShell/plugins/ephemera
   ```

2. Enable the plugin:
   ```sh
   dms ipc call plugins enable ephemera
   ```

3. To open the panel, either use the configured keybind or:
   ```sh
   dms ipc call ephemera toggle
   ```

## Testing changes

### Unit and source-contract tests

Run the Node.js suite after changing JavaScript, provider contracts, persistence, service wiring, export behavior, or panel source contracts:

```sh
node tests/run_tests.js
```

This covers every library in `src/lib/`, security and request contracts, persistence bounds, selected QML source invariants, and pure panel-geometry behavior. Do not hardcode the assertion count in documentation; it changes as coverage grows.

### QML lifecycle and shipping compile tests

```sh
tests/run_qml_tests.sh
```

This exercises the MCP Fetch guard, service/coordinator lifecycles, provider isolation, submission gating, persistence, keyring serialization, exports, Ollama ownership/probe limits, and compilation of the shipping daemon/component graph. It requires Quickshell. The script uses the active Wayland compositor when available or a headless Weston instance when installed; CI supplies pinned Quickshell and Weston versions.

For the live layer-shell geometry harness, run from an active Wayland session:

```sh
tests/run_panel_qml_test.sh
```

It exits with status 77 when no compositor socket is available.

### Reload cycle

QML components require a full DMS restart for testing — DMS caches compiled QML in-process.

After editing any `.qml` or `.js` file:

```sh
# Full restart (required — reload does NOT reliably pick up all changes)
dms restart

# Wait a few seconds for DMS to initialize, then re-enable
dms ipc call plugins enable ephemera

# Open the panel
dms ipc call ephemera toggle
```

**Important:** `dms ipc call plugins reload ephemera` does NOT reliably pick up all changes (especially IPC handlers and JS files). Always use `dms restart` during development.

### Plugin debugging commands

```sh
dms ipc call plugins list              # List all plugins and their status
dms ipc call plugins status ephemera   # Check if enabled/disabled and any errors
dms ipc call plugins enable ephemera   # Enable the plugin
dms ipc call plugins disable ephemera  # Disable the plugin
```

### Checking for errors

QML errors appear in the systemd journal:

```sh
journalctl --user -n 50 --no-pager | grep -i -e error -e warn -e Ephemera
```

Common error patterns:
- `Cannot assign to non-existent property "X"` — property doesn't exist on that type
- `Unable to assign [undefined] to QColor` — using a Theme property that doesn't exist
- `ReferenceError: X is not defined` — typo or missing import

### Testing streaming manually

The following is a direct Ollama endpoint smoke test. It is intentionally not the exact Ephemera process invocation: the plugin uses `curl -q -K -`, keeps the URL, headers, and JSON body in a curl config on stdin, disables redirects, and requests usage accounting.

```sh
# Ollama (LiquidAI example)
echo '{"model":"huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF:latest","messages":[{"role":"user","content":"Hello"}],"max_tokens":4096,"temperature":0.7,"stream":true}' \
  | curl -N -sS --no-buffer --show-error --connect-timeout 5 --max-time 30 \
    -w '\nEPH_STATUS:%{http_code}\n' \
    -H 'Content-Type: application/json' \
    -d @- http://localhost:11434/v1/chat/completions
```

You should see `data:` lines streaming in, ending with `data: [DONE]` and `EPH_STATUS:200`.

### Testing Ollama lifecycle

```sh
# Check if Ollama is ready
curl -s http://localhost:11434/api/version

# List available models
curl -s http://localhost:11434/api/tags | python3 -c "import sys,json; [print(m['name']) for m in json.load(sys.stdin)['models']]"

# Start Ollama manually (plugin also does this automatically)
ollama serve &
```

### What to verify after changes

- Messages appear with entry animation (fade + scale)
- Streaming shows pulsing dots (tertiary color during thinking, primary during generating), then renders markdown when done
- Copy button appears on hover over assistant messages; shows checkmark feedback for 1.5s
- Regenerate button appears on hover over the last assistant message
- After regenerating, pagination arrows (`< 1/2 >`) appear on hover; navigating between variants shows correct content, thinking, and model name
- Switching models between regenerations: each variant's chip shows the model that generated it (not the current global model)
- Navigating to a previous variant mid-stream shows completed content (not streaming artifacts); navigating back to the streaming variant resumes live display
- Cancelling during regeneration preserves partial content as a navigable variant
- Error messages trigger a shake animation
- Composer grows/shrinks as text is typed (44–160px)
- Send button disabled and placeholder turns red when API key is missing
- Send/stop buttons crossfade during streaming
- Empty state shows breathing vapor animation
- Scroll-to-bottom pill appears when scrolled up
- Settings panel fades in/out, accordion fields animate
- System prompt presets dropdown works and populates the text field
- Request timeout slider saves and persists
- Provider pill in header truncates long names with ellipsis; turns red when API key missing or last request failed
- Provider pill and model chips in message bubbles expand when slideout is expanded
- Thinking section has clear visual separation from content (spacing + divider)
- Export button in header copies full conversation as markdown; save button writes to `~/ephemera-chat-<timestamp>.md`
- Missing API key banner shows which env var to set (visible in chat area, not just header pill)
- **Start Ollama** retries startup and **Refresh Models** repeats discovery
- Save Chat History toggle persists messages across sessions; clearing chat also clears persisted data
- Persisted pruning adds text markers where applicable, preserves the `trimmed` flag, and shows the trim notice without altering the live conversation
- Close and Escape only hide the panel — Ollama keeps running; idle auto-stop handles cleanup if the plugin started it
- Escape key hides panel (same as close button — no shutdown dialog)
- Ctrl+L clears chat and composer (blocked during streaming)
- Ctrl+N clears chat and composer (blocked during streaming)
- Ctrl+Shift+S toggles settings overlay
- Up arrow in empty composer recalls last sent message; with text in composer, moves cursor normally
- Expand/collapse button works on the slideout
- Side toggle moves the panel between edges without ever anchoring both sides
- Narrow screens cap collapsed and expanded panel geometry to the active screen
- Custom provider URLs require HTTPS remotely; HTTP is limited to `localhost` and `127.0.0.0/8`; inline errors cover invalid hosts, ports, credentials, unsafe characters, and overlong URLs
- Changing provider clears live messages, variants, and persisted state; changing only the model preserves them
- Max Tokens supports 256–131,072 and No limit, subject to provider/model caps
- MCP enablement, transport consent, exact-contract approval, per-call confirmation, reconnect, rejection, timeout, and tool-result failure paths work as documented
- HTTP errors show contextual hints (401 → check API key, 429 → rate limited, etc.)

## Quickshell QML constraints

Quickshell's QML engine has differences from standard Qt Quick. These will save you debugging time:

### Animations

**Do not** use `target` on standalone animations. This will fail silently or throw `Cannot assign to non-existent property "target"`:

```qml
// WRONG — will not work in Quickshell
NumberAnimation { target: someItem; property: "opacity"; to: 1 }
```

Instead, use one of these patterns:

```qml
// Pattern 1: Behavior on property (reacts to property changes)
Behavior on opacity {
    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
}

// Pattern 2: Animation on property (runs automatically)
SequentialAnimation on opacity {
    loops: Animation.Infinite
    NumberAnimation { to: 0.75; duration: 1200 }
    NumberAnimation { to: 0.5; duration: 1200 }
}
```

### Process stdin

The `Process` type (from `Quickshell.Io`) supports writing to stdin but **does not** have a `closeStdin()` method. To signal EOF:

```qml
Process {
    id: proc
    stdinEnabled: true  // Must be set BEFORE process starts

    onRunningChanged: {
        if (running) {
            proc.write("data to send");
            proc.stdinEnabled = false;  // Signals EOF — this is the correct way
        }
    }
}
```

Once `stdinEnabled` is set to `false`, it cannot be re-enabled for that process run. Re-enable it before starting the next run.

### IPC handlers

Daemon plugins need an explicit `IpcHandler` (from `Quickshell.Io`) to receive IPC calls:

```qml
import Quickshell.Io

IpcHandler {
    target: "ephemera"          // IPC namespace
    function toggle(): string { // Must return string
        doSomething();
        return "SUCCESS";
    }
}
```

Call with: `dms ipc call ephemera toggle`

### Theme properties

Use only properties that exist on `Theme`. Some that **do** exist:
- `Theme.primary`, `Theme.onPrimary`, `Theme.error`, `Theme.onSurface`
- `Theme.surfaceContainer`, `Theme.surfaceContainerHigh`, `Theme.surfaceContainerHighest`
- `Theme.surfaceText`, `Theme.surfaceTextMedium`, `Theme.surfaceVariant`, `Theme.surfaceVariantText`
- `Theme.outline`, `Theme.outlineMedium`, `Theme.outlineVariant`
- `Theme.withAlpha(color, alpha)`, `Theme.cornerRadius`, `Theme.spacingS/M/L/XS`

Some that **do not** exist: `Theme.scrim`, `Theme.errorText`.

### TextArea textFormat binding breakage

Dynamically switching `textFormat` between `Text.RichText` and `Text.PlainText` on the same `TextArea` **breaks the `text` binding**. When Qt re-interprets the content during the format switch, it overwrites the `text` property with its internal representation (e.g., Qt HTML), severing the declarative binding.

**Workaround:** Re-establish the binding after each switch:

```qml
TextArea {
    id: contentArea
    text: useRichText ? renderedHtml : plainText
    textFormat: useRichText ? Text.RichText : Text.PlainText

    Connections {
        target: root
        function onUseRichTextChanged() {
            contentArea.text = Qt.binding(function() {
                return root.useRichText ? root.renderedHtml : root.plainText;
            });
        }
    }
}
```

### StyledText defaults

`StyledText` (from `qs.Widgets`) extends `Text` with:
- `wrapMode: Text.WordWrap` (default)
- `elide: Text.ElideRight` (default)

Elide only works when wrapping is disabled. To truncate text, you must explicitly set:
```qml
StyledText {
    wrapMode: Text.NoWrap  // Required for elide to take effect
    elide: Text.ElideRight
    width: 160             // Must be constrained
}
```

## Security considerations

These are non-negotiable design decisions:

- **API keys via system keyring or environment variables.** Keys are stored encrypted in the system keyring (D-Bus Secret Service) via `secret-tool`, or read from environment variables as fallback. Keys are never persisted by PluginService. The Settings panel provides a UI for storing/clearing keyring keys (via `KeyringService`).
- **Curl config via stdin** (`-K -`). URL, auth headers, and request body are all passed through a curl config file on stdin — nothing appears in `/proc/cmdline` or `ps` output.
- **Link scheme whitelist.** Only `http://` and `https://` links are opened. No `file://`, `javascript:`, or other schemes.
- **HTML escaping in Markdown.js.** All user content is escaped before rendering as rich text. Code blocks, table cells, language labels, link text, and link URLs are all escaped independently.
- **Gemini API key as header** (`x-goog-api-key`), not as a URL query parameter.
- **Custom URL validation.** Custom base URLs require HTTPS for remote hosts. Plaintext HTTP is limited to exact `localhost` or unambiguous dotted-decimal `127.0.0.0/8` addresses. Credentials, invalid ports/hosts, unsafe characters, and values over 2048 characters are rejected.
- **MCP boundary.** Only the reviewed runtime versions/layout are launched. Endpoint consent is identity-bound, redirects fail closed, tool discovery is bounded, exact input/output schemas are enforced, and every invocation requires confirmation.
- **Stdout buffer cap.** The main response process is stopped when its QML text buffer exceeds 5,242,880 string code units. The smaller Ollama readiness, discovery, and GPU probes use curl-enforced 64 KiB raw-byte caps. Neither collector can grow without bound.

## Adding a new provider

1. **`src/lib/Providers.js`** — Add a `registry` entry with `name`, `envVar`, `defaultUrl`, `needsKey`, `hasNativeThinking`, temperature range (`tempMin`/`tempMax`/`tempDefault`), `modelPlaceholder`, and optionally `models` (curated suggestions). Add a corresponding `buildRequest` case. The builder returns `{ url, headers, body }` or a safe `{ error }`; define an explicit transport policy and keep secrets out of argv. Use `extractSystemPrompt()` when the provider represents system prompts separately.

2. **`src/lib/StreamParser.js`** — If the streaming format differs from OpenAI's SSE, add a case in `parseDelta()`.

3. **`src/services/KeyringService.qml`** — The provider's `envVar` from the registry is used automatically for env var fallback. No changes needed unless the provider has special key resolution logic.

4. **UI and tests** — Settings cards use `Providers.getProviderNames()` and the registry, so basic provider/model/key UI updates automatically. Add request, parsing, error-envelope, temperature/token-contract, URL-policy, and lifecycle tests appropriate to the provider before exposing it.

## Code style

- No automated linter or formatter. Follow existing patterns.
- Use `Theme.*` for colors, typography, and layout spacing. Fixed control dimensions are acceptable only when intentional and consistent with existing components.
- Prefer `Behavior on property` for reactive animations.
- Keep JS logic in `.pragma library` files under `src/lib/`; keep QML files focused on UI and state.
- Security-sensitive code should be commented with the rationale.
