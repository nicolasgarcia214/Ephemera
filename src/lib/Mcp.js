.pragma library

/**
 * Build the trust key used to bind tool approvals to one MCP server.
 *
 * @param {string} url - MCP server URL.
 * @param {string} command - Bridge executable command.
 * @returns {string} Stable key for the current MCP bridge target.
 */
function trustKey(url, command) {
    return String(command || "").trim() + "\n" + String(url || "").trim();
}

function _normalizeStringArray(values) {
    var input = values;
    if (typeof input === "string") {
        try { input = JSON.parse(input); } catch (e) { input = []; }
    }
    if (!Array.isArray(input))
        return [];
    var seen = {};
    var result = [];
    for (var i = 0; i < input.length; i++) {
        var value = String(input[i] || "").trim();
        var seenKey = "$" + value;
        if (!value || seen[seenKey]) continue;
        seen[seenKey] = true;
        result.push(value);
    }
    return result;
}

function _setStringAllowed(values, value, allowed) {
    var current = _normalizeStringArray(values);
    var key = String(value || "").trim();
    if (!key) return current;

    var result = [];
    var found = false;
    for (var i = 0; i < current.length; i++) {
        if (current[i] === key) {
            found = true;
            if (allowed === true)
                result.push(current[i]);
        } else {
            result.push(current[i]);
        }
    }
    if (allowed === true && !found)
        result.push(key);
    return result;
}

function _stableStringify(value, depth) {
    var currentDepth = Number(depth) || 0;
    if (currentDepth > 32)
        throw new Error("Object nesting exceeds the supported depth.");
    if (value === undefined)
        return "null";
    if (value === null || typeof value !== "object")
        return JSON.stringify(value);
    if (Array.isArray(value)) {
        var parts = [];
        for (var i = 0; i < value.length; i++)
            parts.push(_stableStringify(value[i], currentDepth + 1));
        return "[" + parts.join(",") + "]";
    }

    var keys = Object.keys(value).sort();
    var fields = [];
    for (var j = 0; j < keys.length; j++) {
        var key = keys[j];
        if (value[key] === undefined)
            continue;
        fields.push(JSON.stringify(key) + ":" + _stableStringify(value[key], currentDepth + 1));
    }
    return "{" + fields.join(",") + "}";
}

/**
 * Return true when a semantic version is at least the required stable version.
 *
 * Prerelease builds are rejected because the bridge is a security boundary.
 *
 * @param {string} version - Installed semantic version.
 * @param {string} minimum - Minimum accepted semantic version.
 * @returns {boolean} Whether the installed version is accepted.
 */
function isVersionAtLeast(version, minimum) {
    var pattern = /^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$/;
    var current = pattern.exec(String(version || "").trim());
    var required = pattern.exec(String(minimum || "").trim());
    if (!current || !required || current[4])
        return false;

    for (var i = 1; i <= 3; i++) {
        var currentPart = Number(current[i]);
        var requiredPart = Number(required[i]);
        if (currentPart > requiredPart) return true;
        if (currentPart < requiredPart) return false;
    }
    return true;
}

/**
 * Return true when a stable semantic version is inside a half-open range.
 *
 * @param {string} version - Installed semantic version.
 * @param {string} minimum - Inclusive minimum accepted version.
 * @param {string} maximumExclusive - Exclusive maximum accepted version.
 * @returns {boolean} Whether the installed version is inside the range.
 */
function isVersionInRange(version, minimum, maximumExclusive) {
    return isVersionAtLeast(version, minimum)
        && !isVersionAtLeast(version, maximumExclusive);
}

/**
 * Parse the self-reported Node runtime used to launch the MCP bridge.
 *
 * The executable is captured during the probe so the checked runtime, rather
 * than a later PATH lookup, is used to start the security-sensitive process.
 *
 * @param {string} jsonText - JSON emitted by the Node runtime probe.
 * @returns {{ nodeVersion: string, undiciVersion: string, executable: string }} Checked runtime information.
 */
function extractNodeRuntimeInfo(jsonText) {
    var empty = { nodeVersion: "", undiciVersion: "", executable: "" };
    try {
        var value = JSON.parse(String(jsonText || ""));
        if (!value || typeof value !== "object" || Array.isArray(value))
            return empty;
        var node = typeof value.nodeVersion === "string"
            ? value.nodeVersion.trim() : "";
        var undici = typeof value.undiciVersion === "string"
            ? value.undiciVersion.trim() : "";
        var executable = typeof value.executable === "string"
            ? value.executable : "";
        if (!node || !undici || executable.charAt(0) !== "/"
                || /[\x00-\x1f\x7f]/.test(executable))
            return empty;
        return {
            nodeVersion: node,
            undiciVersion: undici,
            executable: executable
        };
    } catch (e) {
        return empty;
    }
}

