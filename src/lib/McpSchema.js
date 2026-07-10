.pragma library

var _maxSchemaNodes = 4096;
var _maxValidationSteps = 20000;
var _maxEnumValues = 256;
var _maxContentItems = 1024;

function _hasOwn(value, key) {
    return Object.prototype.hasOwnProperty.call(value, key);
}

function _takeBudget(budget, amount) {
    budget.remaining -= amount || 1;
    return budget.remaining >= 0;
}

function _isPrimitiveJsonValue(value) {
    return value === null || typeof value === "string" || typeof value === "boolean"
        || (typeof value === "number" && isFinite(value));
}

function _matchesSchemaType(value, type) {
    if (type === "null") return value === null;
    if (type === "array") return Array.isArray(value);
    if (type === "object") return !!value && typeof value === "object" && !Array.isArray(value);
    if (type === "integer") return typeof value === "number" && isFinite(value) && Math.floor(value) === value;
    if (type === "number") return typeof value === "number" && isFinite(value);
    return typeof value === type;
}

function _isNonNegativeInteger(value) {
    return typeof value === "number" && isFinite(value)
        && Math.floor(value) === value && value >= 0;
}

function _isFiniteNumber(value) {
    return typeof value === "number" && isFinite(value);
}

function _isSchemaObject(value) {
    return !!value && typeof value === "object" && !Array.isArray(value);
}

function _isBoundedJsonValue(value, depth, budget, ancestors) {
    if (!_takeBudget(budget, 1))
        return false;
    if (value === null || typeof value === "string" || typeof value === "boolean")
        return true;
    if (typeof value === "number")
        return isFinite(value);
    if (!value || typeof value !== "object" || depth > 32)
        return false;
    if (typeof value.toJSON === "function")
        return false;

    for (var ai = 0; ai < ancestors.length; ai++) {
        if (ancestors[ai] === value)
            return false;
    }
    ancestors.push(value);

    var valid = true;
    var keys = Object.keys(value);
    if (Array.isArray(value)) {
        // JSON.stringify silently turns holes into null and ignores named array
        // properties. Reject both so the reviewed value is exactly what is sent.
        if (keys.length !== value.length) {
            valid = false;
        } else {
            for (var ii = 0; ii < value.length; ii++) {
                if (!_hasOwn(value, String(ii))
                        || !_isBoundedJsonValue(value[ii], depth + 1, budget, ancestors)) {
                    valid = false;
                    break;
                }
            }
        }
    } else {
        for (var ki = 0; ki < keys.length; ki++) {
            if (!_isBoundedJsonValue(value[keys[ki]], depth + 1, budget, ancestors)) {
                valid = false;
                break;
            }
        }
    }

    ancestors.pop();
    return valid;
}

function _schemaListError(value, depth, budget) {
    if (!Array.isArray(value) || value.length === 0)
        return "must be a non-empty array of schemas";
    for (var i = 0; i < value.length; i++) {
        var error = _schemaSupportError(value[i], depth + 1, false, budget);
        if (error) return error;
    }
    return "";
}

