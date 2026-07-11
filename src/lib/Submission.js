.pragma library

/**
 * Decide whether a new chat message may be submitted.
 *
 * @param {string} text - Composer text before trimming.
 * @param {boolean} isStreaming - Whether a model stream is active.
 * @param {boolean} transportBusy - Whether the prior transport is still draining.
 * @param {boolean} inCooldown - Whether error backoff still blocks retries.
 * @param {boolean} missingCredentials - Whether the provider requires a missing key.
 * @returns {boolean} true only when the coordinator may accept the message.
 */
function isReady(text, isStreaming, transportBusy, inCooldown, missingCredentials) {
    return typeof text === "string"
        && text.trim().length > 0
        && !isStreaming
        && !transportBusy
        && !inCooldown
        && !missingCredentials;
}
