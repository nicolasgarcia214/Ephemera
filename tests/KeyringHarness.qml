import QtQuick
import Quickshell
import "./src/services"

ShellRoot {
    id: root

    property bool finished: false
    property string phase: "failed-lookup"
    property int operationSuccessCount: 0
    property int operationFailureCount: 0
    property string lastOperationFailure: ""
    property var seenMutationIds: ({})

    function finish(success, message) {
        if (finished) return;
        finished = true;
        console.log("EPHEMERA_KEYRING_TEST " + (success ? "PASS" : "FAIL")
                    + ": " + message);
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
        keyring._keyringAvailable = true;
        keyring._keyringCache = ({ custom: "cached-custom-key" });
        keyring.provider = "custom";
        keyring.refreshKeyringKey();
        pollTimer.start();
    }

    function pollState() {
        if (phase === "failed-lookup") {
            if (keyring._keyringOperation || keyring._keyringQueue.length > 0)
                return;
            if (!check(keyring._keyringCache.custom === "cached-custom-key",
                    "failed lookup changed the cached key")) return;

            keyring._keyringCache = ({ openai: "externally-deleted-key" });
            keyring.provider = "openai";
            phase = "external-deletion";
            keyring.refreshKeyringKey();
            return;
        }

        if (phase === "external-deletion") {
            if (keyring._keyringOperation || keyring._keyringQueue.length > 0)
                return;
            if (!check(keyring._keyringCache.openai === undefined,
                    "successful empty lookup retained an externally deleted key")) return;

            keyring._keyringCache = ({ openai: "clear-success-key" });
            phase = "successful-clear";
            if (!check(keyring.clearKeyringKey("openai"),
                    "successful clear was not queued")) return;
            check(keyring._keyringCache.openai === "clear-success-key",
                  "clear removed the cache before secret-tool completed");
            return;
        }

        if (phase === "successful-clear") {
            if (keyring._keyringCache.openai !== undefined)
                return;

            keyring._keyringCache = ({ anthropic: "clear-failure-key" });
            phase = "failed-clear";
            if (!check(keyring.clearKeyringKey("anthropic"),
                    "failed clear was not queued")) return;
            check(keyring._keyringCache.anthropic === "clear-failure-key",
                  "failed clear removed the cache before secret-tool completed");
            return;
        }

        if (phase === "failed-clear") {
            if (keyring._keyringCache.anthropic !== "actual-anthropic-key")
                return;

            keyring._keyringCache = ({});
            phase = "provider-overlap";
            if (!check(keyring.storeKeyringKey("openai", "stored-openai-key"),
                    "store was not queued")) return;
            keyring.provider = "gemini";
            keyring.refreshKeyringKey();
            check(keyring._keyringCache.openai === undefined,
                  "store updated the cache before secret-tool completed");
            return;
        }

        if (phase === "provider-overlap") {
            if (keyring._keyringCache.openai !== "stored-openai-key"
                    || keyring._keyringCache.gemini !== "actual-gemini-key")
                return;

            keyring._keyringCache = ({
                custom: "cached-custom-key",
                openai: "stored-openai-key"
            });
            phase = "failed-start";
            keyring._secretToolExecutable = "ephemera-missing-secret-tool";
            if (!check(keyring.clearKeyringKey("custom"),
                    "failed-start clear was not queued")) return;
            return;
        }

        if (phase === "failed-start") {
            if (keyring._keyringOperation || keyring._keyringQueue.length > 0)
                return;
            if (!check(keyring._keyringCache.custom === "cached-custom-key",
                    "failed command start changed the last known key")) return;
            if (!check(operationSuccessCount === 2 && operationFailureCount === 2
                    && lastOperationFailure.indexOf("system keyring") >= 0,
                    "keyring mutation results were not emitted exactly and safely")) return;
            finish(true, "lookup outcomes, mutation results, provider overlap, and failed starts kept the cache truthful");
        }
    }

    Component.onCompleted: Qt.callLater(runChecks)

    Timer {
        id: pollTimer
        interval: 10
        repeat: true
        onTriggered: root.pollState()
    }

    Timer {
        interval: 5000
        running: true
        repeat: false
        onTriggered: root.finish(false, "timed out during " + root.phase)
    }

    KeyringService {
        id: keyring
        provider: "openai"
        onKeyringOperationSucceeded: (operationId, operation, provider) => {
            if (!root.check(operationId.length > 0 && !root.seenMutationIds[operationId],
                    "successful mutation omitted or reused its operation identity")) return;
            root.seenMutationIds[operationId] = true;
            root.operationSuccessCount++;
        }
        onKeyringOperationFailed: (operationId, operation, provider, message) => {
            if (!root.check(operationId.length > 0 && !root.seenMutationIds[operationId],
                    "failed mutation omitted or reused its operation identity")) return;
            root.seenMutationIds[operationId] = true;
            root.operationFailureCount++;
            root.lastOperationFailure = message;
        }
    }
}
