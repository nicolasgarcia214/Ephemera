import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import "../lib/Providers.js" as Providers

RowLayout {
    id: root

    required property var aiService
    required property bool slideoutExpanded
    required property bool slideoutExpandable
    required property bool showSettings
    property string displayModel: ""

    signal settingsToggled()
    signal exportRequested()
    signal exportFileRequested()
    signal clearRequested()
    signal expandToggled()
    signal panelSideToggled()
    signal hideRequested()

    spacing: Theme.spacingS
    clip: true

    function showToast(message) {
        // Delegated up to parent via signal — see EphemeraChat
    }

    StyledText {
        text: "Ephemera"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Medium
        color: Theme.surfaceText
        Layout.alignment: Qt.AlignVCenter
    }

    // Provider pill with fixed max width and truncation
    Rectangle {
        id: providerPill
        radius: Theme.cornerRadius
        color: {
            if (aiService.missingApiKey || aiService.lastRequestFailed)
                return Theme.withAlpha(Theme.error, 0.15);
            if (_flashing)
                return Theme.withAlpha(Theme.primary, 0.3);
            return Theme.surfaceVariant;
        }
        border.color: (aiService.missingApiKey || aiService.lastRequestFailed) ? Theme.withAlpha(Theme.error, 0.4) : Theme.withAlpha(Theme.outline, 0)
        border.width: (aiService.missingApiKey || aiService.lastRequestFailed) ? 1 : 0
        height: Theme.fontSizeSmall * 1.6
        Layout.alignment: Qt.AlignVCenter

        Layout.preferredWidth: root.slideoutExpanded ? 320 : 160

        clip: true
        HoverHandler { id: pillHoverHandler }

        property bool _flashing: false

        Behavior on color {
            ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        Timer {
            id: providerFlashTimer
            interval: 150
            onTriggered: providerPill._flashing = false
        }

        StyledText {
            id: providerLabel
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Theme.spacingS - dropdownIcon.width - Theme.spacingS / 2 - 2
            text: root.displayModel
            font.pixelSize: Theme.fontSizeSmall
            color: (aiService.missingApiKey || aiService.lastRequestFailed) ? Theme.error : Theme.surfaceVariantText
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignLeft

            onTextChanged: {
                providerPill._flashing = true;
                providerFlashTimer.start();
            }
        }

        DankIcon {
            id: dropdownIcon
            name: "arrow_drop_down"
            size: Theme.fontSizeSmall
            color: providerLabel.color
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingS / 2
            anchors.verticalCenter: parent.verticalCenter
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: modelSelectorPopup.open()
        }

        ToolTip {
            visible: pillHoverHandler.hovered && providerLabel.truncated && !modelSelectorPopup.visible
            delay: 500
            text: root.displayModel
        }

        Popup {
            id: modelSelectorPopup
            y: providerPill.height + Theme.spacingXS
            property real _hoveredItemWidth: 0
            width: Math.min(Math.max(220, providerPill.width, _hoveredItemWidth), root.width - providerPill.x)
            padding: Theme.spacingS
            Behavior on width {
                enabled: modelSelectorPopup.visible
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            onClosed: _hoveredItemWidth = 0

            background: Rectangle {
                color: Theme.surfaceContainerHighest
                radius: Theme.cornerRadius
                border.color: Theme.outline
                border.width: 1
            }

            contentItem: MouseArea {
                id: popupHoverArea
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                clip: true
                implicitWidth: popupColumn.implicitWidth
                implicitHeight: popupColumn.implicitHeight
                onContainsMouseChanged: {
                    if (!containsMouse && !quickModelField.activeFocus)
                        popupHoverCloseTimer.start()
                    else
                        popupHoverCloseTimer.stop()
                }

                Timer {
                    id: popupHoverCloseTimer
                    interval: 400
                    onTriggered: if (!popupHoverArea.containsMouse) modelSelectorPopup.close()
                }

                Column {
                    id: popupColumn
                    width: modelSelectorPopup.availableWidth
                    spacing: Theme.spacingXS

                // Model text field for quick entry
                DankTextField {
                    id: quickModelField
                    width: parent.width
                    text: aiService.model
                    placeholderText: {
                        var info = Providers.getProviderInfo(aiService.provider);
                        return info.modelPlaceholder || "model-name";
                    }
                    onEditingFinished: {
                        aiService.model = text.trim();
                        aiService.saveSettingValue("model", text.trim());
                    }
                    Keys.onReturnPressed: {
                        editingFinished();
                        modelSelectorPopup.close();
                    }

                    Component.onCompleted: {
                        quickModelField.forceActiveFocus();
                        quickModelField.selectAll();
                    }
                }

                // Model list (hardcoded for external providers, runtime for Ollama)
                Column {
                    width: parent.width
                    spacing: 0
                    visible: aiService.modelChoices.length > 0

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.withAlpha(Theme.outline, 0.15)
                    }

                    Repeater {
                        model: aiService.modelChoices

                        ItemDelegate {
                            width: parent.width
                            height: 32
                            padding: 0
                            leftPadding: Theme.spacingS
                            rightPadding: Theme.spacingS
                            onClicked: {
                                aiService.model = modelData;
                                aiService.saveSettingValue("model", modelData);
                                modelSelectorPopup.close();
                            }
                            background: Rectangle {
                                color: parent.hovered ? Theme.withAlpha(Theme.primary, 0.12) : Theme.withAlpha(Theme.primary, 0)
                                radius: Theme.cornerRadius
                            }

                            contentItem: StyledText {
                                id: modelItemLabel
                                text: modelData
                                font.pixelSize: Theme.fontSizeSmall
                                font.family: Theme.monoFontFamily
                                color: modelData === aiService.model ? Theme.primary : Theme.surfaceText
                                font.weight: modelData === aiService.model ? Font.Medium : Font.Normal
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                                width: parent ? parent.width : 0
                            }

                            HoverHandler {
                                id: itemHover
                                onHoveredChanged: {
                                    if (hovered && modelItemLabel.truncated) {
                                        var needed = modelItemLabel.implicitWidth + Theme.spacingS * 4 + modelSelectorPopup.padding * 2
                                        modelSelectorPopup._hoveredItemWidth = Math.min(
                                            Math.max(modelSelectorPopup._hoveredItemWidth, needed),
                                            root.width - providerPill.x
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                }
            }
        }
    }

    Item { Layout.fillWidth: true }

    EphemeraActionButton {
        iconName: "tune"
        tooltipText: root.showSettings ? "Hide settings" : "Settings"
        onClicked: root.settingsToggled()
    }

    EphemeraActionButton {
        iconName: "content_copy"
        tooltipText: "Copy conversation"
        visible: root.slideoutExpanded
        actionEnabled: (aiService.messageCount || 0) > 0 && !aiService.isStreaming
        onClicked: root.exportRequested()
    }

    EphemeraActionButton {
        iconName: "save_as"
        tooltipText: "Save conversation as .md"
        visible: root.slideoutExpanded
        actionEnabled: (aiService.messageCount || 0) > 0 && !aiService.isStreaming
        onClicked: root.exportFileRequested()
    }

    EphemeraActionButton {
        iconName: "delete_sweep"
        tooltipText: "Clear chat"
        visible: root.slideoutExpanded
        actionEnabled: (aiService.messageCount || 0) > 0 && !aiService.isStreaming
        onClicked: root.clearRequested()
    }

    EphemeraActionButton {
        id: overflowBtn
        iconName: "more_vert"
        tooltipText: "More actions"
        visible: !root.slideoutExpanded
        onClicked: overflowMenu.open()

        Popup {
            id: overflowMenu
            x: overflowBtn.width - width
            y: overflowBtn.height + Theme.spacingXS
            width: 200
            padding: Theme.spacingXS

            background: Rectangle {
                color: Theme.surfaceContainerHighest
                radius: Theme.cornerRadius
                border.color: Theme.outline
                border.width: 1
            }

            Column {
                width: parent.width
                spacing: 0

                ItemDelegate {
                    width: parent.width
                    height: 36
                    enabled: (aiService.messageCount || 0) > 0 && !aiService.isStreaming
                    onClicked: { root.exportRequested(); overflowMenu.close(); }
                    background: Rectangle {
                        color: parent.hovered ? Theme.withAlpha(Theme.primary, 0.12) : Theme.withAlpha(Theme.primary, 0)
                        radius: Theme.cornerRadius
                    }

                    contentItem: Row {
                        spacing: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter

                        DankIcon {
                            name: "content_copy"
                            size: 16
                            color: parent.parent.enabled ? Theme.surfaceText : Theme.surfaceTextMedium
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "Copy conversation"
                            font.pixelSize: Theme.fontSizeSmall
                            color: parent.parent.enabled ? Theme.surfaceText : Theme.surfaceTextMedium
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                ItemDelegate {
                    width: parent.width
                    height: 36
                    enabled: (aiService.messageCount || 0) > 0 && !aiService.isStreaming
                    onClicked: { root.exportFileRequested(); overflowMenu.close(); }
                    background: Rectangle {
                        color: parent.hovered ? Theme.withAlpha(Theme.primary, 0.12) : Theme.withAlpha(Theme.primary, 0)
                        radius: Theme.cornerRadius
                    }

                    contentItem: Row {
                        spacing: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter

                        DankIcon {
                            name: "save_as"
                            size: 16
                            color: parent.parent.enabled ? Theme.surfaceText : Theme.surfaceTextMedium
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "Save as .md"
                            font.pixelSize: Theme.fontSizeSmall
                            color: parent.parent.enabled ? Theme.surfaceText : Theme.surfaceTextMedium
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                ItemDelegate {
                    width: parent.width
                    height: 36
                    enabled: (aiService.messageCount || 0) > 0 && !aiService.isStreaming
                    onClicked: { overflowMenu.close(); root.clearRequested(); }
                    background: Rectangle {
                        color: parent.hovered ? Theme.withAlpha(Theme.primary, 0.12) : Theme.withAlpha(Theme.primary, 0)
                        radius: Theme.cornerRadius
                    }

                    contentItem: Row {
                        spacing: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter

                        DankIcon {
                            name: "delete_sweep"
                            size: 16
                            color: parent.parent.enabled ? Theme.surfaceText : Theme.surfaceTextMedium
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "Clear chat"
                            font.pixelSize: Theme.fontSizeSmall
                            color: parent.parent.enabled ? Theme.surfaceText : Theme.surfaceTextMedium
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
        }
    }

    EphemeraActionButton {
        id: expandBtn
        iconName: root.slideoutExpanded ? "unfold_less" : "unfold_more"
        iconSize: Theme.iconSize - 4
        iconColor: Theme.surfaceText
        visible: root.slideoutExpandable
        tooltipText: root.slideoutExpanded ? "Collapse" : "Expand"
        onClicked: root.expandToggled()

        transform: Rotation {
            angle: 90
            origin.x: expandBtn.width / 2
            origin.y: expandBtn.height / 2
        }
    }

    EphemeraActionButton {
        iconName: aiService.panelOnLeft ? "last_page" : "first_page"
        iconSize: Theme.iconSize - 4
        iconColor: Theme.surfaceText
        tooltipText: aiService.panelOnLeft ? "Move to right" : "Move to left"
        onClicked: root.panelSideToggled()
    }

    EphemeraActionButton {
        iconName: "close"
        iconSize: Theme.iconSize - 4
        iconColor: Theme.surfaceText
        tooltipText: "Close"
        onClicked: root.hideRequested()
    }
}
