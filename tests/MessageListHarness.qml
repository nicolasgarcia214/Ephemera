import QtQuick
import Quickshell
import "./src/components"

ShellRoot {
    id: root

    property bool finished: false
    property string phase: "initial"
    property int growthSteps: 0
    property real userContentY: 0
    property var view: null

    function finish(success, message) {
        if (finished) return;
        finished = true;
        console.log("EPHEMERA_MESSAGE_LIST_TEST "
                    + (success ? "PASS" : "FAIL") + ": " + message);
        Qt.quit();
    }

    function check(condition, message) {
        if (!condition) {
            finish(false, message);
            return false;
        }
        return true;
    }

    function atEnd() {
        return view.contentY + view.height >= view.originY + view.contentHeight - 1;
    }

    function findListView(item) {
        for (var i = 0; i < item.children.length; i++) {
            var child = item.children[i];
            if (child.hasOwnProperty("atYEnd") && child.hasOwnProperty("model"))
                return child;
        }
        return null;
    }

    function appendMessage(id, role, content, status) {
        messages.append({
            id: id, role: role, content: content, thinking: "", status: status,
            modelName: "fixture", variantIndex: 0, variantCount: 1,
            streamStats: "", requestPayload: "", copyStatus: ""
        });
    }

    function grow() {
        var last = messages.count - 1;
        messages.setProperty(last, "content", messages.get(last).content
            + "\nStreaming line " + growthSteps + " with enough text to wrap.");
        growthSteps++;
    }

    function step() {
        if (phase === "initial") {
            view = findListView(list);
            if (!check(view !== null, "MessageList ListView not found")) return;
            if (!check(list.stickToBottom, "list did not start stuck to the bottom")) return;
            phase = "streaming";
        }

        if (phase === "streaming") {
            if (!check(list.stickToBottom,
                    "programmatic follow cleared stickToBottom at step " + growthSteps)) return;
            if (!check(growthSteps === 0 || atEnd(),
                    "growing last message ran below the viewport at step "
                    + growthSteps + " (contentY " + view.contentY
                    + ", contentHeight " + view.contentHeight + ")")) return;
            if (growthSteps < 30) {
                grow();
                stepTimer.start();
                return;
            }
            if (!check(view.contentHeight > view.height * 2,
                    "fixture content never exceeded the viewport")) return;
            view.contentY -= view.height;
            userContentY = view.contentY;
            if (!check(!list.stickToBottom, "user scroll-up did not disable follow")) return;
            phase = "scrolled-up";
            grow();
            stepTimer.start();
            return;
        }

        if (phase === "scrolled-up") {
            if (!check(!list.stickToBottom, "content growth re-enabled follow after scroll-up")) return;
            if (!check(Math.abs(view.contentY - userContentY) < 1 && !atEnd(),
                    "content growth pulled a scrolled-up reader to the bottom")) return;
            list.scrollToBottom();
            phase = "returned";
            grow();
            stepTimer.start();
            return;
        }

        if (phase === "returned") {
            check(list.stickToBottom && atEnd(),
                "scrollToBottom did not resume following growth")
                && finish(true, "view follows streamed growth, yields to scroll-up, and resumes on scrollToBottom");
        }
    }

    ListModel { id: messages }

    FloatingWindow {
        implicitWidth: 400
        implicitHeight: 300
        visible: true

        MessageList {
            id: list
            anchors.fill: parent
            messages: messages
        }
    }

    Component.onCompleted: {
        appendMessage("u1", "user", "Question", "ok");
        appendMessage("a1", "assistant", "Answer begins", "streaming");
        stepTimer.start();
    }

    Timer {
        id: stepTimer
        interval: 50
        repeat: false
        onTriggered: root.step()
    }

    Timer {
        interval: 8000
        running: true
        repeat: false
        onTriggered: root.finish(false, "timed out in " + root.phase)
    }
}
