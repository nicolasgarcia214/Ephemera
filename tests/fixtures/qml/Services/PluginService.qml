pragma Singleton

import QtQuick

QtObject {
    property var _data: ({
        "ephemera:ollamaUrl": "http://127.0.0.1:11434"
    })
    property var _state: ({})
    property int pluginDataSaveCount: 0
    property int pluginStateSaveCount: 0
    property int pluginStateClearCount: 0

    signal pluginDataChanged(string pluginId)
    signal pluginStateChanged(string pluginId)

    function reset(data, state) {
        _data = data || ({
            "ephemera:ollamaUrl": "http://127.0.0.1:11434"
        });
        _state = state || ({});
        pluginDataSaveCount = 0;
        pluginStateSaveCount = 0;
        pluginStateClearCount = 0;
    }

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
        pluginDataSaveCount++;
        pluginDataChanged(pluginId);
    }

    function loadPluginState(pluginId, key, fallback) {
        var namespaced = pluginId + ":" + key;
        return _state[namespaced] !== undefined ? _state[namespaced] : fallback;
    }

    function savePluginState(pluginId, key, value) {
        var copy = {};
        for (var existing in _state)
            copy[existing] = _state[existing];
        copy[pluginId + ":" + key] = value;
        _state = copy;
        pluginStateSaveCount++;
        pluginStateChanged(pluginId);
    }

    function clearPluginState(pluginId) {
        var prefix = pluginId + ":";
        var copy = {};
        for (var existing in _state) {
            if (existing.indexOf(prefix) !== 0)
                copy[existing] = _state[existing];
        }
        _state = copy;
        pluginStateClearCount++;
        pluginStateChanged(pluginId);
    }
}
