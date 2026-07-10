#!/usr/bin/env node
// Comprehensive test suite for Ephemera's pure JS modules.
// Run: node tests/run_tests.js

var fs = require("fs");
var path = require("path");

// ─── Test framework ─────────────────────────────────────────────

var passed = 0;
var failed = 0;
var currentSection = "";

function section(name) {
    currentSection = name;
    console.log("\n=== " + name + " ===");
}

function assert(condition, message) {
    if (condition) {
        passed++;
        console.log("  PASS: " + message);
    } else {
        failed++;
        console.log("  FAIL: " + message);
    }
}

function assertEqual(actual, expected, message) {
    if (actual === expected) {
        passed++;
        console.log("  PASS: " + message);
    } else {
        failed++;
        console.log("  FAIL: " + message);
        console.log("    expected: " + JSON.stringify(expected));
        console.log("    actual:   " + JSON.stringify(actual));
    }
}

function assertDeepEqual(actual, expected, message) {
    var a = JSON.stringify(actual);
    var b = JSON.stringify(expected);
    if (a === b) {
        passed++;
        console.log("  PASS: " + message);
    } else {
        failed++;
        console.log("  FAIL: " + message);
        console.log("    expected: " + b);
        console.log("    actual:   " + a);
    }
}

// ─── Load modules ───────────────────────────────────────────────
// .pragma library modules use a QML-specific engine. We load the source,
// strip the directive, and evaluate the exported functions.

function loadPragmaLib(filename) {
    var src = fs.readFileSync(path.join(__dirname, "..", filename), "utf8");
    src = src.replace(/^\.pragma library\s*/, "");
    // Also strip console.warn calls since they reference QML context
    src = src.replace(/console\.warn\([^)]*\);?/g, "");
    var mod = {};
    var funcNames = (src.match(/^function\s+(\w+)/gm) || []).map(function(m) { return m.replace("function ", ""); });
    // Also export var declarations (like registry)
    var varNames = (src.match(/^var\s+(\w+)/gm) || []).map(function(m) { return m.replace("var ", ""); });
    var exports = funcNames.concat(varNames);
    var fn = new Function("module", "exports", src + "\nmodule.exports = { " + exports.join(", ") + " };");
    fn(mod, mod.exports);
    return mod.exports;
}

var StreamParser = loadPragmaLib("src/lib/StreamParser.js");
var Providers = loadPragmaLib("src/lib/Providers.js");
var Markdown = loadPragmaLib("src/lib/Markdown.js");
var ChatExport = loadPragmaLib("src/lib/ChatExport.js");
var Mcp = loadPragmaLib("src/lib/Mcp.js");
var McpSchema = loadPragmaLib("src/lib/McpSchema.js");
var VariantStore = loadPragmaLib("src/lib/VariantStore.js");
var ErrorHints = loadPragmaLib("src/lib/ErrorHints.js");

// ═════════════════════════════════════════════════════════════════
//  StreamParser tests
// ═════════════════════════════════════════════════════════════════

section("StreamParser.splitLines");
(function() {
    var r = StreamParser.splitLines("data: hello\ndata: world\n", "");
    assertEqual(r.lines.length, 2, "splits two complete lines");
    assertEqual(r.buffer, "", "no remaining buffer");

    r = StreamParser.splitLines("data: partial", "");
    assertEqual(r.lines.length, 0, "incomplete line stays in buffer");
    assertEqual(r.buffer, "data: partial", "buffer contains partial line");

    r = StreamParser.splitLines(" rest\n", "data:");
    assertEqual(r.lines.length, 1, "combines buffer with new data");
    assertEqual(r.lines[0], "data: rest", "correct combined line");

    r = StreamParser.splitLines("data: [DONE]\n", "");
    assertEqual(r.lines[0], "data: [DONE]", "handles [DONE] marker");

    r = StreamParser.splitLines("", "");
    assertEqual(r.lines.length, 0, "empty input produces no lines");
    assertEqual(r.buffer, "", "empty input produces empty buffer");

    r = StreamParser.splitLines("data: a\r\ndata: b\r\n", "");
    assertEqual(r.lines.length, 2, "handles \\r\\n line endings");
    assertEqual(r.lines[0], "data: a", "correct first line with CRLF");

    r = StreamParser.splitLines("\n\n\n", "");
    assertEqual(r.lines.length, 0, "blank lines are filtered");

    r = StreamParser.splitLines("data: chunk1", "");
    assertEqual(r.buffer, "data: chunk1", "no newline keeps data in buffer");
    var r2 = StreamParser.splitLines(" chunk2\n", r.buffer);
    assertEqual(r2.lines[0], "data: chunk1 chunk2", "multi-chunk assembly");
})();

section("StreamParser.parseDelta — OpenAI/Ollama");
(function() {
    var json = JSON.stringify({
        choices: [{ delta: { content: "hello" }, finish_reason: null }]
    });
    var r = StreamParser.parseDelta(json, "openai");
    assertEqual(r.content, "hello", "extracts content from OpenAI delta");
    assertEqual(r.thinking, "", "no thinking in standard delta");
    assertEqual(r.done, false, "not done without finish_reason");

    json = JSON.stringify({
        choices: [{ delta: {}, finish_reason: "stop" }]
    });
    r = StreamParser.parseDelta(json, "openai");
    assertEqual(r.done, true, "done when finish_reason is set");

    json = JSON.stringify({
        choices: [{ delta: { reasoning_content: "let me think..." } }]
    });
    r = StreamParser.parseDelta(json, "openai");
    assertEqual(r.thinking, "let me think...", "extracts reasoning_content");

    json = JSON.stringify({
        choices: [{ delta: { reasoning: "deep thought" } }]
    });
    r = StreamParser.parseDelta(json, "openai");
    assertEqual(r.thinking, "deep thought", "extracts reasoning field");

    r = StreamParser.parseDelta("not json at all", "openai");
    assertEqual(r.content, "", "gracefully handles invalid JSON");
    assertEqual(r.done, false, "not done on parse error");

    json = JSON.stringify({ choices: null });
    r = StreamParser.parseDelta(json, "openai");
    assertEqual(r.content, "", "handles null choices");

    json = JSON.stringify({ choices: [{}] });
    r = StreamParser.parseDelta(json, "openai");
    assertEqual(r.content, "", "handles missing delta");

    json = JSON.stringify({
        choices: [{ delta: { content: "text", reasoning_content: "thought" }, finish_reason: null }]
    });
    r = StreamParser.parseDelta(json, "openai");
    assertEqual(r.content, "text", "content with reasoning");
    assertEqual(r.thinking, "thought", "thinking alongside content");
})();

section("StreamParser.parseDelta — Anthropic");
(function() {
    var json = JSON.stringify({
        type: "content_block_delta",
        delta: { type: "text_delta", text: "hello" }
    });
    var r = StreamParser.parseDelta(json, "anthropic");
    assertEqual(r.content, "hello", "extracts text_delta");
    assertEqual(r.thinking, "", "no thinking in text delta");

    json = JSON.stringify({
        type: "content_block_delta",
        delta: { type: "thinking_delta", thinking: "reasoning..." }
    });
    r = StreamParser.parseDelta(json, "anthropic");
    assertEqual(r.thinking, "reasoning...", "extracts thinking_delta");
    assertEqual(r.content, "", "no content in thinking delta");

    json = JSON.stringify({
        type: "message_delta",
        delta: { stop_reason: "end_turn" }
    });
    r = StreamParser.parseDelta(json, "anthropic");
    assertEqual(r.done, true, "done on message_delta stop_reason");

    json = JSON.stringify({
        type: "content_block_start",
        content_block: { type: "text", text: "" }
    });
    r = StreamParser.parseDelta(json, "anthropic");
    assertEqual(r.content, "", "ignores content_block_start");
    assertEqual(r.done, false, "not done on block start");

    json = JSON.stringify({
        type: "message_delta",
        delta: {}
    });
    r = StreamParser.parseDelta(json, "anthropic");
    assertEqual(r.done, false, "not done without stop_reason");
})();

section("StreamParser.parseDelta — Gemini");
(function() {
    var json = JSON.stringify({
        candidates: [{ content: { parts: [{ text: "gemini says" }] } }]
    });
    var r = StreamParser.parseDelta(json, "gemini");
    assertEqual(r.content, "gemini says", "extracts Gemini text");

    json = JSON.stringify({
        candidates: [{ content: { parts: [{ text: "part1" }, { text: "part2" }] } }]
    });
    r = StreamParser.parseDelta(json, "gemini");
    assertEqual(r.content, "part1part2", "concatenates multiple parts");

    json = JSON.stringify([
        { candidates: [{ content: { parts: [{ text: "a" }] } }] },
        { candidates: [{ content: { parts: [{ text: "b" }] } }] }
    ]);
    r = StreamParser.parseDelta(json, "gemini");
    assertEqual(r.content, "ab", "handles array of chunks");

    json = JSON.stringify({ candidates: [] });
    r = StreamParser.parseDelta(json, "gemini");
    assertEqual(r.content, "", "handles empty candidates");

    json = JSON.stringify({ candidates: [{ content: null }] });
    r = StreamParser.parseDelta(json, "gemini");
    assertEqual(r.content, "", "handles null content");

    json = JSON.stringify({ candidates: [{ content: { parts: [{}] } }] });
    r = StreamParser.parseDelta(json, "gemini");
    assertEqual(r.content, "", "handles parts without text");
})();

section("StreamParser.parseDelta — outputTokens");
(function() {
    // OpenAI: usage.completion_tokens in final chunk
    var json = JSON.stringify({
        choices: [{ delta: {}, finish_reason: "stop" }],
        usage: { prompt_tokens: 50, completion_tokens: 120, total_tokens: 170 }
    });
    var r = StreamParser.parseDelta(json, "openai");
    assertEqual(r.outputTokens, 120, "extracts OpenAI completion_tokens");
    assertEqual(r.done, true, "done alongside usage");

    // OpenAI: no usage in normal delta
    json = JSON.stringify({
        choices: [{ delta: { content: "hi" } }]
    });
    r = StreamParser.parseDelta(json, "openai");
    assertEqual(r.outputTokens, 0, "no outputTokens in normal OpenAI delta");

    // Ollama OpenAI-compatible: usage in final chunk
    json = JSON.stringify({
        choices: [{ delta: {}, finish_reason: "stop" }],
        usage: { completion_tokens: 85 }
    });
    r = StreamParser.parseDelta(json, "ollama");
    assertEqual(r.outputTokens, 85, "extracts Ollama OpenAI-compatible completion_tokens");

    // Ollama native: eval_count in final chunk
    json = JSON.stringify({
        model: "gemma4",
        message: { role: "assistant", content: "" },
        done: true,
        eval_count: 85
    });
    r = StreamParser.parseDelta(json, "ollama");
    assertEqual(r.outputTokens, 85, "extracts Ollama eval_count");

    // Anthropic: usage.output_tokens on message_delta
    json = JSON.stringify({
        type: "message_delta",
        delta: { stop_reason: "end_turn" },
        usage: { output_tokens: 200 }
    });
    r = StreamParser.parseDelta(json, "anthropic");
    assertEqual(r.outputTokens, 200, "extracts Anthropic output_tokens");
    assertEqual(r.done, true, "done alongside Anthropic usage");

    // Anthropic: no usage on content_block_delta
    json = JSON.stringify({
        type: "content_block_delta",
        delta: { type: "text_delta", text: "hi" }
    });
    r = StreamParser.parseDelta(json, "anthropic");
    assertEqual(r.outputTokens, 0, "no outputTokens in Anthropic content delta");

    // Gemini: usageMetadata.candidatesTokenCount
    json = JSON.stringify({
        candidates: [{ content: { parts: [{ text: "done" }] } }],
        usageMetadata: { promptTokenCount: 30, candidatesTokenCount: 450, totalTokenCount: 480 }
    });
    r = StreamParser.parseDelta(json, "gemini");
    assertEqual(r.outputTokens, 450, "extracts Gemini candidatesTokenCount");
    assertEqual(r.content, "done", "content alongside Gemini usage");

    // Gemini: no usageMetadata
    json = JSON.stringify({
        candidates: [{ content: { parts: [{ text: "mid" }] } }]
    });
    r = StreamParser.parseDelta(json, "gemini");
    assertEqual(r.outputTokens, 0, "no outputTokens when Gemini has no usageMetadata");

    // Default: outputTokens is 0 on parse error
    r = StreamParser.parseDelta("not json", "openai");
    assertEqual(r.outputTokens, 0, "outputTokens is 0 on parse error");
})();

