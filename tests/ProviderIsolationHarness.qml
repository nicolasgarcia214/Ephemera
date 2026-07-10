import QtQuick
import Quickshell
import Quickshell.Io
import "./src/services"
import "./src/lib/Providers.js" as Providers

ShellRoot {
    id: root

    property string currentProvider: "ollama"
    property bool finished: false
    property int cancelledCount: 0
    property int finalizedCount: 0
    property var replacementContext: null
    property string phase: "provider-isolation"
    property string staleMarkerPath: Quickshell.env("XDG_RUNTIME_DIR")
        + "/ephemera-stale-output-emitted"

    function finish(success, message) {
        if (finished) return;
        finished = true;
        console.log("EPHEMERA_PROVIDER_ISOLATION_TEST "
                    + (success ? "PASS" : "FAIL") + ": " + message);
        Qt.quit();
    }

    function check(condition, message) {
        if (!condition) {
            finish(false, message);
            return false;
        }
        return true;
    }

    function runChecks() {
        streaming.beginStream("stable-id", 0, [{ role: "user", content: "hello" }]);
        var original = streaming.activeStreamContext();
        if (!check(streaming.matchesActiveStream(
                original.streamId, original.provider, original.generation),
                "new stream identity was not active")) return;

        currentProvider = "openai";
        if (!check(!streaming.isStreaming && streaming.streamPhase === "idle",
                "provider mutation did not cancel the active stream")) return;
        if (!check(!streaming.matchesActiveStream(
                original.streamId, original.provider, original.generation),
                "cancelled stream identity remained valid")) return;

        var staleLaunch = streaming.launchCurl(
            { cmd: ["false"], body: "" }, [], original.streamId,
            original.provider, original.generation);
        if (!check(staleLaunch === false,
                "stale provider context was allowed to launch")) return;

        currentProvider = "ollama";
        streaming.beginStream("stable-id", 0, []);
        var replacement = streaming.activeStreamContext();
        if (!check(replacement.generation !== original.generation,
                "reused stream id did not receive a fresh generation")) return;
        if (!check(!streaming.matchesActiveStream(
                original.streamId, original.provider, original.generation),
                "old generation matched replacement stream")) return;
        streaming.reset();

        if (!check(Providers.normalizeOllamaContextWindow(0) === 0
                && Providers.normalizeOllamaContextWindow(1) === 4096
                && Providers.normalizeOllamaContextWindow(12000) === 16384
                && Providers.normalizeOllamaContextWindow(999999) === 131072,
                "Ollama context bounds were not enforced")) return;

        var request = Providers.buildRequest("ollama", {
            baseUrl: "http://localhost:11434",
            model: "test-model",
            messages: [{ role: "user", content: "hello" }],
            stream: true,
            temperature: 0.7,
            max_tokens: 128,
            ollamaContextWindow: 32768,
            tools: [{ type: "function", function: { name: "echo" } }]
        }, "");
        var body = JSON.parse(request.body);
        if (!check(request.url.endsWith("/api/chat")
                && body.options && body.options.num_ctx === 32768,
                "native Ollama request did not include num_ctx")) return;

        startProcessIsolationCheck();
    }

    function startProcessIsolationCheck() {
        currentProvider = "ollama";
        streaming.beginStream("old-ollama", 0, []);
        var oldContext = streaming.activeStreamContext();
        // Use an OpenAI-compatible event even though this launch starts under
        // Ollama. If it leaks after the provider switch, the replacement
        // parser would accept it and make the isolation failure observable.
        var staleLine = "data: " + JSON.stringify({
            choices: [{ delta: { content: "STALE_CLOUD_OUTPUT" } }]
        });
        var staleScript = "trap \"printf emitted > '" + staleMarkerPath
            + "'; printf '%s\\n%s\\n\\nEPH_STATUS:200\\n' '"
            + staleLine + "' 'data: [DONE]'\" TERM; sleep 2";
        var launched = streaming.launchCurl(
            { cmd: ["sh", "-c", staleScript], body: "ignored" }, [],
            oldContext.streamId, oldContext.provider, oldContext.generation);
        if (!check(launched, "slow Ollama fixture did not launch")) return;
        switchProviderTimer.start();
    }

    function switchWhileProcessExits() {
        if (!check(streaming.transportBusy,
                "slow fixture exited before provider-switch check")) return;

        currentProvider = "openai";
        if (!check(cancelledCount === 1 && !streaming.isStreaming,
                "provider switch did not cancel old process-bound stream")) return;

        streaming.beginStream("new-cloud", 0, []);
        replacementContext = streaming.activeStreamContext();
        var freshLine = "data: " + JSON.stringify({
            choices: [{ delta: { content: "FRESH_CLOUD_OUTPUT" } }]
        });
        var freshScript = "printf '%s\\n%s\\n\\nEPH_STATUS:200\\n' '"
            + freshLine + "' 'data: [DONE]'";
        var launched = streaming.launchCurl(
            { cmd: ["sh", "-c", freshScript], body: "ignored" }, [],
            replacementContext.streamId, replacementContext.provider,
            replacementContext.generation);
        check(launched, "cloud stream was not queued or started");
    }

    function startFailedProcessCheck() {
        phase = "failed-start";
        streaming.beginStream("failed-start", 0, []);
        var context = streaming.activeStreamContext();
        var launched = streaming.launchCurl({
            cmd: ["/ephemera-test/missing-curl"],
            body: "ignored"
        }, [], context.streamId, context.provider, context.generation);
        check(launched, "failed-start fixture was rejected before Process launch");
    }

    function startZeroOutputCheck() {
        phase = "zero-output";
        var finalizedMessageId = streaming._lastFinalizedStreamId;
        streaming.beginStream("zero-output", 0, []);
        if (!check(finalizedMessageId === "new-cloud"
                && streaming._lastFinalizedStreamId === finalizedMessageId,
                "new stream discarded delayed finalized-message attribution")) return;
        var context = streaming.activeStreamContext();
        var launched = streaming.launchCurl({
            cmd: ["sh", "-c", "exit 7"],
            body: "ignored"
        }, [], context.streamId, context.provider, context.generation);
        check(launched, "zero-output fixture was rejected before Process launch");
    }

    function startRecoveryCheck() {
        phase = "recovery";
        streaming.beginStream("recovered-cloud", 0, []);
        var context = streaming.activeStreamContext();
        var freshLine = "data: " + JSON.stringify({
            choices: [{ delta: { content: "RECOVERED_CLOUD_OUTPUT" } }]
        });
        var script = "printf '%s\\n%s\\n\\nEPH_STATUS:200\\n' '"
            + freshLine + "' 'data: [DONE]'";
        var launched = streaming.launchCurl(
            { cmd: ["sh", "-c", script], body: "ignored" }, [],
            context.streamId, context.provider, context.generation);
        check(launched, "stream could not recover after Process failed to start");
    }

    function verifyFinalizedHttpStatus() {
        if (streaming.transportBusy) {
            finalizedStatusTimer.restart();
            return;
        }
        if (!check(streaming.lastHttpStatus === 200,
                "finalized fetch discarded its trailing HTTP status")) return;
        staleMarkerCheck.command = ["test", "-f", staleMarkerPath];
        staleMarkerCheck.running = true;
    }

    Component.onCompleted: Qt.callLater(runChecks)

    Timer {
        interval: 5000
        running: true
        repeat: false
        onTriggered: root.finish(false, "timed out")
    }

    Timer {
        id: switchProviderTimer
        interval: 30
        repeat: false
        onTriggered: root.switchWhileProcessExits()
    }

    StreamingService {
        id: streaming
        provider: root.currentProvider

        onStreamCancelled: streamId => {
            if (streamId === "stable-id")
                return;
            if (streamId !== "old-ollama") {
                root.finish(false, "unexpected stream was cancelled: " + streamId);
                return;
            }
            root.cancelledCount++;
        }

        onStreamError: (streamId, message) => {
            if (root.phase === "zero-output" && streamId === "zero-output") {
                if (streaming._streamContent.indexOf("FRESH_CLOUD_OUTPUT") >= 0
                        || streaming._streamContent.indexOf("STALE_CLOUD_OUTPUT") >= 0) {
                    root.finish(false, "zero-output process replayed a previous response");
                    return;
                }
                Qt.callLater(root.startFailedProcessCheck);
                return;
            }
            if (root.phase === "failed-start" && streamId === "failed-start") {
                if (message.indexOf("Could not start the response process") < 0
                        || streaming.transportBusy) {
                    root.finish(false, "failed Process lifecycle was not cleared");
                    return;
                }
                Qt.callLater(root.startRecoveryCheck);
                return;
            }
            root.finish(false, "stream failed: " + streamId + ": " + message);
        }

        onStreamFinalized: streamId => {
            root.finalizedCount++;
            if (root.phase === "provider-isolation") {
                if (streamId !== "new-cloud" || root.finalizedCount !== 1
                        || streaming._streamContent !== "FRESH_CLOUD_OUTPUT"
                        || streaming._streamContent.indexOf("STALE_CLOUD_OUTPUT") >= 0) {
                    root.finish(false, "stale process output mutated replacement stream");
                    return;
                }
                finalizedStatusTimer.restart();
            } else if (root.phase === "recovery") {
                if (streamId !== "recovered-cloud" || root.finalizedCount !== 2
                        || streaming._streamContent !== "RECOVERED_CLOUD_OUTPUT") {
                    root.finish(false, "stream did not recover after failed Process start");
                    return;
                }
                root.finish(true, "provider generations, queued restart, zero-output completion, failed start, and recovery are isolated");
            } else {
                root.finish(false, "unexpected stream finalized: " + streamId);
            }
        }
    }

    Process {
        id: staleMarkerCheck
        running: false
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.finish(false, "stale fixture never emitted its TERM payload");
                return;
            }
            Qt.callLater(root.startZeroOutputCheck);
        }
    }

    Timer {
        id: finalizedStatusTimer
        interval: 10
        repeat: false
        onTriggered: root.verifyFinalizedHttpStatus()
    }
}
