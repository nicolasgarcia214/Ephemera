import QtQuick
import Quickshell
import "./src/services"

ShellRoot {
    id: root

    property int connectionCount: 0
    property var echoApprovals: []
    property bool largeErrorBounded: false
    property bool malformedResponseRejected: false
    property bool invalidResultRejected: false
    property bool toolCompleted: false
    property bool finished: false
    property int consentRevocationAttempts: 0

    function finish(success, message) {
        if (finished) return;
        finished = true;
        console.log("EPHEMERA_MCP_QML_TEST " + (success ? "PASS" : "FAIL") + ": " + message);
        Qt.quit();
    }

    function verifyEnvelopeBoundaries() {
        var malformedRejected = false;
        var unrelatedSettled = false;
        mcp._pendingRequests[8001] = {
            resolve: function() {},
            reject: function() { malformedRejected = true; }
        };
        mcp._pendingRequests[8002] = {
            resolve: function() { unrelatedSettled = true; },
            reject: function() {}
        };
        mcp._handleLine(JSON.stringify({
            jsonrpc: "2.0", id: 8001, result: {},
            error: { code: "invalid", message: 7 }
        }));
        if (!malformedRejected
                || !Object.prototype.hasOwnProperty.call(
                    mcp._pendingRequests, 8002)) {
            finish(false, "malformed response disturbed an unrelated pending request");
            return;
        }
        mcp._handleLine(JSON.stringify({
            jsonrpc: "2.0", id: 8002, result: {}
        }));
        if (!unrelatedSettled) {
            finish(false, "unrelated pending request remained stalled");
            return;
        }
        mcp._pendingRequests[9001] = {
            resolve: function() { throw new Error("contained callback"); },
            reject: function() {}
        };
        mcp._handleLine(JSON.stringify({
            jsonrpc: "2.0", id: 9001, result: {}
        }));
        if (mcp.connectionError.indexOf("failed safely") < 0) {
            finish(false, "pending callback exception escaped containment");
            return;
        }
        finish(true, "dependency, envelope, HTTPS/HTTP consent, target, reconnect, and callback boundaries passed");
    }

    Component.onCompleted: mcp.connectToServer()

    Timer {
        interval: 8000
        running: true
        repeat: false
        onTriggered: root.finish(false, "timed out")
    }

    MCPService {
        id: mcp
        enabled: true
        mcpUrl: "https://mcp.example.test/sse"

        onMcpConnectionStateChanged: {
            if (!isConnected) return;
            root.connectionCount++;
            if (root.connectionCount === 1) {
                if (connectedUrl !== "https://mcp.example.test/sse"
                        || connectedAllowsInsecureHttp) {
                    root.finish(false, "initial connected target snapshot was incorrect");
                    return;
                }
                if (tools.length !== 1 || tools[0].name !== "echo" || ignoredToolCount !== 2) {
                    root.finish(false, "unsupported input or output schema was exposed");
                    return;
                }
                if (!nodeVersion || !nodeUndiciVersion
                        || bridgeVersion !== "0.1.38" || undiciVersion !== "7.28.0"
                        || openVersion !== "10.2.0") {
                    root.finish(false, "runtime dependency versions were not verified");
                    return;
                }
                root.echoApprovals = setToolApproved([], "echo", true);
                if (cancelRequest("__proto__", "invalid id")) {
                    root.finish(false, "prototype-like cancellation id reached the pending map");
                    return;
                }
                if (callTool("echo", { text: "blocked" }, []) >= 0) {
                    root.finish(false, "unapproved direct tool call was accepted");
                    return;
                }
                if (callTool(" echo ", { text: "blocked" }, root.echoApprovals) >= 0) {
                    root.finish(false, "non-canonical tool name was accepted");
                    return;
                }
                if (callTool("echo", { text: 7 }, root.echoApprovals) >= 0
                        || callTool("echo", { text: "hello", hidden: true }, root.echoApprovals) >= 0
                        || callTool("echo", { text: "x".repeat(20001) }, root.echoApprovals) >= 0) {
                    root.finish(false, "arguments outside the approved input schema were accepted");
                    return;
                }
                var callId = callTool("echo", { text: "__large_error__" }, root.echoApprovals);
                if (callId < 0)
                    root.finish(false, "tool call was not started");
            } else if (root.connectionCount === 2) {
                if (connectedUrl !== "http://mcp-http.example.test/sse"
                        || !connectedAllowsInsecureHttp) {
                    root.finish(false, "consented HTTP target did not receive a fresh snapshot");
                    return;
                }
                allowInsecureHttp = false;
                consentRevocationTimer.start();
            } else {
                root.finish(false, "unexpected extra MCP connection");
            }
        }

        onToolCallCompleted: (callId, result) => {
            if (!root.invalidResultRejected) {
                root.finish(false, "invalid result reached the completion boundary");
                return;
            }
            if (result !== "hello") {
                root.finish(false, "unexpected tool result: " + result);
                return;
            }
            root.toolCompleted = true;
            mcpUrl = "http://mcp-http.example.test/sse";
            allowInsecureHttp = true;
        }

        onToolCallFailed: (callId, error) => {
            if (!root.largeErrorBounded && error.indexOf("MCP error -32000") === 0) {
                if (error.length > 4130) {
                    root.finish(false, "remote JSON-RPC error escaped the UI size bound");
                    return;
                }
                if (error.indexOf("\\u202e") < 0) {
                    root.finish(false, "remote JSON-RPC error kept an invisible control");
                    return;
                }
                root.largeErrorBounded = true;
                var malformedId = callTool("echo", {
                    text: "__malformed_error__"
                }, root.echoApprovals);
                if (malformedId < 0)
                    root.finish(false, "valid call was not started after bounded remote error");
                return;
            }
            if (root.largeErrorBounded && !root.malformedResponseRejected
                    && error.indexOf("Invalid JSON-RPC response") >= 0) {
                root.malformedResponseRejected = true;
                var invalidResultId = callTool("echo", {
                    text: "__invalid_result__"
                }, root.echoApprovals);
                if (invalidResultId < 0)
                    root.finish(false, "valid call was not started after malformed envelope rejection");
                return;
            }
            if (root.malformedResponseRejected && !root.invalidResultRejected
                    && error.indexOf("invalid content") >= 0) {
                root.invalidResultRejected = true;
                var validCallId = callTool("echo", { text: "hello" }, root.echoApprovals);
                if (validCallId < 0)
                    root.finish(false, "valid tool call was not started after result rejection");
                return;
            }
            root.finish(false, "tool call failed: " + error);
        }
    }

    Timer {
        id: consentRevocationTimer
        interval: 50
        repeat: true
        onTriggered: {
            root.consentRevocationAttempts++;
            mcp.connectToServer();
            if (!mcp.isConnected && !mcp.connecting
                    && mcp.connectionError.indexOf(
                        "explicit insecure transport consent") >= 0) {
                stop();
                root.verifyEnvelopeBoundaries();
                return;
            }
            if (root.consentRevocationAttempts >= 20) {
                stop();
                root.finish(false, "revoking HTTP consent did not fail closed");
            }
        }
    }
}
