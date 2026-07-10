.pragma library

// Pure SSE stream parsing functions for Ephemera.
// These functions take state as input and return updates — no side effects.

/**
 * Split raw SSE data into complete lines and a remaining buffer.
 *
 * Combines the previous buffer with the new chunk, splits on newlines (LF or CRLF),
 * and returns complete lines plus any trailing incomplete line as the new buffer.
 * Empty/whitespace-only lines are discarded.
 *
 * @param {string} chunk - New data received from the stream.
 * @param {string} buffer - Incomplete line carried over from the previous call.
 * @returns {{ lines: string[], buffer: string }}
 */
function splitLines(chunk, buffer) {
    var combined = buffer + chunk;
    var parts = combined.split(/\r?\n/);

    var remaining = "";
    if (combined.length > 0 && !combined.endsWith("\n") && !combined.endsWith("\r")) {
        remaining = parts.pop();
    }

    var lines = [];
    for (var i = 0; i < parts.length; i++) {
        var line = parts[i].trim();
        if (line) lines.push(line);
    }

    return { lines: lines, buffer: remaining };
}

/**
 * Parse a single SSE JSON payload into content/thinking deltas.
 *
 * Handles four provider formats:
 * - Anthropic: content_block_delta with thinking_delta or text_delta types.
 * - Gemini: candidates[].content.parts[].text (supports array or single object).
 * - Ollama: native message.content/tool_calls and OpenAI-compatible choices[].delta.
 * - OpenAI/Custom: choices[0].delta.content and .reasoning_content/.reasoning.
 *
 * Also extracts token usage from provider-specific fields when available:
 * - Anthropic: usage.output_tokens from message_delta events.
 * - Gemini: usageMetadata.candidatesTokenCount from any chunk.
 * - Ollama: eval_count from native final chunks or usage.completion_tokens from OpenAI-compatible final chunks.
 * - OpenAI: usage.completion_tokens from the final chunk.
 *
 * @param {string} jsonText - Raw JSON string (after stripping "data:" prefix if present).
 * @param {string} provider - Provider identifier ("anthropic"|"gemini"|"ollama"|"openai"|"custom").
 * @returns {{ content: string, thinking: string, done: boolean, outputTokens: number, toolCalls: Array|false }}
 *   content: assistant text delta (empty string if none).
 *   thinking: reasoning/thinking delta (empty string if none).
 *   done: true if the provider signaled stream completion.
 *   outputTokens: completion token count from API (0 if not present in this event).
 *   toolCalls: provider tool call requests, or false if this chunk has none.
 */
function parseDelta(jsonText, provider) {
    var result = { content: "", thinking: "", done: false, outputTokens: 0, toolCalls: false };
    try {
        var data = JSON.parse(jsonText);
        if (provider === "anthropic") {
            if (data.type === "content_block_delta" && data.delta) {
                if (data.delta.type === "thinking_delta" && data.delta.thinking)
                    result.thinking = data.delta.thinking;
                else if (data.delta.type === "text_delta" && data.delta.text)
                    result.content = data.delta.text;
            }
            if (data.type === "message_delta" && data.delta && data.delta.stop_reason)
                result.done = true;
            // Anthropic sends usage.output_tokens on message_delta
            if (data.type === "message_delta" && data.usage && data.usage.output_tokens > 0)
                result.outputTokens = data.usage.output_tokens;
        } else if (provider === "gemini") {
            var chunks = Array.isArray(data) ? data : [data];
            for (var ci = 0; ci < chunks.length; ci++) {
                if (!chunks[ci]) continue;
                var candidates = chunks[ci].candidates;
                if (!Array.isArray(candidates) || !candidates[0]) continue;
                var content = candidates[0].content;
                if (!content || !Array.isArray(content.parts)) continue;
                var cparts = content.parts;
                for (var pi = 0; pi < cparts.length; pi++) {
                    if (cparts[pi] && cparts[pi].text)
                        result.content += cparts[pi].text;
                }
                // Gemini includes usageMetadata with token counts
                var meta = chunks[ci].usageMetadata;
                if (meta && meta.candidatesTokenCount > 0)
                    result.outputTokens = meta.candidatesTokenCount;
            }
        } else if (provider === "ollama") {
            if (data.message) {
                result.content = typeof data.message.content === "string" ? data.message.content : "";
                result.thinking = data.message.thinking || "";
                if (Array.isArray(data.message.tool_calls) && data.message.tool_calls.length > 0)
                    result.toolCalls = data.message.tool_calls;
                if (data.done)
                    result.done = true;
                if (data.eval_count > 0)
                    result.outputTokens = data.eval_count;
            } else {
                var ochoices = data.choices;
                if (ochoices && ochoices[0] && ochoices[0].delta) {
                    var od = ochoices[0].delta;
                    result.thinking = od.reasoning_content || od.reasoning || "";
                    result.content = od.content || "";
                    if (Array.isArray(od.tool_calls) && od.tool_calls.length > 0)
                        result.toolCalls = od.tool_calls;
                }
                if (ochoices && ochoices[0] && ochoices[0].finish_reason)
                    result.done = true;
                if (data.usage && data.usage.completion_tokens > 0)
                    result.outputTokens = data.usage.completion_tokens;
            }
        } else {
            // OpenAI / OpenAI-compatible
            var choices = data.choices;
            if (choices && choices[0] && choices[0].delta) {
                var d = choices[0].delta;
                result.thinking = d.reasoning_content || d.reasoning || "";
                result.content = d.content || "";
            }
            if (choices && choices[0] && choices[0].finish_reason)
                result.done = true;
            // OpenAI sends usage in the final chunk
            if (data.usage && data.usage.completion_tokens > 0)
                result.outputTokens = data.usage.completion_tokens;
        }
    } catch (e) {
        console.warn("Ephemera: StreamParser.parseDelta parse error for", provider + ":", e);
    }
    return result;
}

