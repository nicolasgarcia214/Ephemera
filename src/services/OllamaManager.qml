import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/Providers.js" as Providers

Item {
    id: root

    property string ollamaUrl: "http://localhost:11434"
    property bool active: true
    property bool isStreaming: false

    // --- Ollama state (exposed to parent) ---
    property ListModel availableModels: ListModel {}
    property bool ollamaWeStarted: false
    property bool ollamaStartPending: false
    property bool ollamaExternallyManaged: false
    property bool ollamaReady: false
    property int ollamaRetries: 0
    readonly property int ollamaMaxRetries: 15
    // curl enforces this against transferred bytes before StdioCollector retains
    // the response. QML string lengths are decoded UTF-16 code units and are not
    // suitable for enforcing a raw byte limit on multi-byte output.
    readonly property int _probeResponseLimitBytes: 64 * 1024
    readonly property int _curlFileSizeExceededExitCode: 63
    property string _probeExecutable: "curl"
    property bool _shuttingDown: false
    property bool _terminationPending: false
    property bool _restartAfterExit: false
    property bool _probePending: false
    property bool _pingProcessActive: false
    property bool _discoveryProcessActive: false
    property bool _discoveryPending: false
    property bool _gpuProcessActive: false
    property string _pendingGpuModel: ""
    property int _lifecycleGeneration: 0
    property int _pingGeneration: -1
    property int _discoveryGeneration: -1
    property int _gpuGeneration: -1
    property int _ollamaPid: -1
    property int ollamaIdleMinutes: 5
    property string readinessError: ""
    property string discoveryError: ""
    property string gpuError: ""
    readonly property string probeError: readinessError || discoveryError || gpuError
    property string gpuLabel: ""
    property int _lastPingResponseBytes: 0
    property int _lastPingResponseCharacters: 0
    property int _lastDiscoveryResponseBytes: 0
    property int _lastDiscoveryResponseCharacters: 0
    property int _lastGpuResponseBytes: 0
    property int _lastGpuResponseCharacters: 0

    signal modelDiscovered(string name)
    signal modelAutoSelected(string name)
    signal gpuStatusReady(string label)

    function ensureReady() {
        if (!active)
            return;
        _shuttingDown = false;
        ollamaIdleTimer.stop();
        retryTimer.stop();
        ollamaRetries = 0;
        if (_terminationPending) {
            _restartAfterExit = true;
            return;
        }
        ping();
    }

    function shutdown() {
        _shuttingDown = true;
        _restartAfterExit = false;
        _invalidateProbes();
        ollamaReady = false;
        ollamaExternallyManaged = false;
        if (ollamaWeStarted || ollamaStartPending || ollamaProcess.running)
            _requestOwnedStop(false);
        else
            _clearOwnership();
    }

    function forceShutdownExternal() {
        _shuttingDown = true;
        _restartAfterExit = false;
        _invalidateProbes();
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
        if (!active || !ollamaWeStarted || ollamaIdleMinutes <= 0) return;
        ollamaIdleTimer.restart();
    }

    function stopIdleTimer() {
        ollamaIdleTimer.stop();
    }

    function discoverModels() {
        discoveryError = "";
        if (!active) return;
        if (!_isUrlSafe()) { discoveryError = "Invalid Ollama URL."; return; }
        if (_discoveryProcessActive) {
            if (_discoveryGeneration !== _lifecycleGeneration) {
                _discoveryPending = true;
                if (modelDiscovery.running)
                    modelDiscovery.running = false;
            }
            return;
        }
        _discoveryPending = false;
        _discoveryGeneration = _lifecycleGeneration;
        modelDiscovery.command = _probeCommand("/api/tags");
        _discoveryProcessActive = true;
        modelDiscovery.running = true;
    }

    function queryGpuStatus(modelName) {
        if (!active || !ollamaReady || !modelName || !_isUrlSafe()) return;
        gpuError = "";
        if (_gpuProcessActive) {
            _pendingGpuModel = modelName;
            if (gpuQuery.running)
                gpuQuery.running = false;
            return;
        }
        _pendingGpuModel = "";
        _gpuQueryModel = modelName;
        _gpuGeneration = _lifecycleGeneration;
        gpuQuery.command = _probeCommand("/api/ps");
        _gpuProcessActive = true;
        gpuQuery.running = true;
    }

    property string _gpuQueryModel: ""

    function cleanupOnDestruction() {
        if (ollamaWeStarted || ollamaStartPending || ollamaProcess.running) {
            _shuttingDown = true;
            _restartAfterExit = false;
            _invalidateProbes();
            ollamaProcess.running = false;
            _kill();
        }
    }

    function _isUrlSafe() {
        return Providers.validateUrl(ollamaUrl).valid;
    }

    // --- Internal ---

    function _probeCommand(path) {
        return [_probeExecutable, "-s", "--connect-timeout", "2", "--max-filesize",
            String(_probeResponseLimitBytes), ollamaUrl + path];
    }

    function _overflowError(probeName) {
        return "Ollama " + probeName + " response exceeded the "
            + _probeResponseLimitBytes + "-byte limit.";
    }

    function _handlePingOutput(output) {
        try {
            var data = JSON.parse(output);
            if (data && typeof data.version === "string" && data.version.length > 0) {
                ollamaReady = true;
                readinessError = "";
                if (!ollamaWeStarted && !ollamaStartPending)
                    ollamaExternallyManaged = true;
                discoverModels();
                return;
            }
        } catch (e) {
            console.warn("Ephemera: Ollama ping parse error:", e);
        }
        _handlePingFailed();
    }

    function _finishPingStartFailure() {
        if (!_pingProcessActive)
            return;
        _pingProcessActive = false;
        var current = active && _pingGeneration === _lifecycleGeneration;
        if (current)
            readinessError = "Could not start Ollama readiness probe. Make sure curl is installed and available in PATH.";
        if (_probePending && active && !_terminationPending)
            Qt.callLater(ping);
    }

    function _finishDiscoveryStartFailure() {
        if (!_discoveryProcessActive)
            return;
        _discoveryProcessActive = false;
        if (active && _discoveryGeneration === _lifecycleGeneration)
            discoveryError = "Could not start Ollama model discovery. Make sure curl is installed and available in PATH.";
        if (_discoveryPending && active) {
            _discoveryPending = false;
            Qt.callLater(discoverModels);
        }
    }

    function _finishGpuStartFailure() {
        if (!_gpuProcessActive)
            return;
        _gpuProcessActive = false;
        if (active && _gpuGeneration === _lifecycleGeneration)
            gpuError = "Could not start Ollama GPU status probe. Make sure curl is installed and available in PATH.";
        if (_pendingGpuModel && active) {
            var pendingModel = _pendingGpuModel;
            _pendingGpuModel = "";
            Qt.callLater(function() { root.queryGpuStatus(pendingModel); });
        }
    }

    function _handleDiscoveryOutput(output) {
        try {
            var data = JSON.parse(output);
            var models = data.models || [];
            availableModels.clear();
            for (var i = 0; i < models.length; i++) {
                var name = models[i].name || "";
                availableModels.append({ name: name, displayName: "ollama:" + name });
            }
            if (availableModels.count > 0)
                modelAutoSelected(availableModels.get(0).name);
        } catch (e) {
            console.warn("Ephemera: model discovery parse error:", e);
            discoveryError = "Failed to parse model list from Ollama.";
        }
    }

    function _handleGpuOutput(output) {
        try {
            var data = JSON.parse(output);
            var models = data.models || [];
            for (var i = 0; i < models.length; i++) {
                var m = models[i];
                if (m.name !== _gpuQueryModel && m.model !== _gpuQueryModel)
                    continue;
                var total = m.size || 0;
                var vram = m.size_vram || 0;
                if (total <= 0) break;
                var families = (m.details && m.details.families) || [];
                var isMoE = families.some(function(f) { return f.toLowerCase().indexOf("moe") !== -1; });
                var pct = Math.round(vram / total * 100);
                if (pct >= 100 || (isMoE && pct > 0))
                    gpuLabel = "GPU";
                else if (pct > 0)
                    gpuLabel = pct + "% GPU";
                else
                    gpuLabel = "CPU";
                gpuStatusReady(gpuLabel);
                return;
            }
        } catch (e) {
            console.warn("Ephemera: GPU status query parse error:", e);
        }
    }

    function _clearOwnership() {
        _ollamaPid = -1;
        ollamaWeStarted = false;
        ollamaStartPending = false;
        _terminationPending = false;
    }

    function _invalidateProbes() {
        _lifecycleGeneration++;
        _probePending = false;
        _discoveryPending = false;
        _pendingGpuModel = "";
        ollamaIdleTimer.stop();
        retryTimer.stop();
        if (ollamaPing.running)
            ollamaPing.running = false;
        if (modelDiscovery.running)
            modelDiscovery.running = false;
        if (gpuQuery.running)
            gpuQuery.running = false;
    }

    function _requestOwnedStop(restartAfterExit) {
        _terminationPending = true;
        _restartAfterExit = restartAfterExit === true && active;
        if (ollamaProcess.running) {
            // Process.running targets the exact child we launched. Ownership
            // remains set until onExited confirms that child terminated.
            ollamaProcess.running = false;
            return;
        }
        if (ollamaWeStarted && _ollamaPid > 0)
            return;

        _clearOwnership();
        if (_restartAfterExit && active) {
            _restartAfterExit = false;
            Qt.callLater(ensureReady);
        }
    }

    function _finishOwnedProcessExit() {
        if (!ollamaWeStarted && !ollamaStartPending && !_terminationPending)
            return;
        var restart = _restartAfterExit && active;
        _clearOwnership();
        _restartAfterExit = false;
        ollamaReady = false;
        ollamaExternallyManaged = false;
        if (restart)
            Qt.callLater(ensureReady);
    }

    function _deactivate() {
        _shuttingDown = true;
        _restartAfterExit = false;
        _invalidateProbes();
        ollamaRetries = 0;
        ollamaReady = false;
        ollamaExternallyManaged = false;
        if (ollamaWeStarted || ollamaStartPending || ollamaProcess.running)
            _requestOwnedStop(false);
        else
            _clearOwnership();
    }

    function _kill() {
        if (_ollamaPid > 0) {
            ollamaKiller.command = ["kill", String(_ollamaPid)];
            ollamaKiller.running = true;
            _ollamaPid = -1;
        }
        // No pkill fallback — if we lost the PID, we don't kill random processes
    }

    function ping() {
        if (!active || _terminationPending || !_isUrlSafe()) return;
        readinessError = "";
        if (_pingProcessActive) {
            if (_pingGeneration !== _lifecycleGeneration) {
                _probePending = true;
                if (ollamaPing.running)
                    ollamaPing.running = false;
            }
            return;
        }
        _probePending = false;
        _pingGeneration = _lifecycleGeneration;
        ollamaPing.command = _probeCommand("/api/version");
        _pingProcessActive = true;
        ollamaPing.running = true;
    }

    function _handlePingFailed() {
        if (!active || _pingGeneration !== _lifecycleGeneration)
            return;
        if (ollamaReady) {
            ollamaReady = false;
            ollamaExternallyManaged = false;
        }

        if (!ollamaWeStarted && !ollamaStartPending && !_terminationPending
                && ollamaRetries === 0) {
            ollamaStartPending = true;
            ollamaProcess.running = true;
        }

        ollamaRetries++;
        if (ollamaRetries <= ollamaMaxRetries)
            retryTimer.start();
    }

    onActiveChanged: {
        if (active)
            ensureReady();
        else
            _deactivate();
    }

    onOllamaUrlChanged: {
        _invalidateProbes();
        ollamaReady = false;
        ollamaRetries = 0;
        ollamaExternallyManaged = false;
        if (!active)
            return;
        if (ollamaWeStarted || ollamaStartPending || ollamaProcess.running) {
            _shuttingDown = true;
            _requestOwnedStop(true);
        } else {
            _shuttingDown = false;
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
                if (!root.active || root._terminationPending)
                    Qt.callLater(function() { ollamaProcess.running = false; });
            } else if (!running && !root._terminationPending
                       && (root.ollamaWeStarted || root.ollamaStartPending)) {
                // QProcess may omit exited when launch itself fails. Normal
                // owned shutdowns are finalized only by onExited below.
                Qt.callLater(root._finishOwnedProcessExit);
            }
        }
        onExited: exitCode => root._finishOwnedProcessExit()
    }

    Process {
        id: ollamaKiller
        running: false
    }

    Process {
        id: ollamaPing
        running: false
        onRunningChanged: {
            if (!running && root._pingProcessActive)
                root._finishPingStartFailure();
        }
        stdout: StdioCollector {
            id: ollamaPingOutput
        }
        onExited: exitCode => {
            root._pingProcessActive = false;
            root._lastPingResponseBytes = ollamaPingOutput.data.byteLength;
            root._lastPingResponseCharacters = ollamaPingOutput.text.length;
            var current = root.active
                && root._pingGeneration === root._lifecycleGeneration;
            if (current && exitCode === root._curlFileSizeExceededExitCode) {
                root.ollamaReady = false;
                root.ollamaExternallyManaged = false;
                root.readinessError = root._overflowError("readiness");
            } else if (current && exitCode === 0) {
                root._handlePingOutput(ollamaPingOutput.text);
            } else if (current) {
                root._handlePingFailed();
            }
            if (root._probePending && root.active && !root._terminationPending)
                Qt.callLater(root.ping);
        }
    }

    Process {
        id: modelDiscovery
        running: false
        onRunningChanged: {
            if (!running && root._discoveryProcessActive)
                root._finishDiscoveryStartFailure();
        }
        stdout: StdioCollector {
            id: modelDiscoveryOutput
        }
        onExited: exitCode => {
            root._discoveryProcessActive = false;
            root._lastDiscoveryResponseBytes = modelDiscoveryOutput.data.byteLength;
            root._lastDiscoveryResponseCharacters = modelDiscoveryOutput.text.length;
            var current = root.active && root._discoveryGeneration
                === root._lifecycleGeneration;
            if (current && exitCode === root._curlFileSizeExceededExitCode)
                root.discoveryError = root._overflowError("model discovery");
            else if (current && exitCode === 0)
                root._handleDiscoveryOutput(modelDiscoveryOutput.text);
            if (root._discoveryPending && root.active) {
                root._discoveryPending = false;
                Qt.callLater(root.discoverModels);
            }
        }
    }

    Process {
        id: gpuQuery
        running: false
        onRunningChanged: {
            if (!running && root._gpuProcessActive)
                root._finishGpuStartFailure();
        }
        stdout: StdioCollector {
            id: gpuQueryOutput
        }
        onExited: exitCode => {
            root._gpuProcessActive = false;
            root._lastGpuResponseBytes = gpuQueryOutput.data.byteLength;
            root._lastGpuResponseCharacters = gpuQueryOutput.text.length;
            var current = root.active
                && root._gpuGeneration === root._lifecycleGeneration;
            if (current && exitCode === root._curlFileSizeExceededExitCode)
                root.gpuError = root._overflowError("GPU status");
            else if (current && exitCode === 0)
                root._handleGpuOutput(gpuQueryOutput.text);
            if (root._pendingGpuModel && root.active) {
                var pendingModel = root._pendingGpuModel;
                root._pendingGpuModel = "";
                Qt.callLater(function() { root.queryGpuStatus(pendingModel); });
            }
        }
    }

    // --- Timers ---

    Timer {
        id: retryTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (root.active)
                root.ping();
        }
    }

    Timer {
        id: ollamaIdleTimer
        interval: root.ollamaIdleMinutes * 60 * 1000
        repeat: false
        onTriggered: {
            if (root.active && root.ollamaWeStarted && !root.isStreaming)
                root.shutdown();
        }
    }
}
