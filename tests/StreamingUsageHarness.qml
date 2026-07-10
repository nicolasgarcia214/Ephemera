import QtQuick
import Quickshell
import "./src/services"

ShellRoot {
    id: root

    property string currentProvider: "openai"
    property string phase: "openai-usage"
    property int finalizedCount: 0
    property bool finished: false

    function finish(success, message) {
        if (finished) return;
        finished = true;
        console.log("EPHEMERA_STREAM_USAGE_TEST "
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

    function sse(payload) {
        return "data: " + JSON.stringify(payload);
    }

    function launch(streamId, script) {
        streaming.beginStream(streamId, 0, []);
        var context = streaming.activeStreamContext();
        if (!streaming.launchCurl({
                cmd: ["sh", "-c", script],
                body: "ignored"
            }, [], context.streamId, context.provider, context.generation)) {
            finish(false, "could not launch " + streamId);
        }
    }

    function startOpenAiUsage() {
        phase = "openai-usage";
        currentProvider = "openai";
        var content = sse({ choices: [{ delta: { content: "hello" }, finish_reason: null }] });
        var finishLine = sse({ choices: [{ delta: {}, finish_reason: "stop" }] });
        var usage = sse({ choices: [], usage: {
            prompt_tokens: 3, completion_tokens: 12, total_tokens: 15
        } });
        launch("openai-usage", "printf '%s\\n' '" + content
            + "'; printf '%s\\n' '" + finishLine
            + "'; printf '%s\\n' '" + usage
            + "' 'data: [DONE]' ''; printf '%s\\n' 'EPH_STATUS:200'");
    }

    function startCustomMissingUsage() {
        phase = "custom-missing-usage";
        currentProvider = "custom";
        var content = sse({ choices: [{ delta: { content: "fallback" }, finish_reason: null }] });
        var finishLine = sse({ choices: [{ delta: {}, finish_reason: "stop" }] });
        launch("custom-missing-usage", "printf '%s\\n' '" + content
            + "' '" + finishLine + "' ''; printf '%s\\n' 'EPH_STATUS:200'");
    }

    function startOllamaUsage() {
        phase = "ollama-usage";
        currentProvider = "ollama";
        var content = sse({ choices: [{ delta: { content: "local" }, finish_reason: null }] });
        var finishLine = sse({ choices: [{ delta: {}, finish_reason: "stop" }] });
        var usage = sse({ choices: [], usage: { completion_tokens: 7 } });
        launch("ollama-usage", "printf '%s\\n' '" + content
            + "' '" + finishLine + "' '" + usage
            + "' 'data: [DONE]' ''; printf '%s\\n' 'EPH_STATUS:200'");
    }

    function startNativeOllama() {
        phase = "native-ollama";
        currentProvider = "ollama";
        var finalLine = JSON.stringify({
            message: { role: "assistant", content: "native" },
            done: true,
            eval_count: 5
        });
        launch("native-ollama", "printf '%s\\n' '" + finalLine
            + "' ''; printf '%s\\n' 'EPH_STATUS:200'");
    }

    function advanceWhenIdle() {
        if (streaming.transportBusy) {
            advanceTimer.restart();
            return;
        }
        if (phase === "openai-usage")
            startCustomMissingUsage();
        else if (phase === "custom-missing-usage")
            startOllamaUsage();
        else if (phase === "ollama-usage")
            startNativeOllama();
        else {
            streaming.handleStreamChunk("data: [DONE]\\n");
            if (!check(finalizedCount === 4,
                    "completion markers or process exit finalized more than once")) return;
            finish(true, "usage ordering, missing usage fallback, native completion, and exactly-once finalization passed");
        }
    }

    Component.onCompleted: Qt.callLater(startOpenAiUsage)

    Timer {
        interval: 10000
        running: true
        repeat: false
        onTriggered: root.finish(false, "timed out")
    }

    Timer {
        id: advanceTimer
        interval: 10
        repeat: false
        onTriggered: root.advanceWhenIdle()
    }

    StreamingService {
        id: streaming
        provider: root.currentProvider

        onStreamContentUpdated: {
            // Ensure tok/s is rendered without making the transport fixture slow.
            streaming.streamStartTime = Date.now() - 1000;
        }

        onStreamError: (streamId, message) =>
            root.finish(false, streamId + " failed: " + message)

        onStreamFinalized: (streamId, stats) => {
            root.finalizedCount++;
            if (root.phase === "openai-usage") {
                if (!root.check(streamId === "openai-usage"
                        && streaming._apiOutputTokens === 12,
                        "OpenAI finalized before its usage-only chunk")) return;
                if (!root.check(stats.indexOf("tok/s") >= 0
                        && stats.indexOf("~") < 0,
                        "OpenAI stats did not use API completion tokens")) return;
            } else if (root.phase === "custom-missing-usage") {
                if (!root.check(streamId === "custom-missing-usage"
                        && streaming._apiOutputTokens === 0,
                        "custom provider missing-usage fallback was not preserved")) return;
            } else if (root.phase === "ollama-usage") {
                if (!root.check(streamId === "ollama-usage"
                        && streaming._apiOutputTokens === 7,
                        "Ollama compatibility stream finalized before usage")) return;
            } else if (!root.check(streamId === "native-ollama"
                    && streaming._apiOutputTokens === 5,
                    "native Ollama completion changed")) return;

            if (!root.check(root.finalizedCount <= 4,
                    "stream finalized more than once")) return;
            advanceTimer.restart();
        }
    }
}