function _schemaSupportError(schema, depth, requireObjectRoot, budget) {
    var currentDepth = Number(depth) || 0;
    var remaining = budget || { remaining: _maxSchemaNodes };
    if (!_takeBudget(remaining, 1))
        return "exceeds the supported complexity";
    if (currentDepth > 32)
        return "exceeds the supported nesting depth";
    if (!_isSchemaObject(schema))
        return "must be a JSON Schema object";
    if (requireObjectRoot && schema.type !== "object")
        return "must declare an object at the root";

    var allowed = {
        "$comment": true, "$id": true, "$schema": true,
        "title": true, "description": true, "default": true, "examples": true,
        "deprecated": true, "readOnly": true, "writeOnly": true,
        "type": true, "enum": true, "const": true,
        "allOf": true, "anyOf": true, "oneOf": true, "not": true,
        "minLength": true, "maxLength": true,
        "minimum": true, "maximum": true,
        "exclusiveMinimum": true, "exclusiveMaximum": true,
        "minItems": true, "maxItems": true, "items": true,
        "minProperties": true, "maxProperties": true,
        "required": true, "properties": true, "additionalProperties": true
    };
    var keys = Object.keys(schema);
    for (var ki = 0; ki < keys.length; ki++) {
        if (!_hasOwn(allowed, keys[ki]))
            return "uses unsupported keyword '" + keys[ki] + "'";
    }

    if (schema.$schema !== undefined
            && schema.$schema !== "https://json-schema.org/draft/2020-12/schema") {
        return "uses an unsupported JSON Schema dialect";
    }

    var validTypes = {
        "null": true, "boolean": true, "object": true, "array": true,
        "number": true, "integer": true, "string": true
    };
    if (schema.type !== undefined) {
        var types = Array.isArray(schema.type) ? schema.type : [schema.type];
        if (types.length === 0)
            return "declares no supported types";
        var seenTypes = {};
        for (var ti = 0; ti < types.length; ti++) {
            var typeKey = "$" + types[ti];
            if (typeof types[ti] !== "string" || !_hasOwn(validTypes, types[ti])
                    || seenTypes[typeKey])
                return "declares an invalid type";
            seenTypes[typeKey] = true;
        }
    }

    if (schema.enum !== undefined) {
        if (!Array.isArray(schema.enum) || schema.enum.length === 0
                || schema.enum.length > _maxEnumValues)
            return "declares an invalid or oversized enum";
        for (var ei = 0; ei < schema.enum.length; ei++) {
            if (!_isPrimitiveJsonValue(schema.enum[ei]))
                return "uses an unsupported complex enum value";
        }
    }
    if (schema.const !== undefined && !_isPrimitiveJsonValue(schema.const))
        return "uses an unsupported complex const value";

    var listKeywords = ["allOf", "anyOf", "oneOf"];
    for (var li = 0; li < listKeywords.length; li++) {
        var listKeyword = listKeywords[li];
        if (schema[listKeyword] !== undefined) {
            var listError = _schemaListError(schema[listKeyword], currentDepth, remaining);
            if (listError) return listKeyword + " " + listError;
        }
    }
    if (schema.not !== undefined) {
        var notError = _schemaSupportError(schema.not, currentDepth + 1, false, remaining);
        if (notError) return "not " + notError;
    }

    var countKeywords = [
        "minLength", "maxLength", "minItems", "maxItems",
        "minProperties", "maxProperties"
    ];
    for (var ci = 0; ci < countKeywords.length; ci++) {
        var countKeyword = countKeywords[ci];
        if (schema[countKeyword] !== undefined && !_isNonNegativeInteger(schema[countKeyword]))
            return countKeyword + " must be a non-negative integer";
    }
    if (schema.minLength !== undefined && schema.maxLength !== undefined
            && schema.minLength > schema.maxLength)
        return "has contradictory string length limits";
    if (schema.minItems !== undefined && schema.maxItems !== undefined
            && schema.minItems > schema.maxItems)
        return "has contradictory array length limits";
    if (schema.minProperties !== undefined && schema.maxProperties !== undefined
            && schema.minProperties > schema.maxProperties)
        return "has contradictory object size limits";

    var numericKeywords = ["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum"];
    for (var ni = 0; ni < numericKeywords.length; ni++) {
        var numericKeyword = numericKeywords[ni];
        if (schema[numericKeyword] !== undefined && !_isFiniteNumber(schema[numericKeyword]))
            return numericKeyword + " must be a finite number";
    }

    if (schema.items !== undefined) {
        var itemsError = _schemaSupportError(schema.items, currentDepth + 1, false, remaining);
        if (itemsError) return "items " + itemsError;
    }
    if (schema.properties !== undefined) {
        if (!_isSchemaObject(schema.properties))
            return "properties must be an object";
        var propertyNames = Object.keys(schema.properties);
        for (var pi = 0; pi < propertyNames.length; pi++) {
            var propertyError = _schemaSupportError(
                schema.properties[propertyNames[pi]], currentDepth + 1, false, remaining);
            if (propertyError)
                return "property '" + propertyNames[pi] + "' " + propertyError;
        }
    }
    if (schema.required !== undefined) {
        if (!Array.isArray(schema.required) || schema.required.length > _maxSchemaNodes)
            return "required must be a bounded array";
        var seenRequired = {};
        for (var ri = 0; ri < schema.required.length; ri++) {
            var requiredName = schema.required[ri];
            if (typeof requiredName !== "string" || seenRequired["$" + requiredName])
                return "required contains an invalid property name";
            seenRequired["$" + requiredName] = true;
        }
    }
    if (schema.additionalProperties !== undefined
            && typeof schema.additionalProperties !== "boolean") {
        var additionalError = _schemaSupportError(
            schema.additionalProperties, currentDepth + 1, false, remaining);
        if (additionalError) return "additionalProperties " + additionalError;
    }
    return "";
}

