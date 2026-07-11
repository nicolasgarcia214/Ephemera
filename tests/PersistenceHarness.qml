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

        finish(true, "atomic persistence lifecycle and migration are safe");
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