function _hasOwn(object, key) {
    return Object.prototype.hasOwnProperty.call(object, key);
}

function _validServerRequestId(id) {
    if (typeof id === "string")
        return id.length > 0 && id.length <= 256;
    return typeof id === "number" && isFinite(id)
        && Math.floor(id) === id && Math.abs(id) <= 9007199254740991;
}

function _validClientResponseId(id) {
    return typeof id === "number" && isFinite(id)
        && Math.floor(id) === id && id >= 1 && id <= 9007199254740991;
}

/**
 * Strictly classify one parsed JSON-RPC 2.0 envelope.
 *
 * Client request identifiers are positive integers generated by Ephemera.
 * Server request identifiers may also be bounded strings, as allowed by the
 * protocol. Invalid response-like envelopes retain a safe numeric responseId
 * so their matching pending request can be rejected instead of left hanging.
 *
 * @param {*} message - Parsed JSON value.
 * @returns {{ kind: string, responseId: (number|null), reason: string }} Classification result.
 */
function classifyJsonRpcMessage(message) {
    var invalid = function(reason, responseId) {
        return {
            kind: "invalid",
            responseId: responseId === undefined ? null : responseId,
            reason: reason
        };
    };
    if (!message || typeof message !== "object" || Array.isArray(message))
        return invalid("JSON-RPC message must be an object.");
    if (message.jsonrpc !== "2.0")
        return invalid("Unsupported JSON-RPC version.");

    var hasMethod = _hasOwn(message, "method");
    var hasId = _hasOwn(message, "id");
    var hasResult = _hasOwn(message, "result");
    var hasError = _hasOwn(message, "error");

    if (hasMethod) {
        if (typeof message.method !== "string" || !message.method
                || message.method.length > 256)
            return invalid("JSON-RPC method must be a bounded non-empty string.");
        if (hasResult || hasError)
            return invalid("JSON-RPC requests must not contain response fields.");
        if (_hasOwn(message, "params")
                && (!message.params || typeof message.params !== "object"))
            return invalid("JSON-RPC params must be an object or array.");
        if (!hasId)
            return { kind: "notification", responseId: null, reason: "" };
        if (!_validServerRequestId(message.id))
            return invalid("JSON-RPC request id is invalid.");
        return { kind: "request", responseId: null, reason: "" };
    }

    var candidateId = hasId && _validClientResponseId(message.id)
        ? message.id : null;
    if (!hasId || candidateId === null)
        return invalid("JSON-RPC response id is invalid.", candidateId);
    if (_hasOwn(message, "params"))
        return invalid("JSON-RPC responses must not contain params.", candidateId);
    if (hasResult === hasError)
        return invalid("JSON-RPC response must contain exactly one of result or error.", candidateId);
    if (hasError) {
        var error = message.error;
        if (!error || typeof error !== "object" || Array.isArray(error)
                || typeof error.code !== "number" || !isFinite(error.code)
                || Math.floor(error.code) !== error.code
                || typeof error.message !== "string")
            return invalid("JSON-RPC error object is invalid.", candidateId);
    }
    return { kind: "response", responseId: candidateId, reason: "" };
}

/**
 * Extract one globally installed npm package version from `npm list --json`.
 *
 * @param {string} jsonText - npm list JSON output.
 * @param {string} packageName - Package name to inspect.
 * @returns {string} Installed version, or an empty string when unavailable.
 */
function extractNpmPackageVersion(jsonText, packageName) {
    return extractNpmPackageInfo(jsonText, packageName).version;
}

/**
 * Extract a checked npm package version and executable path from `npm list --long`.
 *
 * @param {string} jsonText - npm list JSON output.
 * @param {string} packageName - Package name to inspect.
 * @returns {{ version: string, executable: string, undiciVersion: string, openVersion: string }} Installed package information.
 */
