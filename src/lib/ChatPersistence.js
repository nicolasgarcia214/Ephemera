.pragma library

// Persisted chat bounds. These apply only to snapshots stored through
// PluginService; the live message model and active transport remain untouched.
var maxMessages = 200;
var maxVariantsPerMessage = 10;
var maxContentBytes = 32768;
var maxThinkingBytes = 32768;
var maxModelBytes = 512;
var maxIdBytes = 256;
var maxSerializedBytes = 1048576;

// Validation work is capped before walking attacker-controlled collections.
// Ordinary oversized state below these inspection ceilings is normalized and
// pruned; inputs beyond them are treated as structurally malicious.
var maxInputMessages = 1000;
var maxInputVariantKeys = 1000;
var maxInputVariantsPerMessage = 100;
var maxLegacyInputChars = 4194304;

function _hasOwn(object, key) {
    return Object.prototype.hasOwnProperty.call(object, key);
}

function _isObject(value) {
    return value && typeof value === "object" && !Array.isArray(value);
}

function _isInteger(value) {
    return typeof value === "number" && isFinite(value)
        && Math.floor(value) === value;
}

function _isSafeId(value) {
    return typeof value === "string" && value.length > 0
        && value !== "__proto__" && value !== "constructor"
        && value !== "prototype" && _fitsUtf8(value, maxIdBytes);
}

function _fitsUtf8(value, limit) {
    var bytes = 0;
    for (var i = 0; i < value.length; i++) {
        var code = value.charCodeAt(i);
        if (code < 0x80) {
            bytes++;
        } else if (code < 0x800) {
            bytes += 2;
        } else if (code >= 0xD800 && code <= 0xDBFF
                && i + 1 < value.length) {
            var low = value.charCodeAt(i + 1);
            if (low >= 0xDC00 && low <= 0xDFFF) {
                bytes += 4;
                i++;
            } else {
                bytes += 3;
            }
        } else {
            bytes += 3;
        }
        if (bytes > limit) return false;
    }
    return true;
}

function _truncateUtf8(value, limit) {
    var bytes = 0;
    var end = 0;
    for (var i = 0; i < value.length; i++) {
        var code = value.charCodeAt(i);
        var width = 0;
        var units = 1;
        if (code < 0x80) {
            width = 1;
        } else if (code < 0x800) {
            width = 2;
        } else if (code >= 0xD800 && code <= 0xDBFF
                && i + 1 < value.length) {
            var low = value.charCodeAt(i + 1);
            if (low >= 0xDC00 && low <= 0xDFFF) {
                width = 4;
                units = 2;
            } else {
                width = 3;
            }
        } else {
            width = 3;
        }
        if (bytes + width > limit) break;
        bytes += width;
        end = i + units;
        if (units === 2) i++;
    }
    return end === value.length ? value : value.slice(0, end);
}

function _messageKeyAllowed(key) {
    return key === "role" || key === "content" || key === "thinking"
        || key === "id" || key === "timestamp" || key === "status"
        || key === "variantIndex" || key === "variantCount"
        || key === "modelName" || key === "streamStats"
        || key === "requestPayload";
}

function _variantKeyAllowed(key) {
    return key === "content" || key === "thinking" || key === "modelName";
}

function _keysAllowed(object, allowed, maximum) {
    var count = 0;
    for (var key in object) {
        if (!_hasOwn(object, key)) continue;
        count++;
        if (count > maximum || !allowed(key)) return false;
    }
    return true;
}

