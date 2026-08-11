import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    implicitHeight: contentColumn.implicitHeight
    implicitWidth: contentColumn.implicitWidth

    readonly property var taskChoices: [
        {
            displayName: "No linked TaskNote",
            value: ""
        },
        ...Todo.list
            .filter(task => !task.done)
            .map(task => {
                return {
                    displayName: task.content,
                    value: task.id
                };
            })
    ]

    component TimerControlButton: RippleButton {
        id: controlButton

        required property string iconName
        required property string label
        property bool destructive: false

        implicitWidth: 68
        implicitHeight: 39
        buttonRadius: Appearance.rounding.small

        colBackground:
            controlButton.destructive
                ? Appearance.colors.colErrorContainer
                : Appearance.colors.colLayer2
        colBackgroundHover:
            controlButton.destructive
                ? Appearance.colors.colErrorContainerHover
                : Appearance.colors.colLayer2Hover

        contentItem: RowLayout {
            anchors.centerIn: parent
            spacing: 4

            MaterialSymbol {
                text: controlButton.iconName
                iconSize: 17
                color:
                    controlButton.destructive
                        ? Appearance.colors.colOnErrorContainer
                        : Appearance.colors.colOnLayer2
            }

            StyledText {
                text: controlButton.label
                font.pixelSize:
                    Appearance.font.pixelSize.smaller
                color:
                    controlButton.destructive
                        ? Appearance.colors.colOnErrorContainer
                        : Appearance.colors.colOnLayer2
            }
        }
    }

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        spacing: 7

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            spacing: 6

            MaterialSymbol {
                text:
                    TimerService.pomodoroCliAvailable
                        ? "sync"
                        : "cloud_off"
                iconSize: 18
                color:
                    TimerService.pomodoroCliAvailable
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colError
            }

            StyledText {
                Layout.fillWidth: true
                text:
                    TimerService.pomodoroCliAvailable
                        ? (
                            `${TimerService.pomodoroTotalToday} focus`
                            + ` • ${TimerService.pomodoroMinutesToday} min`
                        )
                        : TimerService.pomodoroError
                elide: Text.ElideRight
                font.pixelSize:
                    Appearance.font.pixelSize.smaller
                color:
                    TimerService.pomodoroCliAvailable
                        ? Appearance.colors.colSubtext
                        : Appearance.colors.colError
            }

            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                enabled: TimerService.pomodoroCliAvailable
                onClicked:
                    TimerService.openPomodoroView()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "open_in_new"
                    iconSize: 18
                    color: Appearance.colors.colOnLayer1
                }

                StyledToolTip {
                    text: "Open TaskNotes Pomodoro view"
                }
            }

            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                onClicked:
                    TimerService.refreshPomodoro()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "refresh"
                    iconSize: 18
                    color: Appearance.colors.colOnLayer1
                }

                StyledToolTip {
                    text: "Refresh through Obsidian CLI"
                }
            }
        }

        StyledComboBox {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            buttonIcon: "task_alt"
            textRole: "displayName"
            model: root.taskChoices
            enabled:
                TimerService.pomodoroCliAvailable
                && !TimerService.pomodoroCurrentSession
                && !TimerService.pomodoroBusy

            currentIndex: {
                const index = model.findIndex(
                    item =>
                        item.value
                        === TimerService.pomodoroTaskId
                );
                return index >= 0 ? index : 0;
            }

            onActivated: index => {
                TimerService.selectPomodoroTask(
                    model[index]?.value ?? ""
                );
            }
        }

        CircularProgress {
            Layout.alignment: Qt.AlignHCenter
            lineWidth: 7
            value: {
                const duration = Math.max(
                    1,
                    TimerService.pomodoroLapDuration
                );
                return (
                    TimerService.pomodoroSecondsLeft
                    / duration
                );
            }
            implicitSize: 156
            enableAnimation: true

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: {
                        const minutes = Math.floor(
                            TimerService
                                .pomodoroSecondsLeft
                            / 60
                        ).toString().padStart(2, "0");
                        const seconds = Math.floor(
                            TimerService
                                .pomodoroSecondsLeft
                            % 60
                        ).toString().padStart(2, "0");
                        return `${minutes}:${seconds}`;
                    }
                    font.pixelSize: 34
                    color:
                        Appearance.m3colors.m3onSurface
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text:
                        TimerService.pomodoroLongBreak
                            ? "Long break"
                            : TimerService.pomodoroBreak
                                ? "Break"
                                : "Focus"
                    font.pixelSize:
                        Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: 126
                    visible: text.length > 0
                    text: TimerService.pomodoroTaskTitle
                    elide: Text.ElideRight
                    font.pixelSize:
                        Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colPrimary
                }
            }

            Rectangle {
                anchors {
                    right: parent.right
                    bottom: parent.bottom
                }

                implicitWidth: 34
                implicitHeight: 34
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer2

                StyledText {
                    anchors.centerIn: parent
                    color: Appearance.colors.colOnLayer2
                    text:
                        (TimerService.pomodoroCycle + 1)
                        + "/"
                        + TimerService
                            .cyclesBeforeLongBreak
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 5

            TimerControlButton {
                iconName: "play_arrow"
                label: "Play"
                visible:
                    !TimerService.pomodoroCurrentSession
                enabled:
                    visible
                    && TimerService.pomodoroCliAvailable
                    && !TimerService.pomodoroBusy
                onClicked:
                    TimerService.startPomodoro()
            }

            TimerControlButton {
                iconName: "pause"
                label: "Pause"
                visible:
                    TimerService.pomodoroCurrentSession
                    && TimerService.pomodoroRunning
                enabled:
                    visible
                    && TimerService.pomodoroCliAvailable
                    && !TimerService.pomodoroBusy
                onClicked:
                    TimerService.pausePomodoro()
            }

            TimerControlButton {
                iconName: "play_arrow"
                label: "Resume"
                visible:
                    TimerService.pomodoroCurrentSession
                    && !TimerService.pomodoroRunning
                enabled:
                    visible
                    && TimerService.pomodoroCliAvailable
                    && !TimerService.pomodoroBusy
                onClicked:
                    TimerService.resumePomodoro()
            }

            TimerControlButton {
                iconName: "stop"
                label: "Stop"
                destructive: true
                visible:
                    TimerService.pomodoroCurrentSession
                enabled:
                    visible
                    && TimerService.pomodoroCliAvailable
                    && !TimerService.pomodoroBusy
                onClicked:
                    TimerService.stopPomodoro()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            visible: TimerService.alarmActive
            implicitHeight: alarmRow.implicitHeight + 12
            radius: Appearance.rounding.small
            color: Appearance.colors.colErrorContainer

            RowLayout {
                id: alarmRow
                anchors {
                    fill: parent
                    margins: 6
                }
                spacing: 6

                MaterialSymbol {
                    text: "notifications_active"
                    iconSize: 19
                    color:
                        Appearance.colors
                            .colOnErrorContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    text: TimerService.alarmMessage
                    elide: Text.ElideRight
                    font.pixelSize:
                        Appearance.font.pixelSize.smaller
                    color:
                        Appearance.colors
                            .colOnErrorContainer
                }

                RippleButton {
                    buttonText: "Stop"
                    onClicked:
                        TimerService.dismissAlarm()

                    StyledToolTip {
                        text: "Stop repeating alarm"
                    }
                }

                RippleButton {
                    visible:
                        TimerService.alarmCanStartBreak
                    buttonText:
                        TimerService.pomodoroNextSessionType
                            === "long-break"
                                ? "Start long break"
                                : "Start break"
                    enabled:
                        visible
                        && TimerService.pomodoroCliAvailable
                        && !TimerService.pomodoroBusy
                    onClicked:
                        TimerService.startBreakAfterAlarm()
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text:
                "After focus: Stop alarm or Start break. "
                + "After break: Stop alarm. TaskNotes writes "
                + "sessions to To-Do/Daily."
            font.pixelSize:
                Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
