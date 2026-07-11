import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Common
import qs.Widgets
import "../lib/Markdown.js" as Markdown

Item {
    id: root
    property string role: "assistant"
    property string text: ""
    property string thinking: ""
    property bool thinkingExpanded: false
    property string status: "ok" // ok|streaming|error
    property string modelName: "Assistant"
    property bool expanded: false
    property bool isLastAssistant: false
    property bool canRegenerate: false
    property int variantIndex: 0
    property int variantCount: 1
    signal regenerateRequested
    signal variantChangeRequested(int newIndex)
    signal editRequested(string newText)
    signal copyRequested
    property string copyStatus: ""
    property bool _editing: false
    property string _editText: ""
    property real streamStartTime: 0
    property int streamTokenCount: 0
    property int apiOutputTokens: 0
    property string streamStats: ""
    property bool isLocalProvider: false
    property string requestPayload: ""
    property bool _requestInfoExpanded: false

    readonly property bool isUser: role === "user"
    readonly property real bubbleMaxWidth: isUser ? Math.max(240, Math.floor(width * 0.82)) : width
    readonly property color userBubbleFill: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.1)
    readonly property color userBubbleBorder: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3)
    readonly property color assistantBubbleFill: Theme.surfaceContainer
    readonly property color assistantBubbleBorder: Theme.outline

    readonly property var themeColors: ({
        "codeBg": Theme.surfaceContainerHigh,
        "blockquoteBg": Theme.withAlpha(Theme.surfaceContainerHighest, 0.5),
        "blockquoteBorder": Theme.outlineVariant,
        "inlineCodeBg": Theme.withAlpha(Theme.onSurface, 0.1)
    })

    readonly property bool useMarkdownRendering: !isUser && status !== "streaming"
    property string renderedHtml: ""
    property string _lastRenderKey: ""

    function _updateRenderedHtml() {
        var renderKey = Markdown.renderCacheKey(root.text, themeColors);
        if (!isUser && renderKey !== _lastRenderKey) {
            try {
                renderedHtml = Markdown.markdownToHtml(root.text, themeColors);
            } catch (e) {
                console.warn("Ephemera: markdown render error, falling back to plain text:", e);
                renderedHtml = Markdown.escapeHtml(root.text);
            }
            _lastRenderKey = renderKey;
        }
    }

    onStatusChanged: {
        if (status === "ok" || status === "error")
            _updateRenderedHtml();
        if (status === "error") shakeAnim.start();
    }

    onTextChanged: {
        if (status === "streaming" && thinking.length > 0 && text.length > 0 && thinkingExpanded) {
            thinkingExpanded = false;
        }
        // Re-render if text changes while already in a terminal state
        if (status === "ok" || status === "error")
            _updateRenderedHtml();
    }

    onThemeColorsChanged: {
        // Keep deferred rendering during streaming, even when the theme changes.
        if (status === "ok" || status === "error")
            _updateRenderedHtml();
    }

    // Debounced thinking scroll
    Timer {
        id: thinkingScrollTimer
        interval: 100
        repeat: false
        onTriggered: {
            if (thinkingFlickable.contentHeight > thinkingFlickable.height) {
                thinkingFlickable.contentY = thinkingFlickable.contentHeight - thinkingFlickable.height;
            }
        }
    }

    onThinkingChanged: {
        if (thinkingExpanded)
            thinkingScrollTimer.restart();
    }

    width: parent ? parent.width : implicitWidth
    implicitHeight: bubble.implicitHeight

    // Error shake transform
    transform: Translate {
        id: shakeTranslate

        SequentialAnimation on x {
            id: shakeAnim
            running: false
            NumberAnimation { to: -4; duration: 50; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 4; duration: 50; easing.type: Easing.InOutQuad }
            NumberAnimation { to: -3; duration: 50; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 3; duration: 50; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 0; duration: 50; easing.type: Easing.OutQuad }
        }
    }

    Rectangle {
        id: bubble
        width: Math.min(root.bubbleMaxWidth, root.width)
        x: root.isUser ? (root.width - width) : 0
        radius: Theme.cornerRadius
        color: {
            if (root.isUser) return root.userBubbleFill;
            if (root.status === "error") return Theme.withAlpha(Theme.error, 0.04);
            return hoverHandler.hovered ? Qt.lighter(root.assistantBubbleFill, 1.08) : root.assistantBubbleFill;
        }
        border.color: status === "error" ? Theme.error : (root.isUser ? root.userBubbleBorder : root.assistantBubbleBorder)
        border.width: 1

        implicitHeight: contentColumn.implicitHeight + Theme.spacingM * 2
        height: implicitHeight

        Behavior on color {
            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        Behavior on x {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }

        HoverHandler {
            id: hoverHandler
        }

        // Click anywhere on bubble to toggle thinking during streaming
        MouseArea {
            anchors.fill: parent
            enabled: root.status === "streaming" && root.thinking.length > 0
            visible: enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: root.thinkingExpanded = !root.thinkingExpanded
        }

        Column {
            id: contentColumn
            x: Theme.spacingM
            y: Theme.spacingM
            width: parent.width - Theme.spacingM * 2
            spacing: Theme.spacingS

            RowLayout {
                id: headerRow
                width: parent.width
                spacing: Theme.spacingXS

                Item { Layout.fillWidth: root.isUser }

                Rectangle {
                    id: chipRect
                    radius: Theme.cornerRadius
                    color: root.isUser ? Theme.withAlpha(Theme.primary, 0.14) : Theme.surfaceVariant
                    Layout.preferredHeight: Theme.fontSizeSmall * 1.6
                    Layout.preferredWidth: Math.min(headerText.implicitWidth + Theme.spacingS * 2, root.expanded ? 320 : 160)
                    clip: true

                    Behavior on Layout.preferredWidth {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }

                    StyledText {
                        id: headerText
                        anchors.centerIn: parent
                        width: parent.width - Theme.spacingS * 2
                        text: root.isUser ? "You" : root.modelName
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        color: root.isUser ? Theme.primary : Theme.surfaceVariantText
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                    }

                    HoverHandler {
                        id: chipHover
                    }

                    ToolTip {
                        visible: chipHover.hovered && headerText.truncated
                        delay: 500
                        text: root.modelName
                    }
                }

                Rectangle {
                    width: 18
                    height: 18
                    radius: 9
                    color: root.isUser ? Theme.withAlpha(Theme.primary, 0.20) : Theme.surfaceVariant
                    border.width: 1
                    border.color: root.isUser ? Theme.withAlpha(Theme.primary, 0.35) : Theme.surfaceVariantAlpha

                    DankIcon {
                        anchors.centerIn: parent
                        name: root.isUser ? "person" : "smart_toy"
                        size: 14
                        color: root.isUser ? Theme.primary : Theme.surfaceVariantText
                    }
                }

                DankActionButton {
                    visible: root.isUser && root.status === "ok" && !root._editing
                    opacity: hoverHandler.hovered ? 1.0 : 0.4
                    iconName: "edit"
                    buttonSize: 24
                    iconSize: 14
                    backgroundColor: Theme.withAlpha(Theme.surfaceContainer, 0)
                    iconColor: Theme.primary
                    tooltipText: "Edit"
                    onClicked: {
                        root._editText = root.text;
                        root._editing = true;
                    }

                    Behavior on opacity {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                }

                Item { Layout.fillWidth: !root.isUser }

                Row {
                    visible: !root.isUser && root.variantCount > 1
                    opacity: hoverHandler.hovered ? 1.0 : 0.4
                    spacing: 2
                    Layout.alignment: Qt.AlignVCenter

                    Behavior on opacity {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }

                    DankActionButton {
                        iconName: "chevron_left"
                        buttonSize: 24
                        iconSize: 14
                        backgroundColor: Theme.withAlpha(Theme.surfaceContainer, 0)
                        iconColor: Theme.surfaceVariantText
                        enabled: root.variantIndex > 0
                        opacity: enabled ? 1.0 : 0.3
                        onClicked: root.variantChangeRequested(root.variantIndex - 1)
                    }

                    StyledText {
                        text: (root.variantIndex + 1) + "/" + root.variantCount
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    DankActionButton {
                        iconName: "chevron_right"
                        buttonSize: 24
                        iconSize: 14
                        backgroundColor: Theme.withAlpha(Theme.surfaceContainer, 0)
                        iconColor: Theme.surfaceVariantText
                        enabled: root.variantIndex < root.variantCount - 1
                        opacity: enabled ? 1.0 : 0.3
                        onClicked: root.variantChangeRequested(root.variantIndex + 1)
                    }
                }

                DankActionButton {
                    id: copyBtn
                    visible: !root.isUser && root.status === "ok"
                    opacity: hoverHandler.hovered ? 1.0 : 0.4
                    iconName: root.copyStatus === "copied" ? "check"
                              : root.copyStatus === "error" ? "error"
                              : "content_copy"
                    buttonSize: 24
                    iconSize: 14
                    backgroundColor: Theme.withAlpha(Theme.surfaceContainer, 0)
                    iconColor: root.copyStatus === "copied" ? Theme.success
                               : root.copyStatus === "error" ? Theme.error
                               : Theme.surfaceVariantText
                    tooltipText: root.copyStatus === "copied" ? "Copied!"
                                 : root.copyStatus === "error" ? "Copy failed"
                                 : root.copyStatus === "pending" ? "Copying…"
                                 : "Copy"
                    enabled: root.copyStatus !== "pending"
                    onClicked: root.copyRequested()

                    Behavior on opacity {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                }

                DankActionButton {
                    id: requestInfoBtn
                    visible: !root.isUser && root.requestPayload.length > 0
                    opacity: hoverHandler.hovered ? 1.0 : (root._requestInfoExpanded ? 0.8 : 0.4)
                    iconName: "data_object"
                    buttonSize: 24
                    iconSize: 14
                    backgroundColor: Theme.withAlpha(Theme.surfaceContainer, 0)
                    iconColor: root._requestInfoExpanded ? Theme.primary : Theme.surfaceVariantText
                    tooltipText: root._requestInfoExpanded ? "Hide request" : "View request"
                    onClicked: root._requestInfoExpanded = !root._requestInfoExpanded

                    Behavior on opacity {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                }

                DankActionButton {
                    visible: !root.isUser && root.isLastAssistant && root.canRegenerate && root.status !== "streaming"
                    opacity: hoverHandler.hovered ? 1.0 : 0.4
                    iconName: "refresh"
                    buttonSize: 24
                    iconSize: 14
                    backgroundColor: Theme.withAlpha(Theme.surfaceContainer, 0)
                    iconColor: Theme.surfaceVariantText
                    tooltipText: "Regenerate"
                    onClicked: root.regenerateRequested()

                    Behavior on opacity {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }
                }
            }

            // Header-content separator
            Item {
                width: parent.width
                implicitHeight: 1 + Theme.spacingXS
                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.withAlpha(Theme.outline, 0.15)
                }
            }

            // Thinking section (only visible when thinking exists)
            Column {
                width: parent.width
                visible: root.thinking.length > 0
                spacing: Theme.spacingXS

                MouseArea {
                    width: parent.width
                    height: thinkingHeader.implicitHeight
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.thinkingExpanded = !root.thinkingExpanded

                    Row {
                        id: thinkingHeader
                        spacing: Theme.spacingXS

                        DankIcon {
                            name: "psychology"
                            size: 14
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        DankIcon {
                            name: root.thinkingExpanded ? "expand_more" : "chevron_right"
                            size: 14
                            color: Theme.surfaceTextMedium
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "Thinking" + (root.status === "streaming" && root.text.length === 0 ? "..." : "")
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: Theme.surfaceTextMedium
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                Flickable {
                    id: thinkingFlickable
                    visible: root.thinkingExpanded
                    width: parent.width
                    height: Math.min(contentHeight, 200)
                    contentHeight: thinkingTextArea.implicitHeight
                    clip: true
                    flickableDirection: Flickable.VerticalFlick

                    TextArea {
                        id: thinkingTextArea
                        width: thinkingFlickable.width
                        text: root.thinking
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceTextMedium
                        readOnly: true
                        selectByMouse: true
                        background: null
                        leftPadding: 4
                        rightPadding: 4
                    }

                    ScrollBar.vertical: ScrollBar {}
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.withAlpha(Theme.outline, 0.25)
                    visible: root.thinkingExpanded
                }
            }

            // Extra spacing between thinking and content
            Item {
                width: parent.width
                height: Theme.spacingM
                visible: root.thinking.length > 0
            }

            // Warning banner for errors
            Rectangle {
                visible: root.status === "error"
                width: parent.width
                height: visible ? warningRow.implicitHeight + Theme.spacingS * 2 : 0
                radius: Theme.cornerRadius * 0.75
                color: Theme.withAlpha(Theme.error, 0.08)
                border.color: Theme.withAlpha(Theme.error, 0.3)
                border.width: 1

                Row {
                    id: warningRow
                    x: Theme.spacingS
                    y: Theme.spacingS
                    width: parent.width - Theme.spacingS * 2
                    spacing: Theme.spacingS

                    DankIcon {
                        name: "warning"
                        size: 16
                        color: Theme.error
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Provider not connected"
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        color: Theme.error
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            TextArea {
                id: contentArea
                visible: !root._editing
                text: root.useMarkdownRendering ? root.renderedHtml : root.text
                textFormat: root.useMarkdownRendering ? Text.RichText : Text.PlainText
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeMedium
                font.family: Theme.fontFamily
                color: status === "error" ? Theme.error : Theme.surfaceText
                width: parent.width

                readOnly: true
                selectByMouse: true
                selectionColor: Theme.primary
                selectedTextColor: Theme.onPrimary
                background: null
                leftPadding: 4
                rightPadding: 4

                onLinkActivated: link => {
                    // Only allow http/https — security fix
                    if (/^https?:\/\//i.test(link))
                        Qt.openUrlExternally(link);
                }

                hoverEnabled: true

                // Qt breaks the text binding when textFormat switches between
                // RichText and PlainText. Re-establish it after each switch.
                Connections {
                    target: root
                    function onUseMarkdownRenderingChanged() {
                        contentArea.text = Qt.binding(function() {
                            return root.useMarkdownRendering ? root.renderedHtml : root.text;
                        });
                    }
                }
            }

            // Inline edit area for user messages
            Column {
                visible: root._editing
                width: parent.width
                spacing: Theme.spacingS

                Rectangle {
                    width: parent.width
                    height: Math.max(60, Math.min(200, editArea.contentHeight + Theme.spacingM * 2))
                    radius: Theme.cornerRadius * 0.75
                    color: Theme.surfaceContainerHigh
                    border.color: editArea.activeFocus ? Theme.primary : Theme.outlineMedium
                    border.width: editArea.activeFocus ? 2 : 1

                    ScrollView {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                        TextArea {
                            id: editArea
                            text: root._editText
                            wrapMode: TextArea.Wrap
                            font.pixelSize: Theme.fontSizeMedium
                            font.family: Theme.fontFamily
                            color: Theme.surfaceText
                            background: null
                            padding: 0

                            Component.onCompleted: {
                                editArea.forceActiveFocus();
                                editArea.cursorPosition = editArea.text.length;
                            }

                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) {
                                    root._editing = false;
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Return && !(event.modifiers & Qt.ShiftModifier)) {
                                    if (editArea.text.trim().length > 0) {
                                        root.editRequested(editArea.text.trim());
                                        root._editing = false;
                                    }
                                    event.accepted = true;
                                }
                            }
                        }
                    }
                }

                Row {
                    spacing: Theme.spacingS
                    anchors.right: parent.right

                    DankButton {
                        text: "Cancel"
                        onClicked: root._editing = false
                    }

                    DankButton {
                        text: "Send"
                        backgroundColor: Theme.primary
                        textColor: Theme.onPrimary
                        enabled: editArea.text.trim().length > 0
                        onClicked: {
                            root.editRequested(editArea.text.trim());
                            root._editing = false;
                        }
                    }
                }
            }

            // Pulsing streaming dots (clickable to toggle thinking)
            Item {
                visible: status === "streaming"
                width: streamingRow.width
                height: visible ? streamingRow.height : 0
                x: root.isUser ? (parent.width - width) : 0

                // Thinking phase: thinking exists but no content yet
                readonly property bool isThinkingPhase: root.thinking.length > 0 && root.text.length === 0
                readonly property color dotColor: isThinkingPhase ? Theme.tertiary : Theme.primary

                Row {
                    id: streamingRow
                    spacing: 6
                    height: Theme.fontSizeSmall * 1.6

                    DankIcon {
                        visible: root.thinking.length > 0
                        name: "psychology"
                        size: 16
                        color: parent.parent.dotColor
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: root.thinkingExpanded ? 0.5 : 1.0

                        Behavior on opacity {
                            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }
                    }

                    Repeater {
                        model: 3
                        Rectangle {
                            width: 7
                            height: 7
                            radius: 3.5
                            color: streamingRow.parent.dotColor
                            opacity: 0.4
                            scale: 1.0
                            anchors.verticalCenter: parent.verticalCenter

                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * 160 }
                                NumberAnimation { to: 1.0; duration: 400; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 0.4; duration: 400; easing.type: Easing.InOutSine }
                                PauseAnimation { duration: (2 - index) * 160 }
                            }

                            SequentialAnimation on scale {
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * 160 }
                                NumberAnimation { to: 1.4; duration: 400; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 400; easing.type: Easing.InOutSine }
                                PauseAnimation { duration: (2 - index) * 160 }
                            }
                        }
                    }

                    // Waiting for first token hint
                    StyledText {
                        visible: root.status === "streaming" && root.streamStartTime === 0 && root.text.length === 0 && root.thinking.length === 0
                        text: root.isLocalProvider ? "Loading model\u2026" : "Sending request\u2026"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceTextMedium
                        opacity: 0.7
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // Elapsed time + tokens/sec counter
                    StyledText {
                        visible: root.streamStartTime > 0
                        text: _elapsedText
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceTextMedium
                        opacity: 0.7
                        anchors.verticalCenter: parent.verticalCenter

                        property string _elapsedText: "0.0s"

                        Timer {
                            running: root.status === "streaming" && root.streamStartTime > 0
                            interval: 100
                            repeat: true
                            onTriggered: {
                                var elapsed = (Date.now() - root.streamStartTime) / 1000;
                                var label = elapsed.toFixed(1) + "s";
                                var tokens = root.apiOutputTokens > 0 ? root.apiOutputTokens : root.streamTokenCount;
                                if (tokens > 0 && elapsed > 0.5) {
                                    var tps = tokens / elapsed;
                                    var prefix = root.apiOutputTokens > 0 ? "" : "~";
                                    label += " · " + prefix + tps.toFixed(1) + " tok/s";
                                }
                                parent._elapsedText = label;
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: root.thinking.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (root.thinking.length > 0)
                            root.thinkingExpanded = !root.thinkingExpanded;
                    }
                }
            }

            // Persisted stream stats (toggle on click)
            Item {
                visible: root.status !== "streaming" && root.streamStats.length > 0 && !root.isUser
                width: statsRow.implicitWidth
                height: 22

                property bool _statsVisible: false

                Row {
                    id: statsRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS

                    DankIcon {
                        name: "speed"
                        size: 14
                        color: Theme.surfaceTextMedium
                        opacity: parent.parent._statsVisible ? 0.7 : 0.5
                        anchors.verticalCenter: parent.verticalCenter

                        Behavior on opacity {
                            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }
                    }

                    StyledText {
                        visible: parent.parent._statsVisible
                        text: root.streamStats
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceTextMedium
                        opacity: 0.5
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: parent._statsVisible = !parent._statsVisible
                }
            }

            // Request payload section (collapsible)
            Column {
                width: parent.width
                visible: root._requestInfoExpanded && root.requestPayload.length > 0
                spacing: Theme.spacingXS

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.withAlpha(Theme.outline, 0.15)
                }

                Row {
                    spacing: Theme.spacingXS

                    DankIcon {
                        name: "data_object"
                        size: 14
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: "Request payload"
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        color: Theme.surfaceTextMedium
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Flickable {
                    width: parent.width
                    height: Math.min(contentHeight, 250)
                    contentHeight: requestInfoTextArea.implicitHeight
                    clip: true
                    flickableDirection: Flickable.VerticalFlick

                    TextArea {
                        id: requestInfoTextArea
                        width: parent.width
                        text: root.requestPayload
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.monoFontFamily
                        color: Theme.surfaceTextMedium
                        readOnly: true
                        selectByMouse: true
                        background: null
                        leftPadding: 4
                        rightPadding: 4
                    }

                    ScrollBar.vertical: ScrollBar {}
                }
            }
        }
    }
}