section("StreamParser.routeThinkTags");
(function() {
    var r = StreamParser.routeThinkTags("hello world", "", false);
    assertDeepEqual(r.contentParts, ["hello world"], "plain text goes to content");
    assertDeepEqual(r.thinkingParts, [], "no thinking");
    assertEqual(r.insideThinkTag, false, "not inside tag");

    r = StreamParser.routeThinkTags("<think>thinking here</think>normal", "", false);
    assertEqual(r.thinkingParts.join(""), "thinking here", "text inside think tags");
    assertEqual(r.contentParts.join(""), "normal", "text after close tag");
    assertEqual(r.insideThinkTag, false, "not inside after close");

    r = StreamParser.routeThinkTags("<think>partial", "", false);
    assertEqual(r.insideThinkTag, true, "inside think tag when not closed");
    assertEqual(r.thinkingParts.join(""), "partial", "partial thinking captured");

    r = StreamParser.routeThinkTags("more</think>done", "", true);
    assertEqual(r.thinkingParts.join(""), "more", "continues thinking from state");
    assertEqual(r.contentParts.join(""), "done", "content after close tag");

    // Partial tag at boundary
    r = StreamParser.routeThinkTags("hello<thi", "", false);
    assertEqual(r.tagBuffer, "<thi", "partial tag buffered");
    assertEqual(r.contentParts.join(""), "hello", "content before partial tag");

    // Resume with rest of tag
    r = StreamParser.routeThinkTags("nk>inside", r.tagBuffer, r.insideThinkTag);
    assertEqual(r.insideThinkTag, true, "entered think tag from resumed buffer");
    assertEqual(r.thinkingParts.join(""), "inside", "thinking after resumed tag");

    // Newline after opening tag stripped
    r = StreamParser.routeThinkTags("<think>\nthinking", "", false);
    assertEqual(r.thinkingParts.join(""), "thinking", "leading newline after <think> stripped");

    // Newline after closing tag stripped
    r = StreamParser.routeThinkTags("thought</think>\ncontent", "", true);
    assertEqual(r.thinkingParts.join(""), "thought", "thinking before close");
    assertEqual(r.contentParts.join(""), "content", "leading newline after </think> stripped");

    // Empty think tags
    r = StreamParser.routeThinkTags("<think></think>content", "", false);
    assertEqual(r.contentParts.join(""), "content", "empty think tags produce no thinking");
    assertDeepEqual(r.thinkingParts, [], "no thinking parts from empty tags");

    // Multiple think blocks
    r = StreamParser.routeThinkTags("<think>a</think>b<think>c</think>d", "", false);
    assertEqual(r.thinkingParts.join(""), "ac", "multiple think blocks concatenated");
    assertEqual(r.contentParts.join(""), "bd", "content between think blocks");

    // Partial closing tag at boundary
    r = StreamParser.routeThinkTags("thinking</thi", "", true);
    assertEqual(r.tagBuffer, "</thi", "partial close tag buffered");
    assertEqual(r.thinkingParts.join(""), "thinking", "thinking before partial close tag");

    // Empty input
    r = StreamParser.routeThinkTags("", "", false);
    assertDeepEqual(r.contentParts, [], "empty input produces no content");
    assertDeepEqual(r.thinkingParts, [], "empty input produces no thinking");
})();

section("StreamParser.extractHttpStatus");
(function() {
    var r = StreamParser.extractHttpStatus("some body text\nEPH_STATUS:200\n");
    assertEqual(r.status, 200, "extracts 200 status");
    assertEqual(r.body, "some body text", "extracts body before marker");

    r = StreamParser.extractHttpStatus("error response\nEPH_STATUS:401\n");
    assertEqual(r.status, 401, "extracts 401 status");

    r = StreamParser.extractHttpStatus("no status marker here");
    assertEqual(r.status, 0, "returns 0 when no marker");
    assertEqual(r.body, "no status marker here", "returns full text as body");

    r = StreamParser.extractHttpStatus("");
    assertEqual(r.status, 0, "handles empty string");
    assertEqual(r.body, "", "empty body from empty string");

    r = StreamParser.extractHttpStatus(null);
    assertEqual(r.status, 0, "handles null input");

    r = StreamParser.extractHttpStatus(undefined);
    assertEqual(r.status, 0, "handles undefined input");

    r = StreamParser.extractHttpStatus("line1\nline2\nEPH_STATUS:500\n");
    assertEqual(r.status, 500, "extracts status from multiline");
    assert(r.body.indexOf("line1") >= 0, "body contains first line");
    assert(r.body.indexOf("line2") >= 0, "body contains second line");
})();

section("StreamParser.parseDelta — Ollama native /api/chat");
(function() {
    // Normal content chunk
    var json = JSON.stringify({
        model: "gemma4",
        message: { role: "assistant", content: "Hello" },
        done: false
    });
    var r = StreamParser.parseDelta(json, "ollama");
    assertEqual(r.content, "Hello", "extracts Ollama native content");
    assertEqual(r.done, false, "not done on normal chunk");
    assertEqual(r.toolCalls, false, "no tool calls on normal chunk");

    json = JSON.stringify({
        model: "gemma4",
        message: { role: "assistant", content: "", thinking: "native thought" },
        done: false
    });
    r = StreamParser.parseDelta(json, "ollama");
    assertEqual(r.thinking, "native thought", "extracts Ollama native thinking");

    json = JSON.stringify({
        model: "gemma4",
        message: { role: "assistant", thinking: "thinking without content" },
        done: false
    });
    r = StreamParser.parseDelta(json, "ollama");
    assertEqual(r.content, "", "missing native content defaults to empty string");
    assertEqual(r.thinking, "thinking without content", "extracts thinking when content is omitted");

    // Tool call chunk (MCP tool)
    json = JSON.stringify({
        model: "gemma4",
        message: {
            role: "assistant",
            content: "",
            tool_calls: [{ function: { name: "web_search", arguments: { query: "ww2" } } }]
        },
        done: false
    });
    r = StreamParser.parseDelta(json, "ollama");
    assertEqual(r.content, "", "tool call chunk has empty content");
    assertEqual(r.done, false, "not done on tool call chunk");
    assert(Array.isArray(r.toolCalls), "returns tool calls as an array");
    assertEqual(r.toolCalls[0].function.name, "web_search", "keeps tool call name");

    // Tool call with done: true (intermediate turn end)
    json = JSON.stringify({
        model: "gemma4",
        message: {
            role: "assistant",
            content: "",
            tool_calls: [{ function: { name: "web_search", arguments: { query: "ww2" } } }]
        },
        done: true,
        eval_count: 15
    });
    r = StreamParser.parseDelta(json, "ollama");
    assert(Array.isArray(r.toolCalls), "detects tool calls even with done:true");
    assertEqual(r.done, true, "done is true on tool call turn end");
    assertEqual(r.outputTokens, 15, "extracts eval_count on tool call chunk");

    // Final done chunk (actual response complete)
    json = JSON.stringify({
        model: "gemma4",
        message: { role: "assistant", content: "" },
        done: true,
        eval_count: 200
    });
    r = StreamParser.parseDelta(json, "ollama");
    assertEqual(r.content, "", "final done chunk has empty content");
    assertEqual(r.done, true, "done is true on final chunk");
    assertEqual(r.toolCalls, false, "no tool calls on final chunk");
    assertEqual(r.outputTokens, 200, "extracts eval_count on final chunk");

    // No tool_calls field at all
    json = JSON.stringify({
        model: "gemma4",
        message: { role: "assistant", content: "normal" },
        done: false
    });
    r = StreamParser.parseDelta(json, "ollama");
    assertEqual(r.toolCalls, false, "no tool calls when field absent");

    // Empty tool_calls array
    json = JSON.stringify({
        model: "gemma4",
        message: { role: "assistant", content: "hi", tool_calls: [] },
        done: false
    });
    r = StreamParser.parseDelta(json, "ollama");
    assertEqual(r.toolCalls, false, "empty tool_calls array is not tool calls");
    assertEqual(r.content, "hi", "content still extracted with empty tool_calls");
})();

section("StreamParser.extractNonStreamingText — OpenAI");
(function() {
    var body = JSON.stringify({
        choices: [{ message: { content: "response text" } }]
    });
    var r = StreamParser.extractNonStreamingText(body, "openai");
    assertEqual(r, "response text", "extracts message content");

    body = JSON.stringify({ choices: [{ text: "legacy text" }] });
    r = StreamParser.extractNonStreamingText(body, "openai");
    assertEqual(r, "legacy text", "extracts legacy text field");

    body = JSON.stringify({ choices: [] });
    r = StreamParser.extractNonStreamingText(body, "openai");
    assertEqual(r, "", "handles empty choices");

    r = StreamParser.extractNonStreamingText("not json", "openai");
    assertEqual(r, "", "handles invalid JSON");
})();

section("StreamParser.extractNonStreamingText — Anthropic");
(function() {
    var body = JSON.stringify({
        content: [{ text: "part1" }, { text: "part2" }]
    });
    var r = StreamParser.extractNonStreamingText(body, "anthropic");
    assertEqual(r, "part1part2", "concatenates Anthropic content parts");

    body = JSON.stringify({ content: [] });
    r = StreamParser.extractNonStreamingText(body, "anthropic");
    assertEqual(r, "", "handles empty content array");

    body = JSON.stringify({ text: "fallback" });
    r = StreamParser.extractNonStreamingText(body, "anthropic");
    assertEqual(r, "fallback", "uses text field as fallback");
})();

section("StreamParser.extractNonStreamingText — Gemini");
(function() {
    var body = JSON.stringify({
        candidates: [{ content: { parts: [{ text: "gemini response" }] } }]
    });
    var r = StreamParser.extractNonStreamingText(body, "gemini");
    assertEqual(r, "gemini response", "extracts Gemini response");

    body = JSON.stringify([
        { candidates: [{ content: { parts: [{ text: "a" }, { text: "b" }] } }] }
    ]);
    r = StreamParser.extractNonStreamingText(body, "gemini");
    assertEqual(r, "ab", "handles array-wrapped Gemini response");
})();

// ═════════════════════════════════════════════════════════════════
//  Providers tests
// ═════════════════════════════════════════════════════════════════

section("Providers.normalizeBaseUrl");
(function() {
    assertEqual(Providers.normalizeBaseUrl("https://api.openai.com"), "https://api.openai.com", "leaves valid URL as-is");
    assertEqual(Providers.normalizeBaseUrl("https://api.openai.com/"), "https://api.openai.com", "strips trailing slash");
    assertEqual(Providers.normalizeBaseUrl("http://localhost:11434"), "http://localhost:11434", "allows http");
    assertEqual(Providers.normalizeBaseUrl("ftp://bad.com"), "", "rejects non-http(s) scheme");
    assertEqual(Providers.normalizeBaseUrl(""), "", "rejects empty string");
    assertEqual(Providers.normalizeBaseUrl(null), "", "rejects null");
    assertEqual(Providers.normalizeBaseUrl(undefined), "", "rejects undefined");
    assertEqual(Providers.normalizeBaseUrl("  https://api.openai.com  "), "https://api.openai.com", "trims whitespace");
    assertEqual(Providers.normalizeBaseUrl("https://" + "a".repeat(2048)), "", "rejects overly long URL");
    assertEqual(Providers.normalizeBaseUrl("https://example.com///"), "https://example.com//", "only strips single trailing slash");
})();

section("Providers.sanitizeApiKey");
(function() {
    assertEqual(Providers.sanitizeApiKey("sk-abc123"), "sk-abc123", "passes clean key through");
    assertEqual(Providers.sanitizeApiKey("sk-abc\r\n123"), "sk-abc123", "strips CR and LF");
    assertEqual(Providers.sanitizeApiKey("sk-abc\x00123"), "sk-abc123", "strips null bytes");
    assertEqual(Providers.sanitizeApiKey("  sk-abc  "), "sk-abc", "trims whitespace");
    assertEqual(Providers.sanitizeApiKey(""), "", "handles empty string");
    assertEqual(Providers.sanitizeApiKey(null), "", "handles null");
    assertEqual(Providers.sanitizeApiKey(undefined), "", "handles undefined");
    assertEqual(Providers.sanitizeApiKey("sk-abc\x01\x1f"), "sk-abc", "strips all control characters");
})();

