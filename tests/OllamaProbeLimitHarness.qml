import QtQuick
import Quickshell
import "./src/services"

ShellRoot {
    id: root

    property bool finished: false
    property string phase: "normal-ready"
    property int pollCount: 0

    function finish(success, message) {
        if (finished) return;
        finished = true;
        console.log("EPHEMERA_OLLAMA_PROBE_LIMIT_TEST "
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

    function setPhase(nextPhase, url) {
        phase = nextPhase;
        pollCount = 0;
        if (url)
            manager.ollamaUrl = url;
        pollTimer.restart();
    }

    function checkExactResponse(bytes, characters, probeName) {
        return check(bytes === manager._probeResponseLimitBytes,
                probeName + " did not retain exactly the byte limit")
            && check(characters < bytes,
                probeName + " used decoded character count as its byte limit");
    }

    function poll() {
        pollCount++;
        if (pollCount > 400) {
            finish(false, "probe transition timed out in " + phase);
            return;
        }

        if (phase === "normal-ready") {
            if (!manager.ollamaReady || manager._discoveryProcessActive) {
                pollTimer.restart();
                return;
            }
            if (!check(manager.availableModels.count === 1,
                    "normal model discovery did not complete")) return;
            phase = "normal-gpu";
            manager.queryGpuStatus("normal-model");
            return;
        }

        if (phase === "exact-ready") {
            if (!manager.ollamaReady || manager._discoveryProcessActive) {
                pollTimer.restart();
                return;
            }
            if (!checkExactResponse(manager._lastPingResponseBytes,
                    manager._lastPingResponseCharacters, "readiness")) return;
            if (!checkExactResponse(manager._lastDiscoveryResponseBytes,
                    manager._lastDiscoveryResponseCharacters, "discovery")) return;
            if (!check(manager.probeError === "",
                    "exact-bound readiness or discovery failed")) return;
            phase = "exact-gpu";
            manager.queryGpuStatus("exact-model");
            return;
        }

        if (phase === "readiness-overflow") {
            if (!manager.readinessError) {
                pollTimer.restart();
                return;
            }
            if (!check(manager.readinessError
                    === "Ollama readiness response exceeded the 65536-byte limit.",
                    "readiness overflow did not expose a deterministic error")) return;
            if (!checkExactResponse(manager._lastPingResponseBytes,
                    manager._lastPingResponseCharacters,
                    "overflowing readiness")) return;
            if (!check(!manager.ollamaReady && !manager.ollamaWeStarted
                    && !manager.ollamaStartPending && manager.ollamaRetries === 0,
                    "readiness overflow changed Ollama ownership or retried startup")) return;
            setPhase("readiness-recovery", "http://127.0.0.10:11434");
            return;
        }

        if (phase === "readiness-recovery") {
            if (!manager.ollamaReady || manager._discoveryProcessActive) {
                pollTimer.restart();
                return;
            }
            if (!check(manager.readinessError === "",
                    "readiness did not recover after overflow")) return;
            setPhase("discovery-overflow", "http://127.0.0.13:11434");
            return;
        }

        if (phase === "discovery-overflow") {
            if (!manager.discoveryError) {
                pollTimer.restart();
                return;
            }
            if (!check(manager.ollamaReady && !manager._discoveryProcessActive,
                    "discovery overflow damaged readiness")) return;
            if (!check(manager.discoveryError
                    === "Ollama model discovery response exceeded the 65536-byte limit.",
                    "discovery overflow did not expose a deterministic error")) return;
            if (!checkExactResponse(manager._lastDiscoveryResponseBytes,
                    manager._lastDiscoveryResponseCharacters,
                    "overflowing discovery")) return;
            if (!check(!manager.ollamaWeStarted && !manager.ollamaStartPending,
                    "discovery overflow changed Ollama ownership")) return;
            setPhase("gpu-overflow-ready", "http://127.0.0.14:11434");
            return;
        }

        if (phase === "gpu-overflow-ready") {
            if (!manager.ollamaReady || manager._discoveryProcessActive) {
                pollTimer.restart();
                return;
            }
            phase = "gpu-overflow";
            manager.queryGpuStatus("gpu-model");
            pollTimer.restart();
            return;
        }

        if (phase === "gpu-overflow") {
            if (!manager.gpuError) {
                pollTimer.restart();
                return;
            }
            if (!check(manager.gpuError
                    === "Ollama GPU status response exceeded the 65536-byte limit.",
                    "GPU overflow did not expose a deterministic error")) return;
            if (!checkExactResponse(manager._lastGpuResponseBytes,
                    manager._lastGpuResponseCharacters,
                    "overflowing GPU probe")) return;
            if (!check(manager.ollamaReady && !manager.ollamaWeStarted
                    && !manager.ollamaStartPending,
                    "GPU overflow changed readiness or ownership")) return;
            setPhase("final-recovery-ready", "http://127.0.0.10:11434");
            return;
        }

        if (phase === "final-recovery-ready") {
            if (!manager.ollamaReady || manager._discoveryProcessActive) {
                pollTimer.restart();
                return;
            }
            phase = "final-recovery-gpu";
            manager.queryGpuStatus("normal-model");
            return;
        }

        if (phase === "empty-discovery") {
            if (manager._discoveryProcessActive || !manager.discoveryError) {
                pollTimer.restart();
                return;
            }
            if (!check(manager.ollamaReady
                    && manager.discoveryError
                        === "Failed to parse model list from Ollama."
                    && manager._lastDiscoveryResponseBytes === 0
                    && manager._lastDiscoveryResponseCharacters === 0,
                    "zero-output discovery replayed retained collector data")) return;
            manager._probeExecutable = "/ephemera-test/missing-curl";
            phase = "failed-readiness-start";
            manager.ping();
            pollTimer.restart();
            return;
        }

        if (phase === "failed-readiness-start") {
            if (!manager.readinessError) {
                pollTimer.restart();
                return;
            }
            if (!check(!manager._pingProcessActive
                    && manager.readinessError
                        === "Could not start Ollama readiness probe. Make sure curl is installed and available in PATH."
                    && manager.ollamaRetries === 0
                    && !manager.ollamaStartPending,
                    "failed readiness launch remained active or lacked feedback")) return;
            phase = "failed-discovery-start";
            manager.discoverModels();
            pollTimer.restart();
            return;
        }

        if (phase === "failed-discovery-start") {
            if (!manager.discoveryError) {
                pollTimer.restart();
                return;
            }
            if (!check(!manager._discoveryProcessActive
                    && manager.discoveryError
                        === "Could not start Ollama model discovery. Make sure curl is installed and available in PATH.",
                    "failed discovery launch remained active or lacked feedback")) return;
            phase = "failed-gpu-start";
            manager.ollamaReady = true;
            manager.queryGpuStatus("normal-model");
            pollTimer.restart();
            return;
        }

        if (phase === "failed-gpu-start") {
            if (!manager.gpuError) {
                pollTimer.restart();
                return;
            }
            if (!check(!manager._gpuProcessActive
                    && manager.gpuError
                        === "Could not start Ollama GPU status probe. Make sure curl is installed and available in PATH.",
                    "failed GPU launch remained active or lacked feedback")) return;
            phase = "failed-start-recovery";
            manager._probeExecutable = "curl";
            manager.ensureReady();
            pollTimer.restart();
            return;
        }

        if (phase === "failed-start-recovery") {
            if (!manager.ollamaReady || manager._discoveryProcessActive) {
                pollTimer.restart();
                return;
            }
            if (!check(!manager._pingProcessActive
                    && manager.readinessError === "",
                    "readiness probe did not recover after failed launch")) return;
            manager.active = false;
            finish(true, "version readiness, capped probes, overflow recovery, zero-output isolation, and failed-start cleanup passed");
        }
    }

    Component.onCompleted: {
        manager.active = true;
        pollTimer.start();
    }

    Timer {
        interval: 11000
        running: true
        repeat: false
        onTriggered: root.finish(false, "timed out")
    }

    Timer {
        id: pollTimer
        interval: 20
        repeat: false
        onTriggered: root.poll()
    }

    OllamaManager {
        id: manager
        active: false
        ollamaUrl: "http://127.0.0.10:11434"

        onGpuStatusReady: label => {
            if (root.phase === "normal-gpu") {
                if (!root.check(label === "GPU",
                        "normal GPU probe did not preserve its label")) return;
                root.setPhase("exact-ready", "http://127.0.0.11:11434");
            } else if (root.phase === "exact-gpu") {
                if (!root.check(label === "GPU",
                        "exact-bound GPU probe did not preserve its label")) return;
                if (!root.checkExactResponse(manager._lastGpuResponseBytes,
                        manager._lastGpuResponseCharacters, "GPU probe")) return;
                root.setPhase("readiness-overflow",
                    "http://127.0.0.12:11434");
            } else if (root.phase === "final-recovery-gpu") {
                if (!root.check(label === "GPU" && manager.gpuError === "",
                        "GPU probe did not recover after overflow")) return;
                root.setPhase("empty-discovery",
                    "http://127.0.0.15:11434");
            }
        }
    }
}
