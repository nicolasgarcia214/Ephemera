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

    function requestSettings(payload) {
        var settings = JSON.parse(JSON.stringify(payload));
        delete settings.messages;
        return settings;
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
        if (!check(PluginService.loadPluginState(
                    "ephemera", "chatState", null) === null,
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

        runRequestMutationChecks();
    }

    function runRequestMutationChecks() {
        service.model = "snapshot-model";
        service.systemPrompt = "snapshot prompt";
        service.temperature = 0.25;
        service.maxTokens = 2048;
        service.unlimitedTokens = false;
        service.maxTurns = 3;
        service.timeout = 45;
        service.ollamaThinkingMode = "low";
        service.ollamaContextWindow = 8192;
        service.thinkingEnabled = false;
        service.setOllamaUrl("http://127.0.0.1:11434");

        service._startStreaming("snapshot turn");
        var streamId = service.activeStreamId;
        var streamIndex = service.findIndexById(streamId);
        var initialPayload = JSON.parse(
            service.messagesModel.get(streamIndex).requestPayload);

        service.model = "future-model";
        service.systemPrompt = "future prompt";
        service.temperature = 1.5;
        service.maxTokens = 8192;
        service.unlimitedTokens = true;
        service.maxTurns = 1;
        service.timeout = 90;
        service.ollamaThinkingMode = "high";
        service.ollamaContextWindow = 32768;
        service.thinkingEnabled = true;
        service.setOllamaUrl("http://localhost:11434");

        // A replacement launch is the same coordinator path used by retries.
        service._launchCurl();
        var replacementPayload = JSON.parse(
            service.messagesModel.get(streamIndex).requestPayload);
        if (!check(JSON.stringify(replacementPayload) === JSON.stringify(initialPayload),
                "active stream replacement adopted edited request settings")) return;

        var context = service._activeStreamContext();
        var continuationMessages = initialPayload.messages.concat([
            { role: "assistant", content: "", tool_calls: [{
                function: { name: "lookup", arguments: "{}" }
            }] },
            { role: "tool", tool_name: "lookup", content: "tool result" }
        ]);
        if (!check(service._launchCurlWithMessages(
                    context.streamId, continuationMessages,
                    context.provider, context.generation),
                "active MCP continuation was rejected")) return;
        var continuationPayload = JSON.parse(
            service.messagesModel.get(streamIndex).requestPayload);
        if (!check(JSON.stringify(requestSettings(continuationPayload))
                    === JSON.stringify(requestSettings(initialPayload))
                && JSON.stringify(continuationPayload.messages)
                    === JSON.stringify(continuationMessages),
                "MCP continuation rebuilt settings or lost evolving messages")) return;
        if (!check(!service._launchCurlWithMessages(
                    context.streamId, continuationMessages,
                    context.provider, context.generation - 1),
                "stale MCP generation was allowed to resume")) return;

        service.switchVariant(streamId, 0);
        if (!check(service.messagesModel.get(streamIndex).modelName === "snapshot-model",
                "active response attribution adopted the edited model")) return;

        service.cancel();
        if (!check(service.model === "future-model"
                && service.baseUrl === "http://localhost:11434"
                && service.systemPrompt === "future prompt"
                && service.temperature === 1.5
                && service.maxTokens === 8192
                && service.unlimitedTokens
                && service.maxTurns === 1
                && service.timeout === 90
                && service.ollamaThinkingMode === "high"
                && service.ollamaContextWindow === 32768
                && service.thinkingEnabled,
                "stream completion overwrote future request settings")) return;
        nextRequestTimer.start();
    }

    function runNextRequestChecks() {
        service._startStreaming("future turn");
        var streamIndex = service.findIndexById(service.activeStreamId);
        var payload = JSON.parse(
            service.messagesModel.get(streamIndex).requestPayload);
        if (!check(payload.model === "future-model"
                && payload.baseUrl === "http://localhost:11434"
                && payload.temperature === 1.5
                && payload.max_tokens === 0
                && payload.timeout === 90
                && payload.ollamaThinkingMode === "high"
                && payload.ollamaContextWindow === 32768
                && payload.thinkingEnabled
                && payload.messages.length === 2
                && payload.messages[0].role === "system"
                && payload.messages[0].content === "future prompt"
                && payload.messages[1].role === "user"
                && payload.messages[1].content === "future turn",
                "next stream did not use the edited request settings")) return;
        service.cancel();
        finish(true, "provider transactions and per-stream request snapshots are isolated");
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

    Timer {
        id: nextRequestTimer
        interval: 50
        repeat: false
        onTriggered: root.runNextRequestChecks()
    }

    EphemeraService {
        id: service
        pluginId: "ephemera"
    }
}
