import QtQuick

Item {
    property string iconName: ""
    property real buttonSize: 32
    property real iconSize: 20
    property color backgroundColor: "transparent"
    property color iconColor: "transparent"
    property var tooltipText: ""
    property bool enabled: true

    signal clicked()

    implicitWidth: buttonSize
    implicitHeight: buttonSize
}
