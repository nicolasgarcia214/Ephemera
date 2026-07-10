import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: root

    required property string iconName
    property int iconSize: Theme.iconSize - 4
    property color iconColor: Theme.surfaceText
    property string tooltipText: ""
    property string tooltipSide: "bottom"
    property bool actionEnabled: true
    property int buttonSize: 32

    signal clicked()

    implicitWidth: buttonSize
    implicitHeight: buttonSize

    onVisibleChanged: {
        if (!visible) {
            tooltipDelay.stop();
            tooltip.hide();
        }
    }

    DankActionButton {
        anchors.fill: parent
        iconName: root.iconName
        iconSize: root.iconSize
        iconColor: root.iconColor
        enabled: root.actionEnabled
        tooltipText: null
        onClicked: root.clicked()
    }

    HoverHandler {
        id: hoverHandler

        onHoveredChanged: {
            if (hovered && root.tooltipText) {
                tooltipDelay.restart();
            } else {
                tooltipDelay.stop();
                tooltip.hide();
            }
        }
    }

    Timer {
        id: tooltipDelay
        interval: 400
        repeat: false
        onTriggered: {
            if (hoverHandler.hovered && root.tooltipText)
                tooltip.show(root.tooltipText, root, 0, 0, root.tooltipSide);
        }
    }

    DankTooltipV2 {
        id: tooltip
    }
}
