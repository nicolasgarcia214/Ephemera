import QtQuick
import Quickshell
import Quickshell.Io
import "../lib/Providers.js" as Providers

Item {
    id: root

    // --- Input (set by parent) ---
    property string provider: "ollama"

    // --- Keyring state ---
    property var _keyringCache: ({})
    property bool _keyringAvailable: false
    property var _keyringQueue: []
    property var _keyringOperation: null
    property string _keyringOperationOutput: ""
    property int _keyringOperationSequence: 0
    property string _secretToolExecutable: "secret-tool"

    signal keyringOperationSucceeded(string operationId, string operation, string provider)
    signal keyringOperationFailed(string operationId, string operation, string provider, string message)

    // --- Public API ---

    function resolveApiKey(prov) {
        var info = Providers.getProviderInfo(prov);
        if (!info.envVar) return "";
        var cached = _keyringCache[prov];
        if (cached && cached.length > 0) return cached;
        return Quickshell.env(info.envVar) || "";
    }

    function hasApiKeyForProvider(prov) {
        var info = Providers.getProviderInfo(prov);
        if (!info.envVar) return true;
        var cached = _keyringCache[prov];
        if (cached && cached.length > 0) return true;
        return (Quickshell.env(info.envVar) || "").length > 0;
    }

    function apiKeySource(prov) {
        var info = Providers.getProviderInfo(prov);
        if (!info.envVar) return "";
        var cached = _keyringCache[prov];
        if (cached && cached.length > 0) return "keyring";
        if ((Quickshell.env(info.envVar) || "").length > 0) return "env";
        return "";
    }

    function checkSecretToolAvailable() {
        secretToolCheck.running = true;
    }

    function refreshKeyringKey() {
        if (!_keyringAvailable) return;
        if (provider === "ollama") return;
        var info = Providers.getProviderInfo(provider);
        if (!info.envVar) return;
        _enqueueKeyringOperation("lookup", provider, "");
    }

    function storeKeyringKey(prov, key) {
        if (!_keyringAvailable || !key) return "";
        var safeKey = Providers.sanitizeApiKey(key);
        if (!safeKey) return "";
        return _enqueueKeyringOperation("store", prov, safeKey);
    }

    function clearKeyringKey(prov) {
        if (!_keyringAvailable) return "";
        return _enqueueKeyringOperation("clear", prov, "");
    }

    // --- Internal ---

    // Always return a new object so QML property var change detection fires.
    function _cloneCache() {
        var c = {};
        var old = _keyringCache;
        for (var k in old) c[k] = old[k];
        return c;
    }

    function _appendKeyringOperation(type, prov, key, operationId) {
        var queue = _keyringQueue.slice();
        queue.push({
            type: type,
            provider: prov,
            key: key,
            operationId: operationId || ""
        });
        _keyringQueue = queue;
    }

    function _enqueueKeyringOperation(type, prov, key) {
        var info = Providers.getProviderInfo(prov);
        if (!info.envVar) return "";
        var operationId = "";
        if (type === "store" || type === "clear") {
            _keyringOperationSequence++;
            operationId = type + "-" + Date.now() + "-" + _keyringOperationSequence;
        }
        _appendKeyringOperation(type, prov, key, operationId);
        if (!_keyringOperation && !keyringCommand.running)
            Qt.callLater(_startNextKeyringOperation);
        return operationId || "lookup";
    }

    function _finishKeyringOperation(exitCode) {
        var operation = _keyringOperation;
        var output = _keyringOperationOutput;
        _keyringOperation = null;
        _keyringOperationOutput = "";

        if (operation && operation.type === "lookup" && exitCode === 0) {
            var key = Providers.sanitizeApiKey(output);
            var cache = _cloneCache();
            if (key.length > 0)
                cache[operation.provider] = key;
            else
                delete cache[operation.provider];
            _keyringCache = cache;
        } else if (operation && operation.type === "store") {
            if (exitCode === 0) {
                var storeCache = _cloneCache();
                storeCache[operation.provider] = operation.key;
                _keyringCache = storeCache;
            } else {
                _appendKeyringOperation("lookup", operation.provider, "", "");
            }
        } else if (operation && operation.type === "clear") {
            if (exitCode === 0) {
                var clearCache = _cloneCache();
                delete clearCache[operation.provider];
                _keyringCache = clearCache;
            } else {
                _appendKeyringOperation("lookup", operation.provider, "", "");
            }
        }

        if (operation && (operation.type === "store" || operation.type === "clear")) {
            if (exitCode === 0) {
                keyringOperationSucceeded(operation.operationId, operation.type,
                                          operation.provider);
            } else {
                var action = operation.type === "store" ? "store" : "clear";
                keyringOperationFailed(operation.operationId, operation.type,
                    operation.provider,
                    "Could not " + action + " the API key in the system keyring.");
            }
        }

        Qt.callLater(_startNextKeyringOperation);
    }

    function _recoverFailedKeyringStart() {
        if (!_keyringOperation || keyringCommand.running) return;
        _finishKeyringOperation(-1);
    }

    function _startNextKeyringOperation() {
        if (!_keyringAvailable || _keyringOperation
                || keyringCommand.running || _keyringQueue.length === 0)
            return;

        var queue = _keyringQueue.slice();
        var operation = queue.shift();
        _keyringQueue = queue;
        _keyringOperation = operation;
        _keyringOperationOutput = "";
        keyringCommand.stdinEnabled = (operation.type === "store");

        if (operation.type === "lookup") {
            keyringCommand.command = [_secretToolExecutable, "lookup", "service",
                                      "ephemera", "provider", operation.provider];
        } else if (operation.type === "store") {
            var info = Providers.getProviderInfo(operation.provider);
            var label = "Ephemera " + (info.name || operation.provider)
                        + " API key";
            keyringCommand.command = [_secretToolExecutable, "store", "--label=" + label,
                                      "service", "ephemera", "provider",
                                      operation.provider];
        } else {
            keyringCommand.command = [_secretToolExecutable, "clear", "service",
                                      "ephemera", "provider", operation.provider];
        }
        keyringCommand.running = true;
    }

    // --- Processes ---

    Process {
        id: secretToolCheck
        running: false
        command: ["which", "secret-tool"]
        onExited: exitCode => {
            root._keyringAvailable = (exitCode === 0);
            if (root._keyringAvailable)
                root.refreshKeyringKey();
        }
    }

    Process {
        id: keyringCommand
        running: false
        stdout: StdioCollector {
            onStreamFinished: root._keyringOperationOutput = text
        }
        onRunningChanged: {
            var operation = root._keyringOperation;
            if (running && operation && operation.type === "store") {
                keyringCommand.write(operation.key);
                keyringCommand.stdinEnabled = false;
            } else if (!running && operation) {
                root._recoverFailedKeyringStart();
            }
        }
        onExited: exitCode => root._finishKeyringOperation(exitCode)
    }
}
