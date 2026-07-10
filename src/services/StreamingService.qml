import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/StreamParser.js" as StreamParser
import "../lib/ErrorHints.js" as ErrorHints
import "../lib/Backoff.js" as Backoff
import "../lib/Providers.js" as Providers
import "../lib/Mcp.js" as Mcp
import "../lib/McpSchema.js" as McpSchema

Item {
    id: root

    // --- Input from coordinator ---
    property string provider: "ollama"
    property string ollamaUrl: "http://localhost:11434"
    property int timeout: 300

    // --- Streaming state ---
    property bool isStreaming: false
    property string activeStreamId: ""
    property string _activeProvider: ""
    property int _streamGeneration: 0
    property string streamBuffer: ""
    property string pendingStdinBody: ""
    property var _pendingLaunch: null
    property string _fetchStreamId: ""
    property string _fetchProvider: ""
    property int _fetchGeneration: -1
    property string _fetchOutput: ""
    property bool _processActive: false
    property real streamStartTime: 0
    property int streamTokenCount: 0
    property int _apiOutputTokens: 0
    property bool _insideThinkTag: false
    property string _tagBuffer: ""
    property string _streamContent: ""
    property string _streamThinking: ""
    property string _roundContent: ""
    property string _roundThinking: ""
    property int _streamVariantIndex: 0
    property string _lastFinalizedStreamId: ""
    property string _completedFetchStreamId: ""
    property string _completedFetchProvider: ""
    property int _completedFetchGeneration: -1
    property bool _seenToolCalls: false
    property var _pendingToolCalls: []
    property var _allToolCalls: []
    property var _toolResults: []
    property bool mcpConnected: false
    property var mcpTools: []
    property bool toolCallsAllowed: false
    property var approvedToolContracts: []
    property var _conversationMessages: []
    property int _pendingCallId: -1
    property var _pendingToolCallMeta: null
    property var _pendingApprovalToolCall: null
    property string _pendingApprovalToolName: ""
    property string _pendingApprovalToolDescription: ""
    property var _pendingApprovalToolArgs: ({})
    property string _pendingApprovalToolArgumentsText: ""
    property int _toolRoundCount: 0
    readonly property int _maxToolRounds: 4
    readonly property int _maxToolCallsPerRound: 16
    readonly property int _maxToolResultChars: 20000
    readonly property int _maxToolArgumentChars: 20000
    readonly property int _toolCallTimeoutMs: 30000
    readonly property bool toolApprovalPending: _pendingApprovalToolCall !== null
    readonly property string pendingToolName: _pendingApprovalToolName
    readonly property string pendingToolDescription: _pendingApprovalToolDescription
    readonly property string pendingToolArgumentsText: _pendingApprovalToolArgumentsText
    readonly property bool transportBusy: _processActive
    readonly property string streamPhase: {
        if (!isStreaming) return "idle";
        if (toolApprovalPending) return "awaiting-approval";
        if (_pendingCallId >= 0) return "executing-tool";
        if (_pendingLaunch) return "queued";
        if (_fetchMatchesActiveStream()) return "fetching";
        return "preparing";
    }
    property int lastHttpStatus: 0
    property bool lastRequestFailed: false

    // --- Error backoff state ---
    property real _cooldownUntil: 0
    property int _consecutiveErrors: 0
    readonly property int _backoffBaseMs: 2000
    readonly property int _backoffMaxMs: 30000

    // --- Export state ---
    property string exportPendingBody: ""
    property string lastExportedFile: ""

    // --- Signals to coordinator ---
    signal streamContentUpdated(string streamId, string deltaText)
    signal streamThinkingUpdated(string streamId, string deltaText)
    signal streamFinalized(string streamId, string stats)
    signal streamError(string streamId, string message)
    signal streamCancelled(string streamId, string stats)
    signal streamToolRoundReady(string streamId, var messages, string streamProvider, int streamGeneration)
    signal mcpToolCallRequested(string toolName, var toolArguments, var approvedContracts,
                                string streamId, string streamProvider, int streamGeneration)
    signal mcpToolCallCancellationRequested(var callId, string reason)

    // --- Public API ---

    function isInErrorCooldown() {
        return Backoff.isInCooldown(_cooldownUntil);
    }

    function resetErrorState() {
        _cooldownUntil = 0;
        _consecutiveErrors = 0;
    }

    function activeStreamContext() {
        return {
            streamId: activeStreamId,
            provider: _activeProvider,
            generation: _streamGeneration
        };
    }

    function matchesActiveStream(streamId, streamProvider, streamGeneration) {
        return isStreaming
            && activeStreamId === streamId
            && _activeProvider === streamProvider
            && _streamGeneration === streamGeneration;
    }

    function launchCurl(curlResult, messages, streamId, streamProvider, streamGeneration) {
        if (!curlResult
                || !matchesActiveStream(streamId, streamProvider, streamGeneration))
            return false;

        var launch = {
            curlResult: curlResult,
            messages: messages,
            streamId: streamId,
            provider: streamProvider,
            generation: streamGeneration
        };
        if (_processActive) {
            // Process.running=false requests termination asynchronously. Keep
            // exactly one identity-bound launch queued until onExited.
            _pendingLaunch = launch;
            chatFetcher.running = false;
            return true;
        }
        return _startCurl(launch);
    }

    function _startCurl(launch) {
        if (!launch || !matchesActiveStream(
                launch.streamId, launch.provider, launch.generation))
            return false;
        if (_processActive) {
            _pendingLaunch = launch;
            chatFetcher.running = false;
            return true;
        }

        _pendingLaunch = null;
        _fetchStreamId = launch.streamId;
        _fetchProvider = launch.provider;
        _fetchGeneration = launch.generation;
        // StdioCollector exposes a fresh process buffer after the first read,
        // but may still expose the prior text when a new process emits no
        // output. Parse deltas from zero and keep a launch-local completion
        // buffer so zero-output runs cannot replay the prior response.
        streamCollector.lastLen = 0;
        _fetchOutput = "";
        streamBuffer = "";
        _insideThinkTag = false;
        _tagBuffer = "";
        _roundContent = "";
        _roundThinking = "";
        if (launch.messages)
            _conversationMessages = launch.messages;
        pendingStdinBody = launch.curlResult.body;
        chatFetcher.stdinEnabled = true;
        chatFetcher.command = launch.curlResult.cmd;
        _processActive = true;
        chatFetcher.running = true;
        return true;
    }

    function _fetchMatchesActiveStream() {
        return matchesActiveStream(
            _fetchStreamId, _fetchProvider, _fetchGeneration);
    }

    function _fetchMatchesFinalizedStream() {
        return !isStreaming
            && _fetchStreamId.length > 0
            && _fetchStreamId === _completedFetchStreamId
            && _fetchProvider === _completedFetchProvider
            && _fetchGeneration === _completedFetchGeneration;
    }

    function _finishCurlProcess(exitCode, failedToStart) {
        if (!_processActive)
            return;

        var fetchStreamId = _fetchStreamId;
        var fetchMatches = _fetchMatchesActiveStream();
        var queued = _pendingLaunch;
        _processActive = false;
        _pendingLaunch = null;
        _fetchStreamId = "";
        _fetchProvider = "";
        _fetchGeneration = -1;

        if (queued && _startCurl(queued))
            return;
        if (!fetchMatches)
            return;
        if (failedToStart) {
            _markError(fetchStreamId,
                "Could not start the response process. Make sure curl is installed and available in PATH.");
        } else if (exitCode !== 0) {
            _markError(fetchStreamId, _curlExitHint(exitCode));
        }
    }

    function failActiveStream(message, streamId, streamProvider, streamGeneration) {
        if (!matchesActiveStream(streamId, streamProvider, streamGeneration))
            return false;
        _markError(streamId, message);
        return true;
    }

    function cancel() {
        if (!isStreaming) return;
        var streamId = activeStreamId;

        // Flush any remaining tag buffer before clearing state
        if (_tagBuffer.length > 0) {
            if (_insideThinkTag)
                _applyModelThinkingDelta(streamId, _tagBuffer);
            else
                _applyModelContentDelta(streamId, _tagBuffer);
            _tagBuffer = "";
        }
        _insideThinkTag = false;
        isStreaming = false;
        _clearToolState(true, "Stream cancelled.");
        _pendingLaunch = null;

        streamCancelled(streamId, _buildStreamStats());
        chatFetcher.running = false;
        activeStreamId = "";
        _activeProvider = "";
    }

    function approvePendingToolCall() {
        if (!toolApprovalPending || !isStreaming)
            return false;
        var toolName = _pendingApprovalToolName;
        var toolArgs = _pendingApprovalToolArgs;
        _clearPendingToolApproval();
        _invokeToolCall(toolName, toolArgs);
        return true;
    }

    function rejectPendingToolCall(reason) {
        if (!toolApprovalPending || !isStreaming)
            return false;
        var toolName = _pendingApprovalToolName;
        var message = reason || "Tool call rejected by user.";
        _appendToolAudit(activeStreamId, "Tool rejected: " + toolName + "\n");
        _recordToolResult(toolName, "Error: " + message);
        _clearPendingToolApproval();
        _executeNextToolCall();
        return true;
    }

    function reset() {
        if (chatFetcher.running)
            chatFetcher.running = false;
        isStreaming = false;
        activeStreamId = "";
        _activeProvider = "";
        streamStartTime = 0;
        streamTokenCount = 0;
        _apiOutputTokens = 0;
        _streamContent = "";
        _streamThinking = "";
        _roundContent = "";
        _roundThinking = "";
        _insideThinkTag = false;
        _tagBuffer = "";
        _clearToolState(true, "Stream reset.");
        streamBuffer = "";
        pendingStdinBody = "";
        _pendingLaunch = null;
        _lastFinalizedStreamId = "";
        _completedFetchStreamId = "";
        _completedFetchProvider = "";
        _completedFetchGeneration = -1;
    }

    function beginStream(streamId, variantIndex, messages) {
        _streamGeneration++;
        activeStreamId = streamId;
        _activeProvider = provider;
        isStreaming = true;
        streamStartTime = 0;
        streamTokenCount = 0;
        lastHttpStatus = 0;
        lastRequestFailed = false;
        _streamContent = "";
        _streamThinking = "";
        _roundContent = "";
        _roundThinking = "";
        _apiOutputTokens = 0;
        _streamVariantIndex = variantIndex;
        _completedFetchStreamId = "";
        _completedFetchProvider = "";
        _completedFetchGeneration = -1;
        _clearToolState(false, "");
        _conversationMessages = messages || [];
        _pendingLaunch = null;
    }

    onProviderChanged: {
        if (isStreaming && _activeProvider && provider !== _activeProvider)
            cancel();
    }

    function exportToClipboard(markdownText) {
        Quickshell.execDetached(["wl-copy", "--", markdownText]);
    }

    function exportToFile(markdownText, homeDir, filename) {
        // install -m 0600 sets restrictive permissions (owner-only read/write)
        exportFileWriter.command = ["install", "-m", "0600", "/dev/stdin", filename];
        exportPendingBody = markdownText;
        exportFileWriter.stdinEnabled = true;
        exportFileWriter.running = true;
    }

    // --- Internal: stream processing ---
    function handleStreamChunk(chunk) {
        var result = StreamParser.splitLines(chunk, streamBuffer);
        streamBuffer = result.buffer;

        for (var i = 0; i < result.lines.length; i++) {
            var line = result.lines[i];

            if (line === "data: [DONE]" || line === "data:[DONE]") {
                if (_pendingToolCalls.length === 0)
                    _finalizeStream(activeStreamId);
                continue;
            }

            var jsonPart;
            if (line.startsWith("data:")) {
                jsonPart = line.substring(5).trim();
            } else if (line.startsWith("{")) {
                jsonPart = line;
            } else {
                continue;
            }

            var delta = StreamParser.parseDelta(jsonPart, _activeProvider);

            if (delta.outputTokens > 0)
                _apiOutputTokens = delta.outputTokens;

            if (delta.toolCalls && delta.toolCalls.length > 0) {
                if (_allToolCalls.length + delta.toolCalls.length > _maxToolCallsPerRound) {
                    chatFetcher.running = false;
                    _markError(activeStreamId, "MCP tool call limit exceeded for one model turn.");
                    return;
                }
                _seenToolCalls = true;
                for (var tci = 0; tci < delta.toolCalls.length; tci++) {
                    _pendingToolCalls.push(delta.toolCalls[tci]);
                    _allToolCalls.push(delta.toolCalls[tci]);
                }
            }
            if (delta.thinking) {
                streamTokenCount++;
                _applyModelThinkingDelta(activeStreamId, delta.thinking);
            }
            if (delta.content) {
                streamTokenCount++;
                if (!Providers.getProviderInfo(_activeProvider).hasNativeThinking) {
                    var tagResult = StreamParser.routeThinkTags(delta.content, _tagBuffer, _insideThinkTag);
                    _tagBuffer = tagResult.tagBuffer;
                    _insideThinkTag = tagResult.insideThinkTag;
                    for (var ti = 0; ti < tagResult.thinkingParts.length; ti++)
                        _applyModelThinkingDelta(activeStreamId, tagResult.thinkingParts[ti]);
                    for (var ci = 0; ci < tagResult.contentParts.length; ci++)
                        _applyModelContentDelta(activeStreamId, tagResult.contentParts[ci]);
                } else {
                    _applyModelContentDelta(activeStreamId, delta.content);
                }
            }
            if (delta.done) {
                if (_pendingToolCalls.length === 0)
                    _finalizeStream(activeStreamId);
            }
        }
    }

    function _truncateToolResult(text) {
        if (!text || text.length <= _maxToolResultChars)
            return text || "";
        return text.substring(0, _maxToolResultChars) + "\n\n[Tool result truncated]";
    }

    function _recordToolResult(toolName, content) {
        _toolResults.push({
            role: "tool",
            tool_name: toolName,
            content: _truncateToolResult(content)
        });
    }

    function _clearToolState(cancelPending, reason) {
        if (cancelPending && _pendingCallId >= 0)
            mcpToolCallCancellationRequested(_pendingCallId, reason || "Tool call cancelled.");
        _clearPendingToolApproval();
        _seenToolCalls = false;
        _pendingToolCalls = [];
        _allToolCalls = [];
        _toolResults = [];
        _toolRoundCount = 0;
        _pendingCallId = -1;
        _pendingToolCallMeta = null;
        toolCallTimer.stop();
    }

    function _clearPendingToolApproval() {
        _pendingApprovalToolCall = null;
        _pendingApprovalToolName = "";
        _pendingApprovalToolDescription = "";
        _pendingApprovalToolArgs = ({});
        _pendingApprovalToolArgumentsText = "";
    }

    function handleStreamFinished(text) {
        var parsed = StreamParser.extractHttpStatus(text);
        lastHttpStatus = parsed.status;
        var bodyText = parsed.body;

        if (isStreaming) {
            if (_roundContent.length === 0 && bodyText && lastHttpStatus > 0 && lastHttpStatus < 400) {
                var fallback = StreamParser.extractNonStreamingText(bodyText, _activeProvider);
                if (fallback && fallback.length > 0)
                    _applyModelContentDelta(activeStreamId, fallback);
            }
        }

        if (lastHttpStatus >= 400 && isStreaming) {
            var preview = bodyText.length > 600 ? bodyText.slice(0, 600) + "\u2026" : bodyText;
            var hint = ErrorHints.httpErrorHint(lastHttpStatus);
            var msg = "Request failed (HTTP " + lastHttpStatus + ")";
            if (hint) msg += "\n" + hint;
            if (preview) msg += "\n\n" + preview;
            _markError(activeStreamId, msg);
            return;
        }

        if (_pendingToolCalls.length > 0) {
            _beginToolRound();
            return;
        }

        if (isStreaming && !_seenToolCalls) {
            if (lastHttpStatus === 0 && _roundContent.length === 0) {
                var providerName = _providerDisplayName();
                var connMsg = _activeProvider === "ollama"
                    ? "Could not connect to Ollama.\nMake sure Ollama is running at " + ollamaUrl + "."
                    : "Could not connect to " + providerName + ".\nCheck your network connection and provider settings.";
                _markError(activeStreamId, connMsg);
                return;
            }
            _finalizeStream(activeStreamId);
        }
    }

    function _beginToolRound() {
        if (_toolRoundCount >= _maxToolRounds) {
            _markError(activeStreamId, "MCP tool call limit reached before another tool could run.");
            return;
        }
        _toolRoundCount++;
        _executeNextToolCall();
    }

    function _executeNextToolCall() {
        if (_pendingToolCalls.length === 0) {
            _resumeWithToolResults();
            return;
        }
        var toolCall = _pendingToolCalls.shift();
        var parsedCall = Mcp.parseToolCall(toolCall);
        if (!parsedCall.valid) {
            _markError(activeStreamId, "MCP tool call blocked. " + parsedCall.error);
            return;
        }
        var toolName = parsedCall.name;
        var rawToolArgs = parsedCall.arguments;
        var blockMessage = _toolPermissionBlockMessage(toolName);
        if (blockMessage) {
            _markError(activeStreamId, blockMessage);
            return;
        }
        var validation = _validateToolArguments(toolName, rawToolArgs);
        if (!validation.valid) {
            _markError(activeStreamId, validation.error);
            return;
        }
        _requestToolApproval(toolCall, toolName, validation.value, validation.text);
    }

    function _toolPermissionBlockMessage(toolName) {
        if (!toolCallsAllowed) {
            return "MCP tool call blocked. Enable model tool calls in MCP settings to let the model request tools.";
        }
        if (!mcpConnected) {
            return "MCP tool call blocked. MCP service is not connected.";
        }
        if (!Mcp.isToolApproved(Mcp.findTool(mcpTools, toolName), approvedToolContracts)) {
            return "MCP tool call blocked. The tool '" + toolName + "' is not approved in MCP settings.";
        }
        return "";
    }

    function _toolArgumentBlockMessage(toolName, argumentsText) {
        if (argumentsText.length <= _maxToolArgumentChars)
            return "";
        return "MCP tool call blocked. The arguments for '" + toolName + "' are too large to review safely.";
    }

    function _validateToolArguments(toolName, rawArguments) {
        var rawText = Mcp.formatToolArguments(rawArguments, 0);
        var sizeError = _toolArgumentBlockMessage(toolName, rawText);
        if (sizeError)
            return { valid: false, value: {}, text: "", error: sizeError };

        var parsed = Mcp.parseToolArguments(rawArguments);
        if (!parsed.valid) {
            return {
                valid: false,
                value: {},
                text: "",
                error: "MCP tool call blocked. Invalid arguments for '" + toolName + "': " + parsed.error
            };
        }

        var text = Mcp.formatToolArguments(parsed.value, 0);
        sizeError = _toolArgumentBlockMessage(toolName, text);
        if (sizeError)
            return { valid: false, value: {}, text: "", error: sizeError };

        var schemaValidation = McpSchema.validateToolArguments(
            Mcp.findTool(mcpTools, toolName), parsed.value);
        if (!schemaValidation.valid) {
            return {
                valid: false,
                value: {},
                text: "",
                error: "MCP tool call blocked. " + schemaValidation.error
            };
        }
        return { valid: true, value: parsed.value, text: text, error: "" };
    }

    function _requestToolApproval(toolCall, toolName, toolArgs, argumentsText) {
        _pendingApprovalToolCall = toolCall;
        _pendingApprovalToolName = toolName;
        var tool = Mcp.findTool(mcpTools, toolName);
        _pendingApprovalToolDescription = tool
            ? Mcp.formatReviewText(tool.description || tool.title || "") : "";
        _pendingApprovalToolArgs = toolArgs || {};
        _pendingApprovalToolArgumentsText = argumentsText || Mcp.formatToolArguments(toolArgs, 0);
        _appendToolAudit(activeStreamId, "\nTool request awaiting approval: " + toolName + "\n");
    }

    function _invokeToolCall(toolName, toolArgs) {
        var blockMessage = _toolPermissionBlockMessage(toolName);
        if (blockMessage) {
            _markError(activeStreamId, blockMessage);
            return;
        }
        var validation = _validateToolArguments(toolName, toolArgs);
        if (!validation.valid) {
            _markError(activeStreamId, validation.error);
            return;
        }
        toolArgs = validation.value;
        _appendToolAudit(activeStreamId, "\nCalling tool: " + toolName + "\n");
        _pendingToolCallMeta = {
            name: toolName,
            streamId: activeStreamId,
            provider: _activeProvider,
            generation: _streamGeneration
        };
        _pendingCallId = -2;
        mcpToolCallRequested(toolName, toolArgs, approvedToolContracts,
                             activeStreamId, _activeProvider, _streamGeneration);
        if (_pendingCallId === -2) {
            _pendingCallId = -1;
            _pendingToolCallMeta = null;
            _markError(activeStreamId, "MCP tool execution handler is unavailable.");
        }
    }

    function toolCallStarted(toolName, callId) {
        if (!isStreaming) {
            if (callId >= 0)
                mcpToolCallCancellationRequested(callId, "Stream is no longer active.");
            return;
        }
        if (callId < 0) {
            _markError(activeStreamId, "MCP tool call was rejected by the execution boundary.");
            return;
        }
        if (!_pendingToolCallMeta
                || _pendingToolCallMeta.name !== toolName
                || !matchesActiveStream(_pendingToolCallMeta.streamId,
                                        _pendingToolCallMeta.provider,
                                        _pendingToolCallMeta.generation)) {
            if (callId >= 0)
                mcpToolCallCancellationRequested(callId, "Stream identity changed before tool execution.");
            _pendingCallId = -1;
            _pendingToolCallMeta = null;
            return;
        }
        _pendingCallId = callId;
        toolCallTimer.restart();
    }

    function _onToolCallCompleted(callId, result) {
        if (callId !== _pendingCallId) return;
        toolCallTimer.stop();
        _pendingCallId = -1;
        var resultText = (typeof result === "string") ? result : JSON.stringify(result);
        _appendToolAudit(activeStreamId, "Tool completed: " + _pendingToolCallMeta.name + "\n");
        _recordToolResult(_pendingToolCallMeta.name, resultText);
        _pendingToolCallMeta = null;
        _executeNextToolCall();
    }

    function _onToolCallFailed(callId, error) {
        if (callId !== _pendingCallId) return;
        toolCallTimer.stop();
        _pendingCallId = -1;
        _appendToolAudit(activeStreamId, "Tool failed: " + (_pendingToolCallMeta ? _pendingToolCallMeta.name : "unknown_tool") + "\n");
        _recordToolResult(_pendingToolCallMeta ? _pendingToolCallMeta.name : "unknown_tool", "Error: " + error);
        _pendingToolCallMeta = null;
        _executeNextToolCall();
    }

    function _resumeWithToolResults() {
        if (_toolResults.length === 0) { _finalizeStream(activeStreamId); return; }
        var updatedMessages = Mcp.buildToolResumeMessages(
            _conversationMessages,
            _roundContent,
            _roundThinking,
            _allToolCalls,
            _toolResults
        );
        _conversationMessages = updatedMessages;
        _toolResults = [];
        _seenToolCalls = false;
        _pendingToolCalls = [];
        _allToolCalls = [];
        streamToolRoundReady(activeStreamId, updatedMessages, _activeProvider, _streamGeneration);
    }

    Timer {
        id: toolCallTimer
        interval: root._toolCallTimeoutMs
        repeat: false
        onTriggered: {
            if (root._pendingCallId >= 0) {
                var callId = root._pendingCallId;
                root.mcpToolCallCancellationRequested(callId, "MCP tool call timed out.");
                root._onToolCallFailed(callId, "MCP tool call timed out.");
            }
        }
    }

    function _applyModelContentDelta(streamId, deltaText) {
        if (!deltaText) return;
        if (streamStartTime === 0) streamStartTime = Date.now();
        _roundContent += deltaText;
        _streamContent += deltaText;
        streamContentUpdated(streamId, deltaText);
    }

    function _applyModelThinkingDelta(streamId, deltaText) {
        if (!deltaText) return;
        if (streamStartTime === 0) streamStartTime = Date.now();
        _roundThinking += deltaText;
        _streamThinking += deltaText;
        streamThinkingUpdated(streamId, deltaText);
    }

    function _appendToolAudit(streamId, text) {
        if (!text) return;
        if (streamStartTime === 0) streamStartTime = Date.now();
        _streamThinking += text;
        streamThinkingUpdated(streamId, text);
    }

    function _finalizeStream(streamId) {
        if (!isStreaming || activeStreamId !== streamId) return;

        if (_tagBuffer.length > 0) {
            if (_insideThinkTag)
                _applyModelThinkingDelta(streamId, _tagBuffer);
            else
                _applyModelContentDelta(streamId, _tagBuffer);
            _tagBuffer = "";
        }
        _insideThinkTag = false;

        _lastFinalizedStreamId = streamId;
        _completedFetchStreamId = streamId;
        _completedFetchProvider = _activeProvider;
        _completedFetchGeneration = _streamGeneration;
        _pendingLaunch = null;
        isStreaming = false;
        activeStreamId = "";
        _cooldownUntil = 0;
        _consecutiveErrors = 0;
        streamFinalized(streamId, _buildStreamStats());
        _activeProvider = "";
    }

    function _markError(streamId, message) {
        _streamContent = message;
        _pendingLaunch = null;
        _clearToolState(true, message);
        isStreaming = false;
        activeStreamId = "";
        lastRequestFailed = true;
        _consecutiveErrors++;
        _cooldownUntil = Backoff.computeCooldownUntil(_consecutiveErrors, _backoffBaseMs, _backoffMaxMs);
        streamError(streamId, message);
        _activeProvider = "";
    }

    function _buildStreamStats() {
        if (streamStartTime === 0) return "";
        var elapsed = (Date.now() - streamStartTime) / 1000;
        var label = elapsed.toFixed(1) + "s";
        // Prefer API-reported token count (accurate); fall back to delta count (approximate)
        var tokens = _apiOutputTokens > 0 ? _apiOutputTokens : streamTokenCount;
        if (tokens > 0 && elapsed > 0.5) {
            var tps = tokens / elapsed;
            var prefix = _apiOutputTokens > 0 ? "" : "~";
            label += " · " + prefix + tps.toFixed(1) + " tok/s";
        }
        return label;
    }

    function _providerDisplayName() {
        return Providers.getProviderInfo(_activeProvider || provider).name;
    }

    function _curlExitHint(exitCode) {
        return ErrorHints.curlExitHint(exitCode, _activeProvider || provider,
                                       _providerDisplayName(), ollamaUrl);
    }

    // --- Processes ---

    Process {
        id: chatFetcher
        running: false
        stdinEnabled: true

        onRunningChanged: {
            if (running) {
                root._processActive = true;
                if (root.pendingStdinBody) {
                    chatFetcher.write(root.pendingStdinBody);
                    chatFetcher.stdinEnabled = false;
                    root.pendingStdinBody = "";
                }
            } else if (root._processActive) {
                // Quickshell emits runningChanged, but not exited, when QProcess
                // fails to start. Complete the lifecycle here so future launches
                // cannot remain queued behind a process that never existed.
                root._finishCurlProcess(-1, true);
            }
        }

        stdout: StdioCollector {
            id: streamCollector
            waitForEnd: false
            property int lastLen: 0

            onTextChanged: {
                var fetchIsActive = root._fetchMatchesActiveStream();
                var fetchIsFinalized = root._fetchMatchesFinalizedStream();
                // Enforce the cap for the process even after its stream
                // identity has been cancelled. Stale output remains inert,
                // but it cannot grow without bound while termination drains.
                if (text.length > 5242880) {
                    chatFetcher.running = false;
                    if (fetchIsActive)
                        root._markError(root.activeStreamId,
                            "Response exceeded maximum buffer size (5 MB).");
                    return;
                }
                if (!fetchIsActive && !fetchIsFinalized)
                    return;
                var newData = text.substring(lastLen);
                lastLen = text.length;
                root._fetchOutput += newData;
                if (fetchIsActive)
                    root.handleStreamChunk(newData);
            }

            onStreamFinished: {
                if (root._fetchMatchesActiveStream()
                        || root._fetchMatchesFinalizedStream())
                    root.handleStreamFinished(root._fetchOutput);
            }
        }

        onExited: exitCode => root._finishCurlProcess(exitCode, false)
    }

    Process {
        id: exportFileWriter
        running: false
        stdinEnabled: true

        onRunningChanged: {
            if (running && root.exportPendingBody) {
                exportFileWriter.write(root.exportPendingBody);
                exportFileWriter.stdinEnabled = false;
                root.exportPendingBody = "";
            }
        }

        onExited: exitCode => {
            if (exitCode === 0)
                root.lastExportedFile = exportFileWriter.command[1];
        }
    }
}
