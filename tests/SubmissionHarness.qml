import QtQuick
import Quickshell
import "./src/services"

ShellRoot {
    id: root

    property bool finished: false
    property string acceptedStreamId: ""

    function finish(success, message) {
        if (finished) return;
        finished = true;
        console.log("EPHEMERA_SUBMISSION_TEST "
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
        service.model = "test-model";
        if (!check(!service.sendMessage("  ") && service.messagesModel.count === 0,
                "empty text was accepted")) return;

        if (!check(service.sendMessage("accepted draft"),
                "ready submission was rejected")) return;
        acceptedStreamId = service.activeStreamId;
        if (!check(acceptedStreamId.length > 0
                && service.isStreaming
                && service.messagesModel.count === 2,
                "accepted submission did not start one stream")) return;

        var assistantBefore = service.messagesModel.get(1);
        if (!check(!service.sendMessage("must stay drafted")
                && service.activeStreamId === acceptedStreamId
                && service.isStreaming
                && service.messagesModel.count === 2
                && service.messagesModel.get(1).status === assistantBefore.status
                && service.messagesModel.get(1).content === assistantBefore.content,
                "active-stream rejection mutated or replaced the stream")) return;

        completionPoll.start();
    }

    function checkPostStreamRejections() {
        if (service.isStreaming || service.messagesModel.get(1).status === "streaming")
            return;
        completionPoll.stop();
        if (!check(service.messagesModel.get(1).status === "ok"
                && service.messagesModel.get(1).content === "accepted response",
                "rejected submission stopped or corrupted the accepted transport")) return;

        service.model = "";
        if (!check(service.sendMessage("trigger cooldown"),
                "pre-cooldown submission was not accepted")) return;
        var cooldownCount = service.messagesModel.count;
        var cooldownMessage = service.messagesModel.get(cooldownCount - 1).content;
        if (!check(!service.sendMessage("cooldown draft")
                && service.messagesModel.count === cooldownCount
                && service.messagesModel.get(cooldownCount - 1).content === cooldownMessage,
                "cooldown rejection changed chat state")) return;

        service.setProvider("openai");
        if (!check(service.missingApiKey
                && !service.canSubmitMessage("missing-key draft")
                && !service.sendMessage("missing-key draft")
                && service.messagesModel.count === 0,
                "missing credentials did not reject submission")) return;

        finish(true, "accepted and rejected submissions preserve draft and stream contracts");
    }

    Component.onCompleted: Qt.callLater(runChecks)

    Timer {
        id: completionPoll
        interval: 20
        repeat: true
        onTriggered: root.checkPostStreamRejections()
    }

    Timer {
        interval: 5000
        running: true
        repeat: false
        onTriggered: root.finish(false, "timed out")
    }

    EphemeraService {
        id: service
        pluginId: "ephemera-submission"
    }
}
