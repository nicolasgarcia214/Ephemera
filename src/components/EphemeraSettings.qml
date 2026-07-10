import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

Item {
    id: root
    property bool isVisible: false
    signal closeRequested

    required property var aiService

    visible: isVisible

    onCloseRequested: {
        if (providerCard.validatePendingFields)
            providerCard.validatePendingFields();
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.98)
        radius: Theme.cornerRadius
        border.color: Theme.surfaceVariantAlpha
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingM

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingL

                StyledText {
                    text: "Ephemera Settings"
                    font.pixelSize: Theme.fontSizeLarge
                    color: Theme.surfaceText
                    font.weight: Font.Medium
                    Layout.alignment: Qt.AlignVCenter
                }

                Item { Layout.fillWidth: true }

                DankButton {
                    text: "Close"
                    iconName: "close"
                    onClicked: closeRequested()
                }
            }

            DankFlickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentHeight: settingsColumn.implicitHeight + Theme.spacingXL
                contentWidth: width

                Column {
                    id: settingsColumn
                    width: Math.min(550, parent.width - Theme.spacingL * 2)
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.spacingL

                    ProviderSettingsCard {
                        id: providerCard
                        aiService: root.aiService
                    }

                    ModelParametersCard {
                        aiService: root.aiService
                    }

                    ApiKeysCard {
                        aiService: root.aiService
                    }

                    ChatHistoryCard {
                        aiService: root.aiService
                    }

                    McpSettingsCard {
                        aiService: root.aiService
                    }
                }
            }
        }
    }
}
