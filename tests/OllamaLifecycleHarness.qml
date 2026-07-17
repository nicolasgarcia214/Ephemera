import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services
import "./src/services"

ShellRoot {
    id: root

    property bool finished: false
    property string phase: "non-ollama"
    property int pollCount: 0
    property string lifecycleDir: Quickshell.env("EPHEMERA_OLLAMA_LIFECYCLE_DIR")
    property string eventsPath: lifecycleDir + "/events"

    function finish(success, message) {
        if (finished) return;
        finished = true;
        console.log("EPHEMERA_OLLAMA_LIFECYCLE_TEST "
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

    function startChecks() {
        PluginService.savePluginData("ollama-lifecycle", "provider", "openai");
        serviceLoader.active = true;
        manager.ensureReady();
        manager.ping();
        Qt.callLater(function() {
            if (serviceLoader.item)
                serviceLoader.item.ensureOllamaReady();
        });
        settleTimer.start();
    }

    function verifyNonOllama() {
        eventCheck.command = ["test", "!", "-e", eventsPath];
        eventCheck.running = true;
    }

    function beginOwnedProviderSwitch() {
        phase = "owned-provider-switch";
        pollCount = 0;
        manager.active = true;
        pollTimer.start();
    }

    function pollLifecycle() {
        pollCount++;
        if (pollCount > 160) {
            finish(false, "lifecycle transition timed out in " + phase);
            return;
        }

        if (phase === "owned-provider-switch") {
            if (!manager.ollamaReady || !manager.ollamaWeStarted) {
                pollTimer.start();
                return;
            }
            manager.active = false;
            if (!check(manager.ollamaWeStarted,
                    "provider switch discarded ownership before process exit")) return;
            phase = "owned-provider-exit";
            pollTimer.start();
            return;
        }

        if (phase === "owned-provider-exit") {
            if (manager.ollamaWeStarted) {
                pollTimer.start();
                return;
            }
            if (!check(!manager.ollamaReady && !manager.ollamaExternallyManaged,
                    "provider switch retained stale Ollama readiness")) return;
            phase = "owned-endpoint-start";
            pollCount = 0;
            manager.active = true;
            pollTimer.start();
            return;
        }

        if (phase === "owned-endpoint-start") {
            if (!manager.ollamaReady || !manager.ollamaWeStarted) {
                pollTimer.start();
                return;
            }
            phase = "owned-endpoint-change";
            manager.ollamaUrl = "http://127.0.0.1:11434";
            if (!check(manager.ollamaWeStarted,
                    "endpoint change discarded ownership before process exit")) return;
            pollTimer.start();
            return;
        }

        if (phase === "owned-endpoint-change") {
            if (!manager.ollamaReady || !manager.ollamaExternallyManaged
                    || manager.ollamaWeStarted) {
                pollTimer.start();
                return;
            }
            phase = "external-provider-switch";
            manager.active = false;
            settleTimer.restart();
        }
    }

    function verifyEventOrder() {
        var script = "starts=$(grep -c '^START$' '" + eventsPath
            + "'); stops=$(grep -c '^STOP$' '" + eventsPath
            + "'); second_stop=$(grep -n '^STOP$' '" + eventsPath
            + "' | tail -n 1 | cut -d: -f1); external=$(grep -n '^PING_EXTERNAL$' '"
            + eventsPath + "' | head -n 1 | cut -d: -f1); "
            + "test \"$starts\" -eq 2 -a \"$stops\" -eq 2 "
            + "-a \"$external\" -gt \"$second_stop\"";
        eventCheck.command = ["sh", "-c", script];
        eventCheck.running = true;
    }

    function beginRemoteProbe() {
        phase = "remote-probe";
        manager.ollamaUrl = "https://ollama.example.test";
        manager.active = true;
        if (!check(!manager.localProcessManaged,
                "remote endpoint was treated as a managed local process")) return;
        if (!check(manager.forceShutdownExternal() === false,
                "remote endpoint allowed a local external-process kill")) return;
        remoteCheckTimer.start();
    }

    function verifyRemoteProbeOnly() {
        var script = "starts=$(grep -c '^START$' '" + eventsPath
            + "'); remote=$(grep -c '^PING_REMOTE$' '" + eventsPath
            + "'); test \"$starts\" -eq 2 -a \"$remote\" -ge 1";
        eventCheck.command = ["sh", "-c", script];
        eventCheck.running = true;
    }

    Component.onCompleted: Qt.callLater(startChecks)

    Timer {
        interval: 10000
        running: true
        repeat: false
        onTriggered: root.finish(false, "timed out")
    }

    Timer {
        id: settleTimer
        interval: 100
        repeat: false
        onTriggered: {
            if (root.phase === "non-ollama")
                root.verifyNonOllama();
            else if (root.phase === "external-provider-switch")
                root.verifyEventOrder();
        }
    }

    Timer {
        id: pollTimer
        interval: 50
        repeat: false
        onTriggered: root.pollLifecycle()
    }

    Timer {
        id: remoteCheckTimer
        interval: 250
        repeat: false
        onTriggered: root.verifyRemoteProbeOnly()
    }

    OllamaManager {
        id: manager
        active: false
        ollamaUrl: "http://localhost:11434"
    }

    Loader {
        id: serviceLoader
        active: false
        sourceComponent: Component {
            EphemeraService {
                pluginId: "ollama-lifecycle"
            }
        }
    }

    Process {
        id: eventCheck
        running: false
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.finish(false, root.phase === "non-ollama"
                    ? "non-Ollama readiness invoked curl or ollama"
                    : "owned stop/restart ordering or external ownership failed");
                return;
            }
            if (root.phase === "non-ollama")
                root.beginOwnedProviderSwitch();
            else if (root.phase === "external-provider-switch")
                root.beginRemoteProbe();
            else
                root.finish(true, "provider gates, owned shutdown, endpoint restart ordering, external ownership, and remote probe-only behavior are isolated");
        }
    }
}
