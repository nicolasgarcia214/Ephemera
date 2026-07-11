import QtQuick

Item {
    property var options: []
    property var currentValue

    signal valueChanged(var value)

    implicitHeight: 36
}
