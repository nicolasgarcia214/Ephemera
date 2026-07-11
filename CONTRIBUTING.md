# Contributing to Ephemera

This guide covers everything you need to know to work on Ephemera — a Quickshell daemon plugin that provides an ephemeral AI chat slideout for Wayland desktops.

## Prerequisites

- A running [DankMaterialShell (DMS)](https://danklinux.com) installation (provides Quickshell + `qs.Common`, `qs.Widgets`, `qs.Services`)
- `curl`, `wl-copy` (from wl-clipboard), and optionally [Ollama](https://ollama.com)
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
│   │   └── OllamaManager.qml           # Ollama lifecycle — auto-start, ping, shutdown, model discovery
│   ├── components/
│   │   ├── EphemeraPanel.qml            # Wayland layer-shell PanelWindow — slide/expand animations
│   │   ├── EphemeraChat.qml             # Main UI — header, message area, composer, overlays
│   │   ├── ChatComposer.qml            # Auto-growing text input with send/stop/clear
│   │   ├── ChatHeader.qml              # Header bar — model selector, actions, overflow menu
│   │   ├── ChatToast.qml               # Ephemeral notification overlay
│   │   ├── ClearChatDialog.qml         # Clear chat confirmation dialog
│   │   ├── EphemeraSettings.qml         # Settings shell — delegates to card components below
│   │   ├── ProviderSettingsCard.qml     # Provider/model selection with URL validation
│   │   ├── ModelParametersCard.qml      # Temperature, max tokens, system prompt, timeout sliders
│   │   ├── ApiKeysCard.qml              # API key status from provider registry
│   │   ├── ChatHistoryCard.qml          # Persistence toggle
│   │   ├── AccordionSection.qml         # Reusable animated show/hide container
│   │   ├── SettingsCard.qml             # Reusable themed card with icon and title
│   │   ├── MessageList.qml              # ListView wrapper with auto-scroll and entry animations
│   │   └── MessageBubble.qml            # Message rendering (markdown, variants, copy, regenerate, timer)
│   └── lib/
│       ├── Providers.js                 # Provider registry + curl command builders + URL validation
│       ├── Markdown.js                  # Markdown-to-HTML converter with security hardening
│       ├── StreamParser.js              # SSE stream parsing — parseDelta() per provider format
│       ├── ChatExport.js                # Chat export to markdown format
│       ├── VariantStore.js              # Pure-function variant store operations (save, get, evict)
│       └── ErrorHints.js                # Contextual error hints for HTTP/curl error codes
├── tests/
│   └── run_tests.js                     # Unit tests for all JS modules (319 tests)
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
│  ├─ Provider settings (persisted via PluginService)
│  ├─ Chat persistence (opt-in via persistChat toggle, debounced saves)
│  └─ Providers.js (provider registry, curl command builders, URL validation)
│
├─ StreamingService (child service, src/services/)
│  ├─ Curl process (stdin config via -K -, SSE streaming, 5MB buffer cap)
│  ├─ Stream buffers (_streamContent, _streamThinking, _streamVariantIndex)
│  ├─ Backoff.js (exponential backoff with jitter for error cooldown)
│  └─ ErrorHints.js (contextual HTTP/curl error messages)
│
├─ KeyringService (child service, src/services/)
│  └─ API key resolution (system keyring via secret-tool → env var fallback)
│
├─ OllamaManager (child service, src/services/)
│  └─ Ollama lifecycle (ping → auto-start → discover models, 15 retries)
│
└─ Variants (one per screen)
   └─ EphemeraPanel (PanelWindow with slide/expand animations)
      └─ EphemeraChat
         ├─ MessageList → MessageBubble (uses Markdown.js, streaming timer)
         ├─ Composer (auto-growing text input)
         └─ EphemeraSettings (overlay)
            ├─ ProviderSettingsCard
            ├─ ModelParametersCard
            ├─ ApiKeysCard
            └─ ChatHistoryCard
```

**Data flow:** User types → `EphemeraChat.sendCurrentMessage()` → `EphemeraService.sendMessage()` → builds payload with sliding context window → `Providers.buildCurlCommand()` → spawns curl via `Process` with body on stdin → `StdioCollector` captures SSE chunks → `handleStreamChunk()` parses `data:` lines → `StreamParser.parseDelta()` extracts text per provider → `updateStreamContent()` appends to `_streamContent` buffer and conditionally updates ListModel (only if the user is viewing the streaming variant) → UI updates live.

**Regeneration flow:** User clicks Regenerate → `regenerate()` saves current `{content, thinking, modelName}` into `variantStore[msgId]` → increments `variantCount`, sets new variant's `modelName` to the current model, resets message for streaming → `_launchCurl()` starts new request (no new messages appended) → stream writes to `_streamContent`/`_streamThinking` buffers → on finalize, saved to `variantStore` at `_streamVariantIndex` → user navigates variants via `switchVariant()` which loads content and `modelName` from `variantStore`, so each variant's bubble chip shows the model that generated it.

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

### Unit tests

Pure JS modules in `src/lib/` have a Node.js test suite:

```sh
node tests/run_tests.js
```

This tests Providers.js, StreamParser.js, Markdown.js, ChatExport.js, VariantStore.js, ErrorHints.js, and Backoff.js. Run after any change to JS files.

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

You can test the exact curl command the plugin would issue:

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
# Check if Ollama is running
curl -s http://localhost:11434/api/tags

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
- "Connect to Ollama" button in settings triggers reconnect
- Save Chat History toggle persists messages across sessions; clearing chat also clears persisted data
- All dismiss actions (close button, Escape, Mod+A) only hide the panel — Ollama keeps running; idle auto-stop handles cleanup if the plugin started it
- Escape key hides panel (same as close button — no shutdown dialog)
- Ctrl+L clears chat (blocked during streaming)
- Ctrl+N clears chat and composer (blocked during streaming)
- Ctrl+Shift+S toggles settings overlay
- Up arrow in empty composer recalls last sent message; with text in composer, moves cursor normally
- Expand/collapse button works on the slideout
- Custom base URLs are validated (http/https only, valid hostname, max 2048 chars); inline error shown on invalid input
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
- **Custom URL validation.** Custom base URLs must start with `http://` or `https://`, have a valid hostname, and be under 2048 characters. Validation errors shown inline.
- **Stdout buffer cap.** The `StdioCollector` is capped at 5MB (checked before processing the new chunk). A rogue endpoint cannot exhaust memory.

## Adding a new provider

1. **`src/lib/Providers.js`** — Add a `registry` entry with `name`, `envVar`, `defaultUrl`, `needsKey`, `hasNativeThinking`, temperature range (`tempMin`/`tempMax`/`tempDefault`), `modelPlaceholder`, and optionally `models` (hardcoded list). Add a corresponding `buildRequest` case in `buildRequest()`. The request builder returns `{ url, headers, body }`. Use the shared `extractSystemPrompt(payload.messages)` helper to separate system messages if the provider needs them in a different field.

2. **`src/lib/StreamParser.js`** — If the streaming format differs from OpenAI's SSE, add a case in `parseDelta()`.

3. **`src/services/KeyringService.qml`** — The provider's `envVar` from the registry is used automatically for env var fallback. No changes needed unless the provider has special key resolution logic.

4. **UI auto-updates** — Settings cards use `Providers.getProviderNames()` and the registry, so the new provider appears automatically in dropdowns, API key status, and model placeholders.

## Code style

- No automated linter or formatter. Follow existing patterns.
- Use `Theme.*` for all colors, spacing, and sizing — never hardcode values.
- Prefer `Behavior on property` for reactive animations.
- Keep JS logic in `.pragma library` files under `src/lib/`; keep QML files focused on UI and state.
- Security-sensitive code should be commented with the rationale.
