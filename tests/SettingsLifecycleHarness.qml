import QtQuick
import Quickshell
import "./src/components"

ShellRoot {
    id: root

    property bool finished: false
    property int saveCount: 0
    property string savedKey: ""
    property string savedValue: ""

    function finish(success, message) {
        if (finished) return;
        finished = true;
        console.log("EPHEMERA_SETTINGS_LIFECYCLE_TEST "
                    + (success ? "PASS" : "FAIL") + ": " + message);
        Qt.quit();
    }

    QtObject {
        id: mockService
        property string provider: "openai"
        property string systemPrompt: ""
        property real temperature: 0.7
        property real tempMin: 0
        property real tempMax: 2
        property int maxTokens: 4096
        property bool unlimitedTokens: false
        property int maxTurns: 10
        property int timeout: 300

        function saveSettingValue(key, value) {
            root.saveCount++;
            root.savedKey = key;
            root.savedValue = value;
        }
    }

    Loader {
        id: settingsLoader
        active: true
        sourceComponent: Component {
            ModelParametersCard {
                aiService: mockService
            }
        }
        onLoaded: {
            item._saveSystemPromptImmediately("  preset 雪\nvalue  ");
            presetTimer.start();
        }
    }

    Timer {
        id: presetTimer
        interval: 620
        repeat: false
        onTriggered: {
            if (root.saveCount !== 1 || root.savedValue !== "  preset 雪\nvalue  ") {
                root.finish(false, "preset selection scheduled a duplicate save or changed exact text");
                return;
            }
            root.saveCount = 0;
            settingsLoader.item._queueSystemPromptSave("  persist 雪\nbefore close  ");
            closeTimer.start();
        }
    }

    Timer {
        id: closeTimer
        interval: 220
        repeat: false
        onTriggered: {
            settingsLoader.item.flushPendingSettings();
            settingsLoader.active = false;
        }
    }

    Timer {
        interval: 1300
        running: true
        repeat: false
        onTriggered: {
            if (root.saveCount !== 1 || root.savedKey !== "systemPrompt"
                    || root.savedValue !== "  persist 雪\nbefore close  ") {
                root.finish(false, "destroyed settings did not flush exactly one pending prompt save: count="
                    + root.saveCount + " key=" + root.savedKey + " value=" + root.savedValue);
                return;
            }
            root.finish(true, "settings destruction flushed the pending system prompt before its debounce elapsed");
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: false
        onTriggered: root.finish(false, "timed out")
    }
}
