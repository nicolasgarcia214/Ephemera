import QtQuick
import qs.Common
import qs.Widgets
import "../lib/Providers.js" as Providers

SettingsCard {
    id: root

    required property var aiService

    function hasPendingOperation() {
        for (var i = 0; i < providerRepeater.count; i++) {
            var item = providerRepeater.itemAt(i);
            if (item && item._operationPending)
                return true;
        }
        return false;
    }

    function _delegateForProvider(provider) {
        for (var i = 0; i < providerRepeater.count; i++) {
            var item = providerRepeater.itemAt(i);
            if (item && item.modelData.provider === provider)
                return item;
        }
        return null;
    }

    Row {
        width: parent.width
        spacing: Theme.spacingM

        DankIcon {
            name: "vpn_key"
            size: Theme.iconSize
            color: Theme.primary
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            text: "API Keys"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Medium
            color: Theme.surfaceText
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    StyledText {
        text: aiService._keyringAvailable
            ? "Keys are stored encrypted in your system keyring.\nFallback: environment variables."
            : "API keys are read from environment variables.\nThey are never stored on disk."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
        width: parent.width
    }

    Column {
        width: parent.width
        spacing: Theme.spacingS

        Repeater {
            id: providerRepeater
            // Show key status for providers that need an API key
            model: {
                var providers = Providers.getProviderNames();
                var items = [];
                for (var i = 0; i < providers.length; i++) {
                    var info = Providers.getProviderInfo(providers[i]);
                    if (info.envVar)
                        items.push({ envVar: info.envVar, provider: providers[i] });
                }
                return items;
            }

            Column {
                id: delegate
                required property var modelData
                width: parent.width
                spacing: 0

                property bool _editing: false
                property bool _hasKeyring: aiService.apiKeySource(modelData.provider) === "keyring"
                property bool _operationPending: false
                property string _pendingOperationId: ""
                property string _pendingOperationType: ""
                property string _operationError: ""
                readonly property string _pendingInputText: keyInput.text

                function _setInputForTest(value) {
                    _editing = true;
                    keyInput.text = value;
                }

                function _submitStore() {
                    var key = keyInput.text.trim();
                    if (!key || _operationPending)
                        return false;
                    _operationError = "";
                    var operationId = aiService.storeKeyringKey(modelData.provider, key);
                    if (!operationId) {
                        _operationError = "Could not queue the API key for keyring storage.";
                        return false;
                    }
                    _pendingOperationId = operationId;
                    _pendingOperationType = "store";
                    _operationPending = true;
                    return true;
                }

                function _clearStoredKey() {
                    if (_operationPending)
                        return false;
                    _operationError = "";
                    var operationId = aiService.clearKeyringKey(modelData.provider);
                    if (!operationId) {
                        _operationError = "Could not queue the API key for keyring removal.";
                        return false;
                    }
                    _pendingOperationId = operationId;
                    _pendingOperationType = "clear";
                    _operationPending = true;
                    return true;
                }

                Connections {
                    target: root.aiService

                    function onKeyringOperationSucceeded(operationId, operation, provider) {
                        if (!delegate._operationPending
                                || operationId !== delegate._pendingOperationId
                                || operation !== delegate._pendingOperationType
                                || provider !== delegate.modelData.provider)
                            return;
                        delegate._operationPending = false;
                        delegate._pendingOperationId = "";
                        delegate._pendingOperationType = "";
                        delegate._operationError = "";
                        if (operation === "store") {
                            keyInput.text = "";
                            delegate._editing = false;
                        }
                    }

                    function onKeyringOperationFailed(operationId, operation, provider, message) {
                        if (!delegate._operationPending
                                || operationId !== delegate._pendingOperationId
                                || operation !== delegate._pendingOperationType
                                || provider !== delegate.modelData.provider)
                            return;
                        delegate._operationPending = false;
                        delegate._pendingOperationId = "";
                        delegate._pendingOperationType = "";
                        delegate._operationError = message;
                        if (operation === "store")
                            delegate._editing = true;
                    }
                }

                Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: aiService.hasApiKeyForProvider(modelData.provider) ? Theme.success : Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    StyledText {
                        text: modelData.envVar
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.monoFontFamily
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    StyledText {
                        text: {
                            var src = aiService.apiKeySource(modelData.provider);
                            if (src === "keyring") return "(keyring)";
                            if (src === "env") return "(env)";
                            return "";
                        }
                        visible: text.length > 0
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                AccordionSection {
                    show: aiService._keyringAvailable

                    // -- Stored confirmation --
                    Row {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: delegate._hasKeyring && !delegate._editing

                        DankIcon {
                            name: "check_circle"
                            size: 16
                            color: Theme.success
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            text: "Stored in keyring"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Item { width: Theme.spacingXS; height: 1 }

                        DankButton {
                            text: "Replace"
                            enabled: !delegate._operationPending
                            onClicked: delegate._editing = true
                        }

                        DankButton {
                            text: delegate._operationPending ? "Working…" : "Clear"
                            enabled: !delegate._operationPending
                            onClicked: delegate._clearStoredKey()
                        }
                    }

                    // -- Key input --
                    Row {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: !delegate._hasKeyring || delegate._editing

                        DankTextField {
                            id: keyInput
                            width: parent.width - saveBtn.width - Theme.spacingS
                                   - (cancelBtn.visible ? cancelBtn.width + Theme.spacingS : 0)
                            placeholderText: delegate._editing ? "Paste new API key" : "Paste API key"
                            echoMode: TextInput.Password
                            enabled: !delegate._operationPending
                        }

                        DankButton {
                            id: saveBtn
                            text: delegate._operationPending ? "Saving…" : "Save"
                            enabled: keyInput.text.trim().length > 0
                                && !delegate._operationPending
                            onClicked: delegate._submitStore()
                        }

                        DankButton {
                            id: cancelBtn
                            text: "Cancel"
                            visible: delegate._editing
                            enabled: !delegate._operationPending
                            onClicked: { delegate._editing = false; keyInput.text = ""; }
                        }
                    }

                    StyledText {
                        width: parent.width
                        visible: delegate._operationError.length > 0
                        text: delegate._operationError
                        textFormat: Text.PlainText
                        wrapMode: Text.WordWrap
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.error
                    }
                }
            }
        }
    }
}
