import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import "./src/services"
import "./src/components"

Item {
    id: root

    function toggle() {
        _togglePanels(variants.instances, CompositorService.getFocusedScreenName());
    }

    // Close every open panel; when none was open, open the focused screen's.
    function _togglePanels(panels, screenName) {
        var closed = false;
        for (var i = 0; i < panels.length; i++) {
            if (panels[i].isVisible) {
                panels[i].hide();
                closed = true;
            }
        }
        var panel = closed ? null : _panelForScreen(panels, screenName);
        if (panel)
            panel.show();
    }

    // Prefer the panel on the named (focused) screen; fall back to the first.
    function _panelForScreen(panels, screenName) {
        for (var i = 0; screenName && i < panels.length; i++) {
            if (panels[i].modelData && panels[i].modelData.name === screenName)
                return panels[i];
        }
        return panels.length > 0 ? panels[0] : null;
    }

    IpcHandler {
        target: "ephemera"

        function toggle(): string {
            root.toggle();
            return "EPHEMERA_TOGGLE_SUCCESS";
        }
    }

    // Single shared service — conversation state is shared across all screens.
    // Opening the panel on multiple screens simultaneously shows the same chat.
    EphemeraService {
        id: ephemeraService
        pluginId: root.pluginId
    }

    Variants {
        id: variants
        model: Quickshell.screens

        delegate: EphemeraPanel {
            id: panel
            required property var modelData
            panelWidth: 480
            expandable: true
            expandedWidth: 960
            gap: 6
            panelOnLeft: ephemeraService.panelOnLeft

            content: EphemeraChat {
                aiService: ephemeraService
                slideoutExpandable: panel.expandable
                slideoutExpanded: panel.expanded
                onExpandToggled: panel.expanded = !panel.expanded
                onHideRequested: panel.hide()
            }
        }
    }
}