function _validateStructure(payload, version) {
    if (!_isObject(payload) || payload.version !== version
            || !Array.isArray(payload.messages) || !_isObject(payload.variants)
            || payload.messages.length > maxInputMessages
            || !_keysAllowed(payload, function(key) {
                return key === "version" || key === "messages"
                    || key === "variants";
            }, 3))
        return false;

    var ids = {};
    var previousRole = "";
    for (var i = 0; i < payload.messages.length; i++) {
        var message = payload.messages[i];
        if (!_isObject(message) || !_keysAllowed(message, _messageKeyAllowed, 11)
                || (message.role !== "user" && message.role !== "assistant")
                || (message.role === "assistant" && previousRole !== "user")
                || typeof message.content !== "string"
                || !_isSafeId(message.id) || ids[message.id] !== undefined
                || typeof message.timestamp !== "number"
                || !isFinite(message.timestamp)
                || (message.thinking !== undefined
                    && typeof message.thinking !== "string")
                || (message.modelName !== undefined
                    && typeof message.modelName !== "string")
                || (message.streamStats !== undefined
                    && typeof message.streamStats !== "string")
                || (message.requestPayload !== undefined
                    && typeof message.requestPayload !== "string"))
            return false;

        var status = message.status === undefined ? "ok" : message.status;
        if (status !== "ok" && status !== "error" && status !== "streaming")
            return false;
        var variantIndex = message.variantIndex === undefined
            ? 0 : message.variantIndex;
        var variantCount = message.variantCount === undefined
            ? 1 : message.variantCount;
        if (!_isInteger(variantIndex) || variantIndex < 0
                || !_isInteger(variantCount) || variantCount < 1
                || variantIndex >= variantCount)
            return false;

        ids[message.id] = true;
        previousRole = message.role;
    }

    var variantKeyCount = 0;
    for (var msgId in payload.variants) {
        if (!_hasOwn(payload.variants, msgId)) continue;
        variantKeyCount++;
        if (variantKeyCount > maxInputVariantKeys || !_isSafeId(msgId))
            return false;
        var values = payload.variants[msgId];
        if (!Array.isArray(values)
                || values.length > maxInputVariantsPerMessage)
            return false;
        for (var j = 0; j < values.length; j++) {
            var variant = values[j];
            if (!_isObject(variant)
                    || !_keysAllowed(variant, _variantKeyAllowed, 3)
                    || typeof variant.content !== "string"
                    || (variant.thinking !== undefined
                        && typeof variant.thinking !== "string")
                    || (variant.modelName !== undefined
                        && typeof variant.modelName !== "string"))
                return false;
        }
    }
    return true;
}

function _sanitizeText(value, limit, result) {
    var normalized = _truncateUtf8(value || "", limit);
    if (normalized !== (value || "")) result.changed = true;
    return normalized;
}

function _sanitizeMessage(message, result) {
    var status = message.status === undefined ? "ok" : message.status;
    if (status === "streaming") status = "ok";
    var normalized = {
        role: message.role,
        content: _sanitizeText(message.content, maxContentBytes, result),
        thinking: _sanitizeText(message.thinking || "", maxThinkingBytes, result),
        id: message.id,
        timestamp: message.timestamp,
        status: status,
        variantIndex: message.variantIndex === undefined
            ? 0 : message.variantIndex,
        variantCount: message.variantCount === undefined
            ? 1 : message.variantCount,
        modelName: _sanitizeText(message.modelName || "", maxModelBytes, result)
    };
    if (message.status === undefined || message.thinking === undefined
            || message.variantIndex === undefined
            || message.variantCount === undefined
            || message.modelName === undefined || message.status === "streaming"
            || _hasOwn(message, "streamStats")
            || _hasOwn(message, "requestPayload"))
        result.changed = true;
    return normalized;
}

function _sanitizeVariants(message, rawVariants, result) {
    if (message.role !== "assistant" || !_hasOwn(rawVariants, message.id))
        return [];
    var source = rawVariants[message.id];
    var start = Math.max(0, source.length - maxVariantsPerMessage);
    if (start > 0) result.changed = true;
    var variants = [];
    for (var i = start; i < source.length; i++) {
        variants.push({
            content: _sanitizeText(source[i].content, maxContentBytes, result),
            thinking: _sanitizeText(source[i].thinking || "",
                                    maxThinkingBytes, result),
            modelName: _sanitizeText(source[i].modelName || "",
                                     maxModelBytes, result)
        });
        if (source[i].thinking === undefined
                || source[i].modelName === undefined)
            result.changed = true;
    }

    var adjustedIndex = message.variantIndex - start;
    if (variants.length === 0) {
        if (message.variantIndex !== 0 || message.variantCount !== 1)
            result.changed = true;
        message.variantIndex = 0;
        message.variantCount = 1;
    } else if (adjustedIndex < 0 || adjustedIndex >= variants.length) {
        message.variantIndex = 0;
        message.variantCount = variants.length;
        message.content = variants[0].content;
        message.thinking = variants[0].thinking;
        message.modelName = variants[0].modelName;
        result.changed = true;
    } else {
        if (message.variantIndex !== adjustedIndex
                || message.variantCount !== variants.length)
            result.changed = true;
        message.variantIndex = adjustedIndex;
        message.variantCount = variants.length;
        var selected = variants[adjustedIndex];
        if (message.content !== selected.content
                || message.thinking !== selected.thinking
                || message.modelName !== selected.modelName) {
            message.content = selected.content;
            message.thinking = selected.thinking;
            message.modelName = selected.modelName;
            result.changed = true;
        }
    }
    return variants;
}

function _payloadBytes(version, messages, variants) {
    return utf8ByteLength(JSON.stringify({
        version: version,
        messages: messages,
        variants: variants
    }));
}

