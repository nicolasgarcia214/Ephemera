import childProcess from "node:child_process";

export function browserUrlWasBlocked(url, command = "/ephemera-test/xdg-open") {
    try {
        const child = childProcess.spawn(command, [url]);
        child.on("error", function() {});
        return false;
    } catch (error) {
        return true;
    }
}
