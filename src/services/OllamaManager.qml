import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/Providers.js" as Providers

Item {
    id: root

    property string ollamaUrl: "http://localhost:11434"
    property bool isStreaming: false

    // --- Ollama state (exposed to parent) ---
    property ListModel availableModels: ListModel {}
    property bool ollamaWeStarted: false
    property bool ollamaStartPending: false
    property bool ollamaExternallyManaged: false
    property bool ollamaReady: false
    property int ollamaRetries: 0
    readonly property int ollamaMaxRetries: 15
    property bool _shuttingDown: false
    property int _ollamaPid: -1
    property int ollamaIdleMinutes: 5
    property string discoveryError: ""
    property string gpuLabel: ""

    signal modelDiscovered(string name)
    signal modelAutoSelected(string name)
    signal gpuStatusReady(string label)

    function ensureReady() {
        _shuttingDown = false;
        ollamaIdleTimer.stop();
        retryTimer.stop();
        ollamaRetries = 0;
        ping();
    }

    function shutdown() {
        _shuttingDown = true;
        ollamaIdleTimer.stop();
        retryTimer.stop();
        if (ollamaWeStarted) {
            if (_ollamaPid > 0) {
                // Kill by PID — precise, no collateral damage
                ollamaKiller.command = ["kill", String(_ollamaPid)];
                ollamaKiller.running = true;
                _ollamaPid = -1;
            }
            if (ollamaProcess.running)
                ollamaProcess.running = false;
        }
        ollamaWeStarted = false;
        ollamaStartPending = false;
        ollamaReady = false;
    }

    function forceShutdownExternal() {
        _shuttingDown = true;
        ollamaIdleTimer.stop();
        retryTimer.stop();
        // External Ollama: use pkill -x for exact process name match (not -f substring)
        // to avoid killing unrelated processes that merely contain "ollama" in their cmdline
        ollamaKiller.command = ["pkill", "-x", "-U", Quickshell.env("USER") || "", "ollama"];
        ollamaKiller.running = true;
        ollamaReady = false;
        ollamaExternallyManaged = false;
        ollamaWeStarted = false;
        ollamaStartPending = false;
    }

    function scheduleIdleShutdown() {
        if (!ollamaWeStarted || ollamaIdleMinutes <= 0) return;
        ollamaIdleTimer.restart();
    }

    function stopIdleTimer() {
        ollamaIdleTimer.stop();
    }

    function discoverModels() {
        discoveryError = "";
        if (!_isUrlSafe()) { discoveryError = "Invalid Ollama URL."; return; }
        modelDiscovery.command = ["curl", "-s", "--connect-timeout", "2", ollamaUrl + "/api/tags"];
        modelDiscovery.running = true;
    }

    function queryGpuStatus(modelName) {
        if (!ollamaReady || !modelName || !_isUrlSafe()) return;
        _gpuQueryModel = modelName;
        gpuQuery.command = ["curl", "-s", "--connect-timeout", "2", ollamaUrl + "/api/ps"];
        gpuQuery.running = true;
    }

    property string _gpuQueryModel: ""

    function cleanupOnDestruction() {
        if (ollamaWeStarted && !_shuttingDown) {
            _shuttingDown = true;
            ollamaProcess.running = false;
            _kill();
        }
    }

    function _isUrlSafe() {
        return Providers.validateUrl(ollamaUrl).valid;
    }

    // --- Internal ---

    function _kill() {
        if (_ollamaPid > 0) {
            ollamaKiller.command = ["kill", String(_ollamaPid)];
            ollamaKiller.running = true;
            _ollamaPid = -1;
        }
        // No pkill fallback — if we lost the PID, we don't kill random processes
    }

    function ping() {
        if (!_isUrlSafe()) return;
        ollamaPing.command = ["curl", "-s", "--connect-timeout", "2", ollamaUrl + "/api/tags"];
        ollamaPing.running = true;
    }

    function _handlePingFailed() {
        if (ollamaReady) {
            ollamaReady = false;
            ollamaExternallyManaged = false;
        }

        if (!ollamaWeStarted && !ollamaStartPending && ollamaRetries === 0) {
            ollamaStartPending = true;
            ollamaProcess.running = true;
        }

        ollamaRetries++;
        if (ollamaRetries <= ollamaMaxRetries)
            retryTimer.start();
    }

    onOllamaUrlChanged: {
        if (ollamaReady) {
            ollamaReady = false;
            ollamaRetries = 0;
            ollamaExternallyManaged = false;
            ollamaWeStarted = false;
            ping();
        }
    }

    // --- Processes ---

    Process {
        id: ollamaProcess
        command: ["ollama", "serve"]
        running: false
        onRunningChanged: {
            if (running && root.ollamaStartPending) {
                root._ollamaPid = ollamaProcess.processId;
                root.ollamaWeStarted = true;
                root.ollamaStartPending = false;
            } else if (!running && root.ollamaWeStarted && !root._shuttingDown) {
                root._ollamaPid = -1;
                root.ollamaWeStarted = false;
                root.ollamaStartPending = false;
                root.ollamaReady = false;
            }
        }
    }

    Process {
        id: ollamaKiller
        running: false
    }

    Process {
        id: ollamaPing
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text);
                    if (data && data.models !== undefined) {
                        root.ollamaReady = true;
                        if (!root.ollamaWeStarted && !root.ollamaStartPending)
                            root.ollamaExternallyManaged = true;
                        root.discoverModels();
                        return;
                    }
                } catch (e) {
                    console.warn("Ephemera: Ollama ping parse error:", e);
                }
                root._handlePingFailed();
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0)
                root._handlePingFailed();
        }
    }

    Process {
        id: modelDiscovery
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text);
                    var models = data.models || [];
                    root.availableModels.clear();
                    for (var i = 0; i < models.length; i++) {
                        var name = models[i].name || "";
                        root.availableModels.append({ name: name, displayName: "ollama:" + name });
                    }
                    if (root.availableModels.count > 0)
                        root.modelAutoSelected(root.availableModels.get(0).name);
                } catch (e) {
                    console.warn("Ephemera: model discovery parse error:", e);
                    root.discoveryError = "Failed to parse model list from Ollama.";
                }
            }
        }
    }

    Process {
        id: gpuQuery
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(text);
                    var models = data.models || [];
                    for (var i = 0; i < models.length; i++) {
                        var m = models[i];
                        if (m.name !== root._gpuQueryModel && m.model !== root._gpuQueryModel)
                            continue;
                        var total = m.size || 0;
                        var vram = m.size_vram || 0;
                        if (total <= 0) break;
                        var families = (m.details && m.details.families) || [];
                        var isMoE = families.some(function(f) { return f.toLowerCase().indexOf("moe") !== -1; });
                        var pct = Math.round(vram / total * 100);
                        if (pct >= 100 || (isMoE && pct > 0))
                            root.gpuLabel = "GPU";
                        else if (pct > 0)
                            root.gpuLabel = pct + "% GPU";
                        else
                            root.gpuLabel = "CPU";
                        root.gpuStatusReady(root.gpuLabel);
                        return;
                    }
                } catch (e) {
                    console.warn("Ephemera: GPU status query parse error:", e);
                }
            }
        }
    }

    // --- Timers ---

    Timer {
        id: retryTimer
        interval: 1000
        repeat: false
        onTriggered: root.ping()
    }

    Timer {
        id: ollamaIdleTimer
        interval: root.ollamaIdleMinutes * 60 * 1000
        repeat: false
        onTriggered: {
            if (root.ollamaWeStarted && !root.isStreaming)
                root.shutdown();
        }
    }
}
