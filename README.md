# Ephemera

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![DMS Plugin](https://img.shields.io/badge/DMS-Plugin-blueviolet)
![Wayland](https://img.shields.io/badge/Wayland-only-yellow)
![Platform: Linux](https://img.shields.io/badge/Platform-Linux-lightgrey)
![Version](https://img.shields.io/static/v1?label=version&message=1.1.0&color=green) <!-- x-release-please-version -->

AI chat for your desktop — ask quick questions, keep nothing (or everything).

![Ephemera screenshot](screenshots/screenshot.jpg)

Ephemera is a [Quickshell](https://github.com/quickshell-mirror/quickshell) plugin that adds an AI chat slideout panel to your Wayland desktop shell. By default, all conversations live in memory and disappear when you close the panel. Enable **Save Chat History** in settings to persist conversations across sessions.

## Features

- **Multiple providers** — Ollama, OpenAI, Anthropic, Gemini, or any OpenAI-compatible endpoint
- **Streaming responses** — real-time token-by-token output via SSE
- **Thinking/reasoning display** — collapsible thinking section for models that emit `<think>` tags (Qwen3, DeepSeek via Ollama) or explicit `reasoning_content` fields (DeepSeek via OpenAI-compatible providers); thinking and generating phases shown with distinct dot colors
- **Ollama auto-management** — automatically starts `ollama serve` if not running, discovers available models, and re-checks connectivity each time the panel opens
- **Experimental MCP tools for Ollama** — connect a remote MCP server through a version-checked bridge, expose only explicitly approved tool contracts, and confirm every invocation with its complete arguments
- **Markdown rendering** — assistant responses rendered as rich text with code blocks, tables, lists, and blockquotes (deferred until streaming completes for performance)
- **System prompt presets** — quick-select presets (Concise, Code Expert, Translator, Writing Editor) or write a custom system prompt
- **Regenerate with variant pagination** — retry the last assistant response with a single click; previous responses are preserved and navigable with `< 1/2 >` pagination arrows (ChatGPT-style), even mid-stream; each variant remembers which model generated it, so switching models between regenerations shows the correct model chip per variant
- **Edit and regenerate** — click the edit button on any user message to modify it; sending the edit removes all messages after it and regenerates from the new text
- **Export conversation** — copy the full conversation as markdown to clipboard, or save to a `.md` file in your home directory
- **Optional persistence** — messages are ephemeral by default; enable **Save Chat History** in settings to persist conversations across sessions (API keys are never stored)
- **System keyring integration** — store API keys encrypted in GNOME Keyring / KDE Wallet / KeePassXC via `secret-tool`; env vars as fallback; keyring UI hidden gracefully when `secret-tool` is not installed
- **Security-first** — API keys stored encrypted in the system keyring (never by PluginService), request bodies sent via stdin (never in `/proc/cmdline`), API keys passed as headers (not URL params), MCP calls require per-tool and per-call approval, link schemes are restricted, URLs are validated, and process output is bounded

## Requirements

- [Quickshell](https://github.com/quickshell-mirror/quickshell) with a configuration that provides `qs.Common`, `qs.Widgets`, and `qs.Services` modules
- `curl` (used for API requests)
- `wl-copy` from [wl-clipboard](https://github.com/bugaevc/wl-clipboard) (for the copy button)
- `secret-tool` from [libsecret](https://wiki.gnome.org/Projects/Libsecret) (optional — for storing API keys in the system keyring)
- For Ollama: [Ollama](https://ollama.com) installed and at least one model pulled
- For experimental MCP tools: native Linux, Node.js 24.17.0 or newer within major version 24, npm, and the globally installed `mcp-remote` 0.1.38 release. Both Node's bundled Undici and the bridge's direct Undici dependency must be >=7.28.0 and <8; the resolved `open` browser launcher must be the reviewed 10.1.0 or 10.2.0 release

## Installation

Place or symlink this directory into your Quickshell configuration's plugin path, then reload the shell.

## Configuration

### API Keys

#### System keyring (recommended)

If `secret-tool` is installed, you can store API keys directly from the Settings panel. Keys are saved encrypted in your system keyring (GNOME Keyring, KDE Wallet, KeePassXC, or any [freedesktop.org Secret Service](https://specifications.freedesktop.org/secret-service/latest/) provider). The keyring is unlocked with your login session — no extra passwords to manage.

1. Open Settings (tune icon)
2. Scroll to **API Keys**
3. Paste your key and click **Save**

You can also manage keys from the command line:

```bash
# Store a key
echo -n "sk-..." | secret-tool store --label="Ephemera OpenAI API key" service ephemera provider openai

# Check if a key is stored
secret-tool lookup service ephemera provider openai

# Remove a key
secret-tool clear service ephemera provider openai
```

#### Environment variables (fallback)

If `secret-tool` is not installed, or you prefer env vars, set them before starting Quickshell. The keyring is checked first; env vars are used as a fallback.

| Provider   | Environment Variable  |
|------------|-----------------------|
| OpenAI     | `OPENAI_API_KEY`      |
| Anthropic  | `ANTHROPIC_API_KEY`   |
| Gemini     | `GEMINI_API_KEY`      |
| Custom     | `EPHEMERA_API_KEY`    |
| Ollama     | *(none required)*     |

### Experimental MCP Tools

MCP tool calling is available only with the Ollama provider. Install the tested bridge release globally:

```bash
npm install --global mcp-remote@0.1.38 undici@7.28.0 open@10.2.0
```

Before every connection, Ephemera checks the exact Node executable and its bundled Undici, the installed package metadata, the expected executable layout, the exact `mcp-remote` 0.1.38 version, and the bridge's resolved direct Undici and `open` dependencies. Both Undici implementations must be >=7.28.0 and <8; `open` must be exactly 10.1.0 or 10.2.0. A preload then makes the checked direct dependency authoritative for global and direct Fetch calls and rejects every automatic HTTP redirect. Concurrent OAuth startup is intentionally unsupported: when this bridge version tries to poll another process's loopback auth endpoint, Ephemera terminates the secondary bridge instead of permitting loopback access or letting it delete the live peer's lock. Retry after the first authorization finishes. This is a local version-and-layout gate, not cryptographic verification of installed files or proof that the installation has no other vulnerabilities; the local Node and global npm installation remain part of the trusted computing base. The upstream bridge describes itself as experimental and has known transport and OAuth compatibility gaps, so MCP support remains opt-in and may require a manual reconnect. Configure the server under **Settings → MCP Tools**, review and approve the complete individual tool contracts that may be shown to the model, then enable model tool requests. Arguments must match that approved input schema, and every invocation still requires a separate confirmation showing the server, tool, and complete arguments.

HTTPS is the default for remote servers. Plain HTTP is accepted automatically only for loopback addresses; other HTTP endpoints require a separate warning toggle and should be used only on a trusted private network. Bridge Fetch redirects fail closed, including HTTPS redirects, so they cannot downgrade an approved endpoint to plaintext. The initial OAuth URL handed to the Linux browser must obey the same scheme policy; subsequent navigation inside that external browser remains governed by the browser. The guarded browser handoff supports native Linux and intentionally rejects WSL, whose launcher path bypasses `xdg-open`. Endpoint URLs cannot contain embedded credentials, query strings, or fragments because `mcp-remote` receives the URL as a process argument.

`mcp-remote` performs OAuth when required and stores its OAuth session under `~/.mcp-auth`. Those credentials are managed by the bridge, not by Ephemera or PluginService.

### Settings

All settings are configurable from the in-app settings panel (tune icon):

- **Provider** — ollama, openai, anthropic, gemini, or custom
- **Model** — auto-discovered dropdown for Ollama, free-text for others
- **Ollama URL** — defaults to `http://localhost:11434`
- **Ollama Thinking** — Default, Off, Low, Medium, or High reasoning effort for Ollama models that support it; Off requests no thinking
- **Ollama Context Window** — optional 4K–128K native-chat context for MCP/tool rounds; the model default remains the memory-efficient default
- **Custom Base URL** — for OpenAI-compatible endpoints (validated: http/https only, valid hostname, max 2048 chars)
- **Extended Thinking** — toggle for Anthropic provider; enables extended thinking (forces temperature to 1.0, allocates 80% of max tokens as thinking budget)
- **System Prompt** — prepended to every request; quick-select presets available or enter custom text
- **Temperature** — 0.0 (focused) to 2.0 (creative)
- **Max Tokens** — 256 to 16,384
- **Context Turns** — number of recent conversation turns sent to the API (2–100)
- **Request Timeout** — max time for a streaming response (30–600s, default 300s)
- **Ollama Controls** — refresh models button, explicit start/stop button, idle auto-stop timeout (Never, 5, 10, 15, or 30 minutes; only auto-stops Ollama if the plugin started it)
- **Save Chat History** — persist conversations across sessions (off by default)
- **Experimental MCP Tools** — Ollama-only server connection, transport consent, complete contract review, and per-call confirmation

Settings are persisted via Quickshell's `PluginService`. API keys are stored only in the system keyring, never by PluginService.

## Usage

Open the slideout panel via your shell's configured keybind or action. Type a message and press **Enter** to send (Shift+Enter for newline). Press **Escape** to dismiss the panel.

**Keyboard shortcuts:**

| Shortcut | Action |
|---|---|
| Enter | Send message |
| Shift+Enter | Insert newline |
| Escape | Close panel |
| Ctrl+L | Clear chat |
| Ctrl+N | New conversation (clear chat + composer) |
| Ctrl+Shift+S | Toggle settings |
| Up arrow | Recall last sent message (when composer is empty) |

- **Copy** — hover over an assistant message to reveal the copy button (shows a checkmark on success)
- **Edit** — hover over a user message to reveal the edit button; modify the message and press Enter to regenerate the conversation from that point (removes all subsequent messages)
- **Regenerate** — hover over the last assistant message to reveal the regenerate button; after regenerating, use the `<` `>` arrows to navigate between response variants; each variant's model chip shows which model generated it
- **Export** — click the copy icon in the header to copy the conversation as markdown, or the save icon to write it to `~/ephemera-chat-<timestamp>.md`
- **Expand** — use the expand button to widen the panel (480px → 960px); model chips in the header and message bubbles expand to show full model names
- **Error hints** — HTTP errors display contextual suggestions (e.g., 401 → check API key, 429 → rate limited)
- **Missing API key banner** — when a required API key is absent, a prominent banner in the chat area directs you to Settings (if keyring is available) or shows which environment variable to set

## Known Limitations

- **Multi-screen**: The chat service is shared across all screens. Opening the panel on two monitors shows the same conversation.

## Troubleshooting

### Ollama not detected

Ephemera pings `http://localhost:11434/api/tags` on startup. If Ollama isn't found:

1. Verify Ollama is installed: `ollama --version`
2. Pull at least one model: `ollama pull llama3.2`
3. Ephemera will auto-start `ollama serve` if it isn't running — check that the Ollama binary is in your `$PATH` when Quickshell starts
4. If using a custom URL, verify it in Settings → Provider → Ollama URL
5. Use the **Connect to Ollama** button in Settings to retry

### API key not detected

**Easiest fix:** install `secret-tool` and store your key from the Settings panel. This avoids env var scoping issues entirely.

```bash
# Arch
sudo pacman -S libsecret

# Ubuntu/Debian
sudo apt install libsecret-tools
```

**If using env vars:** they must be set **before** Quickshell starts. Variables set in `~/.bashrc` or `~/.zshrc` are often not available to the compositor because it launches before interactive shell configs are sourced.

```bash
# Reliable for compositors — use systemd environment.d:
# ~/.config/environment.d/ephemera.conf
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GEMINI_API_KEY=AI...
EPHEMERA_API_KEY=...
```

You can also export them in your shell profile, but you may need to launch Quickshell from a terminal where the variables are set.

### Empty responses

- Verify the model name is correct for your provider
- Check that streaming is supported by your endpoint
- Increase the **Request Timeout** slider in Settings (default 300s)
- For Ollama, ensure the model is fully downloaded: `ollama list`

### Timeout errors

The default timeout is 300 seconds. For large models or slow hardware, increase it in Settings → Model Parameters → Request Timeout (max 600s).

## Custom Provider

The "custom" provider works with any OpenAI-compatible API (LocalAI, vLLM, LM Studio, OpenRouter, Groq, etc.). Set the base URL in Settings and export `EPHEMERA_API_KEY`. Ephemera appends `/v1/chat/completions` automatically unless the URL already ends with a versioned path.

## License

MIT
