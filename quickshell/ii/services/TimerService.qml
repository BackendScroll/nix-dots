pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common

import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Stopwatch plus a TaskNotes-backed Pomodoro controller.
 *
 * TaskNotes owns the live timer and daily-note session history. QuickShell
 * communicates through the official Obsidian CLI and only interpolates the
 * displayed countdown between state polls.
 */
Singleton {
    id: root

    readonly property var todoConfig:
        Config.options.sidebar.todo
    readonly property string taskNotesBridge:
        Quickshell.shellPath("scripts/tasknotes-bridge.py")
    readonly property string alarmSoundPath:
        Quickshell.shellPath(
            "assets/sounds/pomodoro-alarm.wav"
        )

    property int focusTime:
        Config.options.time.pomodoro.focus
    property int breakTime:
        Config.options.time.pomodoro.breakTime
    property int longBreakTime:
        Config.options.time.pomodoro.longBreak
    property int cyclesBeforeLongBreak:
        Config.options.time.pomodoro.cyclesBeforeLongBreak

    property bool pomodoroCliAvailable: false
    property bool pomodoroBusy: false
    property bool pomodoroRunning: false
    property bool pomodoroBreak: false
    property bool pomodoroLongBreak: false
    property int pomodoroLapDuration: focusTime
    property int pomodoroSecondsLeft: focusTime
    property int pomodoroCycle: 0
    property int pomodoroTotalToday: 0
    property int pomodoroMinutesToday: 0
    property int pomodoroDailySessionCount: 0
    property string pomodoroSessionType: "work"
    property string pomodoroNextSessionType: "work"
    property string pomodoroError: ""
    property string pomodoroCliExecutable:
        todoConfig.obsidianCli
    property var pomodoroCurrentSession: null

    property int pomodoroSyncedSecondsLeft: focusTime
    property double pomodoroSyncedAtMilliseconds:
        Date.now()

    property bool alarmActive: false
    property string alarmMessage: ""
    property string alarmCompletedType: ""
    property bool suppressNextAlarm: false

    readonly property bool alarmCanStartBreak:
        alarmActive
        && alarmCompletedType === "work"

    property string pomodoroTaskId:
        Persistent.states.timer.pomodoro.taskId

    readonly property string pomodoroTaskTitle: {
        const task = Todo.list.find(
            item => item.id === pomodoroTaskId
        );
        return task?.content ?? "";
    }

    property bool stopwatchRunning:
        Persistent.states.timer.stopwatch.running
    property int stopwatchTime: 0
    property int stopwatchStart:
        Persistent.states.timer.stopwatch.start
    property var stopwatchLaps:
        Persistent.states.timer.stopwatch.laps

    function bridgeCommand() {
        return [
            "python3",
            taskNotesBridge,
            "--vault",
            todoConfig.vaultPath,
            "--vault-name",
            todoConfig.vaultName,
            "--obsidian-bin",
            todoConfig.obsidianCli
        ];
    }

    function parseResponse(text) {
        const value = String(text ?? "").trim();

        if (value.length === 0)
            return null;

        try {
            return JSON.parse(value);
        } catch (error) {
            console.warn(
                "[TaskNotes Pomodoro] Invalid bridge response:",
                value
            );
            return null;
        }
    }

    function currentSessionType(state) {
        return String(
            state?.currentSession?.type
            ?? state?.nextSessionType
            ?? "work"
        );
    }

    function sessionIdentity(session) {
        if (!session)
            return "";

        return String(
            session.id
            ?? session.startTime
            ?? (
                `${session.type ?? "session"}:`
                + `${session.taskPath ?? ""}`
            )
        );
    }

    function durationForType(typeName) {
        if (typeName === "long-break")
            return longBreakTime;
        if (typeName === "short-break")
            return breakTime;
        return focusTime;
    }

    function triggerAlarm(completedType) {
        if (!todoConfig.pomodoroAlarmEnabled)
            return;

        alarmCompletedType = completedType;
        alarmMessage =
            completedType === "work"
                ? "Focus complete"
                : "Break complete";
        alarmActive = true;
        playAlarmSound();

        Quickshell.execDetached([
            "notify-send",
            "Pomodoro",
            alarmMessage,
            "-u", "critical",
            "-a", "QuickShell"
        ]);
    }

    function dismissAlarm() {
        alarmActive = false;
        alarmMessage = "";
        alarmCompletedType = "";

        if (alarmSoundProc.running)
            alarmSoundProc.running = false;
    }

    function startBreakAfterAlarm() {
        if (!alarmCanStartBreak || pomodoroBusy)
            return;

        dismissAlarm();

        // The bridge reads TaskNotes' nextSessionType and starts the
        // configured short or long break. It does not start another focus
        // session here.
        runPomodoroAction([
            "pomodoro-start"
        ]);
    }

    function openPomodoroView() {
        Quickshell.execDetached([
            todoConfig.obsidianCli,
            `vault=${todoConfig.vaultName}`,
            "command",
            "id=tasknotes:open-pomodoro-view"
        ]);
    }

    function playAlarmSound() {
        if (
            !alarmActive
            || alarmSoundProc.running
            || !todoConfig.pomodoroAlarmEnabled
        ) {
            return;
        }

        alarmSoundProc.command = [
            "pw-play",
            alarmSoundPath
        ];
        alarmSoundProc.running = true;
    }

    function applyPomodoroStatus(response) {
        const previousSession = pomodoroCurrentSession;
        const previousIdentity =
            sessionIdentity(previousSession);
        const previousType = String(
            previousSession?.type
            ?? pomodoroSessionType
            ?? "work"
        );

        const settings = response.settings ?? {};
        focusTime = Math.max(
            60,
            Math.round(
                (settings.workDuration ?? 25) * 60
            )
        );
        breakTime = Math.max(
            60,
            Math.round(
                (settings.shortBreakDuration ?? 5) * 60
            )
        );
        longBreakTime = Math.max(
            60,
            Math.round(
                (settings.longBreakDuration ?? 15) * 60
            )
        );
        cyclesBeforeLongBreak = Math.max(
            1,
            Math.round(
                settings.longBreakInterval ?? 4
            )
        );

        pomodoroCliAvailable =
            response.cliAvailable ?? false;
        pomodoroCliExecutable =
            response.cliExecutable
            ?? todoConfig.obsidianCli;

        const daily = response.daily ?? {};
        pomodoroDailySessionCount =
            daily.sessionCount ?? 0;

        if (
            !pomodoroCliAvailable
            || !response.state
        ) {
            pomodoroRunning = false;
            pomodoroCurrentSession = null;
            pomodoroSessionType = "work";
            pomodoroNextSessionType = "work";
            pomodoroLapDuration = focusTime;
            pomodoroSyncedSecondsLeft = focusTime;
            pomodoroSecondsLeft = focusTime;
            pomodoroTotalToday =
                daily.pomodorosCompleted ?? 0;
            pomodoroMinutesToday =
                daily.totalMinutes ?? 0;
            pomodoroError =
                "Obsidian CLI unavailable. Open Obsidian, "
                + "load AeternumStrategion, and enable "
                + "Command line interface.";
            return;
        }

        const state = response.state;
        const nextSession = state.currentSession ?? null;
        const nextIdentity =
            sessionIdentity(nextSession);

        pomodoroError = "";
        pomodoroRunning = state.isRunning ?? false;
        pomodoroCurrentSession = nextSession;
        pomodoroNextSessionType = String(
            state.nextSessionType ?? "work"
        );
        pomodoroSessionType =
            currentSessionType(state);
        pomodoroBreak =
            pomodoroSessionType !== "work";
        pomodoroLongBreak =
            pomodoroSessionType === "long-break";

        const plannedMinutes = Number(
            pomodoroCurrentSession?.plannedDuration
            ?? 0
        );
        pomodoroLapDuration =
            plannedMinutes > 0
                ? Math.round(plannedMinutes * 60)
                : durationForType(
                    pomodoroSessionType
                );

        pomodoroSyncedSecondsLeft = Math.max(
            0,
            Math.round(
                state.timeRemaining
                ?? pomodoroLapDuration
            )
        );
        pomodoroSyncedAtMilliseconds =
            Date.now();
        pomodoroSecondsLeft =
            pomodoroSyncedSecondsLeft;

        pomodoroTotalToday = Math.max(
            state.totalPomodoros ?? 0,
            daily.pomodorosCompleted ?? 0
        );
        pomodoroMinutesToday = Math.max(
            state.totalMinutesToday ?? 0,
            daily.totalMinutes ?? 0
        );
        pomodoroCycle =
            pomodoroTotalToday
            % cyclesBeforeLongBreak;

        const activeTask = String(
            pomodoroCurrentSession?.taskPath ?? ""
        );
        if (activeTask.length > 0) {
            Persistent.states.timer.pomodoro.taskId =
                activeTask;
        }

        const sessionFinished =
            previousIdentity.length > 0
            && (
                nextIdentity.length === 0
                || nextIdentity !== previousIdentity
            );

        if (sessionFinished) {
            if (!suppressNextAlarm)
                triggerAlarm(previousType);

            suppressNextAlarm = false;
        }
    }

    function refreshPomodoro() {
        if (pomodoroStatusProc.running)
            return;

        pomodoroStatusProc.command =
            bridgeCommand().concat([
                "pomodoro-status"
            ]);
        pomodoroStatusProc.running = true;
    }

    function runPomodoroAction(argumentsList) {
        if (pomodoroActionProc.running)
            return;

        pomodoroBusy = true;
        pomodoroActionProc.command =
            bridgeCommand().concat(argumentsList);
        pomodoroActionProc.running = true;
    }

    function startPomodoro() {
        if (!pomodoroCliAvailable) {
            refreshPomodoro();
            return;
        }

        dismissAlarm();

        const command = [
            "pomodoro-start",
            "--duration",
            String(Math.round(focusTime / 60))
        ];

        if (pomodoroTaskId.length > 0) {
            command.push("--task-id");
            command.push(pomodoroTaskId);
        }

        runPomodoroAction(command);
    }

    function pausePomodoro() {
        if (
            pomodoroCurrentSession
            && pomodoroRunning
        ) {
            runPomodoroAction([
                "pomodoro-pause"
            ]);
        }
    }

    function resumePomodoro() {
        if (
            pomodoroCurrentSession
            && !pomodoroRunning
        ) {
            dismissAlarm();
            runPomodoroAction([
                "pomodoro-resume"
            ]);
        }
    }

    function stopPomodoro() {
        if (!pomodoroCurrentSession)
            return;

        suppressNextAlarm = true;
        dismissAlarm();
        runPomodoroAction([
            "pomodoro-stop"
        ]);
    }

    function togglePomodoro() {
        if (!pomodoroCurrentSession)
            startPomodoro();
        else if (pomodoroRunning)
            pausePomodoro();
        else
            resumePomodoro();
    }

    function resetPomodoro() {
        stopPomodoro();
    }

    function selectPomodoroTask(taskId) {
        if (pomodoroCurrentSession)
            return;

        Persistent.states.timer.pomodoro.taskId =
            String(taskId ?? "");
    }

    function getCurrentTimeIn10ms() {
        return Math.floor(Date.now() / 10);
    }

    Component.onCompleted: {
        if (!stopwatchRunning)
            stopwatchReset();

        refreshPomodoro();
    }

    Timer {
        interval:
            root.pomodoroCurrentSession
                ? Math.max(
                    1000,
                    root.todoConfig
                        .pomodoroPollMilliseconds
                )
                : Math.max(
                    5000,
                    root.todoConfig
                        .pomodoroIdlePollMilliseconds
                )
        running: true
        repeat: true
        triggeredOnStart: false
        onTriggered: root.refreshPomodoro()
    }

    Timer {
        interval: 250
        running: true
        repeat: true

        onTriggered: {
            if (!root.pomodoroRunning) {
                root.pomodoroSecondsLeft =
                    root.pomodoroSyncedSecondsLeft;
                return;
            }

            const elapsed = Math.floor(
                (
                    Date.now()
                    - root.pomodoroSyncedAtMilliseconds
                ) / 1000
            );
            root.pomodoroSecondsLeft = Math.max(
                0,
                root.pomodoroSyncedSecondsLeft
                - elapsed
            );
        }
    }

    Timer {
        interval: Math.max(
            1000,
            root.todoConfig
                .pomodoroAlarmRepeatMilliseconds
        )
        running: root.alarmActive
        repeat: true
        onTriggered: root.playAlarmSound()
    }

    Process {
        id: alarmSoundProc
        running: false
    }

    Process {
        id: pomodoroStatusProc
        running: false

        stdout: StdioCollector {
            id: pomodoroStatusOutput
        }

        stderr: StdioCollector {
            id: pomodoroStatusError
        }

        onExited: (exitCode, exitStatus) => {
            const response =
                root.parseResponse(
                    pomodoroStatusOutput.text
                );

            if (
                exitCode === 0
                && response?.ok === true
            ) {
                root.applyPomodoroStatus(response);
                return;
            }

            root.pomodoroCliAvailable = false;
            root.pomodoroRunning = false;

            const responseError =
                String(response?.error ?? "").trim();
            const stderrText =
                String(
                    pomodoroStatusError.text ?? ""
                ).trim();

            root.pomodoroError =
                responseError
                || stderrText
                || (
                    "TaskNotes CLI status failed "
                    + `(${exitStatus}).`
                );
        }
    }

    Process {
        id: pomodoroActionProc
        running: false

        stdout: StdioCollector {
            id: pomodoroActionOutput
        }

        stderr: StdioCollector {
            id: pomodoroActionError
        }

        onExited: (exitCode, exitStatus) => {
            root.pomodoroBusy = false;
            const response =
                root.parseResponse(
                    pomodoroActionOutput.text
                );

            if (
                exitCode !== 0
                || response?.ok !== true
            ) {
                root.suppressNextAlarm = false;

                const responseError =
                    String(response?.error ?? "").trim();
                const stderrText =
                    String(
                        pomodoroActionError.text ?? ""
                    ).trim();

                root.pomodoroError =
                    responseError
                    || stderrText
                    || (
                        "TaskNotes CLI action failed "
                        + `(${exitStatus}).`
                    );

                Quickshell.execDetached([
                    "notify-send",
                    "TaskNotes Pomodoro",
                    root.pomodoroError,
                    "-u", "critical",
                    "-a", "QuickShell"
                ]);
            }

            Qt.callLater(root.refreshPomodoro);
            Qt.callLater(Todo.refresh);
        }
    }

    // Stopwatch remains local and independent.
    function refreshStopwatch() {
        stopwatchTime =
            getCurrentTimeIn10ms()
            - stopwatchStart;
    }

    Timer {
        id: stopwatchTimer
        interval: 10
        running: root.stopwatchRunning
        repeat: true
        onTriggered: root.refreshStopwatch()
    }

    function toggleStopwatch() {
        if (root.stopwatchRunning)
            stopwatchPause();
        else
            stopwatchResume();
    }

    function stopwatchPause() {
        Persistent.states.timer.stopwatch.running =
            false;
    }

    function stopwatchResume() {
        if (stopwatchTime === 0) {
            Persistent.states.timer.stopwatch.laps =
                [];
        }

        Persistent.states.timer.stopwatch.running =
            true;
        Persistent.states.timer.stopwatch.start =
            getCurrentTimeIn10ms()
            - stopwatchTime;
    }

    function stopwatchReset() {
        stopwatchTime = 0;
        Persistent.states.timer.stopwatch.laps = [];
        Persistent.states.timer.stopwatch.running =
            false;
    }

    function stopwatchRecordLap() {
        Persistent.states.timer.stopwatch.laps.push(
            stopwatchTime
        );
    }
}
