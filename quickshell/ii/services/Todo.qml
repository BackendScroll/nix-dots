pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property var todoConfig: Config.options.sidebar.todo
    readonly property string vaultPath: todoConfig.vaultPath
    readonly property string vaultName: todoConfig.vaultName
    readonly property string tasksView: todoConfig.tasksView
    readonly property string bridgePath:
        Quickshell.shellPath("scripts/tasknotes-bridge.py")

    property var list: []
    property var mutationQueue: []
    property bool loading: false
    property bool ready: false
    property bool cliAvailable: false
    property string backend: "filesystem"
    property string errorMessage: ""
    property string lastMessage: ""
    property string lastSnapshot: ""

    readonly property bool busy:
        loading || mutationProc.running || mutationQueue.length > 0

    readonly property string vaultUri:
        `obsidian://open?vault=${encodeURIComponent(vaultName)}`

    function baseCommand() {
        return [
            "python3",
            bridgePath,
            "--vault",
            vaultPath,
            "--vault-name",
            vaultName,
            "--obsidian-bin",
            todoConfig.obsidianCli
        ];
    }

    function responseFrom(text) {
        const value = String(text ?? "").trim();

        if (value.length === 0)
            return null;

        try {
            return JSON.parse(value);
        } catch (error) {
            console.warn(
                "[TaskNotes] Could not parse bridge response:",
                error,
                value
            );
            return null;
        }
    }

    function reportError(message) {
        const changed = errorMessage !== message;
        errorMessage = message;

        if (!changed)
            return;

        console.warn("[TaskNotes]", message);
        Quickshell.execDetached([
            "notify-send",
            "TaskNotes",
            message,
            "-u", "critical",
            "-a", "QuickShell"
        ]);
    }

    function refresh() {
        if (listProc.running)
            return;

        loading = true;
        listProc.command = baseCommand().concat(["list"]);
        listProc.running = true;
    }

    function queueMutation(argumentsList) {
        const queue = mutationQueue.slice();
        queue.push(argumentsList);
        mutationQueue = queue;
        runNextMutation();
    }

    function runNextMutation() {
        if (mutationProc.running || mutationQueue.length === 0)
            return;

        mutationProc.command =
            baseCommand().concat(mutationQueue[0]);
        mutationProc.running = true;
    }

    function addTask(description) {
        const title = String(description ?? "").trim();

        if (title.length === 0)
            return;

        queueMutation(["add", "--title", title]);
    }

    function markDone(index) {
        if (index < 0 || index >= list.length)
            return;

        queueMutation([
            "set-done",
            "--id", list[index].id,
            "--done", "true"
        ]);
    }

    function markUnfinished(index) {
        if (index < 0 || index >= list.length)
            return;

        queueMutation([
            "set-done",
            "--id", list[index].id,
            "--done", "false"
        ]);
    }

    // Kept for compatibility with the original UI. TaskNotes uses safe
    // archiving rather than permanently deleting a Markdown task note.
    function deleteItem(index) {
        archiveItem(index);
    }

    function archiveItem(index) {
        if (index < 0 || index >= list.length)
            return;

        queueMutation([
            "archive",
            "--id", list[index].id
        ]);
    }

    function openTask(index) {
        if (index < 0 || index >= list.length)
            return;

        openTaskById(list[index].id);
    }

    function openTaskById(taskId) {
        const task = list.find(item => item.id === taskId);
        const uri = String(task?.uri ?? "");

        if (uri.length > 0)
            Quickshell.execDetached(["xdg-open", uri]);
    }

    function taskDate(task) {
        const scheduled = String(task?.scheduled ?? "").slice(0, 10);
        const due = String(task?.due ?? "").slice(0, 10);

        return scheduled.length > 0 ? scheduled : due;
    }

    function tasksForDate(dateString) {
        const date = String(dateString ?? "").slice(0, 10);

        if (date.length === 0)
            return [];

        return list.filter(task => {
            const scheduled =
                String(task?.scheduled ?? "").slice(0, 10);
            const due = String(task?.due ?? "").slice(0, 10);
            return scheduled === date || due === date;
        }).sort((left, right) => {
            if (left.done !== right.done)
                return left.done ? 1 : -1;

            return String(left.content).localeCompare(
                String(right.content)
            );
        });
    }

    function openVault() {
        Quickshell.execDetached(["xdg-open", vaultUri]);
    }

    function openTasksView() {
        const encodedView = encodeURIComponent(tasksView);
        Quickshell.execDetached([
            "xdg-open",
            `${vaultUri}&file=${encodedView}`
        ]);
    }

    function metadataText(task) {
        const values = [];

        if (task.priority && task.priority !== "none")
            values.push(String(task.priority).toUpperCase());

        if (task.scheduled)
            values.push(`Scheduled ${String(task.scheduled).slice(0, 16)}`);
        else if (task.due)
            values.push(`Due ${String(task.due).slice(0, 16)}`);

        if (task.projects && task.projects.length > 0)
            values.push(task.projects.join(", "));

        if (task.contexts && task.contexts.length > 0)
            values.push(task.contexts.join(", "));

        if (task.recurrence)
            values.push("Recurring");

        return values.join("  •  ");
    }

    Component.onCompleted: refresh()

    Timer {
        interval: Math.max(
            5,
            root.todoConfig.refreshIntervalSeconds
        ) * 1000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Process {
        id: listProc
        running: false

        stdout: StdioCollector {
            id: listOutput
        }

        stderr: StdioCollector {
            id: listError
        }

        onExited: (exitCode, exitStatus) => {
            root.loading = false;

            const response = root.responseFrom(listOutput.text);

            if (exitCode === 0 && response?.ok === true) {
                const nextList = response.tasks ?? [];
                const nextBackend =
                    response.backend ?? "filesystem";
                const nextSnapshot = JSON.stringify(nextList);
                const changed =
                    nextSnapshot !== root.lastSnapshot
                    || nextBackend !== root.backend
                    || root.errorMessage.length > 0;

                root.list = nextList;
                root.ready = true;
                root.cliAvailable =
                    response.cliAvailable ?? false;
                root.backend = nextBackend;
                root.errorMessage = "";
                root.lastSnapshot = nextSnapshot;
                root.lastMessage =
                    `${response.count ?? root.list.length} TaskNotes loaded via ${root.backend}`;

                if (changed)
                    console.log("[TaskNotes]", root.lastMessage);

                return;
            }

            const details =
                response?.error
                ?? String(listError.text ?? "").trim()
                ?? "TaskNotes refresh failed.";

            root.reportError(
                details.length > 0
                    ? details
                    : `TaskNotes refresh failed (${exitStatus}).`
            );
        }
    }

    Process {
        id: mutationProc
        running: false

        stdout: StdioCollector {
            id: mutationOutput
        }

        stderr: StdioCollector {
            id: mutationError
        }

        onExited: (exitCode, exitStatus) => {
            const response = root.responseFrom(mutationOutput.text);
            const queue = root.mutationQueue.slice();

            if (queue.length > 0)
                queue.shift();

            root.mutationQueue = queue;

            if (exitCode === 0 && response?.ok === true) {
                root.errorMessage = "";
                root.lastMessage = "TaskNotes updated";
            } else {
                const details =
                    response?.error
                    ?? String(mutationError.text ?? "").trim()
                    ?? "TaskNotes update failed.";

                root.reportError(
                    details.length > 0
                        ? details
                        : `TaskNotes update failed (${exitStatus}).`
                );
            }

            if (root.mutationQueue.length > 0) {
                Qt.callLater(root.runNextMutation);
            } else {
                root.refresh();
            }
        }
    }
}

