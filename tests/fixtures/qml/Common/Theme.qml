pragma Singleton

import QtQuick

QtObject {
    id: root

    readonly property color background: "#101010"
    readonly property color surfaceContainer: "#202020"
    readonly property color surfaceContainerHigh: "#282828"
    readonly property color surfaceContainerHighest: "#303030"
    readonly property color surfaceVariant: "#383838"
    readonly property color surfaceVariantAlpha: "#66383838"
    readonly property color surfaceText: "#f5f5f5"
    readonly property color surfaceTextMedium: "#c8c8c8"
    readonly property color surfaceVariantText: "#b0b0b0"
    readonly property color primary: "#9ecbff"
    readonly property color secondary: "#c4b5fd"
    readonly property color tertiary: "#f0abfc"
    readonly property color _onPrimary: "#101010"
    readonly property color _onSurface: "#f5f5f5"
    readonly property alias onPrimary: root._onPrimary
    readonly property alias onSurface: root._onSurface
    readonly property color error: "#ff8a80"
    readonly property color success: "#75d69c"
    readonly property color outline: "#808080"
    readonly property color outlineMedium: "#666666"
    readonly property color outlineVariant: "#505050"
    readonly property color outlineButton: "#a0a0a0"
    readonly property real cornerRadius: 12
    readonly property real spacingXS: 4
    readonly property real spacingS: 8
    readonly property real spacingM: 12
    readonly property real spacingL: 16
    readonly property real spacingXL: 24
    readonly property real iconSize: 24
    readonly property real fontSizeSmall: 12
    readonly property real fontSizeMedium: 14
    readonly property real fontSizeLarge: 18
    readonly property string fontFamily: "sans-serif"
    readonly property string monoFontFamily: "monospace"
    readonly property int fontWeight: Font.Normal
    readonly property real popupTransparency: 1
    readonly property int shortDuration: 100
    readonly property int standardEasing: Easing.OutCubic

    function withAlpha(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha);
    }

    function px(value, dpr) {
        return Math.round(value * dpr) / dpr;
    }

    function snap(value, dpr) {
        return Math.round(value * dpr) / dpr;
    }
}
