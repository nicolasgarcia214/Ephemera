import QtQuick

Item {
    property real minimum: 0
    property real maximum: 100
    property real step: 1
    property real value: 0
    property bool showValue: true

    signal sliderValueChanged(var newValue)
}
