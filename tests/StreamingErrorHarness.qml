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
        console.log("EPHEMERA_STREAM_ERROR_TEST " + (success ? "PASS" : "FAIL") + ": " + message);
        Qt.quit();
    }

    Component.onCompleted: {
        streaming.beginStream("provider-error", 0, []);
        var context = streaming.activeStreamContext();
        if (!streaming.launchCurl({
                cmd: ["curl", "--ephemera-stream-error-test"],
                body: ""
            }, [], context.streamId, context.provider, context.generation)) {
            finish(false, "could not launch the error transport fixture");
        }
    }

    Timer {
        interval: 10000
        running: true
        repeat: false
        onTriggered: root.finish(false, "timed out waiting for provider error lifecycle")
    }

    Timer {
        id: lifecycleCheck
        interval: 750
        repeat: false
        onTriggered: {
            if (root.errorCount !== 1 || root.finalizedCount !== 0) {
                root.finish(false, "provider failure did not emit exactly one error and zero finalizations");
                return;
            }
            if (streaming.isStreaming || streaming.transportBusy
                    || streaming.activeStreamId !== "" || !streaming.lastRequestFailed) {
                root.finish(false, "provider failure did not stop and clear the active transport");
                return;
            }
            root.finish(true, "provider error stopped transport once without success finalization");
        }
    }

    StreamingService {
        id: streaming
        provider: "openai"

        onStreamError: (streamId, message) => {
            root.errorCount++;
            if (streamId !== "provider-error" || message.length >= 100
                    || message.indexOf("api-key") >= 0 || message.indexOf("<b>") >= 0) {
                root.finish(false, "provider error signal was unbounded, unsafe, or identity-mismatched");
                return;
            }
            streaming.handleStreamChunk("data: [DONE]\n");
            lifecycleCheck.restart();
        }

        onStreamFinalized: streamId => {
            root.finalizedCount++;
            root.finish(false, "failed stream finalized successfully: " + streamId);
        }
    }
}
