import QtQuick
import Quickshell
import "./src/services"

ShellRoot {
    id: root

    property int errorCount: 0
    property int finalizedCount: 0
    property bool finished: false

    function finish(success, message) {
        if (finished) return;
        finished = true;
        console.log("EPHEMERA_STREAM_EXIT_TEST "
                    + (success ? "PASS" : "FAIL") + ": " + message);
        Qt.quit();
    }

    Component.onCompleted: {
        streaming.beginStream("partial-timeout", 0, []);
        var context = streaming.activeStreamContext();
        var delta = "data: " + JSON.stringify({
            choices: [{ delta: { content: "partial" }, finish_reason: null }]
        });
        var terminal = "data: " + JSON.stringify({
            choices: [{ delta: {}, finish_reason: "stop" }]
        });
        var script = "printf '%s\\n%s\\n%s\\n\\nEPH_STATUS:200\\n' '"
            + delta + "' '" + terminal + "' 'data: [DONE]'; exit 28";
        if (!streaming.launchCurl({
                cmd: ["sh", "-c", script],
                body: "ignored"
            }, [], context.streamId, context.provider, context.generation)) {
            finish(false, "could not launch partial-timeout fixture");
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: false
        onTriggered: root.finish(false, "timed out")
    }

    Timer {
        id: lifecycleCheck
        interval: 50
        repeat: false
        onTriggered: {
            if (root.errorCount !== 1 || root.finalizedCount !== 0
                    || streaming.isStreaming || streaming.transportBusy
                    || !streaming.lastRequestFailed) {
                root.finish(false, "nonzero exit was not authoritative");
                return;
            }
            root.finish(true, "partial HTTP 200 output followed by exit 28 failed once without finalization");
        }
    }

    StreamingService {
        id: streaming
        provider: "openai"

        onStreamError: (streamId, message) => {
            root.errorCount++;
            if (streamId !== "partial-timeout"
                    || message.toLowerCase().indexOf("timed out") < 0) {
                root.finish(false, "unexpected error result: " + streamId + ": " + message);
                return;
            }
            lifecycleCheck.restart();
        }

        onStreamFinalized: streamId => {
            root.finalizedCount++;
            root.finish(false, "failed transport finalized: " + streamId);
        }
    }
}