function extractNpmPackageInfo(jsonText, packageName) {
    try {
        var data = JSON.parse(String(jsonText || ""));
        var dependencies = data && data.dependencies;
        var entry = dependencies && dependencies[String(packageName || "")];
        var version = entry && entry.version ? String(entry.version).trim() : "";
        var packagePath = entry && entry.path ? String(entry.path) : "";
        var bin = entry && entry.bin;
        var relativeBin = typeof bin === "string" ? bin : (bin && bin[String(packageName || "")]);
        relativeBin = String(relativeBin || "");
        var runtimeDependencies = entry && entry.dependencies;
        var undiciEntry = runtimeDependencies && runtimeDependencies.undici;
        var undiciVersion = undiciEntry && undiciEntry.version
            ? String(undiciEntry.version).trim() : "";
        var openEntry = runtimeDependencies && runtimeDependencies.open;
        var openVersion = openEntry && openEntry.version
            ? String(openEntry.version).trim() : "";
        if (!version || packagePath.charAt(0) !== "/" || relativeBin !== "dist/proxy.js")
            return { version: "", executable: "", undiciVersion: "", openVersion: "" };
        if (/[\x00-\x1f\x7f]/.test(packagePath))
            return { version: "", executable: "", undiciVersion: "", openVersion: "" };
        return {
            version: version,
            executable: packagePath + "/" + relativeBin,
            undiciVersion: undiciVersion,
            openVersion: openVersion
        };
    } catch (e) {
        return { version: "", executable: "", undiciVersion: "", openVersion: "" };
    }
}

/**
 * Reject MCP endpoint forms that would expose credentials through process argv.
 *
 * @param {string} url - Validated HTTP(S) MCP endpoint.
 * @returns {string} Empty when safe, otherwise a user-facing error.
 */
