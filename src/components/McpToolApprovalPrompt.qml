import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Widgets
import "../lib/Mcp.js" as Mcp

Rectangle {
    id: root

    property string toolName: ""
    property string toolDescription: ""
    property string argumentsText: "{}"
    property string serverUrl: ""

    signal approveRequested()
    signal rejectRequested()

    height: approvalColumn.implicitHeight + Theme.spacingM * 2
    radius: Theme.cornerRadius
    color: Theme.surfaceContainerHighest
    border.color: Theme.withAlpha(Theme.primary, 0.35)
    border.width: 1

    Column {
        id: approvalColumn
        x: Theme.spacingM
        y: Theme.spacingM
        width: parent.width - Theme.spacingM * 2
        spacing: Theme.spacingS

        Row {
            width: parent.width
            spacing: Theme.spacingS

            DankIcon {
                name: "rule"
                size: 18
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                width: parent.width - Theme.spacingS - 18
                text: "Approve MCP tool: " + root.toolName
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        StyledText {
            width: parent.width
            text: root.toolDescription
            textFormat: Text.PlainText
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
            maximumLineCount: 6
            elide: Text.ElideRight
            visible: root.toolDescription.length > 0
        }

        StyledText {
            width: parent.width
            text: "Server: " + Mcp.formatReviewText(root.serverUrl)
            textFormat: Text.PlainText
            font.pixelSize: Theme.fontSizeSmall
            font.family: Theme.monoFontFamily
            color: Theme.surfaceVariantText
            elide: Text.ElideMiddle
            visible: root.serverUrl.length > 0
        }

        StyledText {
            width: parent.width
            text: "This tool may read or modify external data. Approve only after reviewing every argument."
            textFormat: Text.PlainText
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.error
            wrapMode: Text.WordWrap
        }

        Rectangle {
            width: parent.width
            height: Math.min(220, Math.max(72, argumentsTextArea.implicitHeight + Theme.spacingS * 2))
            radius: Theme.cornerRadius * 0.75
            color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.75)
            border.color: Theme.outlineMedium
            border.width: 1
            clip: true

            ScrollView {
                anchors.fill: parent
                anchors.margins: Theme.spacingS
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                TextArea {
                    id: argumentsTextArea
                    width: parent.width
                    text: root.argumentsText
                    readOnly: true
                    selectByMouse: true
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    font.pixelSize: Theme.fontSizeSmall
                    font.family: Theme.monoFontFamily
                    color: Theme.surfaceText
                    background: null
                    padding: 0
                }
            }
        }

        Row {
            anchors.right: parent.right
            spacing: Theme.spacingS

            DankButton {
                text: "Reject"
                iconName: "close"
                onClicked: root.rejectRequested()
            }

            DankButton {
                text: "Approve"
                iconName: "check"
                backgroundColor: Theme.primary
                textColor: Theme.onPrimary
                onClicked: root.approveRequested()
            }
        }
    }
}