function _unicodeLength(value) {
    var text = String(value || "");
    var count = 0;
    for (var i = 0; i < text.length; i++, count++) {
        var code = text.charCodeAt(i);
        if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
            var next = text.charCodeAt(i + 1);
            if (next >= 0xdc00 && next <= 0xdfff)
                i++;
        }
    }
    return count;
}

function _matchesJsonSchema(value, schema, depth, budget) {
    var currentDepth = Number(depth) || 0;
    if (!_takeBudget(budget, 1))
        return false;
    if (currentDepth > 32 || !schema || typeof schema !== "object" || Array.isArray(schema))
        return false;

    if (schema.const !== undefined && value !== schema.const)
        return false;
    if (Array.isArray(schema.enum)) {
        var enumMatch = false;
        for (var ei = 0; ei < schema.enum.length; ei++) {
            if (!_takeBudget(budget, 1)) return false;
            if (value === schema.enum[ei]) {
                enumMatch = true;
                break;
            }
        }
        if (!enumMatch) return false;
    }

    if (Array.isArray(schema.allOf)) {
        for (var ai = 0; ai < schema.allOf.length; ai++) {
            if (!_matchesJsonSchema(value, schema.allOf[ai], currentDepth + 1, budget))
                return false;
        }
    }
    if (Array.isArray(schema.anyOf)) {
        var anyMatch = false;
        for (var yi = 0; yi < schema.anyOf.length; yi++) {
            if (_matchesJsonSchema(value, schema.anyOf[yi], currentDepth + 1, budget)) {
                anyMatch = true;
                break;
            }
        }
        if (!anyMatch) return false;
    }
    if (Array.isArray(schema.oneOf)) {
        var oneMatches = 0;
        for (var oi = 0; oi < schema.oneOf.length; oi++) {
            if (_matchesJsonSchema(value, schema.oneOf[oi], currentDepth + 1, budget))
                oneMatches++;
        }
        if (budget.remaining < 0) return false;
        if (oneMatches !== 1) return false;
    }
    if (schema.not) {
        var excluded = _matchesJsonSchema(value, schema.not, currentDepth + 1, budget);
        if (budget.remaining < 0 || excluded)
            return false;
    }

    if (schema.type !== undefined) {
        var types = Array.isArray(schema.type) ? schema.type : [schema.type];
        var typeMatch = false;
        for (var ti = 0; ti < types.length; ti++) {
            if (_matchesSchemaType(value, types[ti])) {
                typeMatch = true;
                break;
            }
        }
        if (!typeMatch) return false;
    }

    if (typeof value === "string") {
        var stringLength = _unicodeLength(value);
        if (schema.minLength !== undefined && stringLength < schema.minLength) return false;
        if (schema.maxLength !== undefined && stringLength > schema.maxLength) return false;
    } else if (typeof value === "number") {
        if (schema.minimum !== undefined && value < Number(schema.minimum)) return false;
        if (schema.maximum !== undefined && value > Number(schema.maximum)) return false;
        if (schema.exclusiveMinimum !== undefined && value <= Number(schema.exclusiveMinimum)) return false;
        if (schema.exclusiveMaximum !== undefined && value >= Number(schema.exclusiveMaximum)) return false;
    } else if (Array.isArray(value)) {
        if (schema.minItems !== undefined && value.length < Number(schema.minItems)) return false;
        if (schema.maxItems !== undefined && value.length > Number(schema.maxItems)) return false;
        if (schema.items && typeof schema.items === "object") {
            for (var ii = 0; ii < value.length; ii++) {
                if (!_matchesJsonSchema(value[ii], schema.items, currentDepth + 1, budget))
                    return false;
            }
        }
    } else if (value && typeof value === "object") {
        var keys = Object.keys(value);
        if (schema.minProperties !== undefined && keys.length < Number(schema.minProperties)) return false;
        if (schema.maxProperties !== undefined && keys.length > Number(schema.maxProperties)) return false;
        if (Array.isArray(schema.required)) {
            for (var ri = 0; ri < schema.required.length; ri++) {
                if (!_takeBudget(budget, 1)) return false;
                if (!_hasOwn(value, String(schema.required[ri])))
                    return false;
            }
        }
        var properties = schema.properties && typeof schema.properties === "object"
            ? schema.properties : {};
        for (var ki = 0; ki < keys.length; ki++) {
            if (!_takeBudget(budget, 1)) return false;
            var key = keys[ki];
            if (_hasOwn(properties, key)) {
                if (!_matchesJsonSchema(value[key], properties[key], currentDepth + 1, budget))
                    return false;
            } else if (schema.additionalProperties === false) {
                return false;
            } else if (schema.additionalProperties && typeof schema.additionalProperties === "object") {
                if (!_matchesJsonSchema(value[key], schema.additionalProperties, currentDepth + 1, budget))
                    return false;
            }
        }
    }
    return true;
}