section("Providers.openaiChatCompletionsUrl");
(function() {
    assertEqual(
        Providers.openaiChatCompletionsUrl("https://api.openai.com"),
        "https://api.openai.com/v1/chat/completions",
        "appends /v1/chat/completions to base URL"
    );
    assertEqual(
        Providers.openaiChatCompletionsUrl("https://api.openai.com/v1"),
        "https://api.openai.com/v1/chat/completions",
        "appends only /chat/completions when /v1 present"
    );
    assertEqual(
        Providers.openaiChatCompletionsUrl("https://custom.host/v2"),
        "https://custom.host/v2/chat/completions",
        "handles /v2 versioning"
    );
    assertEqual(
        Providers.openaiChatCompletionsUrl(""),
        "https://api.openai.com/v1/chat/completions",
        "defaults to OpenAI when empty"
    );
    assertEqual(
        Providers.openaiChatCompletionsUrl(null),
        "https://api.openai.com/v1/chat/completions",
        "defaults to OpenAI when null"
    );
})();

section("Providers.extractSystemPrompt");
(function() {
    var r = Providers.extractSystemPrompt([
        { role: "system", content: "You are helpful." },
        { role: "user", content: "Hi" },
        { role: "assistant", content: "Hello!" }
    ]);
    assertEqual(r.systemText, "You are helpful.", "extracts system message");
    assertEqual(r.filtered.length, 2, "filters out system message");
    assertEqual(r.filtered[0].role, "user", "first filtered is user");
    assertEqual(r.filtered[1].role, "assistant", "second filtered is assistant");

    r = Providers.extractSystemPrompt([{ role: "user", content: "Hi" }]);
    assertEqual(r.systemText, "", "empty system when none present");
    assertEqual(r.filtered.length, 1, "all messages preserved");

    r = Providers.extractSystemPrompt([]);
    assertEqual(r.systemText, "", "empty messages handled");
    assertEqual(r.filtered.length, 0, "empty filtered list");
})();

section("Providers.clampTemperature");
(function() {
    // Basic clamping
    assertEqual(Providers.clampTemperature("openai", "gpt-4", 0.5), 0.5, "passes valid temp through for OpenAI");
    assertEqual(Providers.clampTemperature("openai", "gpt-4", 3.0), 2.0, "clamps above max for OpenAI");
    assertEqual(Providers.clampTemperature("openai", "gpt-4", -1.0), 0.0, "clamps below min for OpenAI");
    assertEqual(Providers.clampTemperature("anthropic", "claude-3", 1.5), 1.0, "clamps to Anthropic max of 1.0");
    assertEqual(Providers.clampTemperature("anthropic", "claude-3", 0.5), 0.5, "valid Anthropic temp");

    // Default temperature when not provided
    assertEqual(Providers.clampTemperature("openai", "gpt-4", undefined), 1.0, "uses OpenAI default when undefined");
    assertEqual(Providers.clampTemperature("openai", "gpt-4", null), 1.0, "uses OpenAI default when null");
    assertEqual(Providers.clampTemperature("ollama", "llama3", undefined), 0.8, "uses Ollama default");

    // Unsupported models — exact match
    assertEqual(Providers.clampTemperature("openai", "o1", 0.5), undefined, "o1 exact match returns undefined");
    assertEqual(Providers.clampTemperature("openai", "o3", 0.5), undefined, "o3 exact match returns undefined");

    // Unsupported models — prefix with separator
    assertEqual(Providers.clampTemperature("openai", "o1-mini", 0.5), undefined, "o1-mini returns undefined");
    assertEqual(Providers.clampTemperature("openai", "o1-preview", 0.5), undefined, "o1-preview returns undefined");
    assertEqual(Providers.clampTemperature("openai", "o3-mini", 0.5), undefined, "o3-mini returns undefined");
    assertEqual(Providers.clampTemperature("openai", "o1_custom", 0.5), undefined, "o1_custom returns undefined");

    // BUG FIX: Models that start with o1/o3 but aren't reasoning models
    var result = Providers.clampTemperature("openai", "o1.5", 0.5);
    assert(result !== undefined, "o1.5 is NOT an unsupported model (not a reasoning model)");

    result = Providers.clampTemperature("openai", "o100", 0.5);
    assert(result !== undefined, "o100 is NOT an unsupported model");

    result = Providers.clampTemperature("openai", "o3x", 0.5);
    assert(result !== undefined, "o3x is NOT an unsupported model");

    // Case insensitivity
    assertEqual(Providers.clampTemperature("openai", "O1-MINI", 0.5), undefined, "case insensitive match");
    assertEqual(Providers.clampTemperature("openai", "O1.5", 0.5) !== undefined, true, "case insensitive non-match");

    // Unknown provider falls back to custom
    assertEqual(Providers.clampTemperature("unknown", "model", 0.5), 0.5, "unknown provider uses custom range");

    // Edge: zero temperature
    assertEqual(Providers.clampTemperature("openai", "gpt-4", 0.0), 0.0, "zero temperature is valid");
})();

section("Providers.getProviderInfo");
(function() {
    var info = Providers.getProviderInfo("openai");
    assertEqual(info.name, "OpenAI", "OpenAI name");
    assertEqual(info.envVar, "OPENAI_API_KEY", "OpenAI env var");
    assertEqual(info.needsKey, true, "OpenAI needs key");

    info = Providers.getProviderInfo("ollama");
    assertEqual(info.name, "Ollama", "Ollama name");
    assertEqual(info.envVar, null, "Ollama has no env var");
    assertEqual(info.needsKey, false, "Ollama doesn't need key");

    info = Providers.getProviderInfo("anthropic");
    assertEqual(info.envVar, "ANTHROPIC_API_KEY", "Anthropic env var");

    info = Providers.getProviderInfo("gemini");
    assertEqual(info.envVar, "GEMINI_API_KEY", "Gemini env var");

    info = Providers.getProviderInfo("custom");
    assertEqual(info.envVar, "EPHEMERA_API_KEY", "Custom env var");

    info = Providers.getProviderInfo("nonexistent");
    assertEqual(info.envVar, "EPHEMERA_API_KEY", "unknown provider falls back to custom");
})();

section("Providers.getTemperatureRange");
(function() {
    var r = Providers.getTemperatureRange("openai");
    assertEqual(r.min, 0.0, "OpenAI min temp");
    assertEqual(r.max, 2.0, "OpenAI max temp");
    assertEqual(r.defaultValue, 1.0, "OpenAI default temp");

    r = Providers.getTemperatureRange("anthropic");
    assertEqual(r.max, 1.0, "Anthropic max temp is 1.0");

    r = Providers.getTemperatureRange("ollama");
    assertEqual(r.defaultValue, 0.8, "Ollama default temp is 0.8");
})();

section("Providers.getProviderNames");
(function() {
    var names = Providers.getProviderNames();
    assert(names.indexOf("ollama") >= 0, "includes ollama");
    assert(names.indexOf("openai") >= 0, "includes openai");
    assert(names.indexOf("anthropic") >= 0, "includes anthropic");
    assert(names.indexOf("gemini") >= 0, "includes gemini");
    assert(names.indexOf("custom") >= 0, "includes custom");
    assertEqual(names.length, 5, "exactly 5 providers");
})();

section("Providers.escapeCurlConfig");
(function() {
    assertEqual(Providers.escapeCurlConfig("hello"), "hello", "passes clean string through");
    assertEqual(Providers.escapeCurlConfig('say "hi"'), 'say \\"hi\\"', "escapes double quotes");
    assertEqual(Providers.escapeCurlConfig("back\\slash"), "back\\\\slash", "escapes backslashes");
    assertEqual(Providers.escapeCurlConfig("line\nbreak"), "line\\nbreak", "escapes newlines");
    assertEqual(Providers.escapeCurlConfig("tab\there"), "tab\\there", "escapes tabs");
    assertEqual(Providers.escapeCurlConfig(""), "", "handles empty string");
    assertEqual(Providers.escapeCurlConfig(null), "", "handles null");
})();

// Helper: extract JSON body from a curl config string
function parseCurlConfigBody(config) {
    var match = config.match(/^data = "((?:[^"\\]|\\.)*)"/m);
    if (!match) return null;
    var val = match[1];
    // Unescape curl config escaping (placeholder for \\\\ to avoid double-processing)
    val = val.replace(/\\\\/g, '\x01')
             .replace(/\\"/g, '"')
             .replace(/\\n/g, '\n')
             .replace(/\\r/g, '\r')
             .replace(/\\t/g, '\t')
             .replace(/\x01/g, '\\');
    return JSON.parse(val);
}

section("Providers.buildCurlCommand");
(function() {
    // Ollama (no key needed)
    var payload = {
        provider: "ollama", baseUrl: "http://localhost:11434",
        model: "llama3", messages: [{ role: "user", content: "hi" }],
        temperature: 0.7, max_tokens: 4096, stream: true, timeout: 60
    };
    var r = Providers.buildCurlCommand("ollama", payload, "");
    assert(r !== null, "Ollama request builds without key");
    assert(r.cmd.indexOf("curl") >= 0, "command starts with curl");
    assert(r.cmd.indexOf("-K") >= 0, "uses -K flag for config-from-stdin");
    assert(r.cmd.indexOf("--max-time") >= 0, "includes timeout");
    // Body is now in curl config, not direct JSON
    assert(r.body.indexOf('url = "') >= 0, "config contains url directive");
    assert(r.body.indexOf('data = "') >= 0, "config contains data directive");
    var body = parseCurlConfigBody(r.body);
    assertEqual(body.model, "llama3", "body contains model");
    assertEqual(body.stream, true, "body has stream: true");
    assertEqual(body.reasoning_effort, undefined, "default Ollama thinking omits reasoning_effort");
    assert(r.body.indexOf('url = "http://localhost:11434/v1/chat/completions"') >= 0, "Ollama chat defaults to OpenAI-compatible endpoint");

    // No secrets in /proc/cmdline — verify cmd has no auth headers or URLs
    var cmdStr = r.cmd.join(" ");
    assert(cmdStr.indexOf("localhost:11434") < 0, "URL not in cmd args (hidden in config)");

    payload.tools = [{
        type: "function",
        function: {
            name: "web_search",
            description: "Search",
            parameters: { type: "object", properties: {} }
        }
    }];
    r = Providers.buildCurlCommand("ollama", payload, "");
    body = parseCurlConfigBody(r.body);
    assert(r.body.indexOf('url = "http://localhost:11434/api/chat"') >= 0, "Ollama tools use native chat endpoint");
    assertEqual(body.max_tokens, undefined, "Ollama native chat does not use OpenAI max_tokens");
    assertEqual(body.temperature, undefined, "Ollama native chat does not use top-level temperature");
    assertEqual(body.options.num_predict, 4096, "Ollama native chat maps max_tokens to num_predict");
    assertEqual(body.options.temperature, 0.7, "Ollama native chat maps temperature into options");
    assertEqual(body.tools.length, 1, "Ollama tool schema included");
    assertEqual(body.tools[0].function.name, "web_search", "Ollama tool name included");
    payload.ollamaThinkingMode = "none";
    r = Providers.buildCurlCommand("ollama", payload, "");
    body = parseCurlConfigBody(r.body);
    assertEqual(body.think, false, "Ollama native chat maps thinking off to think false");
    payload.ollamaThinkingMode = "high";
    r = Providers.buildCurlCommand("ollama", payload, "");
    body = parseCurlConfigBody(r.body);
    assertEqual(body.think, "high", "Ollama native chat maps thinking effort to think");
    delete payload.tools;

    payload.messages = [
        { role: "assistant", content: "", tool_calls: [{ function: { name: "web_search", arguments: {} } }] },
        { role: "tool", tool_name: "web_search", content: "result" }
    ];
    r = Providers.buildCurlCommand("ollama", payload, "");
    body = parseCurlConfigBody(r.body);
    assert(r.body.indexOf('url = "http://localhost:11434/api/chat"') >= 0, "Ollama tool history keeps the native endpoint");
    assertEqual(body.tools, undefined, "native tool history does not require current tool exposure");
    payload.messages = [{ role: "user", content: "hi" }];

    payload.ollamaThinkingMode = "none";
    r = Providers.buildCurlCommand("ollama", payload, "");
    body = parseCurlConfigBody(r.body);
    assertEqual(body.reasoning_effort, "none", "Ollama thinking off maps to reasoning_effort none");

    payload.ollamaThinkingMode = "low";
    r = Providers.buildCurlCommand("ollama", payload, "");
    body = parseCurlConfigBody(r.body);
    assertEqual(body.reasoning_effort, "low", "Ollama low thinking maps to reasoning_effort low");

    payload.ollamaThinkingMode = "medium";
    r = Providers.buildCurlCommand("ollama", payload, "");
    body = parseCurlConfigBody(r.body);
    assertEqual(body.reasoning_effort, "medium", "Ollama medium thinking maps to reasoning_effort medium");

    payload.ollamaThinkingMode = "high";
    r = Providers.buildCurlCommand("ollama", payload, "");
    body = parseCurlConfigBody(r.body);
    assertEqual(body.reasoning_effort, "high", "Ollama high thinking maps to reasoning_effort high");

    payload.ollamaThinkingMode = "invalid";
    r = Providers.buildCurlCommand("ollama", payload, "");
    body = parseCurlConfigBody(r.body);
    assertEqual(body.reasoning_effort, undefined, "invalid Ollama thinking mode falls back to default");
    payload.ollamaThinkingMode = "default";

    // OpenAI (key required)
    payload.provider = "openai";
    payload.baseUrl = "https://api.openai.com";
    r = Providers.buildCurlCommand("openai", payload, "sk-test123");
    assert(r !== null, "OpenAI request builds with key");
    assert(r.body.indexOf("Bearer sk-test123") >= 0, "auth header in config body");
    assert(r.cmd.join(" ").indexOf("Bearer") < 0, "auth header NOT in cmd args");

    // OpenAI without key returns null
    r = Providers.buildCurlCommand("openai", payload, "");
    assertEqual(r, null, "OpenAI returns null without key");

    // Anthropic
    payload.provider = "anthropic";
    payload.baseUrl = "https://api.anthropic.com";
    payload.thinkingEnabled = false;
    r = Providers.buildCurlCommand("anthropic", payload, "sk-ant-test");
    assert(r !== null, "Anthropic request builds");
    assert(r.body.indexOf("x-api-key") >= 0, "uses x-api-key header in config");
    assert(r.body.indexOf("anthropic-version") >= 0, "includes version header in config");
    assert(r.cmd.join(" ").indexOf("x-api-key") < 0, "x-api-key NOT in cmd args");
    body = parseCurlConfigBody(r.body);
    assert(body.max_tokens > 0, "Anthropic body has max_tokens");

    // Anthropic with thinking enabled
    payload.thinkingEnabled = true;
    r = Providers.buildCurlCommand("anthropic", payload, "sk-ant-test");
    assert(r.body.indexOf("interleaved-thinking") >= 0, "includes thinking beta header in config");
    body = parseCurlConfigBody(r.body);
    assert(body.thinking !== undefined, "body includes thinking config");
    assertEqual(body.thinking.type, "enabled", "thinking type is enabled");
    assert(body.thinking.budget_tokens > 0, "thinking budget set");

    // Gemini
    payload.provider = "gemini";
    payload.baseUrl = "https://generativelanguage.googleapis.com";
    payload.thinkingEnabled = false;
    r = Providers.buildCurlCommand("gemini", payload, "gemini-key");
    assert(r !== null, "Gemini request builds");
    assert(r.body.indexOf("x-goog-api-key") >= 0, "uses header for Gemini key in config");
    assert(r.body.indexOf("streamGenerateContent") >= 0, "uses streaming endpoint");
    assert(r.body.indexOf("alt=sse") >= 0, "requests SSE format");
    assert(r.cmd.join(" ").indexOf("x-goog-api-key") < 0, "Gemini key NOT in cmd args");

    // Custom provider delegates to openai
    r = Providers.buildCurlCommand("custom", payload, "custom-key");
    assert(r !== null, "Custom provider builds");

    // Key sanitization — dirty key still builds, no control chars leak
    r = Providers.buildCurlCommand("openai", payload, "sk-test\r\n\x00injected");
    assert(r !== null, "builds even with dirty key");
    assert(r.body.indexOf("\r") < 0, "no CR in config body");
    // Note: \\n in config is the escaped literal, not an actual newline
    assert(r.body.indexOf("sk-testinjected") >= 0, "sanitized key in config");
})();

