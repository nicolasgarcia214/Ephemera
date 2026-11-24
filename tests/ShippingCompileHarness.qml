import QtQuick
import Quickshell
import qs.Services
import "."
import "./src/components"
import "./src/services"

ShellRoot {
    id: root

    property bool finished: false
    property int explicitComponentCount: 0

    function finish(success, message) {
        if (finished) return;
        finished = true;
        console.log("EPHEMERA_SHIPPING_COMPILE_TEST "
                    + (success ? "PASS" : "FAIL") + ": " + message);
        Qt.quit();
    }

    function requireObject(object, name) {
        if (!object) {
            finish(false, name + " was not created");
            return;
        }
        explicitComponentCount++;
    }

    function checkFocusedPanelSelection() {
        var left = { modelData: { name: "DP-1" } };
        var right = { modelData: { name: "HDMI-A-1" } };
        var panels = [left, right];
        var cases = [
            [shippingDaemon._panelForScreen(panels, "HDMI-A-1"), right, "focused screen"],
            [shippingDaemon._panelForScreen(panels, "eDP-1"), left, "unknown screen fallback"],
            [shippingDaemon._panelForScreen(panels, ""), left, "no focused screen fallback"],
            [shippingDaemon._panelForScreen([], "DP-1"), null, "no panels"]
        ];
        for (var i = 0; i < cases.length; i++) {
            if (cases[i][0] !== cases[i][1]) {
                finish(false, "daemon toggle panel selection failed: " + cases[i][2]);
                return false;
            }
        }
        function panel(name, open) {
            return { modelData: { name: name }, isVisible: open,
                     show: function() { this.isVisible = true; },
                     hide: function() { this.isVisible = false; } };
        }
        var a = panel("DP-1", true), b = panel("HDMI-A-1", false);
        shippingDaemon._togglePanels([a, b], "HDMI-A-1");
        if (a.isVisible || b.isVisible) {
            finish(false, "daemon toggle opened a second panel instead of closing the open one");
            return false;
        }
        shippingDaemon._togglePanels([a, b], "HDMI-A-1");
        if (a.isVisible || !b.isVisible) {
            finish(false, "daemon toggle did not open the focused screen's panel");
            return false;
        }
        return true;
    }

    EphemeraDaemon {
        id: shippingDaemon

        property string pluginId: "ephemera-shipping-compile-test"
        property var pluginData: ({})
        property var pluginService: PluginService
    }

    EphemeraService {
        id: fixtureService
        pluginId: "ephemera-shipping-compile-test"
    }

    EphemeraPanel {
        id: productionPanel
        visible: false
        modelData: null
        content: Component {
            EphemeraChat {
                aiService: fixtureService
                showSettings: true
                slideoutExpandable: true
                slideoutExpanded: true
            }
        }
    }

    Item {
        id: explicitComponents
        visible: false
        width: 960
        height: 800

        AccordionSection { id: accordionSection }
        ApiKeysCard { id: apiKeysCard; aiService: fixtureService }
        ChatComposer { id: chatComposer; aiService: fixtureService }
        ChatHeader {
            id: chatHeader
            aiService: fixtureService
            slideoutExpanded: true
            slideoutExpandable: true
            showSettings: true
        }
        ChatHistoryCard { id: chatHistoryCard; aiService: fixtureService }
        ChatToast { id: chatToast }
        ClearChatDialog { id: clearChatDialog }
        EphemeraActionButton { id: actionButton; iconName: "check" }
        EphemeraChat {
            id: ephemeraChat
            aiService: fixtureService
            showSettings: true
            slideoutExpandable: true
            slideoutExpanded: true
        }
        EphemeraSettings {
            id: ephemeraSettings
            aiService: fixtureService
            isVisible: true
        }
        McpSettingsCard { id: mcpSettingsCard; aiService: fixtureService }
        McpToolApprovalPrompt { id: mcpToolApprovalPrompt }
        McpToolContractCard {
            id: mcpToolContractCard
            toolContract: ({
                name: "fixture_tool",
                description: "Compile fixture",
                inputSchema: { type: "object", properties: {} }
            })
            contractApproved: false
            approvalEnabled: true
            reviewingContract: true
        }
        MessageBubble {
            id: messageBubble
            role: "assistant"
            text: "Shipping compile fixture"
            thinking: "Fixture reasoning"
            status: "ok"
            requestPayload: "{}"
            variantCount: 2
        }
        MessageList {
            id: messageList
            messages: fixtureService.messagesModel
        }
        ModelParametersCard { id: modelParametersCard; aiService: fixtureService }
        ProviderSettingsCard { id: providerSettingsCard; aiService: fixtureService }
        SettingsCard { id: settingsCard }
    }

    Component.onCompleted: {
        fixtureService.messagesModel.append({
            id: "compile-user",
            role: "user",
            content: "Compile every delegate",
            thinking: "",
            status: "ok",
            modelName: "fixture",
            variantIndex: 0,
            variantCount: 1,
            streamStats: "",
            requestPayload: ""
        });
        fixtureService.messagesModel.append({
            id: "compile-assistant",
            role: "assistant",
            content: "Delegate instantiated",
            thinking: "Compile fixture reasoning",
            status: "ok",
            modelName: "fixture",
            variantIndex: 0,
            variantCount: 2,
            streamStats: "1 token",
            requestPayload: "{}"
        });

        requireObject(shippingDaemon, "EphemeraDaemon");
        if (!checkFocusedPanelSelection()) return;
        requireObject(productionPanel, "EphemeraPanel");
        requireObject(accordionSection, "AccordionSection");
        requireObject(apiKeysCard, "ApiKeysCard");
        requireObject(chatComposer, "ChatComposer");
        requireObject(chatHeader, "ChatHeader");
        requireObject(chatHistoryCard, "ChatHistoryCard");
        requireObject(chatToast, "ChatToast");
        requireObject(clearChatDialog, "ClearChatDialog");
        requireObject(actionButton, "EphemeraActionButton");
        requireObject(ephemeraChat, "EphemeraChat");
        requireObject(ephemeraSettings, "EphemeraSettings");
        requireObject(mcpSettingsCard, "McpSettingsCard");
        requireObject(mcpToolApprovalPrompt, "McpToolApprovalPrompt");
        requireObject(mcpToolContractCard, "McpToolContractCard");
        requireObject(messageBubble, "MessageBubble");
        requireObject(messageList, "MessageList");
        requireObject(modelParametersCard, "ModelParametersCard");
        requireObject(providerSettingsCard, "ProviderSettingsCard");
        requireObject(settingsCard, "SettingsCard");

        settleTimer.start();
    }

    Timer {
        id: settleTimer
        interval: 500
        repeat: false
        onTriggered: {
            if (root.finished) return;
            if (fixtureService.messagesModel.count !== 2) {
                root.finish(false, "production message model did not instantiate delegates");
                return;
            }
            root.finish(root.explicitComponentCount === 20,
                        root.explicitComponentCount + " shipping objects created");
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: false
        onTriggered: root.finish(false, "timed out")
    }
}