function mcpUrlSafetyError(url) {
    var value = String(url || "").trim();
    var authority = /^https?:\/\/([^/?#]+)/i.exec(value);
    if (!authority)
        return "MCP URL must use http:// or https://.";
    if (authority[1].indexOf("@") >= 0)
        return "MCP URL must not contain embedded credentials.";
    if (value.indexOf("?") >= 0 || value.indexOf("#") >= 0)
        return "MCP URL must not contain a query string or fragment because the bridge URL is visible to local processes.";
    return "";
}

/**
 * Return true for HTTP endpoints on the local loopback interface.
 *
 * @param {string} url - MCP endpoint URL.
 * @returns {boolean} Whether the endpoint is loopback HTTP.
 */
function isLoopbackHttpUrl(url) {
    var match = /^http:\/\/([^/:?#]+)(?::\d+)?(?:[/?#]|$)/i.exec(String(url || "").trim());
    if (!match) return false;
    var host = match[1].toLowerCase();
    if (host === "localhost")
        return true;

    var octets = host.split(".");
    if (octets.length !== 4 || octets[0] !== "127")
        return false;
    for (var i = 0; i < octets.length; i++) {
        if (!/^\d{1,3}$/.test(octets[i]) || Number(octets[i]) > 255)
            return false;
    }
    return true;
}

/**
 * Return true when a non-loopback HTTP endpoint needs explicit consent.
 *
 * @param {string} url - MCP endpoint URL.
 * @returns {boolean} Whether insecure transport consent is required.
 */
function requiresInsecureHttpConsent(url) {
    var value = String(url || "").trim();
    return /^http:\/\//i.test(value) && !isLoopbackHttpUrl(value);
}

/**
 * Return true when a tool contract can be represented safely by this client.
 *
 * @param {Object} tool - MCP tools/list entry.
 * @returns {boolean} Whether the tool is supported.
 */
function isSupportedTool(tool) {
    if (!tool || typeof tool !== "object" || Array.isArray(tool))
        return false;
    if (typeof tool.name !== "string")
        return false;
    var name = tool.name.trim();
    if (name !== tool.name || !/^[A-Za-z0-9_.-]{1,128}$/.test(name))
        return false;
    if (!tool.inputSchema || typeof tool.inputSchema !== "object" || Array.isArray(tool.inputSchema))
        return false;
    if (tool.inputSchema.type !== "object")
        return false;
    if (tool.title !== undefined
            && (typeof tool.title !== "string" || tool.title.length > 256))
        return false;
    if (tool.description !== undefined
            && (typeof tool.description !== "string" || tool.description.length > 4096))
        return false;
    if (tool.outputSchema !== undefined
            && (!tool.outputSchema || typeof tool.outputSchema !== "object" || Array.isArray(tool.outputSchema)))
        return false;
    if (tool.annotations !== undefined
            && (!tool.annotations || typeof tool.annotations !== "object" || Array.isArray(tool.annotations)))
        return false;
    if (tool.execution !== undefined
            && (!tool.execution || typeof tool.execution !== "object" || Array.isArray(tool.execution)))
        return false;
    if (tool.execution && tool.execution.taskSupport === "required")
        return false;
    return true;
}

/**
 * Find a tool by its exact, case-sensitive advertised name.
 *
 * Tool names are authorization identifiers, so callers must never normalize a
 * model-provided name for comparison and then execute the unnormalized value.
 *
 * @param {Array} tools - Current sanitized MCP tools.
 * @param {string} toolName - Exact tool name requested by the model.
 * @returns {Object|null} Matching tool contract, or null.
 */
function findTool(tools, toolName) {
    if (!Array.isArray(tools) || typeof toolName !== "string")
        return null;
    for (var i = 0; i < tools.length; i++) {
        if (tools[i] && tools[i].name === toolName)
            return tools[i];
    }
    return null;
}

/**
 * Filter invalid, unsupported, and duplicate tool contracts.
 *
 * @param {Array} tools - MCP tools/list entries.
 * @returns {Array} Supported tools with unique names.
 */
function sanitizeTools(tools) {
    if (!Array.isArray(tools)) return [];
    var seen = {};
    var result = [];
    for (var i = 0; i < tools.length; i++) {
        var tool = tools[i];
        if (!isSupportedTool(tool) || !toolFingerprint(tool)) continue;
        var name = tool.name;
        var seenKey = "$" + name;
        if (seen[seenKey]) continue;
        seen[seenKey] = true;
        result.push(tool);
    }
    return result;
}

/**
 * Build a stable fingerprint for a tool's executable contract.
 *
 * @param {Object} tool - MCP tools/list entry.
 * @returns {string} Stable serialized contract.
 */
function _executableToolContract(tool) {
    if (!tool || tool.name === undefined)
        return null;
    return {
        name: String(tool.name || ""),
        title: tool.title || "",
        description: tool.description || "",
        inputSchema: tool.inputSchema || {},
        outputSchema: tool.outputSchema || {},
        annotations: tool.annotations || {},
        execution: tool.execution || {}
    };
}

function toolFingerprint(tool) {
    if (!tool || tool.name === undefined)
        return "";
    var contract = _executableToolContract(tool);
    try {
        return _stableStringify(contract, 0);
    } catch (e) {
        return "";
    }
}

/**
 * Format the complete executable contract for explicit user review.
 *
 * @param {Object} tool - MCP tools/list entry.
 * @returns {string} Pretty JSON containing every approval-bound field.
 */
function formatToolContract(tool) {
    var contract = _executableToolContract(tool);
    if (!contract) return "{}";
    try {
        return formatReviewText(JSON.stringify(contract, null, 2));
    } catch (e) {
        return "{}";
    }
}

/**
 * Build the persisted approval key for a specific tool contract.
 *
 * @param {Object} tool - MCP tools/list entry.
 * @returns {string} Approval key containing tool name and schema fingerprint.
 */
function toolApprovalKey(tool) {
    var name = tool && typeof tool.name === "string" ? tool.name : "";
    if (!name) return "";
    var fingerprint = toolFingerprint(tool);
    if (!fingerprint) return "";
    return name + "\n" + fingerprint;
}

/**
 * Normalize persisted tool approval keys.
 *
 * @param {Array|string} approvals - Tool approval keys or a JSON-encoded array.
 * @returns {Array<string>} Unique approval keys.
 */
function normalizeToolApprovalKeys(approvals) {
    return _normalizeStringArray(approvals);
}

/**
 * Return true if a specific current tool contract is approved.
 *
 * @param {Object} tool - MCP tools/list entry.
 * @param {Array|string} approvals - Persisted approval keys.
 * @returns {boolean} Whether the exact tool contract is approved.
 */
function isToolApproved(tool, approvals) {
    var key = toolApprovalKey(tool);
    if (!key) return false;
    var normalized = normalizeToolApprovalKeys(approvals);
    for (var i = 0; i < normalized.length; i++) {
        if (normalized[i] === key)
            return true;
    }
    return false;
}

/**
 * Add or remove the current tool contract from persisted approvals.
 *
 * @param {Array|string} approvals - Current approval keys.
 * @param {Object} tool - MCP tools/list entry.
 * @param {boolean} allowed - Whether this exact contract should be approved.
 * @returns {Array<string>} Updated approval keys.
 */
function setToolApproved(approvals, tool, allowed) {
    return _setStringAllowed(approvals, toolApprovalKey(tool), allowed);
}

/**
 * Keep only approvals that still match currently advertised tool contracts.
 *
 * @param {Array|string} approvals - Current approval keys.
 * @param {Array} tools - MCP tools/list entries.
 * @returns {Array<string>} Pruned approval keys.
 */
function pruneApprovedTools(approvals, tools) {
    var approved = normalizeToolApprovalKeys(approvals);
    if (!Array.isArray(tools) || tools.length === 0)
        return [];

    var available = {};
    for (var i = 0; i < tools.length; i++) {
        var key = toolApprovalKey(tools[i]);
        if (key) available[key] = true;
    }

    var result = [];
    for (var j = 0; j < approved.length; j++) {
        if (available[approved[j]])
            result.push(approved[j]);
    }
    return result;
}

/**
 * Build the message list used to resume an Ollama chat after tool execution.
 *
 * @param {Array} conversationMessages - Messages already sent to the model.
 * @param {string} assistantContent - Assistant content from the tool-call turn.
 * @param {string} assistantThinking - Native Ollama thinking from the tool-call turn.
 * @param {Array} toolCalls - Tool calls requested by the model.
 * @param {Array} toolResults - Tool result messages.
 * @returns {Array} New message list with assistant tool call and tool results.
 */
function buildToolResumeMessages(conversationMessages, assistantContent, assistantThinking, toolCalls, toolResults) {
    var updated = Array.isArray(conversationMessages) ? conversationMessages.slice() : [];
    var assistantMessage = {
        role: "assistant",
        content: assistantContent || "",
        tool_calls: Array.isArray(toolCalls) ? toolCalls.slice() : []
    };
    if (assistantThinking && String(assistantThinking).length > 0)
        assistantMessage.thinking = String(assistantThinking);
    updated.push(assistantMessage);

    var results = Array.isArray(toolResults) ? toolResults : [];
    for (var i = 0; i < results.length; i++)
        updated.push(results[i]);
    return updated;
}

/**
 * Append one tools/list page to an accumulated tool array.
 *
 * @param {Array} existing - Previously collected tools.
 * @param {Object} result - MCP tools/list result.
 * @returns {{ tools: Array, nextCursor: string }}
 */
function appendToolsPage(existing, result) {
    var merged = Array.isArray(existing) ? existing.slice() : [];
    var page = (result && Array.isArray(result.tools)) ? result.tools : [];
    for (var i = 0; i < page.length; i++)
        merged.push(page[i]);
    var next = (result && result.nextCursor !== undefined && result.nextCursor !== null)
        ? String(result.nextCursor)
        : "";
    return { tools: merged, nextCursor: next };
}

/**
 * Convert an MCP tools/call result into compact text suitable for a chat model.
 *
 * @param {Object|string} result - MCP tool result payload.
 * @returns {string} Text representation of the result.
 */
function formatToolResult(result) {
    if (result === undefined || result === null)
        return "";
    if (typeof result === "string")
        return result;

    var parts = [];
    if (Array.isArray(result.content)) {
        for (var i = 0; i < result.content.length; i++) {
            var item = result.content[i];
            if (!item) continue;
            if (item.type === "text" && item.text !== undefined) {
                parts.push(String(item.text));
            } else if (item.type === "resource" && item.resource) {
                if (item.resource.text !== undefined)
                    parts.push(String(item.resource.text));
                else
                    parts.push("[resource: " + (item.resource.uri || item.resource.mimeType || "embedded") + "]");
            } else if (item.type === "resource_link") {
                parts.push("[resource: " + (item.name || item.uri || "link") + "]");
            } else if (item.type === "image") {
                parts.push("[image: " + (item.mimeType || "image") + "]");
            } else if (item.type === "audio") {
                parts.push("[audio: " + (item.mimeType || "audio") + "]");
            } else {
                parts.push(JSON.stringify(item));
            }
        }
    }

    if (result.structuredContent !== undefined)
        parts.push(JSON.stringify(result.structuredContent));

    if (parts.length > 0)
        return parts.join("\n");

    return JSON.stringify(result);
}

/**
 * Return true when a successful JSON-RPC tools/call response reports tool-level
 * failure through the MCP result's isError flag.
 *
 * @param {Object} result - MCP tool result payload.
 * @returns {boolean}
 */
function isToolError(result) {
    return !!(result && result.isError === true);
}

/**
 * Normalize tool-call arguments from provider-specific payload shapes.
 *
 * @param {Object|string} args - Tool arguments from a model tool call.
 * @returns {{ valid: boolean, value: Object, error: string }} Validation result.
 */
function parseToolArguments(args) {
    if (typeof args === "string") {
        try {
            var parsed = JSON.parse(args);
            if (parsed && typeof parsed === "object" && !Array.isArray(parsed))
                return { valid: true, value: parsed, error: "" };
            return { valid: false, value: {}, error: "Tool arguments must be a JSON object." };
        } catch (e) {
            return { valid: false, value: {}, error: "Tool arguments contain invalid JSON." };
        }
    }
    if (args && typeof args === "object" && !Array.isArray(args))
        return { valid: true, value: args, error: "" };
    if (args === undefined || args === null)
        return { valid: true, value: {}, error: "" };
    return { valid: false, value: {}, error: "Tool arguments must be an object." };
}

/**
 * Validate and normalize one provider tool-call envelope without changing its name.
 *
 * @param {Object} toolCall - Provider tool-call payload.
 * @returns {{ valid: boolean, name: string, arguments: Object|string, error: string }} Parsed call.
 */
function parseToolCall(toolCall) {
    if (!toolCall || typeof toolCall !== "object" || Array.isArray(toolCall))
        return { valid: false, name: "", arguments: {}, error: "Tool call must be an object." };
    var fn = toolCall.function && typeof toolCall.function === "object"
        && !Array.isArray(toolCall.function) ? toolCall.function : toolCall;
    var name = fn.name;
    if (typeof name !== "string" || name !== name.trim()
            || !/^[A-Za-z0-9_.-]{1,128}$/.test(name)) {
        return { valid: false, name: "", arguments: {}, error: "Tool call has an invalid name." };
    }
    return {
        valid: true,
        name: name,
        arguments: fn.arguments,
        error: ""
    };
}

// Keep this Unicode 17 Default_Ignorable_Code_Point predicate aligned with
// Providers.js. The extra line/interlinear controls are unsafe in review text.
function _isUnsafeReviewCodePoint(codePoint) {
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

function _reviewEscape(codePoint) {
    var hex = codePoint.toString(16);
    if (codePoint > 0xffff)
        return "\\u{" + hex + "}";
    while (hex.length < 4) hex = "0" + hex;
    return "\\u" + hex;
}

function _escapeReviewControls(text) {
    var value = text === undefined || text === null ? "" : String(text);
    var result = "";
    for (var i = 0; i < value.length; i++) {
        var first = value.charCodeAt(i);
        var codePoint = first;
        var width = 1;
        var unpairedSurrogate = false;
        if (first >= 0xd800 && first <= 0xdbff) {
            if (i + 1 < value.length) {
                var second = value.charCodeAt(i + 1);
                if (second >= 0xdc00 && second <= 0xdfff) {
                    codePoint = 0x10000 + ((first - 0xd800) * 0x400)
                        + (second - 0xdc00);
                    width = 2;
                } else {
                    unpairedSurrogate = true;
                }
            } else {
                unpairedSurrogate = true;
            }
        } else if (first >= 0xdc00 && first <= 0xdfff) {
            unpairedSurrogate = true;
        }

        var unsafeControl = (codePoint <= 0x08)
            || (codePoint >= 0x0b && codePoint <= 0x0c)
            || (codePoint >= 0x0e && codePoint <= 0x1f)
            || (codePoint >= 0x7f && codePoint <= 0x9f);
        if (unpairedSurrogate || unsafeControl || _isUnsafeReviewCodePoint(codePoint))
            result += _reviewEscape(codePoint);
        else
            result += value.substr(i, width);
        i += width - 1;
    }
    return result;
}

/**
 * Escape invisible and bidirectional controls in untrusted review text.
 *
 * @param {*} value - Server- or model-provided value shown in an approval UI.
 * @returns {string} Review-safe plain text.
 */
function formatReviewText(value) {
    return _escapeReviewControls(value);
}

/**
 * Format tool arguments for a compact user approval prompt.
 *
 * @param {Object|string} args - Tool arguments.
 * @param {number} maxChars - Maximum characters before truncation.
 * @returns {string} Pretty JSON/string preview.
 */
function formatToolArguments(args, maxChars) {
    var text = "";
    if (args === undefined || args === null) {
        text = "{}";
    } else if (typeof args === "string") {
        text = args;
    } else {
        try {
            text = JSON.stringify(args, null, 2);
        } catch (e) {
            text = String(args);
        }
    }

    var limit = Number(maxChars) || 0;
    if (limit > 0 && text.length > limit)
        return formatReviewText(text.substring(0, limit) + "\n\n[Arguments truncated]");
    return formatReviewText(text || "{}");
}
