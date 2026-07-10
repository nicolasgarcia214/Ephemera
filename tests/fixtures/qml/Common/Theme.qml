pragma Singleton

import QtQuick

QtObject {
    readonly property color surfaceContainer: "#202020"
    readonly property real cornerRadius: 12
    readonly property real spacingL: 16

    function px(value, dpr) {
        return Math.round(value * dpr) / dpr;
    }

    function snap(value, dpr) {
        return Math.round(value * dpr) / dpr;
    }
}
