.pragma library

// Secure curl command builder for Ephemera.
// Security improvements over DMS AI Assistant:
//   1. Body via stdin (-d @-) — conversation never in /proc/cmdline
//   2. Gemini key as header (x-goog-api-key) — not in URL query param
//   3. No --compressed flag (breaks StdioCollector)

/**
 * Validate a URL for use as a provider base URL.
 *
 * Enforces: http(s) scheme only, valid hostname, max 2048 chars, no control
 * characters, default-ignorable formatting code points, or characters unsafe in URLs
 * (angle brackets, quotes, backticks, curly braces, pipes, backslashes, spaces).
 *
 * @param {string} url - URL to validate.
 * @returns {{ valid: boolean, error: string }} error is empty when valid or when URL is absent.
 */
function validateUrl(url) {
    var u = (url || "").trim();
    if (!u) return { valid: false, error: "" }; // empty is not an error, just absent
    if (u.length > 2048)
        return { valid: false, error: "URL is too long (max 2048 characters)." };
    if (!/^https?:\/\//i.test(u))
        return { valid: false, error: "Must start with http:// or https://" };
    if (!/^https?:\/\/[a-zA-Z0-9]/.test(u))
        return { valid: false, error: "Invalid hostname in URL." };
    // Reject control characters and characters unsafe in URLs (prevents injection via path)
    if (/[\x00-\x20\x7f-\x9f<>"'{}|\\^`]/.test(u))
        return { valid: false, error: "URL contains invalid characters." };
    if (_containsUnsafeUnicodeFormatting(u))
        return { valid: false, error: "URL contains invisible or directional control characters." };
    return { valid: true, error: "" };
}

// Unicode 17 Default_Ignorable_Code_Point ranges, plus line separators,
// interlinear annotation controls, and unpaired surrogates that can change
// when a JavaScript string is encoded for process argv.
function _isUnsafeFormattingCodePoint(codePoint) {
    return codePoint === 0x00ad || codePoint === 0x034f || codePoint === 0x061c
        || (codePoint >= 0x115f && codePoint <= 0x1160)
        || (codePoint >= 0x17b4 && codePoint <= 0x17b5)
        || (codePoint >= 0x180b && codePoint <= 0x180f)
        || (codePoint >= 0x200b && codePoint <= 0x200f)
        || (codePoint >= 0x2028 && codePoint <= 0x202e)
        || (codePoint >= 0x2060 && codePoint <= 0x206f)
        || codePoint === 0x3164
        || (codePoint >= 0xfe00 && codePoint <= 0xfe0f)
        || codePoint === 0xfeff || codePoint === 0xffa0
        || (codePoint >= 0xfff0 && codePoint <= 0xfffb)
        || (codePoint >= 0x1bca0 && codePoint <= 0x1bca3)
        || (codePoint >= 0x1d173 && codePoint <= 0x1d17a)
        || (codePoint >= 0xe0000 && codePoint <= 0xe0fff);
}

function _containsUnsafeUnicodeFormatting(value) {
    var text = String(value || "");
    for (var i = 0; i < text.length; i++) {
        var first = text.charCodeAt(i);
        if (first >= 0xd800 && first <= 0xdbff) {
            if (i + 1 >= text.length)
                return true;
            var second = text.charCodeAt(i + 1);
            if (second < 0xdc00 || second > 0xdfff)
                return true;
            var codePoint = 0x10000 + ((first - 0xd800) * 0x400)
                + (second - 0xdc00);
            if (_isUnsafeFormattingCodePoint(codePoint))
                return true;
            i++;
        } else if ((first >= 0xdc00 && first <= 0xdfff)
                || _isUnsafeFormattingCodePoint(first)) {
            return true;
        }
    }
    return false;
}

function normalizeBaseUrl(url) {
    var u = (url || "").trim();
    if (!u) return "";
    if (!validateUrl(u).valid) return "";
    return u.endsWith("/") ? u.slice(0, -1) : u;
}

/**
 * Sanitize an API key by stripping newlines and control characters.
 *
 * Prevents HTTP header injection by removing CR, LF, null bytes, and all
 * C0 control characters (U+0000–U+001F). The result is trimmed.
 *
 * @param {string} key - Raw API key string.
 * @returns {string} Sanitized key, or "" if input is falsy.
 */
function sanitizeApiKey(key) {
    if (!key) return "";
    return key.replace(/[\r\n\x00-\x1f]/g, "").trim();
}

// Shared helper: separates system messages from conversation messages.
// Returns { systemText: string, filtered: Array<{role, content}> }
function extractSystemPrompt(messages) {
    var systemText = "";
    var filtered = [];
    for (var i = 0; i < messages.length; i++) {
        var m = messages[i];
        if (m.role === "system") {
            systemText = m.content;
        } else {
            filtered.push(m);
        }
    }
    return { systemText: systemText, filtered: filtered };
}

function openaiChatCompletionsUrl(baseUrl) {
    var b = normalizeBaseUrl(baseUrl || "https://api.openai.com");
    if (/\/v\d+$/.test(b))
        return b + "/chat/completions";
    return b + "/v1/chat/completions";
}

/**
 * Escape a string for use inside a double-quoted curl config value.
 *
 * Curl config files (-K) use "value" syntax where backslashes, double quotes,
 * and whitespace characters must be escaped. Without this, a JSON body containing
 * quotes would break the config parser.
 *
 * @param {string} str - Raw string to escape.
 * @returns {string} Escaped string safe for curl config double-quoted context.
 */
function escapeCurlConfig(str) {
    if (!str) return "";
    return str
        .replace(/\\/g, "\\\\")
        .replace(/"/g, '\\"')
        .replace(/\n/g, "\\n")
        .replace(/\r/g, "\\r")
        .replace(/\t/g, "\\t");
}

/**
 * Build a curl command array and stdin config body for a streaming API request.
 *
 * All sensitive data (URL, auth headers, request body) is passed through a curl
 * config file on stdin (-K -), ensuring nothing appears in /proc/cmdline or ps output.
 *
 * @param {string} provider - Provider identifier.
 * @param {Object} payload - Request payload (must include baseUrl, model, messages, timeout, etc.).
 * @param {string} apiKey - Resolved API key (may be empty for Ollama).
 * @returns {{ cmd: string[], body: string } | null}
 *   cmd: curl argument array (no secrets). body: curl config string to write to stdin.
 *   Returns null if the provider requires a key but none is provided.
 */
function buildCurlCommand(provider, payload, apiKey) {
    var request = buildRequest(provider, payload, apiKey);
    if (!request || !request.url)
        return null;

    var timeout = payload.timeout || 30;
    // Command has no secrets — URL, headers, and body all go through stdin config
    var cmd = [
        "curl", "-K", "-", "-N", "-sS", "--no-buffer", "--show-error",
        "--connect-timeout", "5",
        "--max-time", String(timeout),
        "-w", "\\nEPH_STATUS:%{http_code}\\n"
    ];

    // Build curl config for stdin — hides URL, auth headers, and body from /proc/cmdline
    var config = 'url = "' + escapeCurlConfig(request.url) + '"\n';
    config += 'request = "POST"\n';
    config += 'header = "Content-Type: application/json"\n';

    var headers = request.headers || [];
    for (var i = 0; i < headers.length; i += 2) {
        if (headers[i] === "-H" && headers[i + 1])
            config += 'header = "' + escapeCurlConfig(headers[i + 1]) + '"\n';
    }

    config += 'data = "' + escapeCurlConfig(request.body || "{}") + '"\n';

    return { cmd: cmd, body: config };
}

function buildRequest(provider, payload, apiKey) {
    switch (provider) {
    case "ollama":
        return ollamaRequest(payload);
    case "anthropic":
        return anthropicRequest(payload, apiKey);
    case "gemini":
        return geminiRequest(payload, apiKey);
    case "custom":
        return customRequest(payload, apiKey);
    default:
        return openaiRequest(payload, apiKey);
    }
}

function ollamaRequest(payload) {
    var base = normalizeBaseUrl(payload.baseUrl || "http://localhost:11434");
    var hasTools = payload.tools && payload.tools.length > 0;
    var messages = Array.isArray(payload.messages) ? payload.messages : [];
    var hasNativeToolHistory = false;
    for (var i = 0; i < messages.length; i++) {
        var message = messages[i];
        if (message && (message.role === "tool"
                || (Array.isArray(message.tool_calls) && message.tool_calls.length > 0))) {
            hasNativeToolHistory = true;
            break;
        }
    }
    var useNativeChat = hasTools || hasNativeToolHistory;
    var url = base + (useNativeChat ? "/api/chat" : "/v1/chat/completions");
    var temp = clampTemperature("ollama", payload.model, payload.temperature);
    var thinkingMode = normalizeOllamaThinkingMode(payload.ollamaThinkingMode);
    var body = {
        model: payload.model,
        messages: payload.messages,
        stream: true
    };
    if (useNativeChat) {
        var options = {};
        if (payload.max_tokens > 0) options.num_predict = payload.max_tokens;
        if (temp !== undefined) options.temperature = temp;
        var contextWindow = normalizeOllamaContextWindow(payload.ollamaContextWindow);
        if (contextWindow > 0) options.num_ctx = contextWindow;
        if (Object.keys(options).length > 0)
            body.options = options;
        if (thinkingMode === "none")
            body.think = false;
        else if (thinkingMode !== "default")
            body.think = thinkingMode;
        if (hasTools)
            body.tools = payload.tools;
    } else {
        if (payload.max_tokens > 0) body.max_tokens = payload.max_tokens;
        if (temp !== undefined) body.temperature = temp;
        if (thinkingMode !== "default")
            body.reasoning_effort = thinkingMode;
    }
    // No auth header for Ollama
    return { url: url, headers: [], body: JSON.stringify(body) };
}

/**
 * Normalize an optional Ollama context window. Zero uses the model default;
 * explicit values are bounded to avoid accidental extreme memory allocation.
 * Explicit values round up to a supported preset so the persisted value and
 * settings UI cannot diverge.
 *
 * @param {*} value - Requested context size.
 * @returns {number} 0 or one of 4096, 8192, 16384, 32768, 65536, 131072.
 */
function normalizeOllamaContextWindow(value) {
    var parsed = Number(value);
    if (!isFinite(parsed) || parsed <= 0)
        return 0;
    var presets = [4096, 8192, 16384, 32768, 65536, 131072];
    for (var i = 0; i < presets.length; i++) {
        if (parsed <= presets[i])
            return presets[i];
    }
    return presets[presets.length - 1];
}

function normalizeOllamaThinkingMode(mode) {
    var m = String(mode || "default").trim().toLowerCase();
    switch (m) {
    case "none":
    case "low":
    case "medium":
    case "high":
        return m;
    default:
        return "default";
    }
}

function openaiRequest(payload, apiKey) {
    var url = openaiChatCompletionsUrl(payload.baseUrl || "https://api.openai.com");
    var safeKey = sanitizeApiKey(apiKey);
    if (!safeKey) return null;
    var headers = ["-H", "Authorization: Bearer " + safeKey];
    var temp = clampTemperature("openai", payload.model, payload.temperature);
    var body = {
        model: payload.model,
        messages: payload.messages,
        stream: true,
        stream_options: { include_usage: true }
    };
    if (payload.max_tokens > 0) body.max_tokens = payload.max_tokens;
    if (temp !== undefined) body.temperature = temp;
    return { url: url, headers: headers, body: JSON.stringify(body) };
}

function anthropicRequest(payload, apiKey) {
    var base = normalizeBaseUrl(payload.baseUrl || "https://api.anthropic.com");
    var url = base + "/v1/messages";
    var safeKey = sanitizeApiKey(apiKey);
    if (!safeKey) return null;
    var headers = [
        "-H", "x-api-key: " + safeKey,
        "-H", "anthropic-version: 2023-06-01"
    ];

    if (payload.thinkingEnabled)
        headers.push("-H", "anthropic-beta: interleaved-thinking-2025-05-14");

    // Extract system prompt from messages if present
    var extracted = extractSystemPrompt(payload.messages);
    var filteredMessages = [];
    for (var i = 0; i < extracted.filtered.length; i++) {
        var m = extracted.filtered[i];
        filteredMessages.push({
            role: m.role === "assistant" ? "assistant" : "user",
            content: m.content
        });
    }

    // Anthropic requires max_tokens — use 128000 as high cap when unlimited
    var maxTokens = (payload.max_tokens > 0) ? payload.max_tokens : 128000;
    // Anthropic requires temperature=1 when extended thinking is enabled
    var temp = payload.thinkingEnabled ? 1 : clampTemperature("anthropic", payload.model, payload.temperature);
    var body = {
        model: payload.model,
        messages: filteredMessages,
        max_tokens: maxTokens,
        stream: true
    };
    if (temp !== undefined) body.temperature = temp;

    if (payload.thinkingEnabled)
        body.thinking = { type: "enabled", budget_tokens: Math.max(1024, Math.floor(maxTokens * 0.8)) };

    if (extracted.systemText)
        body.system = extracted.systemText;

    return { url: url, headers: headers, body: JSON.stringify(body) };
}

function geminiRequest(payload, apiKey) {
    var base = normalizeBaseUrl(payload.baseUrl || "https://generativelanguage.googleapis.com");
    // Validate model name — prevent path traversal via user-supplied free text
    var model = payload.model || "gemini-2.5-flash";
    if (!/^[a-zA-Z0-9._:\-]+$/.test(model)) return null;
    // Key as header, NOT in URL — security fix
    var url = base + "/v1beta/models/" + model
        + ":streamGenerateContent?alt=sse";
    var safeKey = sanitizeApiKey(apiKey);
    if (!safeKey) return null;
    var headers = ["-H", "x-goog-api-key: " + safeKey];

    // Extract system prompt
    var extracted = extractSystemPrompt(payload.messages);
    var contents = [];
    for (var i = 0; i < extracted.filtered.length; i++) {
        var m = extracted.filtered[i];
        contents.push({
            role: m.role === "user" ? "user" : "model",
            parts: [{ text: m.content }]
        });
    }

    var temp = clampTemperature("gemini", payload.model, payload.temperature);
    var genConfig = {};
    if (payload.max_tokens > 0) genConfig.maxOutputTokens = payload.max_tokens;
    if (temp !== undefined) genConfig.temperature = temp;
    var body = {
        contents: contents,
        generationConfig: genConfig
    };
    if (extracted.systemText)
        body.system_instruction = { parts: [{ text: extracted.systemText }] };

    return { url: url, headers: headers, body: JSON.stringify(body) };
}

function customRequest(payload, apiKey) {
    return openaiRequest(payload, apiKey);
}

// ─── Provider Registry ──────────────────────────────────────────
// Centralized metadata for each provider. Adding a new provider only requires
// adding one entry here and a buildRequest function above.

var registry = {
    "ollama": {
        name: "Ollama",
        envVar: null,
        defaultUrl: "http://localhost:11434",
        needsKey: false,
        hasNativeThinking: false,
        tempMin: 0.0, tempMax: 2.0, tempDefault: 0.8,
        modelPlaceholder: "llama3.2"
    },
    "openai": {
        name: "OpenAI",
        envVar: "OPENAI_API_KEY",
        defaultUrl: "https://api.openai.com",
        needsKey: true,
        hasNativeThinking: false,
        tempMin: 0.0, tempMax: 2.0, tempDefault: 1.0,
        modelPlaceholder: "gpt-5.4",
        // o1/o3 reasoning models don't support temperature
        tempUnsupportedModels: ["o1", "o3"],
        models: [
            "gpt-5.4", "gpt-5.4-pro", "gpt-5", "gpt-5-mini", "gpt-5-nano",
            "gpt-4.1", "o4-mini", "o3", "o3-pro", "gpt-4o", "gpt-4o-mini"
        ]
    },
    "anthropic": {
        name: "Anthropic",
        envVar: "ANTHROPIC_API_KEY",
        defaultUrl: "https://api.anthropic.com",
        needsKey: true,
        hasNativeThinking: true,
        tempMin: 0.0, tempMax: 1.0, tempDefault: 1.0,
        modelPlaceholder: "claude-sonnet-4-6",
        models: [
            "claude-opus-4-6", "claude-sonnet-4-6", "claude-haiku-4-5",
            "claude-sonnet-4-5", "claude-opus-4-5"
        ]
    },
    "gemini": {
        name: "Gemini",
        envVar: "GEMINI_API_KEY",
        defaultUrl: "https://generativelanguage.googleapis.com",
        needsKey: true,
        hasNativeThinking: true,
        tempMin: 0.0, tempMax: 2.0, tempDefault: 1.0,
        modelPlaceholder: "gemini-2.5-flash",
        models: [
            "gemini-3.1-pro-preview", "gemini-3-flash-preview",
            "gemini-3.1-flash-lite-preview", "gemini-2.5-pro",
            "gemini-2.5-flash", "gemini-2.5-flash-lite"
        ]
    },
    "custom": {
        name: "custom provider",
        envVar: "EPHEMERA_API_KEY",
        defaultUrl: "https://api.openai.com",
        needsKey: true,
        hasNativeThinking: false,
        tempMin: 0.0, tempMax: 2.0, tempDefault: 0.7,
        modelPlaceholder: "model-name"
    }
};

function getProviderInfo(provider) {
    return registry[provider] || registry["custom"];
}

function getProviderNames() {
    return Object.keys(registry);
}

/**
 * Get the hardcoded model list for a provider.
 *
 * Returns the models array from the registry entry, or an empty array
 * if the provider has no predefined models (e.g. ollama, custom).
 *
 * @param {string} provider - Provider identifier.
 * @returns {string[]} Array of model name strings.
 */
function getModelList(provider) {
    var info = registry[provider];
    return (info && info.models) ? info.models : [];
}

/**
 * Clamp temperature to a provider's valid range, or return undefined if unsupported.
 *
 * Some models (OpenAI o1/o3 reasoning models) do not support temperature at all.
 * Detection uses prefix matching with separator check: "o1-mini" matches but "o100" does not.
 * Falls back to the provider's default temperature when the input is null/undefined.
 *
 * @param {string} provider - Provider identifier.
 * @param {string} model - Model name (checked against tempUnsupportedModels).
 * @param {number} temperature - Requested temperature value.
 * @returns {number|undefined} Clamped temperature, or undefined if the model rejects temperature.
 */
function clampTemperature(provider, model, temperature) {
    var info = registry[provider] || registry["custom"];
    // Check if model doesn't support temperature
    if (info.tempUnsupportedModels) {
        var m = (model || "").toLowerCase();
        for (var i = 0; i < info.tempUnsupportedModels.length; i++) {
            var prefix = info.tempUnsupportedModels[i];
            if (m === prefix) return undefined;
            // Match prefix followed by a separator (e.g. "o1-mini", "o3-preview")
            // but not a continuation like "o1.5" or "o100"
            if (m.indexOf(prefix) === 0) {
                var next = m.charAt(prefix.length);
                if (next === "-" || next === "_") return undefined;
            }
        }
    }
    var t = (temperature !== undefined && temperature !== null) ? temperature : info.tempDefault;
    return Math.max(info.tempMin, Math.min(info.tempMax, t));
}

function getTemperatureRange(provider) {
    var info = registry[provider] || registry["custom"];
    return { min: info.tempMin, max: info.tempMax, defaultValue: info.tempDefault };
}
