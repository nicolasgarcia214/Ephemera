import QtQuick
import Quickshell
import qs.Services
import "./src/services"

ShellRoot {
    id: root

    property bool finished: false
    property string loadPurpose: "initial"
    property int saveCountAfterDebounce: 0
    property int saveCountAfterDisable: 0
    property int boundedSaveCount: 0
    property string boundedPayload: ""
    property int interruptedSaveCount: 0
    property string interruptedPayload: ""
    property var _nextStep: null

    function finish(success, message) {
        if (finished) return;
        finished = true;
        console.log("EPHEMERA_PERSISTENCE_TEST "
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

    function waitFor(milliseconds, nextStep) {
        _nextStep = nextStep;
        stepTimer.interval = milliseconds;
        stepTimer.restart();
    }

    function defaultData(persisted) {
        var data = {
            "ephemera:ollamaUrl": "http://127.0.0.1:11434",
            "ephemera:persistChat": persisted === true
        };
        return data;
    }

    function message(role, content, id, timestamp) {
        return {
            role: role, content: content, thinking: "",
            id: id, timestamp: timestamp, status: "ok",
            variantIndex: 0, variantCount: 1, modelName: "",
            streamStats: "", requestPayload: ""
        };
    }

    function repeatedText(character, count) {
        var result = "";
        var chunk = character;
        var remaining = count;
        while (remaining > 0) {
            if (remaining % 2 === 1) result += chunk;
            remaining = Math.floor(remaining / 2);
            if (remaining > 0) chunk += chunk;
        }
        return result;
    }

    function reload(nextPurpose, resetCallback) {
        serviceLoader.active = false;
        Qt.callLater(function() {
            if (resetCallback) resetCallback();
            loadPurpose = nextPurpose;
            serviceLoader.active = true;
        });
    }

    function onServiceReady() {
        if (loadPurpose === "initial") {
            runInitialEnable();
        } else if (loadPurpose === "reload-enabled") {
            checkEnabledReload();
        } else if (loadPurpose === "reload-disabled") {
            checkDisabledReload();
        } else if (loadPurpose === "migration") {
            checkMigration();
        } else if (loadPurpose === "bounded-load") {
            checkBoundedLoad();
        } else if (loadPurpose === "bounded-reload") {
            checkBoundedReload();
        } else if (loadPurpose === "interrupted-load") {
            checkInterruptedLoad();
        } else if (loadPurpose === "interrupted-reload") {
            checkInterruptedReload();
        }
    }

    function runInitialEnable() {
        var service = serviceLoader.item;
        if (!check(service && !service.persistChat,
                "coordinator did not start with persistence disabled")) return;
        var baselineSaves = PluginService.pluginStateSaveCount;

        service.messagesModel.append(message(
            "user", "atomic user message", "user-atomic", 1));
        service.messagesModel.append(message(
            "assistant", "atomic assistant message", "assistant-atomic", 2));
        service.messageIndexMap = ({
            "user-atomic": 0,
            "assistant-atomic": 1
        });
        service.variantStore = ({
            "assistant-atomic": [{
                content: "atomic assistant message",
                thinking: "atomic thought",
                modelName: "test-model"
            }]
        });
        service.lastUserText = "atomic user message";

        service.setPersistChat(true);
        if (!check(service.persistChat
                && PluginService.loadPluginData(
                    "ephemera", "persistChat", false) === true,
                "enabling persistence did not save the preference")) return;
        if (!check(PluginService.pluginStateSaveCount === baselineSaves,
                "chat state bypassed the coordinator debounce")) return;
        saveCountAfterDebounce = baselineSaves;
        waitFor(75, checkDebounceStillPending);
    }

    function checkDebounceStillPending() {
        if (!check(PluginService.pluginStateSaveCount === saveCountAfterDebounce,
                "chat state was committed before 150ms")) return;
        waitFor(125, checkAtomicSave);
    }

    function checkAtomicSave() {
        var payload = PluginService.loadPluginState(
            "ephemera", "chatState", null);
        if (!check(PluginService.pluginStateSaveCount
                    === saveCountAfterDebounce + 1,
                "debounced save did not use exactly one state write")) return;
        if (!check(payload && payload.version === 1
                && payload.messages.length === 2
                && payload.variants["assistant-atomic"].length === 1,
                "atomic state payload did not contain history and variants")) return;
        if (!check(PluginService.loadPluginData(
                    "ephemera", "chatHistory", "missing") === "missing"
                && PluginService.loadPluginData(
                    "ephemera", "chatVariants", "missing") === "missing",
                "normal save wrote legacy split settings")) return;

        saveCountAfterDebounce = PluginService.pluginStateSaveCount;
        reload("reload-enabled", null);
    }

    function checkEnabledReload() {
        var service = serviceLoader.item;
        if (!check(PluginService.pluginStateSaveCount
                    === saveCountAfterDebounce + 1,
                "destruction did not synchronously commit enabled chat")) return;
        if (!check(service.persistChat && service.messagesModel.count === 2
                && service.messagesModel.get(0).content === "atomic user message"
                && service.variantStore["assistant-atomic"][0].thinking
                    === "atomic thought",
                "reload did not restore the atomic chat payload")) return;

        service.saveChatHistory();
        service.setPersistChat(false);
        saveCountAfterDisable = PluginService.pluginStateSaveCount;
        if (!check(!service.persistChat
                && PluginService.loadPluginData(
                    "ephemera", "persistChat", true) === false
                && PluginService.loadPluginState(
                    "ephemera", "chatState", null) === null,
                "disabling persistence did not immediately delete state")) return;
        waitFor(225, checkDisableCancelledPendingSave);
    }

    function checkDisableCancelledPendingSave() {
        if (!check(PluginService.pluginStateSaveCount === saveCountAfterDisable
                && PluginService.loadPluginState(
                    "ephemera", "chatState", null) === null,
                "a pending save resurrected state after persistence was disabled")) return;
        reload("reload-disabled", null);
    }

    function checkDisabledReload() {
        var service = serviceLoader.item;
        if (!check(!service.persistChat && service.messagesModel.count === 0,
                "disabled reload resurrected old chat")) return;
        var beforeEnable = PluginService.pluginStateSaveCount;
        service.setPersistChat(true);
        saveCountAfterDebounce = beforeEnable;
        waitFor(200, checkReenabledState);
    }

    function checkReenabledState() {
        var service = serviceLoader.item;
        var payload = PluginService.loadPluginState(
            "ephemera", "chatState", null);
        if (!check(PluginService.pluginStateSaveCount
                    === saveCountAfterDebounce + 1
                && payload && payload.messages.length === 0
                && Object.keys(payload.variants).length === 0,
                "re-enabling persistence resurrected deleted chat")) return;

        service.setPersistChat(false);
        PluginService.savePluginState("ephemera", "chatState", {
            version: 1,
            messages: [message("user", "stale state", "user-stale", 3)],
            variants: {}
        });
        service.messagesModel.append(message(
            "user", "in-memory state", "user-memory", 4));
        service.clearChat();
        if (!check(!service.persistChat && service.messagesModel.count === 0
                && PluginService.loadPluginState(
                    "ephemera", "chatState", null) === null,
                "clearChat did not delete state while persistence was disabled")) return;

        reload("migration", seedLegacyState);
    }

    function seedLegacyState() {
        var data = defaultData(true);
        data["ephemera:chatHistory"] = JSON.stringify([
            message("user", "legacy user", "user-legacy", 10),
            message("assistant", "legacy assistant", "assistant-legacy", 11)
        ]);
        data["ephemera:chatVariants"] = JSON.stringify({
            "assistant-legacy": [{
                content: "legacy assistant",
                thinking: "legacy thought",
                modelName: "legacy-model"
            }]
        });
        PluginService.reset(data, {});
    }

    function checkMigration() {
        var service = serviceLoader.item;
        var payload = PluginService.loadPluginState(
            "ephemera", "chatState", null);
        if (!check(service.persistChat && service.messagesModel.count === 2
                && service.messagesModel.get(0).content === "legacy user"
                && service.variantStore["assistant-legacy"][0].thinking
                    === "legacy thought",
                "legacy split chat did not migrate into the coordinator")) return;
        if (!check(PluginService.pluginStateSaveCount === 1
                && payload && payload.version === 1
                && payload.messages.length === 2
                && payload.variants["assistant-legacy"].length === 1,
                "migration was not promoted with one atomic state write")) return;
        if (!check(PluginService.loadPluginData(
                    "ephemera", "chatHistory", "missing") === ""
                && PluginService.loadPluginData(
                    "ephemera", "chatVariants", "missing") === "",
                "migration did not clear both legacy keys")) return;

        service.messagesModel.clear();
        service.messagesModel.append(message(
            "user", "sentinel", "user-sentinel", 20));
        service.messageIndexMap = ({ "user-sentinel": 0 });
        service.variantStore = ({});
        service.lastUserText = "sentinel";

        var malformedData = defaultData(true);
        malformedData["ephemera:chatHistory"] = "{broken";
        malformedData["ephemera:chatVariants"] = "{}";
        PluginService.reset(malformedData, {});
        service.loadChatHistory();
        if (!check(service.messagesModel.count === 1
                && service.messagesModel.get(0).content === "sentinel"
                && service.messageIndexMap["user-sentinel"] === 0
                && service.lastUserText === "sentinel",
                "malformed legacy state partially mutated the live model")) return;
        if (!check(PluginService.loadPluginData(
                    "ephemera", "chatHistory", "missing") === ""
                && PluginService.loadPluginState(
                    "ephemera", "chatState", null) === null,
                "malformed legacy state did not fail closed")) return;

        var malformedState = {};
        malformedState["ephemera:chatState"] = {
            version: 99,
            messages: [],
            variants: {}
        };
        PluginService.reset(defaultData(true), malformedState);
        service.loadChatHistory();
        if (!check(service.messagesModel.count === 1
                && service.messagesModel.get(0).content === "sentinel"
                && PluginService.loadPluginState(
                    "ephemera", "chatState", null) === null,
                "malformed versioned state did not fail closed atomically")) return;

        reload("bounded-load", seedBoundedState);
    }

    function seedBoundedState() {
        var messages = [];
        for (var i = 0; i < 101; i++) {
            messages.push(message("user", "user turn " + i, "user-" + i,
                                  1000 + i * 2));
            messages.push(message("assistant", "assistant turn " + i,
                                  "assistant-" + i, 1001 + i * 2));
        }
        var variants = [];
        for (var j = 0; j < 11; j++) {
            variants.push({
                content: "variant-" + j,
                thinking: "thought-" + j,
                modelName: "model-" + j
            });
        }
        messages[messages.length - 2].content = repeatedText("x", 32769);
        messages[messages.length - 2].thinking = repeatedText("t", 32769);
        messages[messages.length - 1].variantIndex = 10;
        messages[messages.length - 1].variantCount = 11;

        var state = {};
        state["ephemera:chatState"] = {
            version: 1,
            messages: messages,
            variants: {
                "assistant-100": variants,
                "orphan-assistant": [{
                    content: "orphan", thinking: "", modelName: ""
                }]
            }
        };
        PluginService.reset(defaultData(true), state);
    }

    function checkBoundedLoad() {
        var service = serviceLoader.item;
        var payload = PluginService.loadPluginState(
            "ephemera", "chatState", null);
        if (!check(service.persistChat
                && service.messagesModel.count === service.persistedMessageLimit
                && service.messagesModel.get(0).id === "user-1"
                && service.messagesModel.get(199).id === "assistant-100",
                "oversized versioned history was not pruned by complete oldest turns")) return;
        if (!check(service.messageIndexMap["user-1"] === 0
                && service.messageIndexMap["assistant-100"] === 199
                && service.messageIndexMap["user-0"] === undefined,
                "bounded reload did not rebuild coherent message indices")) return;
        if (!check(service.messagesModel.get(198).content.length
                    === service.persistedContentByteLimit
                && service.messagesModel.get(198).thinking.length
                    === service.persistedThinkingByteLimit,
                "oversized persisted fields were not truncated at their bounds")) return;
        if (!check(service.variantStore["assistant-100"].length
                    === service.maxVariantsPerMessage
                && service.variantStore["assistant-100"][0].content === "variant-1"
                && service.messagesModel.get(199).variantIndex === 9
                && service.messagesModel.get(199).variantCount === 10
                && service.variantStore["orphan-assistant"] === undefined,
                "variant bounds, references, or orphan pruning were inconsistent")) return;
        if (!check(payload && payload.messages.length === 200
                && JSON.stringify(payload).length <= service.persistedPayloadByteLimit
                && PluginService.pluginStateSaveCount === 1,
                "normalized versioned state was not saved atomically within its byte cap")) return;

        boundedPayload = JSON.stringify(payload);
        boundedSaveCount = PluginService.pluginStateSaveCount;
        reload("bounded-reload", null);
    }

    function checkBoundedReload() {
        var service = serviceLoader.item;
        var payload = PluginService.loadPluginState(
            "ephemera", "chatState", null);
        if (!check(service.messagesModel.count === 200
                && service.messagesModel.get(0).id === "user-1"
                && service.messagesModel.get(199).id === "assistant-100"
                && service.messageIndexMap["assistant-100"] === 199,
                "bounded state did not reload consistently")) return;
        if (!check(JSON.stringify(payload) === boundedPayload
                && PluginService.pluginStateSaveCount === boundedSaveCount + 1,
                "bounded reload changed the normalized payload or rewrote it on load")) return;

        var activeText = repeatedText(
            "z", service.persistedContentByteLimit + 100);
        service.messagesModel.setProperty(199, "content", activeText);
        service.messagesModel.setProperty(199, "status", "streaming");
        service._commitChatHistory();
        payload = PluginService.loadPluginState("ephemera", "chatState", null);
        if (!check(service.messagesModel.get(199).content === activeText
                && service.messagesModel.get(199).status === "streaming"
                && payload.messages[payload.messages.length - 1].id === "user-100"
                && payload.variants["assistant-100"] === undefined,
                "snapshot bounding mutated or persisted active transport state")) return;

        service.messagesModel.clear();
        service.messagesModel.append(message(
            "user", "interrupted request", "user-interrupted", 3000));
        var streaming = message(
            "assistant", "partial transport", "assistant-interrupted", 3001);
        streaming.status = "streaming";
        service.messagesModel.append(streaming);
        service.messageIndexMap = ({
            "user-interrupted": 0,
            "assistant-interrupted": 1
        });
        service.variantStore = ({});
        service.lastUserText = "interrupted request";
        service._commitChatHistory();
        payload = PluginService.loadPluginState("ephemera", "chatState", null);
        if (!check(payload.messages.length === 1
                && payload.messages[0].id === "user-interrupted",
                "destruction snapshot did not preserve the dangling user alone")) return;

        interruptedSaveCount = PluginService.pluginStateSaveCount;
        reload("interrupted-load", null);
    }

    function checkInterruptedLoad() {
        var service = serviceLoader.item;
        if (!check(service.messagesModel.count === 1
                && service.messagesModel.get(0).id === "user-interrupted"
                && service.messageIndexMap["user-interrupted"] === 0,
                "dangling user did not reload after an interrupted stream")) return;

        service.messagesModel.append(message(
            "user", "later request", "user-later", 4000));
        service.messagesModel.append(message(
            "assistant", "later response", "assistant-later", 4001));
        service.messageIndexMap = ({
            "user-interrupted": 0,
            "user-later": 1,
            "assistant-later": 2
        });
        service.variantStore = ({
            "assistant-later": [{
                content: "later response", thinking: "later thought",
                modelName: "later-model"
            }]
        });
        service.lastUserText = "later request";
        service._commitChatHistory();

        var payload = PluginService.loadPluginState(
            "ephemera", "chatState", null);
        if (!check(PluginService.pluginStateSaveCount
                    === interruptedSaveCount + 2
                && payload.messages.length === 3
                && payload.messages[0].id === "user-interrupted"
                && payload.messages[1].id === "user-later"
                && payload.messages[2].id === "assistant-later"
                && payload.variants["assistant-later"][0].thinking
                    === "later thought",
                "later completed turn was refused or lost after interruption")) return;

        interruptedPayload = JSON.stringify(payload);
        interruptedSaveCount = PluginService.pluginStateSaveCount;
        reload("interrupted-reload", null);
    }

    function checkInterruptedReload() {
        var service = serviceLoader.item;
        var payload = PluginService.loadPluginState(
            "ephemera", "chatState", null);
        if (!check(service.messagesModel.count === 3
                && service.messagesModel.get(0).id === "user-interrupted"
                && service.messagesModel.get(1).id === "user-later"
                && service.messagesModel.get(2).id === "assistant-later"
                && service.messageIndexMap["assistant-later"] === 2
                && service.variantStore["assistant-later"][0].thinking
                    === "later thought",
                "interrupted history did not reload coherently after later completion")) return;
        if (!check(JSON.stringify(payload) === interruptedPayload
                && PluginService.pluginStateSaveCount === interruptedSaveCount + 1,
                "interrupted history was rewritten or lost during final reload")) return;

        finish(true, "bounded persistence and interrupted-stream reload are safe");
    }

    Component.onCompleted: {
        PluginService.reset(defaultData(false), {});
        serviceLoader.active = true;
    }

    Timer {
        id: loadTimer
        interval: 40
        repeat: false
        onTriggered: root.onServiceReady()
    }

    Timer {
        id: stepTimer
        repeat: false
        onTriggered: {
            var next = root._nextStep;
            root._nextStep = null;
            if (next) next();
        }
    }

    Timer {
        interval: 10000
        running: true
        repeat: false
        onTriggered: root.finish(false, "timed out")
    }

    Loader {
        id: serviceLoader
        active: false
        sourceComponent: serviceComponent
        onLoaded: loadTimer.restart()
    }

    Component {
        id: serviceComponent
        EphemeraService {
            pluginId: "ephemera"
        }
    }
}
