import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import "../lib/Providers.js" as Providers
import "../lib/ChatExport.js" as ChatExport
import "../lib/Mcp.js" as Mcp
import "../lib/VariantStore.js" as VariantStore

Item {
    id: root

    property string pluginId: "ephemera"

    // --- Message state (in-memory only, never persisted) ---
    property ListModel messagesModel: ListModel {}
    property int messageCount: messagesModel.count
    property var messageIndexMap: ({})
    property var variantStore: ({})
    property string lastUserText: ""

    // --- Streaming (delegated to StreamingService) ---
    property alias isStreaming: streamingService.isStreaming
    property alias activeStreamId: streamingService.activeStreamId
    property alias streamStartTime: streamingService.streamStartTime
    property alias streamTokenCount: streamingService.streamTokenCount
    property alias apiOutputTokens: streamingService._apiOutputTokens
    property alias lastRequestFailed: streamingService.lastRequestFailed
    property alias lastHttpStatus: streamingService.lastHttpStatus
    readonly property bool mcpToolApprovalPending: streamingService.toolApprovalPending
    readonly property string mcpPendingToolName: streamingService.pendingToolName
    readonly property string mcpPendingToolDescription: streamingService.pendingToolDescription
    readonly property string mcpPendingToolArgumentsText: streamingService.pendingToolArgumentsText

    // --- Persistence (opt-in) ---
    property bool persistChat: false
    readonly property string _chatStateKey: "chatState"
    readonly property int _chatStateVersion: 1

    // --- Provider settings ---
    property string _provider: "ollama"
    readonly property string provider: _provider
    property string ollamaUrl: "http://localhost:11434"
    property string ollamaThinkingMode: "default"
    property int ollamaContextWindow: 0
    property string baseUrl: "http://localhost:11434"
    property string model: ""
    property real temperature: 0.7
    property int maxTokens: 4096
    property bool unlimitedTokens: false
    property int maxTurns: 10
    property int timeout: 300
    property string systemPrompt: ""
    property bool thinkingEnabled: false
    property bool panelOnLeft: false
    // --- MCP ---
    property bool mcpEnabled: false
    property bool mcpAllowToolRequests: false
    property string mcpToolRequestsTrustKey: ""
    property string mcpUrl: ""
    property bool mcpAllowInsecureHttp: false
    property string mcpInsecureHttpTrustKey: ""
    property var mcpApprovedToolContracts: []
    property string mcpApprovedToolsTrustKey: ""
    readonly property string mcpTrustKey: Mcp.trustKey(mcpUrl, "mcp-remote")
    readonly property bool mcpToolRequestsAllowed: isOllama && mcpEnabled && mcpAllowToolRequests && mcpToolRequestsTrustKey === mcpTrustKey
    readonly property bool mcpInsecureHttpAllowed: mcpAllowInsecureHttp && mcpInsecureHttpTrustKey === mcpTrustKey
    readonly property var activeMcpToolApprovals: mcpApprovedToolsTrustKey === mcpTrustKey ? mcpApprovedToolContracts : []
    readonly property bool mcpConnecting: mcpServiceInstance.connecting
    readonly property bool mcpConnected: mcpServiceInstance.isConnected
    readonly property string mcpConnectionError: mcpServiceInstance.connectionError
    readonly property var mcpTools: mcpServiceInstance.tools
    readonly property int mcpIgnoredToolCount: mcpServiceInstance.ignoredToolCount
    readonly property string mcpBridgeVersion: mcpServiceInstance.bridgeVersion
    property bool _settingsLoaded: false
    property bool _loadingSettings: false

    // --- Ollama (delegated to OllamaManager) ---
    property alias availableModels: ollamaManager.availableModels
    property alias ollamaWeStarted: ollamaManager.ollamaWeStarted
    property alias ollamaStartPending: ollamaManager.ollamaStartPending
    property alias ollamaExternallyManaged: ollamaManager.ollamaExternallyManaged
    property alias ollamaReady: ollamaManager.ollamaReady
    property alias discoveryError: ollamaManager.discoveryError
    readonly property string ollamaProbeError: ollamaManager.probeError
    property alias ollamaIdleMinutes: ollamaManager.ollamaIdleMinutes
    property alias ollamaRetries: ollamaManager.ollamaRetries
    readonly property int ollamaMaxRetries: ollamaManager.ollamaMaxRetries

    // --- Keyring (delegated to KeyringService) ---
    property alias _keyringAvailable: keyringService._keyringAvailable
    property alias _keyringCache: keyringService._keyringCache

    // Per-provider temperature range
    readonly property var temperatureRange: Providers.getTemperatureRange(provider)
    readonly property real tempMax: temperatureRange.max
    readonly property real tempMin: temperatureRange.min

    readonly property var modelChoices: {
        var ollamaCount = availableModels.count;
        if (provider === "ollama") {
            var list = [];
            for (var i = 0; i < ollamaCount; i++)
                list.push(availableModels.get(i).name);
            return list;
        }
        return Providers.getModelList(provider);
    }

    readonly property bool isOllama: provider === "ollama"
    readonly property bool needsApiKey: provider !== "ollama"
    readonly property bool hasApiKey: resolveApiKey().length > 0
    readonly property bool missingApiKey: needsApiKey && !hasApiKey

    // --- Lifecycle ---

    Component.onCompleted: {
        loadSettings();
        loadChatHistory();
        if (isOllama)
            ollamaManager.ensureReady();
        keyringService.checkSecretToolAvailable();
    }

    Component.onDestruction: {
        try { _commitChatHistory(); }
        catch (e) { console.warn("Ephemera: error saving chat on destruction:", e); }
        ollamaManager.cleanupOnDestruction();
    }

    onProviderChanged: {
        streamingService.resetErrorState();
        if (_keyringAvailable)
            keyringService.refreshKeyringKey();
        if (isOllama && mcpEnabled && mcpUrl)
            mcpServiceInstance.connectToServer();
        else
            mcpServiceInstance.disconnectFromServer();
    }

    // ─── Child services ─────────────────────────────────────────────

    KeyringService {
        id: keyringService
        provider: root.provider
    }

    MCPService {
        id: mcpServiceInstance
        mcpUrl: root.mcpUrl
        allowInsecureHttp: root.mcpInsecureHttpAllowed
        enabled: root.isOllama && root.mcpEnabled
        onToolCallCompleted: (callId, result) => streamingService._onToolCallCompleted(callId, result)
        onToolCallFailed: (callId, error) => streamingService._onToolCallFailed(callId, error)
        onMcpToolsUpdated: root._pruneMcpToolApprovals()
    }

    StreamingService {
        id: streamingService
        provider: root.provider
        ollamaUrl: root.ollamaUrl
        timeout: root.timeout

        onStreamContentUpdated: (streamId, deltaText) => root._applyStreamContent(streamId)
        onStreamThinkingUpdated: (streamId, deltaText) => root._applyStreamThinking(streamId)
        onStreamFinalized: (streamId, stats) => root._applyFinalize(streamId, stats)
        onStreamError: (streamId, message) => root._applyError(streamId, message)
        onStreamCancelled: (streamId, stats) => root._applyCancelled(streamId, stats)
        mcpConnected: mcpServiceInstance.isConnected
        mcpTools: mcpServiceInstance.tools
        toolCallsAllowed: root.mcpToolRequestsAllowed
        approvedToolContracts: root.activeMcpToolApprovals
        onMcpToolCallRequested: (toolName, toolArguments, approvedContracts,
                                 streamId, streamProvider, streamGeneration) => {
            if (!streamingService.matchesActiveStream(streamId, streamProvider, streamGeneration)) {
                streamingService.toolCallStarted(toolName, -1);
                return;
            }
            var callId = mcpServiceInstance.callTool(toolName, toolArguments, approvedContracts);
            streamingService.toolCallStarted(toolName, callId);
        }
        onMcpToolCallCancellationRequested: (callId, reason) => {
            mcpServiceInstance.cancelRequest(callId, reason);
        }
        onStreamToolRoundReady: (streamId, messages, streamProvider, streamGeneration) =>
            root._launchCurlWithMessages(streamId, messages, streamProvider, streamGeneration)
    }

    OllamaManager {
        id: ollamaManager
        active: root.isOllama
        ollamaUrl: root.ollamaUrl
        isStreaming: root.isStreaming

        onModelAutoSelected: name => {
            if (!root.model || root.model.length === 0) {
                root.model = name;
                root.saveSettingValue("model", name);
            }
        }

        onGpuStatusReady: label => {
            if (!streamingService._lastFinalizedStreamId) return;
            var idx = root.findIndexById(streamingService._lastFinalizedStreamId);
            if (idx >= 0) {
                var msg = root.messagesModel.get(idx);
                var stats = msg.streamStats || "";
                if (stats && label && stats.indexOf("GPU") === -1 && stats.indexOf("CPU") === -1)
                    root.messagesModel.setProperty(idx, "streamStats", stats + " · " + label);
            }
        }
    }

    // ─── Keyring facade ─────────────────────────────────────────────

    function resolveApiKey(prov) { return keyringService.resolveApiKey(prov || provider); }
    function hasApiKeyForProvider(prov) { return keyringService.hasApiKeyForProvider(prov); }
    function apiKeySource(prov) { return keyringService.apiKeySource(prov); }
    function storeKeyringKey(prov, key) { keyringService.storeKeyringKey(prov, key); }
    function clearKeyringKey(prov) { keyringService.clearKeyringKey(prov); }
    function refreshKeyringKey() { keyringService.refreshKeyringKey(); }

    function _envVarForProvider(prov) {
        var info = Providers.getProviderInfo(prov);
        return info.envVar || "EPHEMERA_API_KEY";
    }

    function _providerDisplayName(prov) {
        var info = Providers.getProviderInfo(prov);
        return info.name || "custom provider";
    }

    // ─── Ollama facade ──────────────────────────────────────────────

    function shutdownOllama() { ollamaManager.shutdown(); }
    function forceShutdownExternalOllama() { ollamaManager.forceShutdownExternal(); }
    function ensureOllamaReady() { if (isOllama) ollamaManager.ensureReady(); }
    function scheduleIdleShutdown() { if (isOllama) ollamaManager.scheduleIdleShutdown(); }
    function discoverModels() { ollamaManager.discoverModels(); }

    // ─── Settings persistence (non-secret only) ────────────────────

    function loadSettings() {
        if (_loadingSettings)
            return;
        _loadingSettings = true;
        try {
            _loadSettingsValues();
        } finally {
            _loadingSettings = false;
        }
    }

    function _loadSettingsValues() {
        var oldProvider = provider;
        var nextProvider = String(PluginService.loadPluginData(
            pluginId, "provider", "ollama")).trim() || "ollama";

        if (_settingsLoaded && oldProvider !== nextProvider)
            clearChat();

        _provider = nextProvider;
        setOllamaUrl(PluginService.loadPluginData(
            pluginId, "ollamaUrl", "http://localhost:11434"), false);
        ollamaThinkingMode = Providers.normalizeOllamaThinkingMode(PluginService.loadPluginData(pluginId, "ollamaThinkingMode", "default"));
        ollamaContextWindow = Providers.normalizeOllamaContextWindow(
            PluginService.loadPluginData(pluginId, "ollamaContextWindow", 0));
        model = String(PluginService.loadPluginData(pluginId, "model", "")).trim();
        temperature = PluginService.loadPluginData(pluginId, "temperature", 0.7);
        maxTokens = PluginService.loadPluginData(pluginId, "maxTokens", 4096);
        maxTurns = PluginService.loadPluginData(pluginId, "maxTurns", 10);
        timeout = PluginService.loadPluginData(pluginId, "timeout", 300);
        systemPrompt = String(PluginService.loadPluginData(pluginId, "systemPrompt", "")).trim();
        thinkingEnabled = PluginService.loadPluginData(pluginId, "thinkingEnabled", false) === true;
        panelOnLeft = PluginService.loadPluginData(pluginId, "panelOnLeft", false) === true;
        mcpEnabled = PluginService.loadPluginData(pluginId, "mcpEnabled", false) === true;
        mcpAllowToolRequests = PluginService.loadPluginData(pluginId, "mcpToolRequestsAllowed", PluginService.loadPluginData(pluginId, "mcpAutoExecuteTools", false)) === true;
        mcpToolRequestsTrustKey = String(PluginService.loadPluginData(pluginId, "mcpToolRequestsTrustKey", PluginService.loadPluginData(pluginId, "mcpAutoExecuteTrustKey", "")));
        mcpUrl = String(PluginService.loadPluginData(pluginId, "mcpUrl", "")).trim();
        mcpAllowInsecureHttp = PluginService.loadPluginData(pluginId, "mcpAllowInsecureHttp", false) === true;
        mcpInsecureHttpTrustKey = String(PluginService.loadPluginData(pluginId, "mcpInsecureHttpTrustKey", ""));
        mcpApprovedToolContracts = Mcp.normalizeToolApprovalKeys(PluginService.loadPluginData(
            pluginId,
            "mcpApprovedToolContracts",
            PluginService.loadPluginData(pluginId, "mcpAllowedTools", "[]")
        ));
        mcpApprovedToolsTrustKey = String(PluginService.loadPluginData(
            pluginId,
            "mcpApprovedToolsTrustKey",
            PluginService.loadPluginData(pluginId, "mcpAllowedToolsTrustKey", "")
        ));
        var legacyMcpToken = String(PluginService.loadPluginData(pluginId, "mcpToken", ""));
        if (legacyMcpToken)
            PluginService.savePluginData(pluginId, "mcpToken", "");
        if (isOllama && mcpEnabled && mcpUrl)
            mcpServiceInstance.connectToServer();
        else
            mcpServiceInstance.disconnectFromServer();
        unlimitedTokens = PluginService.loadPluginData(pluginId, "unlimitedTokens", false) === true;
        var nextPersistChat = PluginService.loadPluginData(
            pluginId, "persistChat", false) === true;
        if (!nextPersistChat && (!_settingsLoaded || persistChat))
            _deletePersistedChat();
        persistChat = nextPersistChat;
        ollamaManager.ollamaIdleMinutes = Number(PluginService.loadPluginData(pluginId, "ollamaIdleMinutes", 5)) || 5;

        var range = Providers.getTemperatureRange(provider);
        if (temperature > range.max) {
            temperature = range.max;
            saveSettingValue("temperature", temperature);
        } else if (temperature < range.min) {
            temperature = range.min;
            saveSettingValue("temperature", temperature);
        }

        updateBaseUrl();
        _settingsLoaded = true;
    }

    function updateBaseUrl() {
        if (provider === "ollama") {
            baseUrl = ollamaUrl;
        } else if (provider === "custom") {
            baseUrl = String(PluginService.loadPluginData(pluginId, "customBaseUrl", Providers.getProviderInfo("custom").defaultUrl)).trim();
        } else {
            baseUrl = Providers.getProviderInfo(provider).defaultUrl;
        }
    }

    function saveSettingValue(key, value) {
        _settingsReloadDebounce.restart();
        PluginService.savePluginData(pluginId, key, value);
    }

    function togglePanelSide() {
        panelOnLeft = !panelOnLeft;
        saveSettingValue("panelOnLeft", panelOnLeft);
    }

    function setProvider(nextProvider) {
        var next = String(nextProvider || "").trim() || "ollama";
        if (next === provider)
            return false;

        // Reset the active request and its tool state before changing identity.
        clearChat();
        _provider = next;
        saveSettingValue("provider", next);
        updateBaseUrl();
        return true;
    }

    function setOllamaUrl(url, persistChange) {
        var next = String(url || "").trim();
        if (!Providers.validateUrl(next).valid)
            return false;

        var changed = next !== ollamaUrl;
        ollamaUrl = next;
        if (provider === "ollama")
            baseUrl = next;

        // PluginService emits synchronously, so persist only after every
        // request and discovery consumer has received the new identity.
        if (persistChange !== false && changed)
            saveSettingValue("ollamaUrl", next);
        return true;
    }

    function setOllamaContextWindow(value) {
        var normalized = Providers.normalizeOllamaContextWindow(value);
        if (normalized === ollamaContextWindow)
            return;
        ollamaContextWindow = normalized;
        saveSettingValue("ollamaContextWindow", normalized);
    }

    function setMcpEnabled(enabled) {
        mcpEnabled = enabled === true && isOllama;
        saveSettingValue("mcpEnabled", mcpEnabled);
        if (mcpEnabled)
            mcpServiceInstance.connectToServer();
        else
            mcpServiceInstance.disconnectFromServer();
    }

    function reconnectMcp() {
        if (isOllama && mcpEnabled)
            mcpServiceInstance.reconnectToServer();
    }

    function disconnectMcp() {
        mcpServiceInstance.disconnectFromServer();
    }

    function setMcpToolRequestsAllowed(enabled) {
        var allowed = enabled === true;
        mcpAllowToolRequests = allowed;
        mcpToolRequestsTrustKey = allowed ? mcpTrustKey : "";
        if (allowed && mcpApprovedToolsTrustKey !== mcpTrustKey) {
            mcpApprovedToolContracts = [];
            mcpApprovedToolsTrustKey = mcpTrustKey;
            saveSettingValue("mcpApprovedToolContracts", JSON.stringify(mcpApprovedToolContracts));
            saveSettingValue("mcpApprovedToolsTrustKey", mcpApprovedToolsTrustKey);
        }
        saveSettingValue("mcpToolRequestsAllowed", allowed);
        saveSettingValue("mcpToolRequestsTrustKey", mcpToolRequestsTrustKey);
    }

    function setMcpUrl(url) {
        var next = String(url || "").trim();
        if (next === mcpUrl) return;
        if (mcpServiceInstance.isConnected || mcpServiceInstance.connecting)
            mcpServiceInstance.disconnectFromServer();
        setMcpToolRequestsAllowed(false);
        setMcpInsecureHttpAllowed(false);
        clearMcpToolApprovals();
        mcpUrl = next;
        saveSettingValue("mcpUrl", next);
    }

    function setMcpInsecureHttpAllowed(enabled) {
        var allowed = enabled === true && Mcp.requiresInsecureHttpConsent(mcpUrl);
        mcpAllowInsecureHttp = allowed;
        mcpInsecureHttpTrustKey = allowed ? mcpTrustKey : "";
        saveSettingValue("mcpAllowInsecureHttp", allowed);
        saveSettingValue("mcpInsecureHttpTrustKey", mcpInsecureHttpTrustKey);
        if (!allowed && (mcpServiceInstance.isConnected || mcpServiceInstance.connecting)
                && Mcp.requiresInsecureHttpConsent(mcpUrl))
            mcpServiceInstance.disconnectFromServer();
    }

    function isMcpToolApproved(toolName) {
        return mcpServiceInstance.isToolApproved(toolName, activeMcpToolApprovals);
    }

    function setMcpToolApproved(toolName, approved) {
        var base = mcpApprovedToolsTrustKey === mcpTrustKey ? mcpApprovedToolContracts : [];
        mcpApprovedToolContracts = mcpServiceInstance.setToolApproved(base, toolName, approved === true);
        mcpApprovedToolsTrustKey = mcpTrustKey;
        saveSettingValue("mcpApprovedToolContracts", JSON.stringify(mcpApprovedToolContracts));
        saveSettingValue("mcpApprovedToolsTrustKey", mcpApprovedToolsTrustKey);
    }

    function approveMcpToolCall() {
        return streamingService.approvePendingToolCall();
    }

    function rejectMcpToolCall() {
        return streamingService.rejectPendingToolCall("Tool call rejected by user.");
    }

    function clearMcpToolApprovals() {
        mcpApprovedToolContracts = [];
        mcpApprovedToolsTrustKey = "";
        saveSettingValue("mcpApprovedToolContracts", JSON.stringify(mcpApprovedToolContracts));
        saveSettingValue("mcpApprovedToolsTrustKey", mcpApprovedToolsTrustKey);
    }

    function _pruneMcpToolApprovals() {
        if (mcpApprovedToolsTrustKey !== mcpTrustKey)
            return;
        var pruned = Mcp.pruneApprovedTools(mcpApprovedToolContracts, mcpServiceInstance.tools);
        if (JSON.stringify(pruned) === JSON.stringify(mcpApprovedToolContracts))
            return;
        mcpApprovedToolContracts = pruned;
        saveSettingValue("mcpApprovedToolContracts", JSON.stringify(mcpApprovedToolContracts));
    }

    Timer {
        id: _settingsReloadDebounce
        interval: 150
        repeat: false
    }

    Connections {
        target: PluginService
        function onPluginDataChanged(pId) {
            if (pId !== root.pluginId) return;
            if (root._loadingSettings) return;
            if (_settingsReloadDebounce.running) return;
            root.loadSettings();
        }
    }

    // ─── Chat state ────────────────────────────────────────────────

    function setPersistChat(enabled) {
        var next = enabled === true;
        if (!next)
            _chatSaveDebounce.stop();
        persistChat = next;
        saveSettingValue("persistChat", next);
        if (next)
            saveChatHistory();
        else
            _deletePersistedChat();
    }

    function _clearLegacyChatData() {
        var history = PluginService.loadPluginData(pluginId, "chatHistory", "");
        var variants = PluginService.loadPluginData(pluginId, "chatVariants", "");
        if (history === "" && variants === "") return;

        // Legacy cleanup emits pluginDataChanged synchronously. Suppress a
        // settings reload until both halves have been removed.
        _settingsReloadDebounce.restart();
        if (history !== "")
            PluginService.savePluginData(pluginId, "chatHistory", "");
        if (variants !== "")
            PluginService.savePluginData(pluginId, "chatVariants", "");
    }

    function _deletePersistedChat() {
        _chatSaveDebounce.stop();
        PluginService.clearPluginState(pluginId);
        _clearLegacyChatData();
    }

    function clearChat() {
        streamingService.reset();
        messagesModel.clear();
        messageIndexMap = ({});
        variantStore = ({});
        lastUserText = "";
        _deletePersistedChat();
    }

    function saveChatHistory() {
        if (!persistChat) return;
        _chatSaveDebounce.restart();
    }

    function _commitChatHistory() {
        if (!persistChat) return;
        var msgs = [];
        for (var i = 0; i < messagesModel.count; i++) {
            var m = messagesModel.get(i);
            if (m.status === "streaming") continue;
            msgs.push({
                role: m.role, content: m.content, thinking: m.thinking || "",
                id: m.id, timestamp: m.timestamp, status: m.status || "ok",
                variantIndex: m.variantIndex || 0, variantCount: m.variantCount || 1,
                modelName: m.modelName || ""
            });
        }
        PluginService.savePluginState(pluginId, _chatStateKey, {
            version: _chatStateVersion,
            messages: msgs,
            variants: JSON.parse(JSON.stringify(variantStore))
        });
    }

    Timer {
        id: _chatSaveDebounce
        interval: 150
        repeat: false
        onTriggered: root._commitChatHistory()
    }

    function _isSafeStateKey(value) {
        return typeof value === "string" && value.length > 0
            && value !== "__proto__" && value !== "constructor"
            && value !== "prototype";
    }

    function _prepareChatState(payload) {
        if (!payload || typeof payload !== "object" || Array.isArray(payload)
                || payload.version !== _chatStateVersion
                || !Array.isArray(payload.messages)
                || !payload.variants || typeof payload.variants !== "object"
                || Array.isArray(payload.variants))
            return null;

        var entries = [];
        var indexMap = {};
        var lastUser = "";
        for (var i = 0; i < payload.messages.length; i++) {
            var m = payload.messages[i];
            if (!m || typeof m !== "object" || Array.isArray(m)
                    || (m.role !== "user" && m.role !== "assistant")
                    || typeof m.content !== "string"
                    || !_isSafeStateKey(m.id)
                    || indexMap[m.id] !== undefined
                    || typeof m.timestamp !== "number" || !isFinite(m.timestamp)
                    || (m.thinking !== undefined && typeof m.thinking !== "string")
                    || (m.modelName !== undefined && typeof m.modelName !== "string"))
                return null;

            var status = m.status === undefined ? "ok" : m.status;
            if (status !== "ok" && status !== "error" && status !== "streaming")
                return null;
            if (status === "streaming") status = "ok";

            var variantIndex = m.variantIndex === undefined ? 0 : m.variantIndex;
            var variantCount = m.variantCount === undefined ? 1 : m.variantCount;
            if (typeof variantIndex !== "number" || !isFinite(variantIndex)
                    || Math.floor(variantIndex) !== variantIndex || variantIndex < 0
                    || typeof variantCount !== "number" || !isFinite(variantCount)
                    || Math.floor(variantCount) !== variantCount || variantCount < 1
                    || variantIndex >= variantCount)
                return null;

            var entry = _createMessageEntry(
                m.role, m.content, m.id, m.timestamp, status, m.modelName || "");
            entry.thinking = m.thinking || "";
            entry.variantIndex = variantIndex;
            entry.variantCount = variantCount;
            entries.push(entry);
            indexMap[m.id] = i;
            if (m.role === "user") lastUser = m.content;
        }

        var variants = {};
        for (var msgId in payload.variants) {
            if (!Object.prototype.hasOwnProperty.call(payload.variants, msgId))
                continue;
            var values = payload.variants[msgId];
            if (!_isSafeStateKey(msgId) || indexMap[msgId] === undefined
                    || !Array.isArray(values)
                    || values.length > maxVariantsPerMessage)
                return null;
            var copied = [];
            for (var j = 0; j < values.length; j++) {
                var variant = values[j];
                if (!variant || typeof variant !== "object" || Array.isArray(variant)
                        || typeof variant.content !== "string"
                        || (variant.thinking !== undefined
                            && typeof variant.thinking !== "string")
                        || (variant.modelName !== undefined
                            && typeof variant.modelName !== "string"))
                    return null;
                copied.push({
                    content: variant.content,
                    thinking: variant.thinking || "",
                    modelName: variant.modelName || ""
                });
            }
            variants[msgId] = copied;
        }

        return {
            entries: entries,
            indexMap: indexMap,
            variants: variants,
            lastUser: lastUser
        };
    }

    function _applyPreparedChatState(prepared) {
        messagesModel.clear();
        for (var i = 0; i < prepared.entries.length; i++)
            messagesModel.append(prepared.entries[i]);
        messageIndexMap = prepared.indexMap;
        variantStore = prepared.variants;
        lastUserText = prepared.lastUser;
    }

    function _discardInvalidStoredChat(message) {
        console.warn("Ephemera: failed to load chat history:", message);
        _chatSaveDebounce.stop();
        PluginService.clearPluginState(pluginId);
        _clearLegacyChatData();
    }

    function loadChatHistory() {
        if (!persistChat) return;

        var stored = PluginService.loadPluginState(pluginId, _chatStateKey, null);
        if (stored !== null) {
            var prepared = _prepareChatState(stored);
            if (!prepared) {
                _discardInvalidStoredChat("invalid versioned state");
                return;
            }
            _clearLegacyChatData();
            _applyPreparedChatState(prepared);
            return;
        }

        var historyRaw = PluginService.loadPluginData(pluginId, "chatHistory", "");
        var variantsRaw = PluginService.loadPluginData(pluginId, "chatVariants", "");
        if (historyRaw === "" && variantsRaw === "") return;

        try {
            if (typeof historyRaw !== "string" || !historyRaw
                    || typeof variantsRaw !== "string")
                throw new Error("invalid legacy values");
            var legacyPayload = {
                version: _chatStateVersion,
                messages: JSON.parse(historyRaw),
                variants: variantsRaw ? JSON.parse(variantsRaw) : {}
            };
            var migrated = _prepareChatState(legacyPayload);
            if (!migrated)
                throw new Error("invalid legacy state");

            // Promote the fully validated pair before erasing the legacy keys.
            PluginService.savePluginState(pluginId, _chatStateKey, legacyPayload);
            _clearLegacyChatData();
            _applyPreparedChatState(migrated);
        } catch (e) {
            _discardInvalidStoredChat(e);
        }
    }

    // ─── Messaging orchestration ───────────────────────────────────

    function sendMessage(text) {
        if (!text || text.trim().length === 0) return;
        if (isStreaming || streamingService.isStreaming) {
            if (activeStreamId)
                _applyError(activeStreamId, "Please wait until the current response finishes.");
            return;
        }
        if (streamingService.isInErrorCooldown()) return;
        ollamaManager.stopIdleTimer();
        _startStreaming(text.trim());
    }

    function regenerate() {
        if (isStreaming || !lastUserText) return;
        if (messagesModel.count === 0) return;
        if (streamingService.isInErrorCooldown()) return;
        ollamaManager.stopIdleTimer();

        var lastIdx = messagesModel.count - 1;
        var last = messagesModel.get(lastIdx);
        if (last.role !== "assistant") return;

        var msgId = last.id;
        _saveVariant(msgId, last.variantIndex, last.content, last.thinking, last.modelName);

        var newCount = last.variantCount + 1;
        var newIndex = newCount - 1;
        messagesModel.setProperty(lastIdx, "variantCount", newCount);
        messagesModel.setProperty(lastIdx, "variantIndex", newIndex);
        messagesModel.setProperty(lastIdx, "content", "");
        messagesModel.setProperty(lastIdx, "thinking", "");
        messagesModel.setProperty(lastIdx, "status", "streaming");
        messagesModel.setProperty(lastIdx, "modelName", model);

        streamingService.beginStream(msgId, newIndex);
        _launchCurl();
    }

    function editAndRegenerate(msgId, newText) {
        if (isStreaming || !newText || newText.trim().length === 0) return;
        if (streamingService.isInErrorCooldown()) return;

        var idx = findIndexById(msgId);
        if (idx < 0) return;
        var msg = messagesModel.get(idx);
        if (msg.role !== "user") return;

        messagesModel.setProperty(idx, "content", newText.trim());

        var removeCount = messagesModel.count - idx - 1;
        for (var i = 0; i < removeCount; i++) {
            var removedMsg = messagesModel.get(idx + 1);
            delete messageIndexMap[removedMsg.id];
            if (variantStore[removedMsg.id])
                delete variantStore[removedMsg.id];
            messagesModel.remove(idx + 1);
        }
        variantStore = JSON.parse(JSON.stringify(variantStore));
        _rebuildIndexMap();

        lastUserText = newText.trim();
        ollamaManager.stopIdleTimer();

        var now = Date.now();
        var streamId = "assistant-" + now;
        messagesModel.append(_createMessageEntry("assistant", "", streamId, now, "streaming", model));
        messageIndexMap[streamId] = messagesModel.count - 1;

        streamingService.beginStream(streamId, 0);
        _launchCurl();
    }

    function cancel() {
        streamingService.cancel();
    }

    readonly property int maxVariantsPerMessage: 10

    function switchVariant(msgId, newIndex) {
        var idx = findIndexById(msgId);
        if (idx < 0) return;
        var msg = messagesModel.get(idx);
        if (newIndex < 0 || newIndex >= msg.variantCount) return;

        if (isStreaming && activeStreamId === msgId && newIndex === streamingService._streamVariantIndex) {
            messagesModel.setProperty(idx, "content", streamingService._streamContent);
            messagesModel.setProperty(idx, "thinking", streamingService._streamThinking);
            messagesModel.setProperty(idx, "variantIndex", newIndex);
            messagesModel.setProperty(idx, "modelName", model);
            messagesModel.setProperty(idx, "status", "streaming");
            return;
        }

        var variant = VariantStore.getVariant(variantStore, msgId, newIndex);
        if (!variant) return;
        messagesModel.setProperty(idx, "content", variant.content);
        messagesModel.setProperty(idx, "thinking", variant.thinking);
        messagesModel.setProperty(idx, "variantIndex", newIndex);
        if (variant.modelName)
            messagesModel.setProperty(idx, "modelName", variant.modelName);
        if (isStreaming && activeStreamId === msgId)
            messagesModel.setProperty(idx, "status", "ok");
    }

    // ─── Export ─────────────────────────────────────────────────────

    function buildConversationMarkdown() {
        var msgs = [];
        for (var i = 0; i < messagesModel.count; i++) {
            var m = messagesModel.get(i);
            msgs.push({ role: m.role, content: m.content });
        }
        return ChatExport.buildMarkdown(msgs);
    }

    function exportConversation() {
        streamingService.exportToClipboard(buildConversationMarkdown());
    }

    function exportConversationToFile() {
        var text = buildConversationMarkdown();
        var filename = ChatExport.generateFilename(Quickshell.env("HOME"));
        streamingService.exportToFile(text, Quickshell.env("HOME"), filename);
        return filename;
    }

    // ─── Message helpers ───────────────────────────────────────────

    function _createMessageEntry(role, content, id, timestamp, status, modelName) {
        return {
            role: role, content: content || "", thinking: "",
            id: id, timestamp: timestamp, status: status || "ok",
            variantIndex: 0, variantCount: 1,
            modelName: modelName || "", streamStats: "", requestPayload: ""
        };
    }

    function _rebuildIndexMap() {
        var map = {};
        for (var i = 0; i < messagesModel.count; i++)
            map[messagesModel.get(i).id] = i;
        messageIndexMap = map;
    }

    function findIndexById(msgId) {
        return messageIndexMap[msgId] !== undefined ? messageIndexMap[msgId] : -1;
    }

    function getMessageContentById(msgId) {
        var idx = findIndexById(msgId);
        if (idx >= 0) return messagesModel.get(idx).content || "";
        return "";
    }

    function setMessageContentById(msgId, text) {
        var idx = findIndexById(msgId);
        if (idx >= 0)
            messagesModel.setProperty(idx, "content", text || "");
    }

    // ─── Internal: streaming orchestration ─────────────────────────

    function _startStreaming(text) {
        var now = Date.now();
        var streamId = "assistant-" + now;

        var userId = "user-" + now;
        messagesModel.append(_createMessageEntry("user", text, userId, now, "ok", ""));
        messageIndexMap[userId] = messagesModel.count - 1;
        lastUserText = text;

        messagesModel.append(_createMessageEntry("assistant", "", streamId, now + 1, "streaming", model));
        messageIndexMap[streamId] = messagesModel.count - 1;

        streamingService.beginStream(streamId, 0);
        _launchCurl();
    }

    function _launchCurl() {
        var context = streamingService.activeStreamContext();
        if (!streamingService.matchesActiveStream(
                context.streamId, context.provider, context.generation)
                || context.provider !== provider)
            return;

        var payload = _buildPayload(lastUserText);
        var result = _buildCurlCommand(payload);
        if (!result) {
            var errorMessage;
            if (provider === "ollama") {
                errorMessage = ollamaReady ? "No Ollama model selected."
                    : "Ollama is not running. Check that ollama is installed and running.";
            } else {
                var envVar = _envVarForProvider(provider);
                var hint = _keyringAvailable
                    ? "Store a key in Settings, or set the " + envVar + " environment variable."
                    : "Set the " + envVar + " environment variable before starting Quickshell.";
                errorMessage = "No API key found.\n" + hint;
            }
            streamingService.failActiveStream(errorMessage, context.streamId,
                                              context.provider, context.generation);
            return;
        }

        var payloadIdx = findIndexById(context.streamId);
        if (payloadIdx >= 0)
            messagesModel.setProperty(payloadIdx, "requestPayload", JSON.stringify(payload, null, 2));
        streamingService.launchCurl(result, payload.messages, context.streamId,
                                    context.provider, context.generation);
    }

    function _buildPayload(latestText) {
        var msgs = [];
        if (systemPrompt && systemPrompt.trim().length > 0)
            msgs.push({ role: "system", content: systemPrompt.trim() });

        var turns = 0;
        var collected = [];
        for (var i = messagesModel.count - 1; i >= 0; i--) {
            var m = messagesModel.get(i);
            if (!m || m.status !== "ok") continue;
            if (m.role !== "user" && m.role !== "assistant") continue;
            collected.unshift({ role: m.role, content: m.content });
            if (m.role === "user") {
                turns++;
                if (turns >= maxTurns) break;
            }
        }

        for (var j = 0; j < collected.length; j++)
            msgs.push(collected[j]);

        var payload = {
            provider: provider,
            baseUrl: baseUrl,
            model: model,
            temperature: temperature,
            max_tokens: unlimitedTokens ? 0 : maxTokens,
            messages: msgs,
            stream: true,
            timeout: timeout,
            ollamaThinkingMode: ollamaThinkingMode,
            ollamaContextWindow: ollamaContextWindow,
            thinkingEnabled: thinkingEnabled
        };
        if (provider === "ollama" && root.mcpToolRequestsAllowed && mcpServiceInstance.isConnected) {
            var tools = mcpServiceInstance.getOllamaTools(activeMcpToolApprovals);
            if (tools.length > 0)
                payload.tools = tools;
        }
        return payload;
    }

    function _launchCurlWithMessages(streamId, messages, streamProvider, streamGeneration) {
        if (!streamingService.matchesActiveStream(
                streamId, streamProvider, streamGeneration)
                || streamProvider !== provider)
            return false;

        var payload = _buildPayload(lastUserText);
        payload.messages = messages;
        var result = _buildCurlCommand(payload);
        if (!result) {
            streamingService.failActiveStream("Could not resume after MCP tool call.",
                                              streamId, streamProvider, streamGeneration);
            return false;
        }
        var payloadIdx = findIndexById(streamId);
        if (payloadIdx >= 0)
            messagesModel.setProperty(payloadIdx, "requestPayload", JSON.stringify(payload, null, 2));
        return streamingService.launchCurl(result, messages, streamId,
                                           streamProvider, streamGeneration);
    }

    function _buildCurlCommand(payload) {
        var requestProvider = payload.provider;
        var key = resolveApiKey(requestProvider);
        if (requestProvider !== "ollama" && !key) return null;
        if (requestProvider === "ollama" && !payload.model) return null;
        return Providers.buildCurlCommand(requestProvider, payload, key);
    }

    // ─── Stream signal handlers (apply to messagesModel) ───────────

    function _applyStreamContent(streamId) {
        var idx = findIndexById(streamId);
        if (idx >= 0) {
            var msg = messagesModel.get(idx);
            if (msg.variantIndex === streamingService._streamVariantIndex)
                messagesModel.setProperty(idx, "content", streamingService._streamContent);
            messagesModel.setProperty(idx, "status", "streaming");
        }
    }

    function _applyStreamThinking(streamId) {
        var idx = findIndexById(streamId);
        if (idx >= 0) {
            var msg = messagesModel.get(idx);
            if (msg.variantIndex === streamingService._streamVariantIndex)
                messagesModel.setProperty(idx, "thinking", streamingService._streamThinking);
            messagesModel.setProperty(idx, "status", "streaming");
        }
    }

    function _applyFinalize(streamId, stats) {
        var idx = findIndexById(streamId);
        if (idx >= 0) {
            _saveVariant(streamId, streamingService._streamVariantIndex, streamingService._streamContent, streamingService._streamThinking, model);
            var msg = messagesModel.get(idx);
            if (msg.variantIndex === streamingService._streamVariantIndex) {
                messagesModel.setProperty(idx, "content", streamingService._streamContent);
                messagesModel.setProperty(idx, "thinking", streamingService._streamThinking);
            }
            messagesModel.setProperty(idx, "streamStats", stats);
            messagesModel.setProperty(idx, "status", "ok");
        }
        if (isOllama) ollamaManager.queryGpuStatus(model);
        saveChatHistory();
    }

    function _applyError(streamId, message) {
        var idx = findIndexById(streamId);
        if (idx >= 0) {
            _saveVariant(streamId, streamingService._streamVariantIndex, message, streamingService._streamThinking, model);
            var msg = messagesModel.get(idx);
            if (msg.variantIndex === streamingService._streamVariantIndex)
                messagesModel.setProperty(idx, "content", message);
            messagesModel.setProperty(idx, "status", "error");
        }
    }

    function _applyCancelled(streamId, stats) {
        var idx = findIndexById(streamId);
        if (idx >= 0) {
            _saveVariant(streamId, streamingService._streamVariantIndex, streamingService._streamContent, streamingService._streamThinking, model);
            var msg = messagesModel.get(idx);
            if (msg.variantIndex === streamingService._streamVariantIndex) {
                messagesModel.setProperty(idx, "content", streamingService._streamContent);
                messagesModel.setProperty(idx, "thinking", streamingService._streamThinking);
            }
            messagesModel.setProperty(idx, "streamStats", stats);
            messagesModel.setProperty(idx, "status", "ok");
        }
        saveChatHistory();
    }

    function _saveVariant(msgId, index, content, thinking, variantModel) {
        var store = JSON.parse(JSON.stringify(variantStore));
        var result = VariantStore.saveVariant(store, msgId, index, content, thinking, variantModel, maxVariantsPerMessage);

        if (result.evicted > 0) {
            var storeLen = store[msgId].length;
            streamingService._streamVariantIndex = Math.max(0, Math.min(streamingService._streamVariantIndex - result.evicted, storeLen - 1));
            var idx = findIndexById(msgId);
            if (idx >= 0) {
                var msg = messagesModel.get(idx);
                if (msg) {
                    var adjusted = VariantStore.adjustAfterEviction(
                        result.evicted, msg.variantIndex, storeLen,
                        isStreaming && activeStreamId === msgId
                    );
                    messagesModel.setProperty(idx, "variantIndex", adjusted.variantIndex);
                    messagesModel.setProperty(idx, "variantCount", adjusted.variantCount);
                }
            }
        }
        variantStore = store;
    }
}
