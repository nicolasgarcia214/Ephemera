import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Widgets
import "../lib/Mcp.js" as Mcp
import "../lib/Providers.js" as Providers

SettingsCard {
    id: root

    required property var aiService
    property string _urlError: ""

    function commitMcpUrl() {
        var url = mcpUrlField.text.trim();
        if (!url) {
            _urlError = "";
            aiService.setMcpUrl("");
            return false;
        }
        var validated = Providers.validateUrl(url);
        if (!validated.valid) {
            _urlError = validated.error || "Invalid MCP URL.";
            return false;
        }
        var safetyError = Mcp.mcpUrlSafetyError(url);
        if (safetyError) {
            _urlError = safetyError;
            return false;
        }
        _urlError = "";
        aiService.setMcpUrl(url);
        return true;
    }

    // Header row
    Row {
        width: parent.width
        spacing: Theme.spacingM

        DankIcon {
            name: "build"
            size: Theme.iconSize
            color: Theme.primary
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            text: "MCP Tools · Experimental"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Medium
            color: Theme.surfaceText
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Column {
        width: parent.width
        spacing: Theme.spacingS

        // Enable toggle
        Row {
            width: parent.width
            spacing: Theme.spacingM

            DankIcon {
                name: "extension"
                size: Theme.iconSize
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS
                width: parent.width - parent.spacing * 2 - Theme.iconSize - mcpEnabledToggle.width

                StyledText {
                    text: "Enable MCP Tools"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }

                StyledText {
                    text: "Opt-in bridge support for Ollama. Expect transport and OAuth compatibility issues."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Switch {
                id: mcpEnabledToggle
                checked: aiService.mcpEnabled
                enabled: aiService.isOllama
                anchors.verticalCenter: parent.verticalCenter
                onToggled: aiService.setMcpEnabled(checked)
            }
        }

        // MCP server configuration
        AccordionSection {
            show: aiService.mcpEnabled

            Row {
                width: parent.width
                spacing: Theme.spacingM

                DankIcon {
                    name: "verified_user"
                    size: Theme.iconSize
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS
                    width: parent.width - parent.spacing * 2 - Theme.iconSize - toolRequestsToggle.width

                    StyledText {
                        text: "Allow Model Tool Requests"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }

                    StyledText {
                        text: "Only selected tools may be requested; every tool run needs approval."
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }
                }

                Switch {
                    id: toolRequestsToggle
                    checked: aiService.mcpToolRequestsAllowed
                    enabled: aiService.isOllama
                    anchors.verticalCenter: parent.verticalCenter
                    onToggled: {
                        aiService.setMcpToolRequestsAllowed(checked);
                    }
                }
            }

            StyledText {
                text: "MCP Server URL"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            DankTextField {
                id: mcpUrlField
                width: parent.width
                text: aiService.mcpUrl
                placeholderText: "http://192.168.1.107:8811/sse"
                onEditingFinished: root.commitMcpUrl()
            }

            StyledText {
                width: parent.width
                text: root._urlError
                visible: text.length > 0
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.error
                wrapMode: Text.Wrap
            }

            Row {
                width: parent.width
                spacing: Theme.spacingM
                visible: Mcp.requiresInsecureHttpConsent(aiService.mcpUrl)

                DankIcon {
                    name: "warning"
                    size: Theme.iconSize
                    color: Theme.error
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS
                    width: parent.width - parent.spacing * 2 - Theme.iconSize - insecureHttpToggle.width

                    StyledText {
                        text: "Allow Unencrypted Remote HTTP"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }

                    StyledText {
                        width: parent.width
                        text: "Traffic can be intercepted. Use only on a trusted private network."
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.error
                        wrapMode: Text.WordWrap
                    }
                }

                Switch {
                    id: insecureHttpToggle
                    checked: aiService.mcpInsecureHttpAllowed
                    anchors.verticalCenter: parent.verticalCenter
                    onToggled: aiService.setMcpInsecureHttpAllowed(checked)
                }
            }

            // Connect / Disconnect button
            Row {
                width: parent.width
                spacing: Theme.spacingS

                DankButton {
                    text: {
                        if (aiService.mcpConnecting) return "Connecting…";
                        if (aiService.mcpConnected) return "Reconnect";
                        return "Connect";
                    }
                    iconName: aiService.mcpConnected ? "refresh" : "link"
                    width: (parent.width - parent.spacing) / 2
                    enabled: {
                        var pendingUrl = mcpUrlField.text.trim();
                        var insecureConsentReady = pendingUrl === aiService.mcpUrl
                            && aiService.mcpInsecureHttpAllowed;
                        return aiService.isOllama
                            && !aiService.mcpConnecting
                            && pendingUrl.length > 0
                            && (!Mcp.requiresInsecureHttpConsent(pendingUrl) || insecureConsentReady);
                    }
                    onClicked: {
                        if (root.commitMcpUrl())
                            aiService.reconnectMcp();
                    }
                }

                DankButton {
                    text: "Disconnect"
                    iconName: "link_off"
                    width: (parent.width - parent.spacing) / 2
                    enabled: aiService.mcpConnected || aiService.mcpConnecting
                    backgroundColor: Theme.error
                    textColor: Theme.onPrimary
                    onClicked: aiService.disconnectMcp()
                }
            }
        }

        // Connection status
        AccordionSection {
            show: aiService.mcpEnabled

            // Error
            Rectangle {
                width: parent.width
                height: mcpErrorText.implicitHeight + Theme.spacingS * 2
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.error, 0.08)
                border.color: Theme.withAlpha(Theme.error, 0.3)
                border.width: 1
                visible: aiService.mcpConnectionError.length > 0

                StyledText {
                    id: mcpErrorText
                    anchors.centerIn: parent
                    width: parent.width - Theme.spacingS * 2
                    text: aiService.mcpConnectionError
                    textFormat: Text.PlainText
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.error
                    wrapMode: Text.Wrap
                }
            }

            // Status pill
            Rectangle {
                width: parent.width
                height: 36
                radius: Theme.cornerRadius
                color: {
                    if (aiService.mcpConnected) return Theme.withAlpha(Theme.primary, 0.10);
                    if (aiService.mcpConnecting) return Theme.withAlpha(Theme.secondary, 0.10);
                    return Theme.withAlpha(Theme.outline, 0.10);
                }
                border.color: {
                    if (aiService.mcpConnected) return Theme.withAlpha(Theme.primary, 0.25);
                    if (aiService.mcpConnecting) return Theme.withAlpha(Theme.secondary, 0.25);
                    return Theme.withAlpha(Theme.outline, 0.15);
                }
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.spacingS

                    DankIcon {
                        name: {
                            if (aiService.mcpConnected) return "check_circle";
                            if (aiService.mcpConnecting) return "pending";
                            return "radio_button_unchecked";
                        }
                        size: 16
                        color: {
                            if (aiService.mcpConnected) return Theme.primary;
                            if (aiService.mcpConnecting) return Theme.secondary;
                            return Theme.surfaceVariantText;
                        }
                        anchors.verticalCenter: parent.verticalCenter

                        SequentialAnimation on rotation {
                            loops: Animation.Infinite
                            running: aiService.mcpConnecting
                            NumberAnimation { from: 0; to: 360; duration: 1500; easing.type: Easing.Linear }
                        }
                    }

                    StyledText {
                        text: {
                            if (aiService.mcpConnected)
                                return "Connected · " + aiService.mcpTools.length + " tools · bridge " + aiService.mcpBridgeVersion;
                            if (aiService.mcpConnecting) return "Connecting…";
                            return "Not connected";
                        }
                        font.pixelSize: Theme.fontSizeSmall
                        color: {
                            if (aiService.mcpConnected) return Theme.primary;
                            if (aiService.mcpConnecting) return Theme.secondary;
                            return Theme.surfaceVariantText;
                        }
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            StyledText {
                width: parent.width
                visible: aiService.mcpIgnoredToolCount > 0
                text: aiService.mcpIgnoredToolCount + " invalid or unsupported tools were ignored."
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }

            // Tool list
            AccordionSection {
                show: aiService.mcpConnected && aiService.mcpTools.length > 0

                Column {
                    width: parent.width
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "Available MCP Tools"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    Repeater {
                        model: aiService.mcpTools

                        McpToolContractCard {
                            required property var modelData
                            width: parent.width
                            toolContract: modelData
                            contractApproved: aiService.isMcpToolApproved(modelData.name)
                            approvalEnabled: aiService.isOllama && aiService.mcpConnected
                            onApprovalChangeRequested: (toolName, approved) =>
                                aiService.setMcpToolApproved(toolName, approved)
                        }
                    }
                }
            }
        }
    }
}
