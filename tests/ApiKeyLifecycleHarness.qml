import QtQuick
import Quickshell
import "./src/components"

ShellRoot {
    id: root

    property bool finished: false
    property var openAiDelegate: null
    property int nextOperation: 0

    function finish(success, message) {
        if (finished) return;
        finished = true;
        console.log("EPHEMERA_API_KEY_LIFECYCLE_TEST "
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

    function begin() {
        openAiDelegate = card._delegateForProvider("openai");
        if (!check(openAiDelegate !== null, "OpenAI key delegate was not created")) return;
        openAiDelegate._setInputForTest("replacement-secret");
        if (!check(openAiDelegate._submitStore(), "key store was not accepted")) return;
        if (!check(openAiDelegate._operationPending
                && openAiDelegate._pendingInputText === "replacement-secret",
                "pending key store discarded the input before confirmation")) return;
        failureTimer.start();
    }

    QtObject {
        id: mockService
        property bool _keyringAvailable: true

        signal keyringOperationSucceeded(string operationId, string operation, string provider)
        signal keyringOperationFailed(string operationId, string operation, string provider, string message)

        function apiKeySource(provider) { return ""; }
        function hasApiKeyForProvider(provider) { return false; }
        function storeKeyringKey(provider, key) {
            root.nextOperation++;
            return "store-test-" + root.nextOperation;
        }
        function clearKeyringKey(provider) {
            root.nextOperation++;
            return "clear-test-" + root.nextOperation;
        }
    }

    ApiKeysCard {
        id: card
        aiService: mockService
        Component.onCompleted: Qt.callLater(root.begin)
    }

    Timer {
        id: failureTimer
        interval: 10
        repeat: false
        onTriggered: {
            var pendingId = openAiDelegate._pendingOperationId;
            mockService.keyringOperationSucceeded(pendingId, "store", "anthropic");
            mockService.keyringOperationSucceeded(pendingId, "clear", "openai");
            mockService.keyringOperationSucceeded("wrong-id", "store", "openai");
            if (!root.check(openAiDelegate._operationPending
                    && openAiDelegate._pendingInputText === "replacement-secret"
                    && openAiDelegate._operationError === "",
                    "an unrelated keyring result changed the pending store")) return;
            mockService.keyringOperationFailed(
                pendingId, "store", "openai",
                "Could not store the API key in the system keyring.");
            Qt.callLater(function() {
                if (!root.check(!openAiDelegate._operationPending
                        && openAiDelegate._editing
                        && openAiDelegate._pendingInputText === "replacement-secret"
                        && openAiDelegate._operationError.indexOf("Could not store") === 0,
                        "failed store did not retain the input and show feedback")) return;
                if (!root.check(openAiDelegate._submitStore(),
                        "retry store was not accepted")) return;
                successTimer.start();
            });
        }
    }

    Timer {
        id: successTimer
        interval: 10
        repeat: false
        onTriggered: {
            mockService.keyringOperationSucceeded(
                openAiDelegate._pendingOperationId, "store", "openai");
            Qt.callLater(function() {
                if (!root.check(!openAiDelegate._operationPending
                        && !openAiDelegate._editing
                        && openAiDelegate._pendingInputText === ""
                        && openAiDelegate._operationError === "",
                        "successful retry did not clear input and feedback")) return;
                root.finish(true, "failed stores retain input with feedback and successful stores clear it after confirmation");
            });
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: false
        onTriggered: root.finish(false, "timed out")
    }
}