section("Providers.buildRequest — system prompt handling");
(function() {
    var payload = {
        provider: "anthropic", baseUrl: "https://api.anthropic.com",
        model: "claude-3", messages: [
            { role: "system", content: "Be helpful" },
            { role: "user", content: "Hi" }
        ],
        temperature: 1.0, max_tokens: 4096, stream: true, timeout: 60,
        thinkingEnabled: false
    };

    var r = Providers.buildCurlCommand("anthropic", payload, "sk-test");
    var body = parseCurlConfigBody(r.body);
    assertEqual(body.system, "Be helpful", "Anthropic extracts system to top-level");
    assertEqual(body.messages.length, 1, "system removed from messages");

    // Gemini system prompt
    payload.provider = "gemini";
    payload.baseUrl = "https://generativelanguage.googleapis.com";
    r = Providers.buildCurlCommand("gemini", payload, "gem-key");
    body = parseCurlConfigBody(r.body);
    assert(body.system_instruction !== undefined, "Gemini has system_instruction");
    assertEqual(body.system_instruction.parts[0].text, "Be helpful", "Gemini system text");

    // OpenAI keeps system in messages
    payload.provider = "openai";
    payload.baseUrl = "https://api.openai.com";
    r = Providers.buildCurlCommand("openai", payload, "sk-test");
    body = parseCurlConfigBody(r.body);
    assertEqual(body.messages[0].role, "system", "OpenAI keeps system in messages");
})();

section("Providers — unlimited tokens");
(function() {
    var payload = {
        provider: "anthropic", baseUrl: "https://api.anthropic.com",
        model: "claude-3", messages: [{ role: "user", content: "Hi" }],
        temperature: 1.0, max_tokens: 0, stream: true, timeout: 60,
        thinkingEnabled: false
    };
    var r = Providers.buildCurlCommand("anthropic", payload, "sk-test");
    var body = parseCurlConfigBody(r.body);
    assertEqual(body.max_tokens, 128000, "Anthropic uses 128000 when unlimited (max_tokens=0)");

    payload.provider = "openai";
    payload.baseUrl = "https://api.openai.com";
    r = Providers.buildCurlCommand("openai", payload, "sk-test");
    body = parseCurlConfigBody(r.body);
    assertEqual(body.max_tokens, undefined, "OpenAI omits max_tokens when 0");
})();

// ═════════════════════════════════════════════════════════════════
//  Markdown tests
// ═════════════════════════════════════════════════════════════════

section("Markdown.escapeHtml");
(function() {
    assertEqual(Markdown.escapeHtml("<script>"), "&lt;script&gt;", "escapes angle brackets");
    assertEqual(Markdown.escapeHtml("a&b"), "a&amp;b", "escapes ampersand");
    assertEqual(Markdown.escapeHtml('a"b'), "a&quot;b", "escapes quotes");
    assertEqual(Markdown.escapeHtml(""), "", "empty string");
    assertEqual(Markdown.escapeHtml(null), "", "null returns empty");
    assertEqual(Markdown.escapeHtml(undefined), "", "undefined returns empty");
    assertEqual(Markdown.escapeHtml("safe text"), "safe text", "safe text unchanged");
    assertEqual(Markdown.escapeHtml("<>&\""), "&lt;&gt;&amp;&quot;", "all special chars");
})();

section("Markdown.markdownToHtml — headers");
(function() {
    var r = Markdown.markdownToHtml("# Title");
    assert(r.indexOf("<h1") >= 0, "h1 generated");
    assert(r.indexOf("Title") >= 0, "title text present");

    r = Markdown.markdownToHtml("## Subtitle");
    assert(r.indexOf("<h2") >= 0, "h2 generated");

    r = Markdown.markdownToHtml("### H3\n#### H4\n##### H5\n###### H6");
    assert(r.indexOf("<h3") >= 0, "h3 generated");
    assert(r.indexOf("<h4") >= 0, "h4 generated");
    assert(r.indexOf("<h5") >= 0, "h5 generated");
    assert(r.indexOf("<h6") >= 0, "h6 generated");
})();

section("Markdown.markdownToHtml — bold/italic/strikethrough");
(function() {
    var r = Markdown.markdownToHtml("**bold**");
    assert(r.indexOf("<b>bold</b>") >= 0, "bold with **");

    r = Markdown.markdownToHtml("*italic*");
    assert(r.indexOf("<i>italic</i>") >= 0, "italic with *");

    r = Markdown.markdownToHtml("***both***");
    assert(r.indexOf("<b><i>both</i></b>") >= 0, "bold+italic with ***");

    r = Markdown.markdownToHtml("__bold__");
    assert(r.indexOf("<b>bold</b>") >= 0, "bold with __");

    r = Markdown.markdownToHtml("_italic_");
    assert(r.indexOf("<i>italic</i>") >= 0, "italic with _");

    r = Markdown.markdownToHtml("~~strikethrough~~");
    assert(r.indexOf("<s>strikethrough</s>") >= 0, "strikethrough");
})();

section("Markdown.markdownToHtml — code blocks");
(function() {
    var r = Markdown.markdownToHtml("```python\nprint('hi')\n```");
    assert(r.indexOf("<code>") >= 0, "code block generated");
    assert(r.indexOf("print") >= 0, "code content present");
    assert(r.indexOf("python") >= 0, "language label present");

    r = Markdown.markdownToHtml("```\nno lang\n```");
    assert(r.indexOf("<code>") >= 0, "code block without language");

    r = Markdown.markdownToHtml("`inline code`");
    assert(r.indexOf("monospace") >= 0, "inline code gets monospace");
    assert(r.indexOf("inline code") >= 0, "inline code content");
})();

section("Markdown.markdownToHtml — links");
(function() {
    var r = Markdown.markdownToHtml("[Click](https://example.com)");
    assert(r.indexOf("href=") >= 0, "link has href");
    assert(r.indexOf("https://example.com") >= 0, "link URL present");
    assert(r.indexOf("Click") >= 0, "link text present");

    // Non-http scheme rejected
    r = Markdown.markdownToHtml("[Bad](javascript:alert(1))");
    assert(r.indexOf("href=") < 0, "javascript: scheme blocked");
    assert(r.indexOf("Bad") >= 0, "link text still rendered");

    r = Markdown.markdownToHtml("[Bad](file:///etc/passwd)");
    assert(r.indexOf("href=") < 0, "file: scheme blocked");

    // Auto-linking
    r = Markdown.markdownToHtml("Visit https://example.com for info");
    assert(r.indexOf("href=") >= 0, "auto-linked URL");
})();

section("Markdown.markdownToHtml — XSS prevention");
(function() {
    var r = Markdown.markdownToHtml('<script>alert("xss")</script>');
    assert(r.indexOf("<script>") < 0, "script tag escaped");
    assert(r.indexOf("&lt;script&gt;") >= 0, "script tag visible as text");

    r = Markdown.markdownToHtml('[XSS](javascript:alert(1))');
    assert(r.indexOf('href="javascript:') < 0, "javascript: scheme not in any href");
    assert(r.indexOf("XSS") >= 0, "link text rendered as plain text");

    // Code block language XSS
    r = Markdown.markdownToHtml('```<script>alert(1)</script>\ncode\n```');
    assert(r.indexOf("<script>alert") < 0, "script in language label escaped");

    // XSS in link text — HTML is escaped by both body escaping and link escaping
    r = Markdown.markdownToHtml('[<img onerror=alert(1)>](https://safe.com)');
    assert(r.indexOf("<img ") < 0, "no raw HTML img tag in output");
})();

section("Markdown.markdownToHtml — lists");
(function() {
    var r = Markdown.markdownToHtml("- item1\n- item2");
    assert(r.indexOf("<ul") >= 0, "unordered list");
    assert(r.indexOf("<li>") >= 0, "list items");

    r = Markdown.markdownToHtml("1. first\n2. second");
    assert(r.indexOf("<ol") >= 0, "ordered list");

    r = Markdown.markdownToHtml("- [x] done\n- [ ] todo");
    assert(r.indexOf("\u2611") >= 0, "checked checkbox");
    assert(r.indexOf("\u2610") >= 0, "unchecked checkbox");
})();

section("Markdown.markdownToHtml — tables");
(function() {
    var table = "| A | B |\n| --- | --- |\n| 1 | 2 |";
    var r = Markdown.markdownToHtml(table);
    assert(r.indexOf("<table") >= 0, "table generated");
    assert(r.indexOf("<th") >= 0, "table headers");
    assert(r.indexOf("<td") >= 0, "table cells");

    // Table content escaping
    table = "| <script> | B |\n| --- | --- |\n| 1 | 2 |";
    r = Markdown.markdownToHtml(table);
    assert(r.indexOf("<script>") < 0, "script in table header escaped");
    assert(r.indexOf("&lt;script&gt;") >= 0, "escaped script visible in table");
})();

section("Markdown.markdownToHtml — blockquotes");
(function() {
    var r = Markdown.markdownToHtml("> quoted text");
    assert(r.indexOf("<blockquote") >= 0, "blockquote generated");
    assert(r.indexOf("quoted text") >= 0, "quoted content present");
})();

