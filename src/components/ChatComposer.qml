import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import qs.Common
import qs.Widgets

Row {
    id: root

    required property var aiService
    property alias text: composer.text
    readonly property bool submissionReady:
        aiService && aiService.canSubmitMessage(composer.text)

    signal sendRequested()
    signal hideRequested()
    signal clearRequested()
    signal settingsToggled()

    function forceActiveFocus() { composer.forceActiveFocus(); }

    function requestSubmission() {
        if (submissionReady)
            sendRequested();
    }

    width: parent ? parent.width : 0
    height: composerContainer.height
    spacing: Theme.spacingM

    Rectangle {
        id: composerContainer
        width: parent.width - actionButtonArea.width - Theme.spacingM
        height: Math.max(44, Math.min(160, composer.contentHeight + Theme.spacingM * 2))
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
        border.color: composer.activeFocus ? Theme.primary : Theme.outlineMedium
        border.width: composer.activeFocus ? 2 : 1

        Behavior on height {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        Behavior on border.color {
            ColorAnimation {
                duration: Theme.shortDuration
                easing.type: Theme.standardEasing
            }
        }

        Behavior on border.width {
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Theme.standardEasing
            }
        }

        ScrollView {
            id: scrollView
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            clip: true
            padding: 0
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            TextArea {
                id: composer
                implicitWidth: scrollView.availableWidth
                wrapMode: TextArea.Wrap
                background: Rectangle { color: Theme.withAlpha(Theme.surfaceContainer, 0) }
                font.pixelSize: Theme.fontSizeMedium
                font.family: Theme.fontFamily
                font.weight: Theme.fontWeight
                color: Theme.surfaceText
                Material.accent: Theme.primary
                padding: 0
                leftPadding: 0
                rightPadding: 0
                topPadding: 0
                bottomPadding: 0

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        root.hideRequested();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return && !(event.modifiers & Qt.ShiftModifier)) {
                        root.requestSubmission();
                        event.accepted = true;
                    } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Return) {
                        root.requestSubmission();
                        event.accepted = true;
                    } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_L) {
                        root.clearRequested();
                        composer.forceActiveFocus();
                        event.accepted = true;
                    } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_N) {
                        root.clearRequested();
                        composer.forceActiveFocus();
                        event.accepted = true;
                    } else if ((event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) === (Qt.ControlModifier | Qt.ShiftModifier) && event.key === Qt.Key_S) {
                        root.settingsToggled();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up && composer.text.length === 0 && aiService.lastUserText.length > 0) {
                        composer.text = aiService.lastUserText;
                        composer.cursorPosition = composer.text.length;
                        event.accepted = true;
                    }
                }
            }
        }

        StyledText {
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            text: aiService.missingApiKey
                ? (aiService._keyringAvailable ? "API key required \u2014 set in Settings" : "API key required \u2014 set env var")
                : "Ask something\u2026  (Shift+Enter for newline)"
            font.pixelSize: Theme.fontSizeMedium
            color: aiService.missingApiKey ? Theme.error : Theme.outlineButton
            verticalAlignment: Text.AlignTop
            visible: composer.text.length === 0
            wrapMode: Text.Wrap
        }
    }

    // Compact send/stop crossfade area
    Item {
        id: actionButtonArea
        width: 44
        height: composerContainer.height

        DankActionButton {
            id: sendBtn
            anchors.centerIn: parent
            iconName: "send"
            buttonSize: 40
            iconSize: 20
            backgroundColor: Theme.primary
            iconColor: Theme.onPrimary
            tooltipText: "Send"
            enabled: root.submissionReady
            opacity: aiService.isStreaming ? 0.0 : 1.0
            scale: aiService.isStreaming ? 0.6 : 1.0
            visible: opacity > 0
            onClicked: root.requestSubmission()

            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }

        DankActionButton {
            id: stopBtn
            anchors.centerIn: parent
            iconName: "stop"
            buttonSize: 40
            iconSize: 20
            backgroundColor: Theme.error
            iconColor: Theme.onPrimary
            tooltipText: "Stop"
            enabled: aiService.isStreaming
            opacity: aiService.isStreaming ? 1.0 : 0.0
            scale: aiService.isStreaming ? 1.0 : 0.6
            visible: opacity > 0
            onClicked: aiService.cancel()

            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }
    }
}
