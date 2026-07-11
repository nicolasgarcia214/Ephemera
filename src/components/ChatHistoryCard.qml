import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Widgets

SettingsCard {
    id: root

    required property var aiService

    Row {
        width: parent.width
        spacing: Theme.spacingM

        DankIcon {
            name: "save"
            size: Theme.iconSize
            color: Theme.primary
            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXS
            width: parent.width - parent.spacing * 2 - Theme.iconSize - persistToggle.width

            StyledText {
                text: "Save Chat History"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            StyledText {
                text: "Persist conversations across sessions. API keys are never stored."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
            }
        }

        Switch {
            id: persistToggle
            checked: aiService.persistChat
            anchors.verticalCenter: parent.verticalCenter
            onToggled: aiService.setPersistChat(checked)
        }
    }
}