section("Markdown.markdownToHtml — horizontal rules");
(function() {
    var r = Markdown.markdownToHtml("---");
    assert(r.indexOf("<hr") >= 0, "horizontal rule from ---");

    r = Markdown.markdownToHtml("***");
    assert(r.indexOf("<hr") >= 0, "horizontal rule from ***");

    r = Markdown.markdownToHtml("___");
    assert(r.indexOf("<hr") >= 0, "horizontal rule from ___");
})();

section("Markdown.markdownToHtml — edge cases");
(function() {
    assertEqual(Markdown.markdownToHtml(""), "", "empty string");
    assertEqual(Markdown.markdownToHtml(null), "", "null input");
    assertEqual(Markdown.markdownToHtml(undefined), "", "undefined input");

    var r = Markdown.markdownToHtml("plain text");
    assert(r.indexOf("plain text") >= 0, "plain text passes through");

    // Very long line
    var long = "a".repeat(5000);
    r = Markdown.markdownToHtml(long);
    assert(r.indexOf("a") >= 0, "handles very long lines");

    // Mixed content
    r = Markdown.markdownToHtml("# Title\n\nSome **bold** text.\n\n```\ncode\n```\n\n- list item");
    assert(r.indexOf("<h1") >= 0, "mixed: has header");
    assert(r.indexOf("<b>") >= 0, "mixed: has bold");
    assert(r.indexOf("<code>") >= 0, "mixed: has code");
    assert(r.indexOf("<ul") >= 0, "mixed: has list");
})();

section("Markdown.markdownToHtml — custom colors");
(function() {
    var colors = {
        codeBg: "#FF0000",
        inlineCodeBg: "#00FF00",
        blockquoteBg: "#0000FF",
        blockquoteBorder: "#FFFFFF"
    };
    var r = Markdown.markdownToHtml("```\ncode\n```", colors);
    assert(r.indexOf("#FF0000") >= 0, "custom code background color applied");

    r = Markdown.markdownToHtml("`inline`", colors);
    assert(r.indexOf("#00FF00") >= 0, "custom inline code background");

    r = Markdown.markdownToHtml("> quote", colors);
    assert(r.indexOf("#0000FF") >= 0, "custom blockquote background");
    assert(r.indexOf("#FFFFFF") >= 0, "custom blockquote border");
})();

// ═════════════════════════════════════════════════════════════════
//  ChatExport tests
// ═════════════════════════════════════════════════════════════════

section("ChatExport.buildMarkdown");
(function() {
    var md = ChatExport.buildMarkdown([
        { role: "user", content: "Hello" },
        { role: "assistant", content: "Hi there!" }
    ]);
    assert(md.indexOf("### You") >= 0, "user header");
    assert(md.indexOf("### Assistant") >= 0, "assistant header");
    assert(md.indexOf("Hello") >= 0, "user content");
    assert(md.indexOf("Hi there!") >= 0, "assistant content");
    assert(md.indexOf("---") >= 0, "separator");

    assertEqual(ChatExport.buildMarkdown([]), "", "empty messages");

    md = ChatExport.buildMarkdown([{ role: "user", content: "Only one" }]);
    assert(md.indexOf("---") < 0, "single message has no separator");
    assert(md.indexOf("Only one") >= 0, "single message content");

    // Multi-turn conversation
    md = ChatExport.buildMarkdown([
        { role: "user", content: "Q1" },
        { role: "assistant", content: "A1" },
        { role: "user", content: "Q2" },
        { role: "assistant", content: "A2" }
    ]);
    var separatorCount = (md.match(/---/g) || []).length;
    assertEqual(separatorCount, 3, "3 separators for 4 messages");
})();

section("ChatExport.generateFilename");
(function() {
    var f = ChatExport.generateFilename("/home/user");
    assert(f.startsWith("/home/user/ephemera-chat-"), "starts with home dir");
    assert(f.endsWith(".md"), "ends with .md");
    assert(f.indexOf(":") < 0, "no colons in filename");
    assert(f.indexOf(".") === f.length - 3 || f.indexOf(".") < f.length - 3, "dots only in extension");

    f = ChatExport.generateFilename("");
    assert(f.startsWith("/ephemera-chat-"), "empty home dir uses /");

    f = ChatExport.generateFilename(null);
    assert(f.indexOf("ephemera-chat-") >= 0, "null home dir handled");
})();

// ═════════════════════════════════════════════════════════════════
// Mcp.js tests
// ═════════════════════════════════════════════════════════════════

section("Mcp.trustKey");
(function() {
    assertEqual(Mcp.trustKey(" http://localhost:8811/sse ", " mcp-remote "), "mcp-remote\nhttp://localhost:8811/sse", "trims URL and command");
    assertEqual(Mcp.trustKey("", "mcp-remote"), "mcp-remote\n", "empty URL remains part of key");
})();

section("Mcp bridge version helpers");
(function() {
    assertEqual(Mcp.isVersionAtLeast("0.1.16", "0.1.16"), true, "accepts the first patched bridge version");
    assertEqual(Mcp.isVersionAtLeast("0.1.38", "0.1.16"), true, "accepts a newer patch version");
    assertEqual(Mcp.isVersionAtLeast("1.0.0", "0.1.16"), true, "accepts a newer major version");
    assertEqual(Mcp.isVersionAtLeast("0.1.15", "0.1.16"), false, "rejects a vulnerable bridge version");
    assertEqual(Mcp.isVersionAtLeast("0.1.16-beta.1", "0.1.16"), false, "rejects prerelease bridge versions");
    assertEqual(Mcp.isVersionAtLeast("latest", "0.1.16"), false, "rejects non-semantic versions");
    assertEqual(Mcp.isVersionInRange("0.1.16", "0.1.16", "0.2.0"), true, "accepts the bottom of the bridge range");
    assertEqual(Mcp.isVersionInRange("0.1.38", "0.1.16", "0.2.0"), true, "accepts a patched bridge in range");
    assertEqual(Mcp.isVersionInRange("0.1.15", "0.1.16", "0.2.0"), false, "rejects a bridge below the range");
    assertEqual(Mcp.isVersionInRange("0.2.0", "0.1.16", "0.2.0"), false, "rejects the exclusive bridge maximum");
    assertEqual(Mcp.isVersionInRange("1.0.0", "0.1.16", "0.2.0"), false, "rejects an unreviewed bridge major version");
    assertEqual(Mcp.isVersionInRange("0.1.38", "0.1.38", "0.1.39"), true, "accepts the reviewed bridge release");
    assertEqual(Mcp.isVersionInRange("0.1.37", "0.1.38", "0.1.39"), false, "rejects an older unreviewed bridge release");
    assertEqual(Mcp.isVersionInRange("0.1.39", "0.1.38", "0.1.39"), false, "rejects a future unreviewed bridge release");
    assertEqual(Mcp.isVersionInRange("7.27.0", "7.28.0", "8.0.0"), false, "rejects a vulnerable Undici 7 release");
    assertEqual(Mcp.isVersionInRange("7.28.0", "7.28.0", "8.0.0"), true, "accepts the patched Undici 7 floor");
    assertEqual(Mcp.isVersionInRange("8.0.0", "7.28.0", "8.0.0"), false, "rejects an unreviewed Undici major release");
    assertEqual(Mcp.isVersionInRange("24.17.0", "24.17.0", "25.0.0"), true, "accepts the reviewed Node 24 LTS floor");
    assertEqual(Mcp.isVersionInRange("24.16.1", "24.17.0", "25.0.0"), false, "rejects Node below the reviewed LTS floor");
    assertEqual(Mcp.isVersionInRange("25.0.0", "24.17.0", "25.0.0"), false, "rejects an unreviewed Node major");

    var runtimeInfo = Mcp.extractNodeRuntimeInfo(JSON.stringify({
        nodeVersion: "24.17.0",
        undiciVersion: "7.28.0",
        executable: "/opt/node/bin/node"
    }));
    assertEqual(runtimeInfo.nodeVersion, "24.17.0", "extracts the probed Node runtime version");
    assertEqual(runtimeInfo.undiciVersion, "7.28.0", "extracts Node's bundled Undici version");
    assertEqual(runtimeInfo.executable, "/opt/node/bin/node", "captures the exact checked Node executable");
    assertEqual(Mcp.extractNodeRuntimeInfo(JSON.stringify({
        nodeVersion: "24.17.0", undiciVersion: "7.28.0", executable: "node"
    })).executable, "", "rejects a non-absolute Node executable");
    assertEqual(Mcp.extractNodeRuntimeInfo(JSON.stringify({
        nodeVersion: "24.17.0", executable: "/opt/node/bin/node"
    })).nodeVersion, "", "fails closed when bundled Undici is not reported");

    var npmOutput = JSON.stringify({
        dependencies: {
            "mcp-remote": {
                version: "0.1.38",
                path: "/opt/npm/lib/node_modules/mcp-remote",
                bin: { "mcp-remote": "dist/proxy.js" },
                dependencies: {
                    undici: { version: "7.28.0" },
                    open: { version: "10.2.0" }
                }
            }
        }
    });
    assertEqual(Mcp.extractNpmPackageVersion(npmOutput, "mcp-remote"), "0.1.38", "extracts the installed npm version");
    assertEqual(Mcp.extractNpmPackageInfo(npmOutput, "mcp-remote").executable, "/opt/npm/lib/node_modules/mcp-remote/dist/proxy.js", "extracts the checked executable path");
    assertEqual(Mcp.extractNpmPackageInfo(npmOutput, "mcp-remote").undiciVersion, "7.28.0", "extracts the direct Undici runtime version");
    assertEqual(Mcp.extractNpmPackageInfo(npmOutput, "mcp-remote").openVersion, "10.2.0", "extracts the reviewed browser launcher version");
    var missingRuntimeDependency = JSON.stringify({
        dependencies: {
            "mcp-remote": {
                version: "0.1.38",
                path: "/opt/npm/lib/node_modules/mcp-remote",
                bin: { "mcp-remote": "dist/proxy.js" }
            }
        }
    });
    assertEqual(Mcp.extractNpmPackageInfo(missingRuntimeDependency, "mcp-remote").undiciVersion,
        "", "fails closed when the Undici runtime dependency is absent");
    assertEqual(Mcp.extractNpmPackageInfo(missingRuntimeDependency, "mcp-remote").openVersion,
        "", "fails closed when the browser launcher dependency is absent");
    var shadowed = JSON.stringify({ dependencies: { "mcp-remote": { version: "0.1.38", path: "/tmp/package", bin: { "mcp-remote": "../shadow" } } } });
    assertEqual(Mcp.extractNpmPackageInfo(shadowed, "mcp-remote").executable, "", "rejects an unexpected package executable layout");
    assertEqual(Mcp.extractNpmPackageVersion("not json", "mcp-remote"), "", "rejects malformed npm output");
    assertEqual(Mcp.extractNpmPackageVersion("{}", "mcp-remote"), "", "handles a missing package");
})();

section("Mcp JSON-RPC envelope validation");
(function() {
    assertEqual(Mcp.classifyJsonRpcMessage({
        jsonrpc: "2.0", id: 1, result: null
    }).kind, "response", "accepts a result response with an explicit null result");
    assertEqual(Mcp.classifyJsonRpcMessage({
        jsonrpc: "2.0", id: 2,
        error: { code: -32601, message: "Method not found" }
    }).kind, "response", "accepts a well-formed JSON-RPC error response");
    assertEqual(Mcp.classifyJsonRpcMessage({
        jsonrpc: "2.0", id: 3, result: {},
        error: { code: -32603, message: "both" }
    }).kind, "invalid", "rejects a response containing result and error");
    assertEqual(Mcp.classifyJsonRpcMessage({
        jsonrpc: "2.0", id: 3, result: {}, params: {}
    }).responseId, 3, "rejects response-only protocol fields without stalling its pending id");
    var malformedError = Mcp.classifyJsonRpcMessage({
        jsonrpc: "2.0", id: 4, error: { code: "-1", message: 7 }
    });
    assertEqual(malformedError.kind, "invalid", "rejects an error-only malformed response");
    assertEqual(malformedError.responseId, 4, "retains the safe pending id for a malformed error response");
    assertEqual(Mcp.classifyJsonRpcMessage({
        jsonrpc: "2.0", id: "__proto__", result: {}
    }).kind, "invalid", "rejects string response ids before pending-map access");
    assertEqual(Mcp.classifyJsonRpcMessage({
        jsonrpc: "2.0", method: 7, params: {}
    }).kind, "invalid", "rejects a non-string method");
    assertEqual(Mcp.classifyJsonRpcMessage({
        jsonrpc: "2.0", method: "ping", id: "server-request", params: []
    }).kind, "request", "accepts a bounded string id for a server request");
    assertEqual(Mcp.classifyJsonRpcMessage({
        jsonrpc: "2.0", method: "notifications/tools/list_changed"
    }).kind, "notification", "accepts a valid notification envelope");
})();

