import QtQuick
import Quickshell
import "./src/components"
import "./src/services"

ShellRoot {
    id: root

    property bool finished: false
    property int attempts: 0

    function finish(success, message) {
        if (finished) return;
        finished = true;
        console.log("EPHEMERA_SETTINGS_CLOSE_GUARD_TEST "
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

    function inspectSettings() {
        attempts++;
        var settings = chat._settingsPanelForTest();
        var delegate = settings
            ? settings._apiKeyDelegateForTest("openai") : null;
        if (!settings || !delegate) {
            if (attempts > 50)
                finish(false, "settings API-key delegate was not created");
            else
                pollTimer.restart();
            return;
        }

        delegate._operationPending = true;
        delegate._pendingOperationId = "store-test-pending";
        delegate._pendingOperationType = "store";
        chat.closeSettings();
        if (!check(chat.showSettings && !chat._settingsClosing,
                   "explicit close destroyed settings during a pending keyring operation")) return;

        chat.visible = false;
        if (!check(chat.showSettings && chat._settingsPanelForTest() === settings,
                   "hiding the panel destroyed pending keyring input state")) return;
        chat.visible = true;

        delegate._operationPending = false;
        delegate._pendingOperationId = "";
        delegate._pendingOperationType = "";
        chat.closeSettings();
        if (!check(chat._settingsClosing,
                   "settings remained blocked after the keyring operation completed")) return;
        closeCheckTimer.start();
    }

    Component.onCompleted: {
        chat.showSettings = true;
        pollTimer.start();
    }

    Timer {
        id: pollTimer
        interval: 20
        repeat: false
        onTriggered: root.inspectSettings()
    }

    Timer {
        id: closeCheckTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (!root.check(!chat.showSettings && !chat._settingsClosing,
                            "settings did not close after pending state cleared")) return;
            root.finish(true, "pending keyring state blocks explicit close and panel-hide destruction until completion");
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: false
        onTriggered: root.finish(false, "timed out")
    }

    EphemeraService {
        id: service
        pluginId: "settings-close-guard"
    }

    EphemeraChat {
        id: chat
        width: 640
        height: 760
        aiService: service
    }
}
