import QtQuick
import Quickshell
import "./src/components"

ShellRoot {
    id: root

    property int testStep: 0
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

    function verifyGeometry(expectedSurfaceWidth, expectedSlideWidth,
                            expectedActiveWidth, label) {
        if (panel.anchors.left && panel.anchors.right) {
            finish(false, label + ": both layer-shell horizontal anchors became active");
            return false;
        }
        if (panel.anchors.left !== panel.panelOnLeft
                || panel.anchors.right === panel.panelOnLeft) {
            finish(false, label + ": layer-shell edge did not follow the selected side");
            return false;
        }
        if (!nearlyEqual(panel.panelWidth, 480)
                || !nearlyEqual(panel.expandedWidth, 960)
                || !nearlyEqual(panel.gap, 6)) {
            finish(false, label + ": preferred width or gap configuration changed");
            return false;
        }
        if (!nearlyEqual(panel.width, expectedSurfaceWidth)
                || !nearlyEqual(panel.implicitWidth, expectedSurfaceWidth)) {
            finish(false, label + ": layer surface width was " + panel.width
                   + ", expected " + expectedSurfaceWidth);
            return false;
        }
        if (!nearlyEqual(panel.alignedWidth, expectedSlideWidth)
                || !nearlyEqual(panel.activeWidth, expectedActiveWidth)) {
            finish(false, label + ": active geometry was " + panel.activeWidth
                   + "/" + panel.alignedWidth + ", expected "
                   + expectedActiveWidth + "/" + expectedSlideWidth);
            return false;
        }

        var visualX = panel.panelOnLeft ? 0 : panel.width - panel.alignedWidth;
        if (!nearlyEqual(panel.mask.item.x, visualX)
                || !nearlyEqual(panel.mask.item.width, panel.alignedWidth)) {
            finish(false, label + ": input mask diverged from the visible panel geometry");
            return false;
        }
        return true;
    }

    function advanceGeometryCases() {
        if (testStep === 0) {
            if (!verifyGeometry(966, 486, 480, "wide collapsed")) return;
            panel.screenWidth = 420;
        } else if (testStep === 1) {
            if (!verifyGeometry(420, 420, 414, "small collapsed")) return;
            panel.expanded = true;
        } else if (testStep === 2) {
            if (!verifyGeometry(420, 420, 414, "small expanded")) return;
            panel.screenWidth = 700;
        } else if (testStep === 3) {
            if (!verifyGeometry(700, 700, 694, "expanded after resize")) return;
            panel.panelOnLeft = true;
        } else if (testStep === 4) {
            if (!verifyGeometry(700, 700, 694, "expanded after side switch")) return;
            panel.expanded = false;
        } else if (testStep === 5) {
            if (!verifyGeometry(700, 486, 480, "collapsed after resize")) return;
            panel.screenWidth = 0;
        } else if (testStep === 6) {
            if (!verifyGeometry(700, 486, 480, "transient zero screen")) return;
            panel.screenWidth = 320;
        } else if (testStep === 7) {
            if (!verifyGeometry(320, 320, 314, "small resize")) return;
            panel.panelOnLeft = false;
            panel.expanded = true;
        } else if (testStep === 8) {
            if (!verifyGeometry(320, 320, 314, "small expanded on right")) return;
            rapidToggleTimer.start();
            return;
        }

        testStep++;
        geometryCaseTimer.restart();
    }

    function verifyToggle() {
        if (!verifyGeometry(320, 320, 314,
                            "rapid side switch " + (toggleCount + 1))) return;

        toggleCount++;
        if (toggleCount === 40) {
            finish(true, "small-screen expansion, resize, transient-screen, and 40 side-switch cases preserved geometry");
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
        id: geometryCaseTimer

        interval: 320
        repeat: false
        onTriggered: root.advanceGeometryCases()
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
        onTriggered: geometryCaseTimer.start()
    }

    Timer {
        interval: 8000
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
        screenWidth: 1200
    }
}