section("Mcp endpoint safety helpers");
(function() {
    assertEqual(Mcp.mcpUrlSafetyError("https://mcp.example.com/sse"), "", "accepts a credential-free HTTPS endpoint");
    assert(Mcp.mcpUrlSafetyError("https://token@mcp.example.com/sse").length > 0, "rejects embedded URL credentials");
    assert(Mcp.mcpUrlSafetyError("https://mcp.example.com/sse?token=secret").length > 0, "rejects query strings that would leak through argv");
    assert(Mcp.mcpUrlSafetyError("https://mcp.example.com/sse#fragment").length > 0, "rejects URL fragments");
    assertEqual(Mcp.isLoopbackHttpUrl("http://localhost:8811/sse"), true, "recognizes localhost HTTP");
    assertEqual(Mcp.isLoopbackHttpUrl("http://127.0.0.1:8811/sse"), true, "recognizes IPv4 loopback HTTP");
    assertEqual(Mcp.isLoopbackHttpUrl("http://127.255.0.1/sse"), true, "recognizes the full IPv4 loopback range");
    assertEqual(Mcp.isLoopbackHttpUrl("http://127.attacker.example/sse"), false, "does not confuse a 127-prefixed hostname with loopback");
    assertEqual(Mcp.isLoopbackHttpUrl("http://127.0.0.1.attacker.example/sse"), false, "does not accept a loopback-looking remote hostname");
    assertEqual(Mcp.isLoopbackHttpUrl("http://127.0.0.999/sse"), false, "rejects invalid loopback octets");
    assertEqual(Mcp.requiresInsecureHttpConsent("http://192.168.1.4:8811/sse"), true, "requires consent for remote HTTP");
    assertEqual(Mcp.requiresInsecureHttpConsent("http://127.attacker.example/sse"), true, "requires consent for a 127-prefixed remote hostname");
    assertEqual(Mcp.requiresInsecureHttpConsent("http://localhost:8811/sse"), false, "does not require extra consent for loopback HTTP");
    assertEqual(Mcp.requiresInsecureHttpConsent("https://mcp.example.com/sse"), false, "does not require consent for HTTPS");
})();

section("Mcp advertised tool validation");
(function() {
    var valid = { name: "search.docs", inputSchema: { type: "object" } };
    var duplicate = { name: "search.docs", description: "duplicate", inputSchema: { type: "object" } };
    var invalidName = { name: "search docs", inputSchema: { type: "object" } };
    var paddedName = { name: " search.docs ", inputSchema: { type: "object" } };
    var invalidSchema = { name: "bad_schema", inputSchema: { type: "array" } };
    var taskOnly = { name: "task_only", inputSchema: { type: "object" }, execution: { taskSupport: "required" } };
    var invalidMetadata = { name: "bad_metadata", description: { text: "not a string" }, inputSchema: { type: "object" } };
    var tools = Mcp.sanitizeTools([valid, duplicate, invalidName, paddedName, invalidSchema, taskOnly, invalidMetadata]);
    assertEqual(tools.length, 1, "keeps only supported tools with unique names");
    assertEqual(tools[0].name, "search.docs", "keeps the first valid tool contract");
    assertEqual(Mcp.findTool(tools, "search.docs"), valid, "finds an exact advertised tool name");
    assertEqual(Mcp.findTool(tools, " search.docs "), null, "does not normalize a requested tool name");

    var deep = { type: "object" };
    var cursor = deep;
    for (var i = 0; i < 40; i++) {
        cursor.properties = { child: { type: "object" } };
        cursor = cursor.properties.child;
    }
    assertEqual(Mcp.toolFingerprint({ name: "deep", inputSchema: deep }), "", "rejects excessively deep tool contracts");
})();

section("Mcp tool approval helpers");
(function() {
    var searchTool = {
        name: "search",
        description: "Search documents",
        inputSchema: {
            type: "object",
            properties: {
                query: { type: "string" },
                limit: { type: "integer" }
            },
            required: ["query"]
        }
    };
    var sameSearchTool = {
        inputSchema: {
            required: ["query"],
            properties: {
                limit: { type: "integer" },
                query: { type: "string" }
            },
            type: "object"
        },
        description: "Search documents",
        name: "search"
    };
    var changedSearchTool = {
        name: "search",
        description: "Search and write documents",
        inputSchema: searchTool.inputSchema
    };

    var key = Mcp.toolApprovalKey(searchTool);
    assert(key.indexOf("search\n") === 0, "approval key includes tool name prefix");
    assert(key.indexOf("Search documents") >= 0, "approval key includes the serialized tool contract");
    assertEqual(Mcp.toolFingerprint(searchTool), Mcp.toolFingerprint(sameSearchTool), "contract fingerprint is stable across object key order");
    var contractText = Mcp.formatToolContract(searchTool);
    assert(contractText.indexOf('"inputSchema"') >= 0, "contract review includes the input schema");
    assert(contractText.indexOf('"outputSchema"') >= 0, "contract review includes every approval-bound field");

    var approvals = Mcp.setToolApproved([], searchTool, true);
    assertEqual(approvals.length, 1, "adds exact tool approval");
    assertEqual(Mcp.isToolApproved(searchTool, approvals), true, "approves current tool contract");
    assertEqual(Mcp.isToolApproved(sameSearchTool, approvals), true, "same contract stays approved");
    assertEqual(Mcp.isToolApproved(changedSearchTool, approvals), false, "changed tool contract is not approved");
    var taskSearchTool = JSON.parse(JSON.stringify(searchTool));
    taskSearchTool.execution = { taskSupport: "optional" };
    assertEqual(Mcp.isToolApproved(taskSearchTool, approvals), false, "changed execution contract is not approved");
    assertEqual(Mcp.isToolApproved(searchTool, ["search"]), false, "name-only approval does not authorize a tool");

    var pruned = Mcp.pruneApprovedTools(approvals, [changedSearchTool]);
    assertEqual(pruned.length, 0, "prunes approvals when advertised contract changes");

    approvals = Mcp.setToolApproved(approvals, searchTool, false);
    assertEqual(approvals.length, 0, "removes exact tool approval");
})();

section("Mcp tool argument helpers");
(function() {
    var parsed = Mcp.parseToolArguments('{"query":"ephemera"}');
    assertEqual(parsed.valid, true, "accepts a JSON object argument string");
    assertEqual(parsed.value.query, "ephemera", "parses JSON argument string");
    assertEqual(Mcp.parseToolArguments("not json").valid, false, "invalid JSON arguments fail closed");
    assertEqual(Mcp.parseToolArguments('["bad"]').valid, false, "JSON array arguments fail closed");
    assertEqual(Mcp.parseToolArguments(["bad"]).valid, false, "array arguments fail closed");
    assertEqual(Mcp.parseToolArguments(null).valid, true, "missing optional arguments become an empty object");
    assertEqual(Mcp.parseToolCall({ function: { name: "search", arguments: { query: "ephemera" } } }).valid, true, "accepts a canonical provider tool call");
    assertEqual(Mcp.parseToolCall({ function: { name: " search ", arguments: {} } }).valid, false, "rejects a padded tool call name");
    assertEqual(Mcp.parseToolCall(null).valid, false, "rejects a malformed tool call envelope");

    var preview = Mcp.formatToolArguments({ query: "ephemera" }, 100);
    assert(preview.indexOf('"query": "ephemera"') >= 0, "formats object arguments as pretty JSON");
    preview = Mcp.formatToolArguments({ query: "ephemera", body: "abcdef" }, 12);
    assert(preview.indexOf("[Arguments truncated]") >= 0, "truncates long argument previews");
    preview = Mcp.formatToolArguments({ body: "a".repeat(32) }, 0);
    assert(preview.indexOf("[Arguments truncated]") < 0, "limit 0 keeps full argument text");
    assert(preview.indexOf("a".repeat(32)) >= 0, "full argument text includes complete value");
    preview = Mcp.formatToolArguments({ path: "safe\u202eevil" }, 0);
    assert(preview.indexOf("\\u202e") >= 0, "escapes bidirectional controls in approval text");
    preview = Mcp.formatToolArguments({ path: "\u202e" + "x".repeat(40) }, 20);
    assert(preview.indexOf("\u202e") < 0 && preview.indexOf("\\u202e") >= 0,
        "escapes bidirectional controls in truncated previews");
    assert(Mcp.formatReviewText("safe\u200bevil").indexOf("\\u200b") >= 0,
        "escapes invisible controls in server descriptions");
    assert(Mcp.formatReviewText("safe\u2060evil").indexOf("\\u2060") >= 0,
        "escapes word-joining controls in review text");
    assert(Mcp.formatReviewText("safe\u00adevil").indexOf("\\u00ad") >= 0,
        "escapes soft hyphens in review text");
    var defaultIgnorableSamples = [
        { value: "\u3164", escaped: "\\u3164", label: "Hangul filler" },
        { value: "\uffa0", escaped: "\\uffa0", label: "halfwidth Hangul filler" },
        { value: "\ufe0f", escaped: "\\ufe0f", label: "BMP variation selector" },
        { value: "\ud834\udd73", escaped: "\\u{1d173}", label: "musical formatting control" },
        { value: "\udb40\udc01", escaped: "\\u{e0001}", label: "language tag" },
        { value: "\udb40\udd00", escaped: "\\u{e0100}", label: "supplementary variation selector" },
        { value: "\ud800", escaped: "\\ud800", label: "unpaired surrogate" }
    ];
    for (var di = 0; di < defaultIgnorableSamples.length; di++) {
        var sample = defaultIgnorableSamples[di];
        var safeReview = Mcp.formatReviewText("before" + sample.value + "after");
        assert(safeReview.indexOf(sample.value) < 0
                && safeReview.indexOf(sample.escaped) >= 0,
            "escapes " + sample.label + " in review text");
    }
})();

section("Mcp.buildToolResumeMessages");
(function() {
    var base = [{ role: "user", content: "what changed?" }];
    var toolCalls = [{ function: { name: "search", arguments: { q: "ephemera" } } }];
    var toolResults = [{ role: "tool", tool_name: "search", content: "result text" }];
    var messages = Mcp.buildToolResumeMessages(base, "checking", "native thinking", toolCalls, toolResults);

    assertEqual(messages.length, 3, "adds assistant tool turn and tool result");
    assertEqual(messages[0].content, "what changed?", "keeps original messages");
    assertEqual(messages[1].role, "assistant", "adds assistant tool-call message");
    assertEqual(messages[1].content, "checking", "keeps assistant content");
    assertEqual(messages[1].thinking, "native thinking", "preserves Ollama native thinking");
    assertEqual(messages[1].tool_calls.length, 1, "keeps tool calls");
    assertEqual(messages[2].role, "tool", "appends tool result");

    messages = Mcp.buildToolResumeMessages(base, "", "", toolCalls, toolResults);
    assertEqual(messages[1].thinking, undefined, "omits empty thinking field");
    assertEqual(base.length, 1, "does not mutate original conversation array");
})();

section("Mcp.appendToolsPage");
(function() {
    var page = Mcp.appendToolsPage([{ name: "first" }], {
        tools: [{ name: "second" }],
        nextCursor: "cursor-2"
    });
    assertEqual(page.tools.length, 2, "appends tool page");
    assertEqual(page.tools[1].name, "second", "keeps appended tool");
    assertEqual(page.nextCursor, "cursor-2", "returns next cursor");

    page = Mcp.appendToolsPage(page.tools, { tools: [{ name: "third" }] });
    assertEqual(page.tools.length, 3, "appends final page");
    assertEqual(page.nextCursor, "", "missing cursor becomes empty string");
})();

section("Mcp.formatToolResult");
(function() {
    var text = Mcp.formatToolResult({
        content: [
            { type: "text", text: "hello" },
            { type: "image", mimeType: "image/png" },
            { type: "resource_link", name: "doc", uri: "file:///doc.md" }
        ],
        structuredContent: { count: 2 }
    });
    assert(text.indexOf("hello") >= 0, "includes text content");
    assert(text.indexOf("[image: image/png]") >= 0, "summarizes image content");
    assert(text.indexOf("[resource: doc]") >= 0, "summarizes resource links");
    assert(text.indexOf('"count":2') >= 0, "includes structured content");

    text = Mcp.formatToolResult({ content: [{ type: "resource", resource: { text: "embedded text" } }] });
    assertEqual(text, "embedded text", "uses embedded resource text");
    assertEqual(Mcp.formatToolResult("plain"), "plain", "passes strings through");
    assertEqual(Mcp.isToolError({ isError: true }), true, "detects MCP tool errors");
    assertEqual(Mcp.isToolError({ isError: false }), false, "non-error result is not an error");
})();