/**
 * Return an explanation when an advertised input schema cannot be validated
 * exactly by the bounded local validator.
 *
 * @param {Object|undefined} schema - Advertised MCP input schema.
 * @returns {string} Empty when supported, otherwise a user-safe explanation.
 */
function inputSchemaSupportError(schema) {
    if (schema === undefined)
        return "Input schema is required.";
    var error = _schemaSupportError(schema, 0, true, { remaining: _maxSchemaNodes });
    return error ? "Input schema " + error + "." : "";
}

/**
 * Validate model-provided arguments against the exact advertised input schema.
 *
 * @param {Object} tool - Current advertised tool contract.
 * @param {Object} argumentsValue - Parsed tool arguments.
 * @returns {{ valid: boolean, error: string }} Validation result.
 */
function validateToolArguments(tool, argumentsValue) {
    if (!argumentsValue || typeof argumentsValue !== "object" || Array.isArray(argumentsValue))
        return { valid: false, error: "MCP tool arguments must be an object." };

    try {
        if (!_isBoundedJsonValue(argumentsValue, 0,
                                 { remaining: _maxValidationSteps }, [])) {
            return {
                valid: false,
                error: "MCP tool arguments must contain only bounded JSON values."
            };
        }
    } catch (e) {
        return {
            valid: false,
            error: "MCP tool arguments must contain only bounded JSON values."
        };
    }

    var inputSchema = tool && tool.inputSchema;
    if (inputSchemaSupportError(inputSchema))
        return { valid: false, error: "MCP tool uses an unsupported input schema." };

    var validationBudget = { remaining: _maxValidationSteps };
    if (!_matchesJsonSchema(argumentsValue, inputSchema, 0, validationBudget))
        return { valid: false, error: "MCP tool arguments did not match the approved input schema." };
    return { valid: true, error: "" };
}

/**
 * Return an explanation when an advertised output schema cannot be validated
 * exactly by the bounded local validator.
 *
 * @param {Object|undefined} schema - Advertised MCP output schema.
 * @returns {string} Empty when supported, otherwise a user-safe explanation.
 */
