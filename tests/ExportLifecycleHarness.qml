import QtQuick
import Quickshell
import Quickshell.Io
import "./src/services"

ShellRoot {
    id: root

    property string phase: "clipboard-success"
    property bool finished: false
    property bool overlapRejected: false
    property bool messageOverlapRejected: false
    property var seenExportIds: ({})
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR")

    function finish(success, message) {
        if (finished) return;
        finished = true;
        console.log("EPHEMERA_EXPORT_LIFECYCLE_TEST "
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

    function checkIdentity(exportId) {
        if (!check(exportId.length > 0, "export signal omitted its identity"))
            return false;
        if (!check(!seenExportIds[exportId], "export identity was reused: " + exportId))
            return false;
        seenExportIds[exportId] = true;
        return true;
    }

    function startClipboardSuccess() {
        if (!streaming.exportToClipboard("CLIPBOARD_SUCCESS"))
            finish(false, "clipboard success fixture was rejected");
    }

    function startClipboardFailure() {
        phase = "clipboard-nonzero";
        if (!streaming.exportToClipboard("CLIPBOARD_FAIL"))
            finish(false, "clipboard nonzero fixture was rejected");
    }

    function startClipboardStartFailure() {
        phase = "clipboard-start-failure";
        streaming._clipboardExportCommand = ["ephemera-missing-wl-copy"];
        if (!streaming.exportToClipboard("CLIPBOARD_SUCCESS"))
            finish(false, "clipboard failed-start fixture was rejected before launch");
    }

    function startFileSuccess() {
        phase = "file-success";
        streaming._clipboardExportCommand = ["wl-copy", "--"];
        if (!streaming.exportToFile("FILE_SUCCESS", runtimeDir,
                                    runtimeDir + "/export-success.md"))
            finish(false, "file success fixture was rejected");
    }

    function startFileFailure() {
        phase = "file-nonzero";
        if (!streaming.exportToFile("FILE_FAIL", runtimeDir,
                                    runtimeDir + "/export-fail.md"))
            finish(false, "file nonzero fixture was rejected");
    }

    function startFileStartFailure() {
        phase = "file-start-failure";
        streaming._fileExportCommand = ["ephemera-missing-install"];
        if (!streaming.exportToFile("FILE_SUCCESS", runtimeDir,
                                    runtimeDir + "/export-start-fail.md"))
            finish(false, "file failed-start fixture was rejected before launch");
    }

    function startOverlapCheck() {
        phase = "overlap";
        streaming._fileExportCommand = ["install"];
        if (!streaming.exportToClipboard("CLIPBOARD_SLOW")) {
            finish(false, "overlap fixture could not start its first export");
            return;
        }
        if (streaming.exportToFile("FILE_SUCCESS", runtimeDir,
                                   runtimeDir + "/export-overlap.md"))
            finish(false, "overlapping file export was accepted");
    }

    function startMessageSuccess() {
        phase = "message-success";
        if (!streaming.copyMessageToClipboard(
                "assistant-secret", "MESSAGE_SECRET_TEXT"))
            finish(false, "message clipboard fixture was rejected");
    }

    function startMessageFailure() {
        phase = "message-nonzero";
        if (!streaming.copyMessageToClipboard("assistant-fail", "MESSAGE_FAIL"))
            finish(false, "message failure fixture was rejected");
    }

    function startOversizedMessage() {
        phase = "message-oversized";
        var oversized = new Array(300001).join("x") + "OVERSIZED_MESSAGE";
        if (!streaming.copyMessageToClipboard("assistant-oversized", oversized))
            finish(false, "oversized message fixture was rejected");
    }

    function startMessageConversationOverlap() {
        phase = "message-conversation-overlap";
        if (!streaming.copyMessageToClipboard("assistant-slow", "MESSAGE_SLOW")) {
            finish(false, "message overlap fixture could not start");
            return;
        }
        if (streaming.exportToClipboard("CLIPBOARD_SUCCESS"))
            finish(false, "conversation copy overlapped an active message copy");
    }

    Component.onCompleted: Qt.callLater(startClipboardSuccess)

    Timer {
        interval: 10000
        running: true
        repeat: false
        onTriggered: root.finish(false, "timed out")
    }

    Process {
        id: fileVerifier
        running: false
        command: [
            "sh", "-c",
            "test \"$(stat -c %a \"$1\")\" = 600 && test \"$(cat \"$1\")\" = FILE_SUCCESS",
            "_", root.runtimeDir + "/export-success.md"
        ]
        onExited: exitCode => {
            if (!root.check(exitCode === 0,
                            "file export did not preserve stdin content and mode 0600")) return;
            Qt.callLater(root.startFileFailure);
        }
    }

    StreamingService {
        id: streaming

        onExportSucceeded: (exportId, exportKind, target) => {
            if (!root.checkIdentity(exportId)) return;
            if (!root.check(!streaming.exportBusy,
                            "successful export did not clear busy state before signaling")) return;

            if (root.phase === "clipboard-success") {
                if (!root.check(exportKind === "clipboard" && target === "clipboard",
                                "clipboard success signal had the wrong contract")) return;
                Qt.callLater(root.startClipboardFailure);
            } else if (root.phase === "file-success") {
                if (!root.check(exportKind === "file"
                                && target === root.runtimeDir + "/export-success.md",
                                "file success signal had the wrong target")) return;
                fileVerifier.running = true;
            } else if (root.phase === "overlap") {
                if (!root.check(exportKind === "clipboard" && root.overlapRejected,
                                "overlap completion was misattributed")) return;
                Qt.callLater(root.startMessageSuccess);
            } else {
                root.finish(false, "unexpected export success during " + root.phase);
            }
        }

        onExportFailed: (exportId, exportKind, message) => {
            if (!root.checkIdentity(exportId)) return;

            if (root.phase === "clipboard-nonzero") {
                if (!root.check(exportKind === "clipboard"
                                && message.indexOf("exit code 23") >= 0,
                                "clipboard nonzero exit was not reported truthfully")) return;
                Qt.callLater(root.startClipboardStartFailure);
            } else if (root.phase === "clipboard-start-failure") {
                if (!root.check(exportKind === "clipboard"
                                && message.indexOf("Could not start clipboard export") >= 0,
                                "clipboard start failure was not reported truthfully")) return;
                Qt.callLater(root.startFileSuccess);
            } else if (root.phase === "file-nonzero") {
                if (!root.check(exportKind === "file"
                                && message.indexOf("exit code 24") >= 0,
                                "file nonzero exit was not reported truthfully")) return;
                Qt.callLater(root.startFileStartFailure);
            } else if (root.phase === "file-start-failure") {
                if (!root.check(exportKind === "file"
                                && message.indexOf("Could not start file export") >= 0,
                                "file start failure was not reported truthfully")) return;
                Qt.callLater(root.startOverlapCheck);
            } else if (root.phase === "overlap") {
                if (!root.check(exportKind === "file"
                                && message.indexOf("already in progress") >= 0,
                                "overlapping export did not receive explicit feedback")) return;
                root.overlapRejected = true;
            } else if (root.phase === "message-conversation-overlap") {
                if (!root.check(exportKind === "clipboard"
                                && message.indexOf("already in progress") >= 0,
                                "overlapping conversation copy was not rejected")) return;
                root.messageOverlapRejected = true;
            } else {
                root.finish(false, "unexpected export failure during " + root.phase
                            + ": " + message);
            }
        }

        onMessageCopySucceeded: messageId => {
            if (!root.check(!streaming.exportBusy,
                            "message success did not clear busy state before signaling")) return;
            if (root.phase === "message-success") {
                if (!root.check(messageId === "assistant-secret",
                                "message success lost its identity")) return;
                Qt.callLater(root.startMessageFailure);
            } else if (root.phase === "message-oversized") {
                if (!root.check(messageId === "assistant-oversized",
                                "oversized message success lost its identity")) return;
                Qt.callLater(root.startMessageConversationOverlap);
            } else if (root.phase === "message-conversation-overlap") {
                if (!root.check(messageId === "assistant-slow"
                                && root.messageOverlapRejected,
                                "message completion was confused with rejected conversation copy")) return;
                root.finish(true, "conversation/file/message success, truthful failures, stdin-only oversized payloads, mode 0600, identities, and overlap rejection passed");
            } else {
                root.finish(false, "unexpected message success during " + root.phase);
            }
        }

        onMessageCopyFailed: (messageId, message) => {
            if (root.phase !== "message-nonzero") {
                root.finish(false, "unexpected message failure during " + root.phase
                            + ": " + message);
                return;
            }
            if (!root.check(messageId === "assistant-fail"
                            && message.indexOf("exit code 23") >= 0,
                            "message failure was not truthful or identity-bound")) return;
            Qt.callLater(root.startOversizedMessage);
        }
    }
}
