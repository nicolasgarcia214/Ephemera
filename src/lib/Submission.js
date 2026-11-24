.pragma library

function isReady(text, isStreaming, transportBusy, inCooldown, missingCredentials) {
    return typeof text === "string"
        && text.trim().length > 0
        && !isStreaming
        && !transportBusy
        && !inCooldown
        && !missingCredentials;
}
