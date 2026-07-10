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
    Component.onCompleted: _syncWindowEdge()

    readonly property real activeWidth: expandable && expanded ? expandedWidth : panelWidth
    implicitWidth: expandable ? expandedWidth + gap : panelWidth + gap
    implicitHeight: modelData ? modelData.height : 800

    WlrLayershell.namespace: "ephemera:panel"
    WlrLayershell.layer: WlrLayershell.Top
    WlrLayershell.exclusiveZone: 0
    WlrLayershell.keyboardFocus: isVisible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    readonly property real dpr: CompositorService.getScreenScale(root.screen)
    readonly property real alignedWidth: Theme.px(activeWidth + gap, dpr)

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
                anchors.rightMargin: panelOnLeft ? 0 : root.gap
                anchors.leftMargin: panelOnLeft ? root.gap : 0

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