section("McpSchema.validateToolArguments");
(function() {
    var tool = {
        name: "write_record",
        inputSchema: {
            type: "object",
            properties: {
                name: { type: "string", minLength: 1, maxLength: 20 },
                count: { type: "integer", minimum: 1, maximum: 5 },
                tags: { type: "array", maxItems: 2, items: { type: "string" } }
            },
            required: ["name", "count"],
            additionalProperties: false
        }
    };
    assertEqual(McpSchema.inputSchemaSupportError(tool.inputSchema), "",
        "accepts a bounded input schema");
    assertEqual(McpSchema.validateToolArguments(tool, {
        name: "ephemera", count: 2, tags: ["qml"]
    }).valid, true, "accepts arguments matching the approved input schema");
    assertEqual(McpSchema.validateToolArguments(tool, {
        name: "ephemera", count: "2"
    }).valid, false, "rejects an argument with the wrong type");
    assertEqual(McpSchema.validateToolArguments(tool, {
        name: "ephemera", count: 2, hidden: true
    }).valid, false, "rejects undeclared arguments when additional properties are forbidden");
    assertEqual(McpSchema.validateToolArguments(tool, {
        name: "ephemera"
    }).valid, false, "rejects missing required arguments");
    assertEqual(McpSchema.validateToolArguments(tool, {
        name: "ephemera", count: 6
    }).valid, false, "rejects arguments outside numeric bounds");
    var permissiveTool = { name: "permissive", inputSchema: { type: "object" } };
    var cyclicArguments = {};
    cyclicArguments.self = cyclicArguments;
    assertEqual(McpSchema.validateToolArguments(permissiveTool, cyclicArguments).valid,
        false, "rejects cyclic arguments before serialization");
    assertEqual(McpSchema.validateToolArguments(permissiveTool, { value: NaN }).valid,
        false, "rejects non-JSON numeric arguments");
    assertEqual(McpSchema.validateToolArguments(permissiveTool, { value: undefined }).valid,
        false, "rejects values that JSON serialization would omit");
    assertEqual(McpSchema.validateToolArguments(permissiveTool, {
        value: { toJSON: function() { return "different"; } }
    }).valid, false, "rejects arguments whose JSON representation differs from review");
    assert(McpSchema.inputSchemaSupportError({
        type: "object",
        properties: { value: { "$ref": "https://attacker.example/input.json" } }
    }).length > 0, "rejects unresolved input schema references before tool exposure");
})();

section("McpSchema.validateToolResult");
(function() {
    var tool = {
        name: "lookup",
        inputSchema: { type: "object" },
        outputSchema: {
            type: "object",
            properties: {
                count: { type: "integer", minimum: 0 },
                labels: { type: "array", items: { type: "string" } }
            },
            required: ["count"],
            additionalProperties: false
        }
    };
    var valid = McpSchema.validateToolResult(tool, {
        content: [{ type: "text", text: "two" }],
        structuredContent: { count: 2, labels: ["a", "b"] }
    });
    assertEqual(valid.valid, true, "accepts structured output matching the advertised schema");
    assertEqual(McpSchema.validateToolResult(tool, {
        content: [{ type: "text", text: "bad" }],
        structuredContent: { count: "two" }
    }).valid, false, "rejects structured output with the wrong type");
    assertEqual(McpSchema.validateToolResult(tool, {
        content: [{ type: "text", text: "missing" }]
    }).valid, false, "rejects missing advertised structured output");
    assertEqual(McpSchema.validateToolResult({ name: "plain" }, {}).valid, false, "rejects a result without the required content array");
    assertEqual(McpSchema.validateToolResult({ name: "plain" }, {
        content: [],
        structuredContent: ["not", "an", "object"]
    }).valid, false, "rejects non-object structured output");
    assertEqual(McpSchema.validateToolResult({ name: "plain" }, {
        content: new Array(1025).fill({ type: "text", text: "" })
    }).valid, false, "rejects an excessive number of result content items");
    assertEqual(McpSchema.validateToolResult(tool, {
        content: [{ type: "script", text: "bad" }],
        structuredContent: { count: 1 }
    }).valid, false, "rejects unsupported MCP content types");
    var referencedTool = {
        name: "lookup_ref",
        inputSchema: { type: "object" },
        outputSchema: { "$ref": "https://attacker.example/schema.json" }
    };
    assertEqual(McpSchema.validateToolResult(referencedTool, {
        content: [],
        structuredContent: { count: 1 }
    }).valid, false, "fails closed on unresolved output schema references");
    var nestedReferenceTool = {
        name: "lookup_nested_ref",
        inputSchema: { type: "object" },
        outputSchema: {
            type: "object",
            properties: {
                optional: { "$ref": "https://attacker.example/optional.json" }
            }
        }
    };
    assert(McpSchema.outputSchemaSupportError(nestedReferenceTool.outputSchema).length > 0,
        "rejects unsupported schema references even when the property is absent");
    assertEqual(McpSchema.validateToolResult(nestedReferenceTool, {
        content: [],
        structuredContent: {}
    }).valid, false, "fails closed on an unvisited nested schema reference");
    assert(McpSchema.outputSchemaSupportError({
        type: "object",
        properties: { value: { enum: [{ nested: true }] } }
    }).length > 0, "rejects complex enum values that cannot be compared within a fixed budget");
    assertEqual(McpSchema.validateToolResult(tool, {
        isError: true,
        content: [{ type: "text", text: "failed" }]
    }).valid, true, "allows a well-formed error result without structured output");
})();

// ═════════════════════════════════════════════════════════════════
// VariantStore.js tests
// ═════════════════════════════════════════════════════════════════

section("VariantStore.saveVariant");

(function() {
    var store = {};
    var result = VariantStore.saveVariant(store, "msg1", 0, "hello", "thinking", "gpt-4", 10);
    assertEqual(result.evicted, 0, "no eviction on first save");
    assertEqual(result.store["msg1"][0].content, "hello", "content saved");
    assertEqual(result.store["msg1"][0].thinking, "thinking", "thinking saved");
    assertEqual(result.store["msg1"][0].modelName, "gpt-4", "modelName saved");
})();

(function() {
    var store = {};
    var idx = 0;
    for (var i = 0; i < 12; i++) {
        var result = VariantStore.saveVariant(store, "msg1", idx, "v" + i, "", "m" + i, 10);
        idx = Math.max(0, idx - result.evicted) + 1;
    }
    assertEqual(store["msg1"].length, 10, "capped at maxVariants");
    assertEqual(store["msg1"][0].content, "v2", "FIFO eviction removes oldest");
})();

(function() {
    var store = {};
    VariantStore.saveVariant(store, "msg1", 0, "a", "", "", 10);
    VariantStore.saveVariant(store, "msg1", 1, "b", "", "", 10);
    var result = VariantStore.saveVariant(store, "msg1", 0, "updated", "", "", 10);
    assertEqual(result.store["msg1"][0].content, "updated", "overwrite existing variant");
    assertEqual(result.evicted, 0, "no eviction on overwrite");
})();

section("VariantStore.getVariant");

(function() {
    var store = {};
    VariantStore.saveVariant(store, "msg1", 0, "content", "think", "model", 10);
    var v = VariantStore.getVariant(store, "msg1", 0);
    assertEqual(v.content, "content", "gets correct variant");
    assertEqual(v.thinking, "think", "gets thinking");
    assertEqual(v.modelName, "model", "gets model name");

    var missing = VariantStore.getVariant(store, "msg1", 5);
    assertEqual(missing, null, "returns null for missing index");

    var missingMsg = VariantStore.getVariant(store, "noMsg", 0);
    assertEqual(missingMsg, null, "returns null for missing msgId");
})();

section("VariantStore.removeVariants");

(function() {
    var store = {};
    VariantStore.saveVariant(store, "msg1", 0, "a", "", "", 10);
    VariantStore.saveVariant(store, "msg2", 0, "b", "", "", 10);
    VariantStore.removeVariants(store, "msg1");
    assertEqual(store["msg1"], undefined, "removes variants for msgId");
    assertEqual(store["msg2"][0].content, "b", "preserves other messages");
})();

section("VariantStore.adjustAfterEviction");

(function() {
    var adj = VariantStore.adjustAfterEviction(2, 5, 8, false);
    assertEqual(adj.variantIndex, 3, "adjusts index by eviction count");
    assertEqual(adj.variantCount, 8, "count equals store length when not streaming");

    adj = VariantStore.adjustAfterEviction(2, 5, 8, true);
    assertEqual(adj.variantCount, 9, "count includes streaming variant");

    adj = VariantStore.adjustAfterEviction(5, 3, 2, false);
    assertEqual(adj.variantIndex, 0, "clamps to 0 when eviction exceeds index");
})();

// ═════════════════════════════════════════════════════════════════
// ErrorHints.js tests
// ═════════════════════════════════════════════════════════════════

section("ErrorHints.httpErrorHint");

(function() {
    assert(ErrorHints.httpErrorHint(401).indexOf("API key") >= 0, "401 mentions API key");
    assert(ErrorHints.httpErrorHint(403).indexOf("denied") >= 0, "403 mentions denied");
    assert(ErrorHints.httpErrorHint(404).indexOf("not found") >= 0, "404 mentions not found");
    assert(ErrorHints.httpErrorHint(429).indexOf("Rate limited") >= 0, "429 mentions rate limited");
    assert(ErrorHints.httpErrorHint(500).indexOf("Server error") >= 0, "500 mentions server error");
    assert(ErrorHints.httpErrorHint(503).indexOf("unavailable") >= 0, "503 mentions unavailable");
    assertEqual(ErrorHints.httpErrorHint(200), "", "200 returns empty string");
    assertEqual(ErrorHints.httpErrorHint(999), "", "unknown status returns empty");
})();

section("ErrorHints.curlExitHint");

(function() {
    var h = ErrorHints.curlExitHint(6, "openai", "OpenAI", "");
    assert(h.indexOf("resolve host") >= 0, "exit 6 mentions DNS");

    h = ErrorHints.curlExitHint(7, "ollama", "Ollama", "http://localhost:11434");
    assert(h.indexOf("Ollama") >= 0, "exit 7 ollama mentions Ollama");
    assert(h.indexOf("11434") >= 0, "exit 7 ollama includes URL");

    h = ErrorHints.curlExitHint(7, "openai", "OpenAI", "");
    assert(h.indexOf("OpenAI") >= 0, "exit 7 non-ollama mentions provider name");

    h = ErrorHints.curlExitHint(28, "openai", "OpenAI", "");
    assert(h.indexOf("timed out") >= 0, "exit 28 mentions timeout");

    h = ErrorHints.curlExitHint(35, "openai", "OpenAI", "");
    assert(h.indexOf("TLS") >= 0, "exit 35 mentions TLS");

    h = ErrorHints.curlExitHint(99, "openai", "OpenAI", "");
    assert(h.indexOf("99") >= 0, "unknown exit code included in message");
})();

// ═════════════════════════════════════════════════════════════════
// Providers.validateUrl tests
// ═════════════════════════════════════════════════════════════════

section("Providers.validateUrl");

