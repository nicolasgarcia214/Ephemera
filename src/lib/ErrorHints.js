.pragma library

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
