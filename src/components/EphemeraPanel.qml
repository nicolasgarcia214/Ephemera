import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services

pragma ComponentBehavior: Bound

PanelWindow {
    id: root

    property bool isVisible: false
    property var modelData: null
    property real panelWidth: 480
    property bool expandable: false
    property bool expanded: false
    property real expandedWidth: 960
    property Component content: null
    property real gap: 0
    property bool panelOnLeft: false
    property real screenWidth: modelData ? Number(modelData.width) : 0

    property real _lastValidScreenWidth: 0

    signal opened()

    onOpened: {
        if (contentLoader.item && contentLoader.item.focusInput)
            contentLoader.item.focusInput();
    }

    function show() {
        visible = true;
        isVisible = true;
    }

    function hide() {
        isVisible = false;
    }

    function toggle() {
        if (isVisible) hide();
        else show();
    }

    function _rememberScreenWidth() {
        var width = Number(screenWidth);
        if (isFinite(width) && width > 0)
            _lastValidScreenWidth = width;
    }

    function _boundedAlignedWidth(preferredWidth, availableWidth, scale) {
        var preferred = Number(preferredWidth);
        if (!isFinite(preferred) || preferred < 0) preferred = 0;

        var available = Number(availableWidth);
        var hasBound = isFinite(available) && available > 0;
        var bounded = hasBound ? Math.min(preferred, available) : preferred;
        var safeScale = Number(scale);
        if (!isFinite(safeScale) || safeScale <= 0) safeScale = 1;

        var aligned = Math.round(bounded * safeScale) / safeScale;
        if (hasBound && aligned > available)
            aligned = Math.floor(available * safeScale) / safeScale;
        return Math.max(0, aligned);
    }

    function _syncWindowEdge() {
        // Layer-shell applies each anchor property independently. Always release
        // the old edge before selecting the new one so a side switch can never
        // transiently stretch the surface between both horizontal edges.
        if (panelOnLeft) {
            root.anchors.right = false;
            root.anchors.left = true;
        } else {
            root.anchors.left = false;
            root.anchors.right = true;
        }
    }

    visible: isVisible
    screen: modelData
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.right: true

    onPanelOnLeftChanged: _syncWindowEdge()
    onScreenWidthChanged: _rememberScreenWidth()
    Component.onCompleted: {
        _syncWindowEdge();
        _rememberScreenWidth();
    }

    readonly property real _safeGap: {
        var value = Number(gap);
        return isFinite(value) && value > 0 ? value : 0;
    }
    readonly property real _effectiveScreenWidth: {
        var width = Number(screenWidth);
        if (isFinite(width) && width > 0) return width;
        return _lastValidScreenWidth;
    }
    readonly property real preferredActiveWidth: expandable && expanded ? expandedWidth : panelWidth
    readonly property real activeWidth: {
        var preferred = Number(preferredActiveWidth);
        if (!isFinite(preferred) || preferred < 0) preferred = 0;
        if (_effectiveScreenWidth <= 0) return preferred;
        return Math.min(preferred, Math.max(0, _effectiveScreenWidth - _safeGap));
    }
    readonly property real _preferredSurfaceWidth: {
        var preferred = expandable ? expandedWidth : panelWidth;
        return Number(preferred) + _safeGap;
    }
    implicitWidth: _boundedAlignedWidth(_preferredSurfaceWidth, _effectiveScreenWidth, dpr)
    implicitHeight: modelData ? modelData.height : 800

    WlrLayershell.namespace: "ephemera:panel"
    WlrLayershell.layer: WlrLayershell.Top
    WlrLayershell.exclusiveZone: 0
    WlrLayershell.keyboardFocus: isVisible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    readonly property real dpr: CompositorService.getScreenScale(root.screen)
    readonly property real alignedWidth: _boundedAlignedWidth(
        activeWidth + _safeGap, _effectiveScreenWidth, dpr
    )

    mask: Region {
        item: Rectangle {
            x: slide.x + layeredContent.x
            y: 0
            width: slide.width
            height: slide.height
        }
    }

    Item {
        id: slide
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        x: root.panelOnLeft ? 0 : parent.width - width
        width: alignedWidth

        property real offset: hiddenOffset()

        function hiddenOffset() {
            return root.panelOnLeft ? -slide.width : slide.width;
        }

        function syncOffset() {
            slide.offset = root.isVisible ? 0 : hiddenOffset();
        }

        onWidthChanged: syncOffset()

        Connections {
            target: root
            function onIsVisibleChanged() {
                slide.syncOffset();
            }
            function onPanelOnLeftChanged() {
                slide.syncOffset();
            }
        }

        Behavior on offset {
            NumberAnimation {
                duration: 400
                easing.type: Easing.OutCubic
                onRunningChanged: {
                    if (!running && !root.isVisible) root.visible = false;
                    if (!running && root.isVisible) root.opened();
                }
            }
        }

        Behavior on width {
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
        }

        Item {
            id: layeredContent
            layer.enabled: Quickshell.env("DMS_DISABLE_LAYER") !== "true"
                           && Quickshell.env("DMS_DISABLE_LAYER") !== "1"
            layer.smooth: false
            layer.textureSize: Qt.size(width * root.dpr, height * root.dpr)

            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width
            x: Theme.snap(slide.offset, root.dpr)

            Item {
                anchors.fill: parent
                anchors.topMargin: root.gap
                anchors.bottomMargin: root.gap
                anchors.rightMargin: panelOnLeft ? 0 : root._safeGap
                anchors.leftMargin: panelOnLeft ? root._safeGap : 0

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(
                        Theme.surfaceContainer.r,
                        Theme.surfaceContainer.g,
                        Theme.surfaceContainer.b,
                        SettingsData.popupTransparency
                    )
                    radius: Theme.cornerRadius
                }

                Item {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingL

                    Loader {
                        id: contentLoader
                        anchors.fill: parent
                        sourceComponent: root.content
                    }
                }
            }
        }
    }
}
