import QtQuick
import Quickshell.Io

Item {
    id: root

    // --- Export state ---
    property int _exportGeneration: 0
    property string _activeExportId: ""
    property string _activeExportKind: ""
    property string _activeExportTarget: ""
    property string _activeClipboardPurpose: ""
    property string _activeClipboardIdentity: ""
    property string _exportPendingBody: ""
    property var _clipboardExportCommand: ["wl-copy", "--"]
    property var _fileExportCommand: [
        "sh", "-c",
        "umask 077; tmp=$(mktemp \"$1.tmp.XXXXXX\") || exit; trap 'rm -f -- \"$tmp\"' 0 1 2 15; exec 3> \"$tmp\" || exit; chmod 0600 \"/proc/$$/fd/3\" || exit; cat >&3 || exit; exec 3>&-; ln \"$tmp\" \"$1\" || exit; rm -f -- \"$tmp\" || exit; trap - 0 1 2 15",
        "ephemera-export"
    ]
    readonly property bool exportBusy: _activeExportId.length > 0
    property string lastExportedFile: ""

    signal exportSucceeded(string exportId, string exportKind, string target)
    signal exportFailed(string exportId, string exportKind, string message)
    signal messageCopySucceeded(string messageId)
    signal messageCopyFailed(string messageId, string message)

    function exportToClipboard(markdownText) {
        return _beginExport("clipboard", "clipboard", markdownText,
                            _clipboardExportCommand, clipboardWriter,
                            "conversation", "");
    }

    function copyMessageToClipboard(messageId, messageText) {
        if (!messageId)
            return false;
        return _beginExport("clipboard", "clipboard", messageText,
                            _clipboardExportCommand, clipboardWriter,
                            "message", messageId);
    }

    function exportToFile(markdownText, homeDir, filename) {
        // Write a private sibling temporary, then publish it with an atomic hard
        // link. link(2) fails for every pre-existing inode type (including FIFOs)
        // without opening the destination. The fd-bound chmod defeats inherited
        // default ACLs and avoids a path swap while writing.
        return _beginExport("file", filename, markdownText,
                            _fileExportCommand.concat([filename]), exportFileWriter);
    }

    function _beginExport(exportKind, target, body, command, process,
                          clipboardPurpose, clipboardIdentity) {
        _exportGeneration++;
        var exportId = exportKind + "-" + _exportGeneration;
        if (exportBusy) {
            var busyMessage = "Another clipboard or file operation is already in progress.";
            if (exportKind === "clipboard" && clipboardPurpose === "message")
                messageCopyFailed(clipboardIdentity, busyMessage);
            else
                exportFailed(exportId, exportKind, busyMessage);
            return false;
        }

        _activeExportId = exportId;
        _activeExportKind = exportKind;
        _activeExportTarget = target;
        _activeClipboardPurpose = clipboardPurpose || "";
        _activeClipboardIdentity = clipboardIdentity || "";
        _exportPendingBody = body;
        process.command = command;
        process.stdinEnabled = true;
        process.running = true;
        return true;
    }

    function _writeExportBody(process) {
        process.write(_exportPendingBody);
        process.stdinEnabled = false;
        _exportPendingBody = "";
    }

    function _finishExport(exportKind, exitCode, failedToStart) {
        if (_activeExportKind !== exportKind)
            return;

        var exportId = _activeExportId;
        var target = _activeExportTarget;
        var clipboardPurpose = _activeClipboardPurpose;
        var clipboardIdentity = _activeClipboardIdentity;
        _activeExportId = "";
        _activeExportKind = "";
        _activeExportTarget = "";
        _activeClipboardPurpose = "";
        _activeClipboardIdentity = "";
        _exportPendingBody = "";

        if (failedToStart) {
            var commandName = exportKind === "clipboard" ? "wl-copy" : "the file export helper";
            var startMessage = "Could not start "
                + (clipboardPurpose === "message" ? "message copy" : exportKind + " export")
                + ". Make sure " + commandName + " is installed and available in PATH.";
            if (clipboardPurpose === "message")
                messageCopyFailed(clipboardIdentity, startMessage);
            else
                exportFailed(exportId, exportKind, startMessage);
        } else if (exitCode !== 0) {
            var failureMessage = (clipboardPurpose === "message"
                                  ? "Could not copy message to the clipboard"
                                  : exportKind === "clipboard"
                                    ? "Could not copy conversation to the clipboard"
                                    : "Could not save the conversation")
                + " (exit code " + exitCode + ").";
            if (clipboardPurpose === "message")
                messageCopyFailed(clipboardIdentity, failureMessage);
            else
                exportFailed(exportId, exportKind, failureMessage);
        } else {
            if (clipboardPurpose === "message") {
                messageCopySucceeded(clipboardIdentity);
            } else {
                if (exportKind === "file")
                    lastExportedFile = target;
                exportSucceeded(exportId, exportKind, target);
            }
        }
    }

    Process {
        id: clipboardWriter
        running: false
        stdinEnabled: true

        onRunningChanged: {
            if (running && root._activeExportKind === "clipboard") {
                root._writeExportBody(clipboardWriter);
            } else if (!running && root._activeExportKind === "clipboard") {
                root._finishExport("clipboard", -1, true);
            }
        }

        onExited: exitCode => root._finishExport("clipboard", exitCode, false)
    }

    Process {
        id: exportFileWriter
        running: false
        stdinEnabled: true

        onRunningChanged: {
            if (running && root._activeExportKind === "file") {
                root._writeExportBody(exportFileWriter);
            } else if (!running && root._activeExportKind === "file") {
                root._finishExport("file", -1, true);
            }
        }

        onExited: exitCode => root._finishExport("file", exitCode, false)
    }
}
