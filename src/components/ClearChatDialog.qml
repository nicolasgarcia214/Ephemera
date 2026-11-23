import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Widgets

Popup {
    id: root

    signal confirmed()

    anchors.centerIn: parent
    width: Math.min(320, (parent ? parent.width : 320) - Theme.spacingL * 2)
    padding: Theme.spacingL
    modal: true
    dim: false
    // Default focus is the safe choice: Ctrl+L then Enter must not wipe the chat.
    onOpened: cancelBtn.forceActiveFocus()

    background: Rectangle {
        color: Theme.surfaceContainerHighest
        radius: Theme.cornerRadius * 2
        border.color: Theme.outline
        border.width: 1
    }

    Column {
        width: parent.width
        spacing: Theme.spacingM

        Row {
            spacing: Theme.spacingS

            DankIcon {
                name: "warning"
                size: 22
                color: Theme.error
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: "Clear conversation?"
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Medium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        StyledText {
            width: parent.width
            text: "This will permanently delete all messages in this chat."
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceTextMedium
            wrapMode: Text.Wrap
        }

        Row {
            anchors.right: parent.right
            spacing: Theme.spacingS

            DankButton {
                id: cancelBtn
                text: "Cancel"
                focus: true
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
                onClicked: root.close()
            }

            DankButton {
                id: clearConfirmBtn
                text: "Clear"
                backgroundColor: Theme.error
                textColor: Theme.onPrimary
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
                onClicked: {
                    root.confirmed();
                    root.close();
                }
            }
        }
    }
}
