.pragma library

var _lastFilenameTimestamp = "";
var _filenameSequence = 0;

function buildMarkdown(messages) {
    var lines = [];
    for (var i = 0; i < messages.length; i++) {
        var m = messages[i];
        var label = m.role === "user" ? "You" : "Assistant";
        lines.push("### " + label + "\n\n" + m.content);
    }
    return lines.join("\n\n---\n\n");
}

function generateFilename(homeDir) {
    var timestamp = new Date().toISOString().replace(/[:.]/g, "-");
    if (timestamp === _lastFilenameTimestamp)
        _filenameSequence++;
    else {
        _lastFilenameTimestamp = timestamp;
        _filenameSequence = 0;
    }
    var suffix = _filenameSequence > 0 ? "-" + _filenameSequence : "";
    return (homeDir || "") + "/ephemera-chat-" + timestamp + suffix + ".md";
}