function _removeOldestVariant(turn, result) {
    for (var i = 0; i < turn.messages.length; i++) {
        var message = turn.messages[i];
        var values = turn.variants[message.id];
        if (!values || values.length === 0) continue;
        values.shift();
        if (message.variantIndex > 0) {
            message.variantIndex--;
        } else if (values.length > 0) {
            message.content = values[0].content;
            message.thinking = values[0].thinking;
            message.modelName = values[0].modelName;
        }
        if (values.length === 0) {
            delete turn.variants[message.id];
            message.variantIndex = 0;
            message.variantCount = 1;
        } else {
            message.variantCount = values.length;
        }
        result.changed = true;
        return true;
    }
    return false;
}

function _mergeOlderTurn(turn, messages, variants) {
    var mergedMessages = turn.messages.concat(messages);
    var mergedVariants = {};
    for (var oldId in turn.variants) {
        if (_hasOwn(turn.variants, oldId))
            mergedVariants[oldId] = turn.variants[oldId];
    }
    for (var retainedId in variants) {
        if (_hasOwn(variants, retainedId))
            mergedVariants[retainedId] = variants[retainedId];
    }
    return { messages: mergedMessages, variants: mergedVariants };
}

function _normalize(payload, version) {
    var result = { changed: false };
    var messages = [];
    var variants = {};
    var end = payload.messages.length;

    while (end > 0) {
        var start = payload.messages[end - 1].role === "user" ? end - 1 : end - 2;
        var turnLength = end - start;
        if (messages.length + turnLength > maxMessages) {
            result.changed = true;
            break;
        }

        var turn = { messages: [], variants: {} };
        for (var i = start; i < end; i++) {
            var normalizedMessage = _sanitizeMessage(payload.messages[i], result);
            turn.messages.push(normalizedMessage);
            var normalizedVariants = _sanitizeVariants(
                normalizedMessage, payload.variants, result);
            if (normalizedVariants.length > 0)
                turn.variants[normalizedMessage.id] = normalizedVariants;
        }

        var candidate = _mergeOlderTurn(turn, messages, variants);
        while (_payloadBytes(version, candidate.messages, candidate.variants)
                > maxSerializedBytes && messages.length === 0
                && _removeOldestVariant(turn, result)) {
            candidate = _mergeOlderTurn(turn, messages, variants);
        }
        if (_payloadBytes(version, candidate.messages, candidate.variants)
                > maxSerializedBytes) {
            result.changed = true;
            break;
        }

        messages = candidate.messages;
        variants = candidate.variants;
        end = start;
    }

    if (end > 0 || messages.length !== payload.messages.length)
        result.changed = true;

    var retainedIds = {};
    for (var m = 0; m < messages.length; m++)
        retainedIds[messages[m].id] = messages[m].role === "assistant";
    for (var rawId in payload.variants) {
        if (_hasOwn(payload.variants, rawId)
                && retainedIds[rawId] !== true) {
            result.changed = true;
            break;
        }
    }

    result.payload = {
        version: version,
        messages: messages,
        variants: variants
    };
    return result;
}

/**
 * Return the UTF-8 byte length of a string.
 *
 * @param {string} value - Text to measure.
 * @returns {number} UTF-8 bytes.
 */
function utf8ByteLength(value) {
    var bytes = 0;
    for (var i = 0; i < value.length; i++) {
        var code = value.charCodeAt(i);
        if (code < 0x80) {
            bytes++;
        } else if (code < 0x800) {
            bytes += 2;
        } else if (code >= 0xD800 && code <= 0xDBFF
                && i + 1 < value.length) {
            var low = value.charCodeAt(i + 1);
            if (low >= 0xDC00 && low <= 0xDFFF) {
                bytes += 4;
                i++;
            } else {
                bytes += 3;
            }
        } else {
            bytes += 3;
        }
    }
    return bytes;
}

/**
 * Validate and normalize a versioned or migrated chat payload without mutating it.
 *
 * @param {Object} payload - Candidate persisted state.
 * @param {number} version - Expected state version.
 * @returns {?{payload: Object, changed: boolean}} Bounded state, or null.
 */
function prepareState(payload, version) {
    if (!_validateStructure(payload, version)) return null;
    return _normalize(payload, version);
}

/**
 * Build a bounded persistence snapshot from a recent live-model window.
 *
 * @param {Array} messages - Completed recent messages in display order.
 * @param {Object} variantStore - Live variant side-channel map.
 * @param {number} version - State schema version.
 * @returns {?{payload: Object, changed: boolean}} Bounded snapshot, or null.
 */
function createSnapshot(messages, variantStore, version) {
    if (!Array.isArray(messages) || !_isObject(variantStore)) return null;
    var scopedVariants = {};
    for (var i = 0; i < messages.length; i++) {
        var message = messages[i];
        if (_isObject(message) && _isSafeId(message.id)
                && _hasOwn(variantStore, message.id))
            scopedVariants[message.id] = variantStore[message.id];
    }
    return prepareState({
        version: version,
        messages: messages,
        variants: scopedVariants
    }, version);
}
