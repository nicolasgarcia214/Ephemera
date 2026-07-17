import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Widgets

SettingsCard {
    id: root

    required property var aiService
    property bool _systemPromptSavePending: false
    property string _pendingSystemPromptText: ""

    function _queueSystemPromptSave(text) {
        aiService.systemPrompt = text;
        _pendingSystemPromptText = text;
        _systemPromptSavePending = true;
        _systemPromptSaveTimer.restart();
    }

    function flushPendingSettings() {
        if (!_systemPromptSavePending)
            return;
        _systemPromptSavePending = false;
        _systemPromptSaveTimer.stop();
        aiService.saveSettingValue("systemPrompt", _pendingSystemPromptText);
    }

    function _saveSystemPromptImmediately(text) {
        systemPromptArea.text = text;
        _pendingSystemPromptText = text;
        _systemPromptSavePending = false;
        _systemPromptSaveTimer.stop();
        aiService.systemPrompt = text;
        aiService.saveSettingValue("systemPrompt", text);
    }

    Component.onDestruction: flushPendingSettings()

    Row {
        width: parent.width
        spacing: Theme.spacingM

        DankIcon {
            name: "tune"
            size: Theme.iconSize
            color: Theme.primary
            anchors.verticalCenter: parent.verticalCenter
        }

        StyledText {
            text: "Model Parameters"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Medium
            color: Theme.surfaceText
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Column {
        width: parent.width
        spacing: Theme.spacingS

        // System prompt
        StyledText {
            text: "System Prompt"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }
        DankDropdown {
            readonly property var _presets: ({
                "None": "",
                "Concise": "Be concise. Answer in as few words as possible while remaining helpful and accurate.",
                "Code Expert": "You are an expert programmer. Provide clean, well-structured code with brief explanations. Prefer practical solutions.",
                "Translator": "You are a translator. Translate the user's text to the target language they specify. If no language is specified, translate to English.",
                "Writing Editor": "You are a writing editor. Improve clarity, grammar, and flow while preserving the author's voice and intent."
            })

            function _presetNameFor(prompt) {
                var keys = Object.keys(_presets);
                for (var i = 0; i < keys.length; i++) {
                    if (_presets[keys[i]] === prompt) return keys[i];
                }
                return "(custom)";
            }

            width: parent.width
            options: ["None", "Concise", "Code Expert", "Translator", "Writing Editor", "(custom)"]
            currentValue: _presetNameFor(aiService.systemPrompt)
            onValueChanged: value => {
                if (_presets.hasOwnProperty(value)) {
                    root._saveSystemPromptImmediately(_presets[value]);
                }
                if (value === "(custom)")
                    systemPromptArea.forceActiveFocus();
            }
        }
        Rectangle {
            width: parent.width
            height: Math.max(80, Math.min(160, systemPromptArea.contentHeight + Theme.spacingM * 2))
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh
            border.color: systemPromptArea.activeFocus ? Theme.primary : Theme.outlineMedium
            border.width: systemPromptArea.activeFocus ? 2 : 1

            Behavior on height {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            ScrollView {
                anchors.fill: parent
                anchors.margins: Theme.spacingS
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                TextArea {
                    id: systemPromptArea
                    text: aiService.systemPrompt
                    placeholderText: "You are a helpful assistant."
                    wrapMode: TextArea.Wrap
                    font.pixelSize: Theme.fontSizeMedium
                    font.family: Theme.fontFamily
                    color: Theme.surfaceText
                    background: null
                    padding: 0

                    onTextChanged: {
                        root._queueSystemPromptSave(text);
                    }

                    Timer {
                        id: _systemPromptSaveTimer
                        interval: 500
                        onTriggered: {
                            if (!root._systemPromptSavePending)
                                return;
                            root._systemPromptSavePending = false;
                            aiService.saveSettingValue(
                                "systemPrompt", root._pendingSystemPromptText);
                        }
                    }
                }
            }
        }

        // Temperature
        Item { width: 1; height: Theme.spacingXS }
        Row {
            width: parent.width
            spacing: Theme.spacingM

            DankIcon {
                name: "thermostat"
                size: Theme.iconSize
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS
                width: parent.width - parent.spacing - Theme.iconSize

                StyledText {
                    text: "Temperature: " + aiService.temperature.toFixed(1)
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }

                StyledText {
                    text: {
                        var maxT = aiService.tempMax;
                        if (maxT <= 1.0)
                            return "Controls randomness (0 = focused, " + maxT.toFixed(1) + " = creative). Capped for " + aiService.provider + ".";
                        return "Controls randomness (0 = focused, " + maxT.toFixed(1) + " = creative)";
                    }
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }
        }

        DankSlider {
            width: parent.width
            height: 32
            minimum: Math.round(aiService.tempMin * 10)
            maximum: Math.round(aiService.tempMax * 10)
            value: Math.round(Math.min(aiService.temperature, aiService.tempMax) * 10)
            showValue: false
            onSliderValueChanged: newValue => {
                var clamped = Math.max(aiService.tempMin, Math.min(aiService.tempMax, newValue / 10));
                aiService.temperature = clamped;
                aiService.saveSettingValue("temperature", clamped);
            }
        }

        // Max Tokens
        Item { width: 1; height: Theme.spacingXS }
        Row {
            width: parent.width
            spacing: Theme.spacingM

            DankIcon {
                name: "data_usage"
                size: Theme.iconSize
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS
                width: parent.width - parent.spacing * 2 - Theme.iconSize - unlimitedToggle.width

                StyledText {
                    text: "Max Tokens: " + (aiService.unlimitedTokens ? "No limit" : aiService.maxTokens)
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }

                StyledText {
                    text: "Maximum response length"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Switch {
                id: unlimitedToggle
                checked: aiService.unlimitedTokens
                anchors.verticalCenter: parent.verticalCenter
                onToggled: {
                    aiService.unlimitedTokens = checked;
                    aiService.saveSettingValue("unlimitedTokens", checked);
                }
            }
        }

        DankSlider {
            width: parent.width
            height: 32
            minimum: 256
            maximum: 131072
            step: 1024
            value: aiService.maxTokens
            showValue: false
            enabled: !aiService.unlimitedTokens
            opacity: aiService.unlimitedTokens ? 0.4 : 1.0
            onSliderValueChanged: newValue => {
                aiService.maxTokens = newValue;
                aiService.saveSettingValue("maxTokens", newValue);
            }
        }

        // Max Context Turns
        Item { width: 1; height: Theme.spacingXS }
        Row {
            width: parent.width
            spacing: Theme.spacingM

            DankIcon {
                name: "history"
                size: Theme.iconSize
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS
                width: parent.width - parent.spacing - Theme.iconSize

                StyledText {
                    text: "Context Turns: " + aiService.maxTurns
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }

                StyledText {
                    text: "Recent conversation turns sent to API"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }
        }

        DankSlider {
            width: parent.width
            height: 32
            minimum: 2
            maximum: 100
            value: aiService.maxTurns
            showValue: false
            onSliderValueChanged: newValue => {
                aiService.maxTurns = newValue;
                aiService.saveSettingValue("maxTurns", newValue);
            }
        }

        // Request Timeout
        Item { width: 1; height: Theme.spacingXS }
        Row {
            width: parent.width
            spacing: Theme.spacingM

            DankIcon {
                name: "timer"
                size: Theme.iconSize
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS
                width: parent.width - parent.spacing - Theme.iconSize

                StyledText {
                    text: "Request Timeout: " + aiService.timeout + "s"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                }

                StyledText {
                    text: "Max time for a streaming response"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }
        }

        DankSlider {
            width: parent.width
            height: 32
            minimum: 30
            maximum: 600
            step: 30
            value: aiService.timeout
            showValue: false
            onSliderValueChanged: newValue => {
                aiService.timeout = newValue;
                aiService.saveSettingValue("timeout", newValue);
            }
        }
    }
}
