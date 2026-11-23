.pragma library

// Contextual error hints for HTTP status codes and curl exit codes.
// Extracted from EphemeraService.qml for testability.

/**
 * Return a human-readable hint for a given HTTP error status code.
 *
 * @param {number} status - HTTP status code.
 * @returns {string} Hint message, or "" for unrecognized/success codes.
 */
function httpErrorHint(status) {
    switch (status) {
    case 401: return "Check your API key \u2014 it may be missing or invalid.";
    case 403: return "Access denied \u2014 verify your API key has the required permissions.";
    case 404: return "Endpoint not found \u2014 check the model name and base URL.";
    case 429: return "Rate limited \u2014 wait a moment and try again.";
    case 500: return "Server error \u2014 the provider may be experiencing issues.";
    case 503: return "Service unavailable \u2014 the provider may be overloaded.";
    default: return "";
    }
}

/**
 * Return a human-readable hint for a curl process exit code.
 *
 * Provider-aware: exit code 7 (connection refused) gives Ollama-specific
 * guidance when the provider is "ollama".
 *
 * @param {number} exitCode - curl process exit code.
 * @param {string} provider - Provider identifier (for Ollama-specific messages).
 * @param {string} providerDisplayName - Human-readable provider name.
 * @param {string} ollamaUrl - Ollama server URL (shown in Ollama-specific hints).
 * @returns {string} Hint message (always non-empty for non-zero exit codes).
 */
function curlExitHint(exitCode, provider, providerDisplayName, ollamaUrl) {
    switch (exitCode) {
    case 6: return "Could not resolve host.\nCheck the provider URL and your DNS settings.";
    case 7: return provider === "ollama"
        ? "Connection refused \u2014 Ollama appears to be down.\nMake sure Ollama is running at " + ollamaUrl + "."
        : "Connection refused \u2014 " + providerDisplayName + " is unreachable.";
    case 28: return "Request timed out.\nThe provider took too long to respond.";
    case 63: return "Response exceeded maximum buffer size (5 MB).";
    case 35: return "TLS/SSL connection error.\nCheck the provider URL and your network.";
    default: return "Request failed (exit code " + exitCode + ").";
    }
}
