pragma Singleton

import QtQuick

QtObject {
    property string focusedScreenName: ""

    function getFocusedScreenName() {
        return focusedScreenName;
    }

    function getScreenScale(screen) {
        return 1;
    }
}
