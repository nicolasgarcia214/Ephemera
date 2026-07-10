import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root

    required property var aiService
    property bool showSettings: false
    property bool _settingsClosing: false
    property bool slideoutExpandable: false
    property bool slideoutExpanded: false
    signal hideRequested
    signal expandToggled

    function focusInput() {
        composerArea.forceActiveFocus();
    }

    Connections {
        target: aiService
        function onIsStreamingChanged() {
            if (!aiService.isStreaming && root.visible)
                composerArea.forceActiveFocus();
        }
    }

    onVisibleChanged: {
        if (!visible) {
            showSettings = false;
            _settingsClosing = false;
            if (aiService) aiService.scheduleIdleShutdown();
        } else {
            if (aiService) aiService.ensureOllamaReady();
            Qt.callLater(function() { composerArea.forceActiveFocus(); });
        }
    }

    readonly property string displayModel: {
        if (!aiService) return "";
        var p = aiService.provider || "ollama";
        var m = aiService.model || "";
        if (m) return p.toUpperCase() + " / " + m;
        return p.toUpperCase();
    }

    function sendCurrentMessage() {
        if (!composerArea.text || composerArea.text.trim().length === 0) return;
        if (!aiService) return;
        aiService.sendMessage(composerArea.text.trim());
        composerArea.text = "";
    }

    function closeSettings() {
        if (_settingsClosing) return;
        _settingsClosing = true;
        if (settingsPanelLoader.item)
            settingsPanelLoader.item.opacity = 0;
        settingsCloseTimer.start();
    }

    function _handleClearRequest() {
        if (!aiService.isStreaming && (aiService.messageCount || 0) > 0)
            clearConfirmDialog.open();
        else if (!aiService.isStreaming)
            composerArea.text = "";
        composerArea.forceActiveFocus();
    }

    Column {
        anchors.fill: parent
        spacing: Theme.spacingM

        // -- Header --
        ChatHeader {
            id: header
            width: parent.width
            aiService: root.aiService
            slideoutExpanded: root.slideoutExpanded
            slideoutExpandable: root.slideoutExpandable
            showSettings: root.showSettings
            displayModel: root.displayModel
            onSettingsToggled: {
                if (root.showSettings) root.closeSettings();
                else root.showSettings = true;
            }
            onExportRequested: {
                aiService.exportConversation();
                chatToast.show("Conversation copied to clipboard");
            }
            onExportFileRequested: {
                var file = aiService.exportConversationToFile();
                chatToast.show("Saved to " + file.split("/").pop());
            }
            onClearRequested: root._handleClearRequest()
            onExpandToggled: root.expandToggled()
            onPanelSideToggled: aiService.togglePanelSide()
            onHideRequested: root.hideRequested()
        }

        // -- Message area --
        Rectangle {
            id: messageArea
            width: parent.width
            height: parent.height - header.height - composerArea.height - Theme.spacingM * 3
            radius: Theme.cornerRadius
            color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, SettingsData.popupTransparency)
            border.color: Theme.surfaceVariantAlpha
            border.width: 1

            MessageList {
                id: list
                anchors.fill: parent
                messages: aiService.messagesModel
                modelName: aiService.model || "Assistant"
                expanded: root.slideoutExpanded
                canRegenerate: !aiService.isStreaming && aiService.lastUserText.length > 0
                isLocalProvider: aiService.isOllama
                streamStartTime: aiService.streamStartTime
                streamTokenCount: aiService.streamTokenCount
                apiOutputTokens: aiService.apiOutputTokens
                onRegenerateRequested: aiService.regenerate()
                onVariantChangeRequested: (msgId, newIndex) => aiService.switchVariant(msgId, newIndex)
                onEditRequested: (msgId, newText) => aiService.editAndRegenerate(msgId, newText)
            }

            // Missing API key banner
            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: Theme.spacingM
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - Theme.spacingL * 2
                height: apiKeyBannerCol.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.error, 0.08)
                border.color: Theme.withAlpha(Theme.error, 0.3)
                border.width: 1
                visible: aiService.missingApiKey
                z: 10

                Column {
                    id: apiKeyBannerCol
                    anchors.centerIn: parent
                    width: parent.width - Theme.spacingM * 2
                    spacing: Theme.spacingXS

                    Row {
                        spacing: Theme.spacingS

                        DankIcon {
                            name: "vpn_key_off"
                            size: 18
                            color: Theme.error
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "API key not found"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.error
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    StyledText {
                        width: parent.width
                        text: aiService._keyringAvailable
                            ? "Open Settings to store your key, or set " + aiService._envVarForProvider(aiService.provider) + " in your environment."
                            : "Set the " + aiService._envVarForProvider(aiService.provider) + " environment variable before starting Quickshell."
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.fontFamily
                        color: Theme.surfaceTextMedium
                        wrapMode: Text.Wrap
                    }
                }
            }

            // Ollama starting banner
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.spacingM
                anchors.horizontalCenter: parent.horizontalCenter
                width: ollamaBannerRow.implicitWidth + Theme.spacingM * 2
                height: 32
                radius: 16
                color: Theme.withAlpha(Theme.primary, 0.10)
                border.color: Theme.withAlpha(Theme.primary, 0.25)
                border.width: 1
                visible: opacity > 0
                opacity: aiService.isOllama && !aiService.ollamaReady && (aiService.ollamaStartPending || aiService.ollamaRetries > 0) ? 1.0 : 0.0
                z: 10

                Behavior on opacity {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                Row {
                    id: ollamaBannerRow
                    anchors.centerIn: parent
                    spacing: Theme.spacingS

                    DankIcon {
                        name: "pending"
                        size: 16
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter

                        SequentialAnimation on rotation {
                            loops: Animation.Infinite
                            NumberAnimation { from: 0; to: 360; duration: 1500; easing.type: Easing.Linear }
                        }
                    }

                    StyledText {
                        text: "Starting Ollama\u2026"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // Breathing empty state
            Column {
                id: emptyState
                anchors.centerIn: parent
                spacing: Theme.spacingS
                visible: opacity > 0
                opacity: (aiService.messageCount || 0) === 0 ? 1.0 : 0.0
                width: parent.width * 0.8

                Behavior on opacity {
                    NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                }

                DankIcon {
                    id: vaporIcon
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "blur_on"
                    size: 48
                    color: Theme.primary
                    opacity: 0.5

                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: root.visible && emptyState.visible
                        NumberAnimation { to: 0.75; duration: 1200; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0.5; duration: 1200; easing.type: Easing.InOutSine }
                    }

                    SequentialAnimation on scale {
                        loops: Animation.Infinite
                        running: root.visible && emptyState.visible
                        NumberAnimation { to: 1.06; duration: 1200; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 1200; easing.type: Easing.InOutSine }
                    }
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Ask anything. Nothing is saved."
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceTextMedium
                    wrapMode: Text.Wrap
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                }

                StyledText {
                    id: subtitleText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "ephemeral by design"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    opacity: 0.5
                    horizontalAlignment: Text.AlignHCenter

                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: root.visible && emptyState.visible
                        NumberAnimation { to: 0.75; duration: 1600; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0.5; duration: 1600; easing.type: Easing.InOutSine }
                    }
                }
            }

            // Scroll-to-bottom pill
            Rectangle {
                id: scrollPill
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.spacingM
                width: scrollPillRow.implicitWidth + Theme.spacingM * 2
                height: 32
                radius: 16
                color: Theme.withAlpha(Theme.primary, 0.85)
                visible: opacity > 0
                opacity: list.stickToBottom ? 0.0 : 1.0
                scale: list.stickToBottom ? 0.8 : 1.0

                Behavior on opacity {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                Row {
                    id: scrollPillRow
                    anchors.centerIn: parent
                    spacing: Theme.spacingXS

                    DankIcon {
                        name: "keyboard_arrow_down"
                        size: 16
                        color: Theme.onPrimary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "New messages"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.onPrimary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: list.scrollToBottom()
                }
            }

            McpToolApprovalPrompt {
                id: toolApprovalPrompt
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.spacingM
                width: parent.width - Theme.spacingL * 2
                visible: aiService.mcpToolApprovalPending
                toolName: aiService.mcpPendingToolName
                toolDescription: aiService.mcpPendingToolDescription
                argumentsText: aiService.mcpPendingToolArgumentsText
                serverUrl: aiService.mcpUrl
                z: 20
                onRejectRequested: {
                    aiService.rejectMcpToolCall();
                    chatToast.show("Tool call rejected");
                }
                onApproveRequested: aiService.approveMcpToolCall()
            }
        }

        // -- Composer --
        ChatComposer {
            id: composerArea
            aiService: root.aiService
            onSendRequested: root.sendCurrentMessage()
            onHideRequested: root.hideRequested()
            onClearRequested: root._handleClearRequest()
            onSettingsToggled: {
                if (root.showSettings) root.closeSettings();
                else root.showSettings = true;
            }
        }
    }

    // -- Toast notification --
    ChatToast {
        id: chatToast
        anchors.fill: parent
        bottomMargin: composerArea.height + Theme.spacingL
    }

    // -- Settings overlay with fade in/out --
    Loader {
        id: settingsPanelLoader
        anchors.fill: parent
        active: showSettings || _settingsClosing
        sourceComponent: settingsPanelComponent

        onLoaded: {
            if (item) {
                item.opacity = 0;
                Qt.callLater(function() {
                    if (settingsPanelLoader.item)
                        settingsPanelLoader.item.opacity = 1;
                });
            }
        }
    }

    Timer {
        id: settingsCloseTimer
        interval: 220
        repeat: false
        onTriggered: {
            showSettings = false;
            _settingsClosing = false;
        }
    }

    Component {
        id: settingsPanelComponent

        EphemeraSettings {
            anchors.fill: parent
            isVisible: true
            onCloseRequested: root.closeSettings()
            aiService: root.aiService

            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    // -- Clear chat dim overlay (scoped to widget, not full window) --
    Rectangle {
        anchors.fill: parent
        color: Theme.withAlpha(Theme.onSurface, 0.4)
        visible: clearConfirmDialog.visible
        z: 99
    }

    // -- Clear chat confirmation dialog --
    ClearChatDialog {
        id: clearConfirmDialog
        onConfirmed: {
            aiService.clearChat();
            composerArea.text = "";
            composerArea.forceActiveFocus();
        }
    }
}
