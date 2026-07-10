import QtQuick
import Quickshell
import "./src/components"

ShellRoot {
    id: root

    property int toggleCount: 0
    property bool finished: false

    function finish(success, message) {
        if (finished) return;
        finished = true;
        console.log("EPHEMERA_PANEL_QML_TEST " + (success ? "PASS" : "FAIL") + ": " + message);
        Qt.quit();
    }

    function nearlyEqual(first, second) {
        return Math.abs(first - second) < 0.01;
    }

    function verifyToggle() {
        if (panel.anchors.left && panel.anchors.right) {
            finish(false, "both layer-shell horizontal anchors became active");
            return;
        }
        if (panel.anchors.left !== panel.panelOnLeft
                || panel.anchors.right === panel.panelOnLeft) {
            finish(false, "layer-shell edge did not follow the selected side");
            return;
        }
        if (panel.expanded) {
            finish(false, "side switching unexpectedly expanded the panel");
            return;
        }
        if (!nearlyEqual(panel.width, panel.implicitWidth)) {
            finish(false, "layer-shell surface was stretched to the screen width");
            return;
        }

        var visualX = panel.panelOnLeft ? 0 : panel.width - panel.alignedWidth;
        if (!nearlyEqual(panel.mask.item.x, visualX)
                || !nearlyEqual(panel.mask.item.width, panel.alignedWidth)) {
            finish(false, "input mask diverged from the visible panel geometry");
            return;
        }

        toggleCount++;
        if (toggleCount === 40) {
            finish(true, "40 rapid side switches preserved geometry and input coverage");
            return;
        }
        rapidToggleTimer.restart();
    }

    Component.onCompleted: panel.show()

    Timer {
        id: rapidToggleTimer

        interval: 10
        repeat: false
        onTriggered: {
            panel.panelOnLeft = !panel.panelOnLeft;
            geometrySettleTimer.restart();
        }
    }

    Timer {
        id: geometrySettleTimer

        interval: 10
        repeat: false
        onTriggered: root.verifyToggle()
    }

    Timer {
        interval: 500
        running: true
        repeat: false
        onTriggered: rapidToggleTimer.start()
    }

    Timer {
        interval: 5000
        running: true
        repeat: false
        onTriggered: root.finish(false, "timed out")
    }

    EphemeraPanel {
        id: panel
        panelWidth: 480
        expandable: true
        expandedWidth: 960
        gap: 6
    }
}
