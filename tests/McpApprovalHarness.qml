import QtQuick
import Quickshell
import "./src/services"

ShellRoot {
    id: root

    property string phase: "connecting"
    property int connectionCount: 0
    property int toolRequestCount: 0
    property int toolCompletionCount: 0
    property int toolRoundCount: 0
    property int toolCancellationCount: 0
    property var approvedContracts: []
    property var activeApprovals: []
    property string currentProvider: "ollama"
    property bool finished: false

    function finish(success, message) {
        if (finished) return;
        finished = true;
        console.log("EPHEMERA_MCP_APPROVAL_TEST " + (success ? "PASS" : "FAIL") + ": " + message);
        Qt.quit();
    }

    function startToolTurn(streamId, approvals, toolArgs) {
        activeApprovals = approvals;
        streaming.beginStream(streamId, 0, [{ role: "user", content: "echo hello" }]);
        streaming.handleStreamChunk(JSON.stringify({
            message: {
                role: "assistant",
                content: "",
                tool_calls: [{
                    function: {
                        name: "echo",
                        arguments: toolArgs || { text: "hello" }
                    }
                }]
            },
            done: true,
            eval_count: 3
        }) + "\n");
        streaming.handleStreamFinished("\nEPH_STATUS:200\n");
    }

    Component.onCompleted: mcp.connectToServer()

    Timer {
        interval: 10000
        running: true
        repeat: false
        onTriggered: root.finish(false, "timed out during " + root.phase)
    }

    MCPService {
        id: mcp
        enabled: true
        mcpUrl: "https://mcp.example.test/sse"

        onMcpConnectionStateChanged: {
            if (!isConnected) return;
            root.connectionCount++;
            if (root.connectionCount === 1) {
                root.approvedContracts = setToolApproved([], "echo", true);
                root.phase = "unapproved";
                Qt.callLater(function() { root.startToolTurn("blocked", []); });
            } else if (root.connectionCount === 2 && root.phase === "reconnecting") {
                root.phase = "identity-cancel";
                Qt.callLater(function() {
                    root.startToolTurn("cancelled-call", root.approvedContracts,
                        { text: "must-not-resume" });
                    if (!streaming.toolApprovalPending
                            || !streaming.approvePendingToolCall()) {
                        root.finish(false, "identity-cancel tool did not enter execution");
                        return;
                    }
                    root.currentProvider = "openai";
                    identityCancellationTimer.start();
                });
            }
        }

        onToolCallCompleted: (callId, result) => {
            root.toolCompletionCount++;
            streaming._onToolCallCompleted(callId, result);
        }

        onToolCallFailed: (callId, error) => streaming._onToolCallFailed(callId, error)
    }

    StreamingService {
        id: streaming
        provider: root.currentProvider
        mcpConnected: mcp.isConnected
        mcpTools: mcp.tools
        toolCallsAllowed: true
        approvedToolContracts: root.activeApprovals

        onMcpToolCallRequested: (toolName, toolArguments, approvals,
                                 streamId, streamProvider, streamGeneration) => {
            if (!streaming.matchesActiveStream(
                    streamId, streamProvider, streamGeneration)) {
                root.finish(false, "tool execution crossed a stream identity boundary");
                return;
            }
            root.toolRequestCount++;
            var callId = mcp.callTool(toolName, toolArguments, approvals);
            streaming.toolCallStarted(toolName, callId);
        }
        onMcpToolCallCancellationRequested: (callId, reason) => {
            if (!mcp.cancelRequest(callId, reason)) {
                root.finish(false, "active MCP request could not be cancelled");
                return;
            }
            root.toolCancellationCount++;
        }

        onStreamCancelled: streamId => {
            if (root.phase !== "identity-cancel" || streamId !== "cancelled-call")
                root.finish(false, "unexpected stream cancellation: " + streamId);
        }

        onStreamError: (streamId, message) => {
            if (root.phase === "unapproved") {
                if (root.toolRequestCount !== 0 || message.indexOf("not approved") < 0) {
                    root.finish(false, "unapproved tool was not blocked cleanly");
                    return;
                }
                root.phase = "permission-recheck";
                Qt.callLater(function() {
                    root.startToolTurn("recheck", root.approvedContracts);
                    if (!streaming.toolApprovalPending) {
                        root.finish(false, "approved tool did not request confirmation");
                        return;
                    }
                    root.activeApprovals = [];
                    streaming.approvePendingToolCall();
                });
            } else if (root.phase === "permission-recheck") {
                if (root.toolRequestCount !== 0 || message.indexOf("not approved") < 0) {
                    root.finish(false, "permission was not rechecked before execution");
                    return;
                }
                root.phase = "invalid-input";
                Qt.callLater(function() {
                    root.startToolTurn("invalid-input", root.approvedContracts,
                        { text: 7, hidden: true });
                });
            } else if (root.phase === "invalid-input") {
                if (root.toolRequestCount !== 0 || streaming.toolApprovalPending
                        || message.indexOf("approved input schema") < 0) {
                    root.finish(false, "out-of-contract arguments were not blocked before approval");
                    return;
                }
                root.phase = "approved";
                Qt.callLater(function() {
                    root.startToolTurn("approved", root.approvedContracts,
                        { text: "hello" });
                    if (!streaming.toolApprovalPending
                            || streaming.pendingToolArgumentsText.indexOf('"text": "hello"') < 0) {
                        root.finish(false, "confirmation did not show complete arguments");
                        return;
                    }
                    streaming.approvePendingToolCall();
                });
            } else {
                root.finish(false, "unexpected stream error: " + message);
            }
        }

        onStreamToolRoundReady: (streamId, messages) => {
            root.toolRoundCount++;
            if (root.phase !== "approved" || root.toolRequestCount !== 1
                    || root.toolCompletionCount !== 1) {
                root.finish(false, "tool execution counts were incorrect");
                return;
            }
            if (messages.length !== 3 || messages[1].role !== "assistant"
                    || messages[1].thinking !== undefined
                    || messages[2].role !== "tool" || messages[2].tool_name !== "echo"
                    || messages[2].content !== "hello") {
                root.finish(false, "tool result round-trip was malformed");
                return;
            }
            root.phase = "reconnecting";
            mcp.reconnectToServer();
        }
    }

    Timer {
        id: identityCancellationTimer
        interval: 250
        repeat: false
        onTriggered: {
            if (root.currentProvider !== "openai" || streaming.isStreaming
                    || root.toolRequestCount !== 2
                    || root.toolCompletionCount !== 1
                    || root.toolRoundCount !== 1
                    || root.toolCancellationCount !== 1) {
                root.finish(false, "provider switch did not contain an in-flight tool result");
                return;
            }
            root.finish(true, "deny, recheck, approve, execute, resume, reconnect, and in-flight cancellation completed");
        }
    }
}
