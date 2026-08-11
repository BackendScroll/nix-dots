import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "calendar_layout.js" as CalendarLayout
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    anchors.topMargin: 8

    property int monthShift: 0
    property var viewingDate:
        CalendarLayout.getDateInXMonthsTime(monthShift)
    property var calendarLayout:
        CalendarLayout.getCalendarLayout(
            viewingDate,
            monthShift === 0
        )
    property string selectedDate:
        CalendarLayout.localDateString(new Date())
    readonly property var selectedTasks:
        Todo.tasksForDate(selectedDate)

    implicitHeight: calendarColumn.implicitHeight + 12

    function selectedDateLabel() {
        const parts = selectedDate.split("-");

        if (parts.length !== 3)
            return selectedDate;

        const date = new Date(
            Number(parts[0]),
            Number(parts[1]) - 1,
            Number(parts[2])
        );

        return date.toLocaleDateString(
            Qt.locale(),
            "ddd, d MMMM"
        );
    }

    Keys.onPressed: event => {
        if (
            (
                event.key === Qt.Key_PageDown
                || event.key === Qt.Key_PageUp
            )
            && event.modifiers === Qt.NoModifier
        ) {
            monthShift +=
                event.key === Qt.Key_PageDown ? 1 : -1;
            event.accepted = true;
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton

        onWheel: event => {
            if (event.angleDelta.y > 0)
                monthShift--;
            else if (event.angleDelta.y < 0)
                monthShift++;
        }
    }

    ColumnLayout {
        id: calendarColumn

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: 4
            rightMargin: 8
        }

        spacing: 5

        RowLayout {
            Layout.fillWidth: true
            spacing: 5

            CalendarHeaderButton {
                clip: true
                buttonText:
                    `${monthShift !== 0 ? "• " : ""}`
                    + viewingDate.toLocaleDateString(
                        Qt.locale(),
                        "MMMM yyyy"
                    )
                tooltipText:
                    monthShift === 0
                        ? ""
                        : "Jump to current month"

                downAction: () => {
                    monthShift = 0;
                    selectedDate =
                        CalendarLayout.localDateString(new Date());
                }
            }

            Item {
                Layout.fillWidth: true
            }

            CalendarHeaderButton {
                forceCircle: true
                downAction: () => monthShift--

                contentItem: MaterialSymbol {
                    text: "chevron_left"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }
            }

            CalendarHeaderButton {
                forceCircle: true
                downAction: () => monthShift++

                contentItem: MaterialSymbol {
                    text: "chevron_right"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 4

            Repeater {
                model: CalendarLayout.weekDays

                delegate: CalendarDayButton {
                    day: modelData.day
                    isToday: modelData.today
                    bold: true
                    enabled: false
                }
            }
        }

        Repeater {
            model: 6

            delegate: RowLayout {
                required property int index

                Layout.alignment: Qt.AlignHCenter
                spacing: 4

                Repeater {
                    model: root.calendarLayout[index]

                    delegate: CalendarDayButton {
                        required property var modelData

                        day: String(modelData.day)
                        dateString: modelData.date
                        isToday: modelData.today
                        selected:
                            modelData.date === root.selectedDate
                        taskCount:
                            Todo.tasksForDate(modelData.date).length

                        onDayClicked: date => {
                            root.selectedDate = date;
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Appearance.colors.colLayer0Border
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            StyledText {
                Layout.fillWidth: true
                text: root.selectedDateLabel()
                font {
                    pixelSize: Appearance.font.pixelSize.small
                    weight: Font.DemiBold
                }
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                text:
                    `${root.selectedTasks.length} task`
                    + (root.selectedTasks.length === 1 ? "" : "s")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        ListView {
            id: agendaList

            Layout.fillWidth: true
            Layout.preferredHeight: 94
            clip: true
            spacing: 3
            model: root.selectedTasks

            delegate: RippleButton {
                required property var modelData

                width: agendaList.width
                implicitHeight: 29
                buttonRadius: Appearance.rounding.small
                onClicked: Todo.openTaskById(modelData.id)

                contentItem: RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 7
                        rightMargin: 7
                    }

                    spacing: 6

                    MaterialSymbol {
                        text:
                            modelData.done
                                ? "task_alt"
                                : modelData.overdue
                                    ? "warning"
                                    : "radio_button_unchecked"
                        iconSize: 16
                        color:
                            modelData.overdue
                                ? Appearance.colors.colError
                                : Appearance.colors.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: modelData.content
                        elide: Text.ElideRight
                        font.pixelSize:
                            Appearance.font.pixelSize.smaller
                        font.strikeout: modelData.done
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        visible:
                            String(
                                modelData.scheduled
                                || modelData.due
                                || ""
                            ).length > 10
                        text:
                            String(
                                modelData.scheduled
                                || modelData.due
                                || ""
                            ).slice(11, 16)
                        font.pixelSize:
                            Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            StyledText {
                anchors.centerIn: parent
                visible: root.selectedTasks.length === 0
                text: "No TaskNotes scheduled"
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }
}
