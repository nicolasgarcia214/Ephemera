pragma Singleton

import QtQuick

QtObject {
    property var _data: ({})

    signal pluginDataChanged(string pluginId)

    function loadPluginData(pluginId, key, fallback) {
        var namespaced = pluginId + ":" + key;
        return _data[namespaced] !== undefined ? _data[namespaced] : fallback;
    }

    function savePluginData(pluginId, key, value) {
        var copy = {};
        for (var existing in _data)
            copy[existing] = _data[existing];
        copy[pluginId + ":" + key] = value;
        _data = copy;
        pluginDataChanged(pluginId);
    }
}
