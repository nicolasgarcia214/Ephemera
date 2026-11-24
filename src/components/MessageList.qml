import QtQuick
import QtQuick.Controls
import qs.Common

Item {
    id: root
    clip: true
    property var messages: null
    property bool stickToBottom: true
    property string modelName: "Assistant"
    property bool expanded: false
    property bool canRegenerate: false
    property bool isLocalProvider: false
    property real streamStartTime: 0
    property int streamTokenCount: 0
    property int apiOutputTokens: 0
    signal regenerateRequested
    signal variantChangeRequested(string msgId, int newIndex)
    signal editRequested(string msgId, string newText)
    signal copyRequested(string msgId)

    property real _lastContentY: 0

    function scrollToBottom() {
        stickToBottom = true;
        _followEnd();
    }

    function _atEnd() {
        return listView.contentY + listView.height
            >= listView.originY + listView.contentHeight - 1;
    }

    function _followEnd() {
        if (stickToBottom)
            listView.positionViewAtEnd();
    }

    ListView {
        id: listView
        anchors.fill: parent
        anchors.leftMargin: Theme.spacingS
        anchors.rightMargin: Theme.spacingS
        anchors.bottomMargin: Theme.spacingS
        anchors.topMargin: Theme.spacingL
        model: root.messages
        spacing: Theme.spacingM
        clip: true
        ScrollBar.vertical: ScrollBar {}

        onContentYChanged: {
            if (root._atEnd())
                root.stickToBottom = true;
            else if (listView.contentY < root._lastContentY)
                root.stickToBottom = false;
            root._lastContentY = listView.contentY;
        }

        onContentHeightChanged: if (root.stickToBottom) Qt.callLater(root._followEnd)
        onHeightChanged: if (root.stickToBottom) Qt.callLater(root._followEnd)

        onModelChanged: Qt.callLater(root.scrollToBottom)

        delegate: Item {
            id: wrapper
            width: listView.width

            readonly property string previousRole: (index > 0 && root.messages) ? (root.messages.get(index - 1).role || "") : ""
            readonly property bool roleChanged: previousRole.length > 0 && previousRole !== (model.role || "")
            readonly property int topGap: roleChanged ? Theme.spacingM : 0

            implicitHeight: bubble.implicitHeight + topGap

            property real _entryOffset: 8
            opacity: 0
            scale: 0.97
            transformOrigin: Item.Bottom

            Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
            Behavior on _entryOffset { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

            Component.onCompleted: {
                opacity = 1;
                scale = 1.0;
                _entryOffset = 0;
            }

            MessageBubble {
                id: bubble
                width: listView.width
                y: wrapper.topGap + wrapper._entryOffset
                role: model.role
                text: model.content
                thinking: model.thinking || ""
                status: model.status
                errorText: model.errorText || ""
                modelName: (model.modelName || "").length > 0 ? model.modelName : root.modelName
                expanded: root.expanded
                isLastAssistant: model.role === "assistant" && index === listView.count - 1
                canRegenerate: root.canRegenerate
                variantIndex: model.variantIndex || 0
                variantCount: model.variantCount || 1
                streamStartTime: model.status === "streaming" ? root.streamStartTime : 0
                streamTokenCount: model.status === "streaming" ? root.streamTokenCount : 0
                apiOutputTokens: model.status === "streaming" ? root.apiOutputTokens : 0
                streamStats: model.streamStats || ""
                isLocalProvider: root.isLocalProvider
                requestPayload: model.requestPayload || ""
                copyStatus: model.copyStatus || ""
                onRegenerateRequested: root.regenerateRequested()
                onVariantChangeRequested: newIndex => root.variantChangeRequested(model.id, newIndex)
                onEditRequested: newText => root.editRequested(model.id, newText)
                onCopyRequested: root.copyRequested(model.id)
            }
        }
    }
}