(function() {
    var r = Providers.validateUrl("https://api.openai.com");
    assert(r.valid, "valid https URL");
    assertEqual(r.error, "", "no error for valid URL");

    r = Providers.validateUrl("http://localhost:11434");
    assert(r.valid, "valid http localhost URL");

    r = Providers.validateUrl("https://api.openai.com/v1");
    assert(r.valid, "valid URL with path");

    r = Providers.validateUrl("http://192.168.1.1:8000");
    assert(r.valid, "valid URL with IP and port");

    r = Providers.validateUrl("ftp://example.com");
    assert(!r.valid, "rejects ftp scheme");
    assert(r.error.indexOf("http://") >= 0, "error mentions http");

    r = Providers.validateUrl("");
    assert(!r.valid, "empty is invalid");
    assertEqual(r.error, "", "empty has no error message");

    r = Providers.validateUrl("https://" + "a".repeat(2050));
    assert(!r.valid, "rejects too-long URL");
    assert(r.error.indexOf("2048") >= 0, "error mentions limit");

    r = Providers.validateUrl("https://!@#$");
    assert(!r.valid, "rejects invalid hostname");

    // Path injection / unsafe character tests
    r = Providers.validateUrl("http://localhost:11434/<script>alert(1)</script>");
    assert(!r.valid, "rejects angle brackets in URL");

    r = Providers.validateUrl("http://example.com/path with spaces");
    assert(!r.valid, "rejects spaces in URL");

    r = Providers.validateUrl('http://example.com/"quoted"');
    assert(!r.valid, "rejects double quotes in URL");

    r = Providers.validateUrl("http://example.com/'quoted'");
    assert(!r.valid, "rejects single quotes in URL");

    r = Providers.validateUrl("http://example.com/`backtick`");
    assert(!r.valid, "rejects backticks in URL");

    r = Providers.validateUrl("http://example.com/{braces}");
    assert(!r.valid, "rejects curly braces in URL");

    r = Providers.validateUrl("http://example.com/path|pipe");
    assert(!r.valid, "rejects pipe character in URL");

    r = Providers.validateUrl("http://example.com/path\\backslash");
    assert(!r.valid, "rejects backslash in URL");

    r = Providers.validateUrl("https://example.com/safe\u202eevil");
    assert(!r.valid, "rejects bidirectional controls in URL paths");

    r = Providers.validateUrl("https://example.com/safe\u200bevil");
    assert(!r.valid, "rejects invisible controls in URL paths");

    r = Providers.validateUrl("https://example.com/safe\u2028evil");
    assert(!r.valid, "rejects Unicode line separators in URL paths");

    r = Providers.validateUrl("https://example.com/safe\u0085evil");
    assert(!r.valid, "rejects C1 controls in URL paths");

    var invisibleUrlCodePoints = [
        { value: "\u3164", label: "Hangul filler" },
        { value: "\uffa0", label: "halfwidth Hangul filler" },
        { value: "\ufe0f", label: "BMP variation selector" },
        { value: "\ud834\udd73", label: "musical formatting control" },
        { value: "\udb40\udc01", label: "language tag" },
        { value: "\udb40\udd00", label: "supplementary variation selector" },
        { value: "\ud800", label: "unpaired surrogate" }
    ];
    for (var ui = 0; ui < invisibleUrlCodePoints.length; ui++) {
        var unsafeUrl = invisibleUrlCodePoints[ui];
        r = Providers.validateUrl("https://example.com/before" + unsafeUrl.value + "after");
        assert(!r.valid, "rejects " + unsafeUrl.label + " in URL paths");
    }

    r = Providers.validateUrl("http://example.com/ok-path_name.ext/v2");
    assert(r.valid, "allows safe path characters (hyphens, underscores, dots)");

    // Hostname must start with alphanumeric
    r = Providers.validateUrl("http://.:8080");
    assert(!r.valid, "rejects dot-only hostname");

    r = Providers.validateUrl("http://:8080");
    assert(!r.valid, "rejects empty hostname with port");

    r = Providers.validateUrl("http://-bad.example.com");
    assert(!r.valid, "rejects hostname starting with hyphen");
})();

// ═════════════════════════════════════════════════════════════════
// Backoff.js tests
// ═════════════════════════════════════════════════════════════════

var Backoff = loadPragmaLib("src/lib/Backoff.js");

section("Backoff.computeDelay");

(function() {
    // Run multiple times to verify range with jitter
    for (var i = 0; i < 20; i++) {
        var d = Backoff.computeDelay(0, 2000, 30000);
        assert(d >= 1000, "attempt 0: delay >= floor (1000ms), got " + d.toFixed(0));
        assert(d <= 2000, "attempt 0: delay <= base (2000ms), got " + d.toFixed(0));
    }

    for (var j = 0; j < 20; j++) {
        var d2 = Backoff.computeDelay(2, 2000, 30000);
        assert(d2 >= 1000, "attempt 2: delay >= floor, got " + d2.toFixed(0));
        assert(d2 <= 8000, "attempt 2: delay <= 8000ms (2000*2^2), got " + d2.toFixed(0));
    }

    // Cap at maxDelay
    for (var k = 0; k < 20; k++) {
        var d3 = Backoff.computeDelay(10, 2000, 30000);
        assert(d3 >= 1000, "attempt 10: delay >= floor, got " + d3.toFixed(0));
        assert(d3 <= 30000, "attempt 10: delay <= maxDelay (30000ms), got " + d3.toFixed(0));
    }

    // Default parameters
    var d4 = Backoff.computeDelay(0);
    assert(d4 >= 1000 && d4 <= 2000, "defaults: delay in [1000, 2000]");

    // Zero/null attempt
    var d5 = Backoff.computeDelay(null, 2000, 30000);
    assert(d5 >= 1000 && d5 <= 2000, "null attempt treated as 0");
})();

section("Backoff.computeCooldownUntil");

(function() {
    // No errors — no cooldown
    assert(Backoff.computeCooldownUntil(0) === 0, "no cooldown when consecutiveErrors is 0");

    // Cooldown should be in the future
    var until = Backoff.computeCooldownUntil(1, 2000, 30000);
    assert(until > Date.now(), "cooldown until is in the future after error");
    assert(until <= Date.now() + 2000, "cooldown until is at most base delay in the future for 1 error");

    // Higher consecutive errors produce longer cooldowns (up to max)
    var until5 = Backoff.computeCooldownUntil(5, 2000, 30000);
    assert(until5 > Date.now(), "cooldown until is in the future for 5 errors");
    assert(until5 <= Date.now() + 30000, "cooldown until is at most maxDelay in the future");
})();

section("Backoff.isInCooldown");

(function() {
    // No cooldown
    assert(!Backoff.isInCooldown(0), "no cooldown when cooldownUntil is 0");

    // Cooldown in the future — should be active
    assert(Backoff.isInCooldown(Date.now() + 5000), "in cooldown when cooldownUntil is in the future");

    // Cooldown in the past — should NOT be active
    assert(!Backoff.isInCooldown(Date.now() - 1000), "not in cooldown when cooldownUntil is in the past");
})();

section("Backoff.maxDelayForAttempt");

(function() {
    assertEqual(Backoff.maxDelayForAttempt(0), 0, "0 errors = 0 delay");
    assertEqual(Backoff.maxDelayForAttempt(1, 2000, 30000), 2000, "1 error = base delay");
    assertEqual(Backoff.maxDelayForAttempt(2, 2000, 30000), 4000, "2 errors = 2x base");
    assertEqual(Backoff.maxDelayForAttempt(3, 2000, 30000), 8000, "3 errors = 4x base");
    assertEqual(Backoff.maxDelayForAttempt(4, 2000, 30000), 16000, "4 errors = 8x base");
    assertEqual(Backoff.maxDelayForAttempt(5, 2000, 30000), 30000, "5 errors = capped at max");
    assertEqual(Backoff.maxDelayForAttempt(10, 2000, 30000), 30000, "10 errors = still capped");
})();

// ═════════════════════════════════════════════════════════════════
// Providers.getModelList tests
// ═════════════════════════════════════════════════════════════════

section("Providers.getModelList");

(function() {
    var openai = Providers.getModelList("openai");
    assert(Array.isArray(openai), "openai returns an array");
    assert(openai.length > 0, "openai has models");
    assert(openai.indexOf("gpt-5.4") >= 0, "openai includes gpt-5.4");

    var anthropic = Providers.getModelList("anthropic");
    assert(Array.isArray(anthropic), "anthropic returns an array");
    assert(anthropic.length > 0, "anthropic has models");
    assert(anthropic.indexOf("claude-sonnet-4-6") >= 0, "anthropic includes claude-sonnet-4-6");

    var gemini = Providers.getModelList("gemini");
    assert(Array.isArray(gemini), "gemini returns an array");
    assert(gemini.length > 0, "gemini has models");
    assert(gemini.indexOf("gemini-2.5-flash") >= 0, "gemini includes gemini-2.5-flash");

    var ollama = Providers.getModelList("ollama");
    assert(Array.isArray(ollama), "ollama returns an array");
    assertEqual(ollama.length, 0, "ollama has no hardcoded models");

    var custom = Providers.getModelList("custom");
    assert(Array.isArray(custom), "custom returns an array");
    assertEqual(custom.length, 0, "custom has no hardcoded models");

    var unknown = Providers.getModelList("nonexistent");
    assert(Array.isArray(unknown), "unknown provider returns an array");
    assertEqual(unknown.length, 0, "unknown provider has no models");
})();

// ═════════════════════════════════════════════════════════════════
// EphemeraPanel side-switch regression tests
// ═════════════════════════════════════════════════════════════════

section("EphemeraPanel rapid side switching");

(function() {
    var panelSource = fs.readFileSync(
        path.join(__dirname, "..", "src/components/EphemeraPanel.qml"),
        "utf8"
    );
    var functionMatch = panelSource.match(
        /function _syncWindowEdge\(\) \{([\s\S]*?)\n    \}\n\n    visible:/
    );
    assert(!!functionMatch, "window edge synchronizer remains testable");
    if (!functionMatch) return;

    var runEdgeSync = new Function("root", "panelOnLeft", functionMatch[1]);
    var left = false;
    var right = true;
    var exposedOppositeEdges = false;
    var anchors = {};

    function recordAnchorState() {
        if (left && right) exposedOppositeEdges = true;
    }

    Object.defineProperties(anchors, {
        left: {
            get: function() { return left; },
            set: function(value) { left = value; recordAnchorState(); }
        },
        right: {
            get: function() { return right; },
            set: function(value) { right = value; recordAnchorState(); }
        }
    });

    for (var i = 0; i < 40; i++) {
        var panelOnLeft = i % 2 === 0;
        runEdgeSync({ anchors: anchors }, panelOnLeft);
        assert(
            left === panelOnLeft && right === !panelOnLeft,
            "toggle " + (i + 1) + " selects exactly one layer-shell edge"
        );
    }

    assert(!exposedOppositeEdges, "40 rapid toggles never expose both horizontal edges");
    assert(
        panelSource.indexOf("onPanelOnLeftChanged: _syncWindowEdge()") >= 0
            && panelSource.indexOf("Component.onCompleted: _syncWindowEdge()") >= 0,
        "side changes and initial construction both synchronize the layer-shell edge"
    );
    assert(
        panelSource.indexOf("x: root.panelOnLeft ? 0 : parent.width - width") >= 0,
        "slide position uses x instead of conditional horizontal anchors"
    );
    assert(
        panelSource.indexOf("x: slide.x + layeredContent.x") >= 0
            && panelSource.indexOf("width: slide.width") >= 0,
        "input mask follows the animated slide geometry"
    );
})();

// ═════════════════════════════════════════════════════════════════
// ChatHeader tooltip coverage
// ═════════════════════════════════════════════════════════════════

section("ChatHeader action tooltips");

(function() {
    var headerSource = fs.readFileSync(
        path.join(__dirname, "..", "src/components/ChatHeader.qml"),
        "utf8"
    );
    var actionSource = fs.readFileSync(
        path.join(__dirname, "..", "src/components/EphemeraActionButton.qml"),
        "utf8"
    );

    var headerActions = headerSource.match(/\bEphemeraActionButton\s*\{/g) || [];
    var tooltipBindings = headerSource.match(/\btooltipText\s*:/g) || [];
    var availabilityBindings = headerSource.match(/\bactionEnabled\s*:/g) || [];

    assertEqual(headerActions.length, 8, "every header action uses the tooltip-safe wrapper");
    assertEqual(tooltipBindings.length, 8, "every header action declares tooltip text");
    assertEqual(availabilityBindings.length, 3, "conversation actions preserve disabled click state");
    assert(
        actionSource.indexOf("enabled: root.actionEnabled") >= 0
            && actionSource.indexOf("HoverHandler {") >= 0
            && actionSource.indexOf("tooltip.show(root.tooltipText, root") >= 0,
        "disabled actions retain an independent hover tooltip path"
    );

    [
        "Settings", "Copy conversation", "Save conversation as .md",
        "Clear chat", "More actions", "Collapse", "Move to right", "Close"
    ].forEach(function(label) {
        assert(headerSource.indexOf(label) >= 0,
            "header exposes tooltip label: " + label);
    });
})();

section("Ollama process identity");

(function() {
    var managerSource = fs.readFileSync(
        path.join(__dirname, "..", "src/services/OllamaManager.qml"),
        "utf8"
    );
    assert(
        managerSource.indexOf("_ollamaPid = ollamaProcess.processId") >= 0,
        "Ollama shutdown tracks Quickshell's current processId property"
    );
    assert(
        managerSource.indexOf("ollamaProcess.pid") < 0,
        "Ollama manager does not read the obsolete undefined pid property"
    );
})();

// ─── Summary ───────────────────────────────────────────────────

console.log("\n" + "=".repeat(50));
console.log("Results: " + passed + " passed, " + failed + " failed");
console.log("=".repeat(50));

process.exit(failed > 0 ? 1 : 0);