function outputSchemaSupportError(schema) {
    if (schema === undefined)
        return "";
    var error = _schemaSupportError(schema, 0, true, { remaining: _maxSchemaNodes });
    return error ? "Output schema " + error + "." : "";
}

/**
 * Validate the MCP result envelope and any advertised structured output.
 *
 * This intentionally supports the bounded structural JSON Schema vocabulary
 * used by MCP tool outputs without evaluating remote regular expressions or
 * resolving remote references.
 *
 * @param {Object} tool - Current advertised tool contract.
 * @param {Object} result - tools/call result payload.
 * @returns {{ valid: boolean, error: string }} Validation result.
 */
function validateToolResult(tool, result) {
    if (!result || typeof result !== "object" || Array.isArray(result))
        return { valid: false, error: "MCP tool returned an invalid result envelope." };
    if (!Array.isArray(result.content))
        return { valid: false, error: "MCP tool returned invalid content." };
    if (result.content.length > _maxContentItems)
        return { valid: false, error: "MCP tool returned too many content items." };
    if (result.isError !== undefined && typeof result.isError !== "boolean")
        return { valid: false, error: "MCP tool returned an invalid error flag." };
    if (result._meta !== undefined && !_isSchemaObject(result._meta))
        return { valid: false, error: "MCP tool returned invalid metadata." };
    if (result.structuredContent !== undefined && !_isSchemaObject(result.structuredContent))
        return { valid: false, error: "MCP tool returned invalid structured output." };

    var content = result.content;
    for (var i = 0; i < content.length; i++) {
        var item = content[i];
        if (!item || typeof item !== "object" || Array.isArray(item) || typeof item.type !== "string")
            return { valid: false, error: "MCP tool returned an invalid content item." };
        if (item.annotations !== undefined && !_isSchemaObject(item.annotations))
            return { valid: false, error: "MCP tool returned invalid content annotations." };
        if (item._meta !== undefined && !_isSchemaObject(item._meta))
            return { valid: false, error: "MCP tool returned invalid content metadata." };
        if (item.type === "text" && typeof item.text !== "string")
            return { valid: false, error: "MCP tool returned invalid text content." };
        if ((item.type === "image" || item.type === "audio")
                && (typeof item.data !== "string" || typeof item.mimeType !== "string"))
            return { valid: false, error: "MCP tool returned invalid media content." };
        if (item.type === "resource_link" && typeof item.uri !== "string")
            return { valid: false, error: "MCP tool returned an invalid resource link." };
        if (item.type === "resource"
                && (!item.resource || typeof item.resource !== "object" || Array.isArray(item.resource)))
            return { valid: false, error: "MCP tool returned an invalid embedded resource." };
        if (item.type === "resource"
                && (typeof item.resource.uri !== "string"
                    || (typeof item.resource.text !== "string"
                        && typeof item.resource.blob !== "string")))
            return { valid: false, error: "MCP tool returned invalid embedded resource data." };
        if (item.type !== "text" && item.type !== "image" && item.type !== "audio"
                && item.type !== "resource_link" && item.type !== "resource")
            return { valid: false, error: "MCP tool returned an unsupported content type." };
    }

    var outputSchema = tool && tool.outputSchema;
    var supportError = outputSchemaSupportError(outputSchema);
    if (supportError)
        return { valid: false, error: "MCP tool uses an unsupported output schema." };
    if (result.isError === true)
        return { valid: true, error: "" };

    if (outputSchema) {
        if (result.structuredContent === undefined)
            return { valid: false, error: "MCP tool omitted output required by its advertised schema." };
        var validationBudget = { remaining: _maxValidationSteps };
        if (!_matchesJsonSchema(result.structuredContent, outputSchema, 0, validationBudget))
            return { valid: false, error: "MCP tool output did not match its advertised schema." };
    }
    return { valid: true, error: "" };
}
