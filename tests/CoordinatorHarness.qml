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
        if (!check(service.ollamaUrl === "http://127.0.0.1:11434"
                && service.baseUrl === "http://127.0.0.1:11434",
                "initial Ollama URL load did not synchronize endpoint identities")) return;

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

        if (!check(service.setOllamaUrl("http://localhost:11434"),
                "coordinator rejected a valid Ollama URL")) return;
        var nextPayload = service._buildPayload("next private turn");
        if (!check(service.ollamaUrl === "http://localhost:11434"
                && service.baseUrl === "http://localhost:11434"
                && nextPayload.baseUrl === "http://localhost:11434",
                "local Ollama URL change left the next request on the old endpoint")) return;
        if (!check(service.messagesModel.count === 1
                && service.lastUserText === "private Ollama context"
                && service.messageIndexMap["user-test"] === 0
                && service.variantStore["assistant-test"][0].content === "private variant",
                "same-provider Ollama URL change cleared conversation state")) return;
        if (!check(PluginService.loadPluginData(
                    "ephemera", "ollamaUrl", "") === "http://localhost:11434",
                "local Ollama URL change was not persisted")) return;

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

        if (!check(service.setProvider("custom"),
                "coordinator rejected the custom provider test setup")) return;
        service.baseUrl = "http://remote.example.test";
        service.model = "custom-model";
        service.sendMessage("private custom-provider request");
        var transportError = "Custom provider HTTP is allowed only for localhost or 127.0.0.0/8; use HTTPS for remote endpoints.";
        if (!check(service.lastRequestFailed
                && !service.isStreaming
                && service.messagesModel.count === 2
                && service.messagesModel.get(1).status === "error"
                && service.messagesModel.get(1).content === transportError
                && service.messagesModel.get(1).requestPayload === "",
                "custom HTTP transport rejection was not reported before launch")) return;

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

        service.messagesModel.append({
            role: "user", content: "same-provider external URL context", thinking: "",
            id: "user-test-4", timestamp: 4, status: "ok",
            variantIndex: 0, variantCount: 1, modelName: "", streamStats: "",
            requestPayload: ""
        });
        PluginService.savePluginData(
            "ephemera", "ollamaUrl", "http://127.0.0.1:11434");
        var externalPayload = service._buildPayload("next external turn");
        if (!check(service.ollamaUrl === "http://127.0.0.1:11434"
                && service.baseUrl === "http://127.0.0.1:11434"
                && externalPayload.baseUrl === "http://127.0.0.1:11434"
                && service.messagesModel.count === 1
                && service.messagesModel.get(0).content
                    === "same-provider external URL context"
                && service._loadingSettings === false,
                "external Ollama URL change was inconsistent or reentrant")) return;

        finish(true, "provider and Ollama endpoint changes are transactional and reentrancy-safe");
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
