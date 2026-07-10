import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import "./src/services"
import "./src/components"

Item {
    id: root

    property var pluginService: null
    property string pluginId: "ephemera"

    function toggle() {
        if (variants.instances.length > 0) {
            variants.instances[0].toggle();
        }
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
