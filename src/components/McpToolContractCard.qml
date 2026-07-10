import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Widgets
import "../lib/Mcp.js" as Mcp

Rectangle {
    id: root

    required property var toolContract
    required property bool contractApproved
    required property bool approvalEnabled
    property bool reviewingContract: false

    signal approvalChangeRequested(string toolName, bool approved)

    height: contentColumn.implicitHeight + Theme.spacingS * 2
    radius: Theme.cornerRadius
    color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.5)

    Column {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Theme.spacingS
        spacing: Theme.spacingS

        Row {
            width: parent.width
            spacing: Theme.spacingS

            DankIcon {
                name: "functions"
                size: 14
                color: Theme.primary
                anchors.top: parent.top
                anchors.topMargin: 2
            }

            Column {
                width: parent.width - 14 - contractButton.width - parent.spacing * 2
                spacing: 2

                StyledText {
                    width: parent.width
                    text: root.toolContract.name
                    textFormat: Text.PlainText
                    font.pixelSize: Theme.fontSizeSmall
                    font.family: Theme.monoFontFamily
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    elide: Text.ElideRight
                }

                StyledText {
                    width: parent.width
                    text: Mcp.formatReviewText(root.toolContract.description || "")
                    textFormat: Text.PlainText
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    visible: text.length > 0
                }
            }

            DankButton {
                id: contractButton
                text: root.contractApproved ? "Approved" : "Review"
                iconName: root.contractApproved ? "verified" : "policy"
                enabled: root.approvalEnabled
                anchors.verticalCenter: parent.verticalCenter
                onClicked: root.reviewingContract = !root.reviewingContract
            }
        }

        AccordionSection {
            show: root.reviewingContract

            StyledText {
                width: parent.width
                text: "Exact approval contract"
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            Rectangle {
                width: parent.width
                height: 220
                radius: Theme.cornerRadius * 0.75
                color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.75)
                border.color: Theme.outlineMedium
                border.width: 1
                clip: true

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingS
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AsNeeded

                    TextArea {
                        width: parent.width
                        text: Mcp.formatToolContract(root.toolContract)
                        readOnly: true
                        selectByMouse: true
                        wrapMode: Text.NoWrap
                        textFormat: Text.PlainText
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.monoFontFamily
                        color: Theme.surfaceText
                        background: null
                        padding: 0
                    }
                }
            }

            StyledText {
                width: parent.width
                text: "Approval is invalidated automatically if any displayed field changes. Every invocation still requires confirmation."
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }

            Row {
                anchors.right: parent.right
                spacing: Theme.spacingS

                DankButton {
                    text: "Cancel"
                    onClicked: root.reviewingContract = false
                }

                DankButton {
                    text: root.contractApproved ? "Revoke" : "Approve exact contract"
                    iconName: root.contractApproved ? "remove_moderator" : "verified_user"
                    backgroundColor: root.contractApproved ? Theme.error : Theme.primary
                    textColor: Theme.onPrimary
                    onClicked: {
                        root.approvalChangeRequested(
                            root.toolContract.name, !root.contractApproved);
                        root.reviewingContract = false;
                    }
                }
            }
        }
    }
}