/**
 * Route streaming text through <think>/</think> tag detection.
 *
 * Processes a delta chunk against the current tag-parsing state to separate
 * thinking content (inside <think> tags) from regular content. Handles partial
 * tags that span chunk boundaries by buffering candidate bytes.
 *
 * State machine: starts outside think tags. When <think> is found, subsequent
 * text routes to thinkingParts until </think> closes it. A leading newline
 * after a tag is consumed (stripped) to avoid blank lines in output.
 *
 * @param {string} delta - New text chunk from the SSE stream.
 * @param {string} tagBuffer - Buffered partial tag from previous call.
 * @param {boolean} insideThinkTag - Whether the parser is currently inside a <think> block.
 * @returns {{ contentParts: string[], thinkingParts: string[], tagBuffer: string, insideThinkTag: boolean }}
 *   contentParts/thinkingParts: text fragments to append to content/thinking buffers.
 *   tagBuffer: partial tag carried forward (empty if no partial match).
 *   insideThinkTag: updated state for next call.
 */
function routeThinkTags(delta, tagBuffer, insideThinkTag) {
    var result = { contentParts: [], thinkingParts: [], tagBuffer: "", insideThinkTag: insideThinkTag };
    var text = tagBuffer + delta;

    while (text.length > 0) {
        var tag = result.insideThinkTag ? "</think" + ">" : "<think" + ">";
        var idx = text.indexOf(tag);

        if (idx >= 0) {
            var before = text.substring(0, idx);
            if (before.length > 0) {
                if (result.insideThinkTag)
                    result.thinkingParts.push(before);
                else
                    result.contentParts.push(before);
            }
            result.insideThinkTag = !result.insideThinkTag;
            text = text.substring(idx + tag.length);
            if (text.startsWith("\n")) text = text.substring(1);
        } else {
            // Check for partial tag at end of buffer
            var partialLen = 0;
            for (var len = Math.min(text.length, tag.length - 1); len > 0; len--) {
                if (text.substring(text.length - len) === tag.substring(0, len)) {
                    partialLen = len;
                    break;
                }
            }

            if (partialLen > 0) {
                result.tagBuffer = text.substring(text.length - partialLen);
                var output = text.substring(0, text.length - partialLen);
                if (output.length > 0) {
                    if (result.insideThinkTag)
                        result.thinkingParts.push(output);
                    else
                        result.contentParts.push(output);
                }
            } else {
                if (result.insideThinkTag)
                    result.thinkingParts.push(text);
                else
                    result.contentParts.push(text);
            }
            text = "";
        }
    }

    return result;
}

/**
 * Parse a non-streaming response body for all provider formats.
 *
 * Used as a fallback when no streaming deltas were received but the HTTP
 * response was successful. Handles Anthropic (content[].text), Gemini
 * (candidates[].content.parts[].text), Ollama native/OpenAI-compatible, and
 * OpenAI/Custom (choices[].message.content).
 *
 * @param {string} bodyText - Raw response body (JSON string).
 * @param {string} provider - Provider identifier.
 * @returns {string} Assistant text content, or "" on failure/missing data.
 */
function extractNonStreamingText(bodyText, provider) {
    try {
        var data = JSON.parse(bodyText);
        if (provider === "anthropic") {
            var content = data.content;
            if (Array.isArray(content)) {
                var out = "";
                for (var i = 0; i < content.length; i++) {
                    if (content[i] && content[i].text)
                        out += content[i].text;
                }
                return out;
            }
            return data.text || "";
        }
        if (provider === "gemini") {
            var gchunks = Array.isArray(data) ? data : [data];
            var gout = "";
            for (var gi = 0; gi < gchunks.length; gi++) {
                if (!gchunks[gi]) continue;
                var cands = gchunks[gi].candidates;
                if (!Array.isArray(cands) || !cands[0]) continue;
                var gcontent = cands[0].content;
                if (!gcontent || !Array.isArray(gcontent.parts)) continue;
                var gparts = gcontent.parts;
                for (var gpi = 0; gpi < gparts.length; gpi++) {
                    if (gparts[gpi] && gparts[gpi].text) gout += gparts[gpi].text;
                }
            }
            return gout;
        }
        if (provider === "ollama") {
            if (data.message && typeof data.message.content === "string")
                return data.message.content;
        }
        // OpenAI / OpenAI-compatible
        var choices = data.choices;
        if (choices && choices[0]) {
            if (choices[0].message && typeof choices[0].message.content === "string")
                return choices[0].message.content;
            if (typeof choices[0].text === "string")
                return choices[0].text;
        }
    } catch (e) {
        console.warn("Ephemera: StreamParser.extractNonStreamingText parse error for", provider + ":", e);
    }
    return "";
}

/**
 * Extract HTTP status from EPH_STATUS marker appended by curl's -w flag.
 *
 * The curl command is configured with -w "\\nEPH_STATUS:%{http_code}\\n" to
 * append the status code after the response body. This function parses that
 * marker and returns the status plus the body text with the marker stripped.
 *
 * @param {string} text - Full curl stdout output (body + status marker).
 * @returns {{ status: number, body: string }} status: HTTP code (0 if no marker). body: response without marker.
 */
function extractHttpStatus(text) {
    var match = (text || "").match(/EPH_STATUS:(\d+)/);
    var status = match ? parseInt(match[1]) : 0;
    var body = text || "";
    var markerIdx = body.lastIndexOf("\nEPH_STATUS:");
    if (markerIdx >= 0) body = body.substring(0, markerIdx);
    return { status: status, body: body.trim() };
}
