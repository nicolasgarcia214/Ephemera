import QtQuick
import QtQuick.Controls

Button {
    property string iconName: ""
    property color backgroundColor: "transparent"
    property color textColor: "transparent"
    property alias border: surface.border

    background: Rectangle { id: surface }
}
