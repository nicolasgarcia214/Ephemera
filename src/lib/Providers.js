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

/**
 * Validate a custom OpenAI-compatible provider base URL.
 *
 * Custom providers may use HTTPS on any valid hostname. Plaintext HTTP is
 * limited to the exact localhost name or an unambiguous dotted-decimal address
 * in 127.0.0.0/8. Userinfo is never accepted because curl would transmit it as
 * credentials independently of the configured API key.
 *
 * @param {string} url - Custom provider base URL to validate.
 * @returns {{ valid: boolean, error: string }} error is safe to show to users.
 */
function validateCustomProviderUrl(url) {
    var baseValidation = validateUrl(url);
    if (!baseValidation.valid)
        return baseValidation;

    var u = String(url || "").trim();
    var match = u.match(/^(https?):\/\/([^\/?#]+)(?:[\/?#]|$)/i);
    if (!match)
        return { valid: false, error: "Invalid custom provider URL." };

    var scheme = match[1].toLowerCase();
    var authority = match[2];
    if (authority.indexOf("@") >= 0) {
        return {
            valid: false,
            error: "Custom provider URLs must not include credentials."
        };
    }

    var host = authority;
    var portSeparator = authority.lastIndexOf(":");
    if (portSeparator >= 0) {
        if (authority.indexOf(":") !== portSeparator)
            return { valid: false, error: "Invalid hostname in custom provider URL." };
        host = authority.slice(0, portSeparator);
        var port = authority.slice(portSeparator + 1);
        if (!/^\d+$/.test(port) || Number(port) > 65535) {
            return { valid: false, error: "Invalid port in custom provider URL." };
        }
    }

    var ipv4 = _parseIpv4Address(host);
    if (!ipv4 && !_isValidHostname(host))
        return { valid: false, error: "Invalid hostname in custom provider URL." };

    if (scheme === "http"
            && host.toLowerCase() !== "localhost"
            && !(ipv4 && ipv4[0] === 127)) {
        return {
            valid: false,
            error: "Custom provider HTTP is allowed only for localhost or 127.0.0.0/8; use HTTPS for remote endpoints."
        };
    }
    return { valid: true, error: "" };
}

function _parseIpv4Address(host) {
    var text = String(host || "");
    if (!/^[0-9.]+$/.test(text))
        return null;
    var parts = text.split(".");
    if (parts.length !== 4)
        return null;
    var octets = [];
    for (var i = 0; i < parts.length; i++) {
        var part = parts[i];
        if (!/^\d{1,3}$/.test(part)
                || (part.length > 1 && part.charAt(0) === "0"))
            return null;
        var value = Number(part);
        if (value > 255)
            return null;
        octets.push(value);
    }
    return octets;
}

function _isValidHostname(host) {
    var text = String(host || "");
    if (!text || text.length > 253 || /^[0-9.]+$/.test(text))
        return false;
    if (text.charAt(text.length - 1) === ".")
        text = text.slice(0, -1);
    if (!text)
        return false;
    var labels = text.split(".");
    for (var i = 0; i < labels.length; i++) {
        var label = labels[i];
        if (!/^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$/.test(label))
            return false;
    }
    return true;
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
 * @returns {{ cmd: string[], body: string } | { error: string } | null}
 *   cmd: curl argument array (no secrets). body: curl config string to write to stdin.
 *   Returns an error-only object for a rejected endpoint, or null if the
 *   provider requires a key but none is provided.
 */
function buildCurlCommand(provider, payload, apiKey) {
    var request = buildRequest(provider, payload, apiKey);
    if (!request)
        return null;
    if (request.error)
        return { error: request.error };
    if (!request.url)
        return null;

    var timeout = payload.timeout || 30;
    // Command has no secrets — URL, headers, and body all go through stdin config
    var cmd = [
        "curl", "-q", "-K", "-",
        "--proto", "=http,https",
        "--proto-redir", "=http,https",
        "--max-redirs", "0",
        "-N", "-sS", "--no-buffer", "--show-error",
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
        body.stream_options = { include_usage: true };
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
    return _openaiCompatibleRequest(payload, apiKey, "openai");
}

function _isOpenAiOSeriesModel(model) {
    return /^o[0-9]+(?:$|[-_])/.test(String(model || "").toLowerCase());
}

function _openaiCompatibleRequest(payload, apiKey, provider) {
    var url = openaiChatCompletionsUrl(payload.baseUrl || "https://api.openai.com");
    var safeKey = sanitizeApiKey(apiKey);
    if (!safeKey) return null;
    var headers = ["-H", "Authorization: Bearer " + safeKey];
    var temp = clampTemperature(provider, payload.model, payload.temperature);
    var body = {
        model: payload.model,
        messages: payload.messages,
        stream: true,
        stream_options: { include_usage: true }
    };
    if (payload.max_tokens > 0) {
        if (provider === "openai" && _isOpenAiOSeriesModel(payload.model))
            body.max_completion_tokens = payload.max_tokens;
        else
            body.max_tokens = payload.max_tokens;
    }
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

    var thinkingMode = _anthropicThinkingMode(payload.model);
    if (payload.thinkingEnabled && thinkingMode === "manual"
            && _anthropicNeedsInterleavedHeader(payload.model)) {
        headers.push("-H", "anthropic-beta: interleaved-thinking-2025-05-14");
    }

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

    // Anthropic requires max_tokens and rejects values above each model's cap.
    var outputCap = _anthropicOutputCap(payload.model);
    var requestedMax = Number(payload.max_tokens);
    var maxTokens = (isFinite(requestedMax) && requestedMax > 0)
        ? Math.min(Math.floor(requestedMax), outputCap) : outputCap;
    // Manual thinking requires a minimum 1,024-token budget strictly below max_tokens.
    if (payload.thinkingEnabled && thinkingMode === "manual" && maxTokens <= 1024)
        maxTokens = Math.min(1025, outputCap);
    var alwaysThinking = _anthropicAlwaysThinking(payload.model);
    var fixedSampling = _anthropicUsesFixedSampling(payload.model);
    var temp = (payload.thinkingEnabled || alwaysThinking || fixedSampling)
        ? undefined : clampTemperature("anthropic", payload.model, payload.temperature);
    var body = {
        model: payload.model,
        messages: filteredMessages,
        max_tokens: maxTokens,
        stream: true
    };
    if (temp !== undefined) body.temperature = temp;

    if (payload.thinkingEnabled) {
        if (thinkingMode === "adaptive") {
            body.thinking = { type: "adaptive", display: "summarized" };
        } else {
            var budgetTokens = Math.max(1024, Math.floor(maxTokens * 0.8));
            body.thinking = {
                type: "enabled",
                budget_tokens: Math.min(budgetTokens, maxTokens - 1)
            };
        }
    } else if (_anthropicNeedsExplicitThinkingDisabled(payload.model)) {
        body.thinking = { type: "disabled" };
    }

    if (extracted.systemText)
        body.system = extracted.systemText;

    return { url: url, headers: headers, body: JSON.stringify(body) };
}

function _anthropicModelMatches(model, prefix) {
    var m = String(model || "").toLowerCase();
    return m === prefix || m.indexOf(prefix + "-") === 0;
}

function _anthropicAlwaysThinking(model) {
    return _anthropicModelMatches(model, "claude-fable-5")
        || _anthropicModelMatches(model, "claude-mythos-5")
        || _anthropicModelMatches(model, "claude-mythos-preview");
}

function _anthropicUsesFixedSampling(model) {
    return _anthropicModelMatches(model, "claude-opus-4-8")
        || _anthropicModelMatches(model, "claude-sonnet-5");
}

function _anthropicNeedsExplicitThinkingDisabled(model) {
    return _anthropicModelMatches(model, "claude-sonnet-5");
}

function _anthropicThinkingMode(model) {
    var adaptiveModels = [
        "claude-fable-5", "claude-mythos-5", "claude-mythos-preview",
        "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6",
        "claude-sonnet-5", "claude-sonnet-4-6"
    ];
    for (var i = 0; i < adaptiveModels.length; i++) {
        if (_anthropicModelMatches(model, adaptiveModels[i]))
            return "adaptive";
    }
    return "manual";
}

function _anthropicNeedsInterleavedHeader(model) {
    var m = String(model || "").toLowerCase();
    if (m.indexOf("haiku") >= 0)
        return false;
    return _anthropicModelMatches(m, "claude-opus-4-5")
        || _anthropicModelMatches(m, "claude-sonnet-4-5")
        || _anthropicModelMatches(m, "claude-opus-4-1")
        || _anthropicModelMatches(m, "claude-opus-4")
        || _anthropicModelMatches(m, "claude-sonnet-4");
}

function _anthropicOutputCap(model) {
    var highCapacityModels = [
        "claude-fable-5", "claude-mythos-5", "claude-mythos-preview",
        "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6",
        "claude-sonnet-5", "claude-sonnet-4-6"
    ];
    for (var i = 0; i < highCapacityModels.length; i++) {
        if (_anthropicModelMatches(model, highCapacityModels[i]))
            return 128000;
    }
    if (_anthropicModelMatches(model, "claude-haiku-4-5")
            || _anthropicModelMatches(model, "claude-opus-4-5")
            || _anthropicModelMatches(model, "claude-sonnet-4-5")
            || _anthropicModelMatches(model, "claude-3-7-sonnet")) {
        return 64000;
    }
    if (String(model || "").toLowerCase().indexOf("claude-3-5-") === 0)
        return 8192;
    if (String(model || "").toLowerCase().indexOf("claude-3-") === 0)
        return 4096;
    return 64000;
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
    var validation = validateCustomProviderUrl(
        payload.baseUrl || registry["custom"].defaultUrl);
    if (!validation.valid)
        return { error: validation.error };
    return _openaiCompatibleRequest(payload, apiKey, "custom");
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
        models: [
            "gpt-5.4", "gpt-5", "gpt-5-mini", "gpt-5-nano",
            "gpt-4.1", "o4-mini", "o3", "gpt-4o", "gpt-4o-mini"
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
            "claude-fable-5", "claude-opus-4-8", "claude-sonnet-5",
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
            "gemini-3.1-flash-lite", "gemini-2.5-pro",
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
 * OpenAI o-series models do not support temperature at all.
 * Falls back to the provider's default temperature when the input is null/undefined.
 *
 * @param {string} provider - Provider identifier.
 * @param {string} model - Model name (checked for OpenAI o-series compatibility).
 * @param {number} temperature - Requested temperature value.
 * @returns {number|undefined} Clamped temperature, or undefined if the model rejects temperature.
 */
function clampTemperature(provider, model, temperature) {
    var info = registry[provider] || registry["custom"];
    if (provider === "openai" && _isOpenAiOSeriesModel(model))
        return undefined;
    var t = (temperature !== undefined && temperature !== null) ? temperature : info.tempDefault;
    return Math.max(info.tempMin, Math.min(info.tempMax, t));
}

function getTemperatureRange(provider) {
    var info = registry[provider] || registry["custom"];
    return { min: info.tempMin, max: info.tempMax, defaultValue: info.tempDefault };
}
