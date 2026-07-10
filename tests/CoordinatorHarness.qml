import QtQuick
import Quickshell
import qs.Services
import "./src/services"

ShellRoot {
    id: root

    property bool finished: false

    function finish(success, message) {
        if (finished) return;
        finished = true;
        console.log("EPHEMERA_COORDINATOR_TEST "
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
        service.messagesModel.append({
            role: "user", content: "private Ollama context", thinking: "",
            id: "user-test", timestamp: 1, status: "ok",
            variantIndex: 0, variantCount: 1, modelName: "", streamStats: "",
            requestPayload: ""
        });
        service.messageIndexMap = ({ "user-test": 0 });
        service.variantStore = ({
            "assistant-test": [{ content: "private variant", thinking: "" }]
        });
        service.lastUserText = "private Ollama context";

        if (!check(service.setProvider("openai"),
                "coordinator rejected a real provider change")) return;
        if (!check(service.provider === "openai"
                && service.messagesModel.count === 0
                && service.lastUserText === ""
                && Object.keys(service.messageIndexMap).length === 0
                && Object.keys(service.variantStore).length === 0,
                "provider change did not clear the conversation")) return;
        if (!check(PluginService.loadPluginData("ephemera", "provider", "") === "openai",
                "provider change was not persisted")) return;

        service.messagesModel.append({
            role: "user", content: "same-provider context", thinking: "",
            id: "user-test-2", timestamp: 2, status: "ok",
            variantIndex: 0, variantCount: 1, modelName: "", streamStats: "",
            requestPayload: ""
        });
        service.messageIndexMap = ({ "user-test-3": 0 });
        service.variantStore = ({
            "assistant-test-3": [{ content: "external variant", thinking: "" }]
        });
        if (!check(!service.setProvider("openai")
                && service.messagesModel.count === 1,
                "same-provider selection cleared chat more than once")) return;

        service.setOllamaContextWindow(32768);
        if (!check(service.ollamaContextWindow === 32768
                && PluginService.loadPluginData(
                    "ephemera", "ollamaContextWindow", 0) === 32768,
                "Ollama context window was not normalized and persisted")) return;

        service.persistChat = true;
        PluginService.savePluginData("ephemera", "persistChat", true);
        externalChangeTimer.start();
    }

    function runExternalProviderChange() {
        service.messagesModel.append({
            role: "user", content: "persisted external-change context", thinking: "",
            id: "user-test-3", timestamp: 3, status: "ok",
            variantIndex: 0, variantCount: 1, modelName: "", streamStats: "",
            requestPayload: ""
        });

        // PluginService emits synchronously. This must not re-enter loadSettings
        // when clearing persisted history as part of the provider transaction.
        PluginService.savePluginData("ephemera", "provider", "ollama");
        if (!check(service.provider === "ollama"
                && service.messagesModel.count === 0
                && Object.keys(service.messageIndexMap).length === 0
                && Object.keys(service.variantStore).length === 0
                && service._loadingSettings === false,
                "external provider change did not complete without reentrancy")) return;
        if (!check(PluginService.loadPluginData(
                    "ephemera", "chatHistory", "missing") === ""
                && PluginService.loadPluginData(
                    "ephemera", "chatVariants", "missing") === "",
                "external provider change did not clear persisted chat")) return;

        finish(true, "provider changes are transactional, reentrancy-safe, and context is persisted");
    }

    Component.onCompleted: Qt.callLater(runChecks)

    Timer {
        interval: 5000
        running: true
        repeat: false
        onTriggered: root.finish(false, "timed out")
    }

    Timer {
        id: externalChangeTimer
        interval: 250
        repeat: false
        onTriggered: root.runExternalProviderChange()
    }

    EphemeraService {
        id: service
        pluginId: "ephemera"
    }
}
