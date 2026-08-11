import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: button

    property string day
    property string dateString: ""
    property int isToday
    property bool bold
    property bool selected: false
    property int taskCount: 0

    signal dayClicked(string dateString)

    Layout.fillWidth: false
    Layout.fillHeight: false
    implicitWidth: 34
    implicitHeight: 34

    toggled: selected || isToday === 1
    buttonRadius: Appearance.rounding.small

    onClicked: button.dayClicked(button.dateString)

    contentItem: Item {
        anchors.fill: parent

        StyledText {
            anchors.fill: parent
            anchors.bottomMargin: button.taskCount > 0 ? 7 : 0
            text: button.day
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.weight:
                button.bold
                    ? Font.DemiBold
                    : Font.Normal
            color:
                button.selected || button.isToday === 1
                    ? Appearance.m3colors.m3onPrimary
                    : button.isToday === 0
                        ? Appearance.colors.colOnLayer1
                        : Appearance.colors.colOutlineVariant

            Behavior on color {
                animation:
                    Appearance.animation.elementMoveFast.colorAnimation
                        .createObject(this)
            }
        }

        Rectangle {
            visible: button.taskCount > 0
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: 3
            }

            width: button.taskCount > 9 ? 14 : 6
            height: 6
            radius: 3
            color:
                button.selected || button.isToday === 1
                    ? Appearance.m3colors.m3onPrimary
                    : Appearance.colors.colPrimary

            StyledText {
                anchors.centerIn: parent
                visible: button.taskCount > 9
                text: "9+"
                font.pixelSize: 6
                color:
                    button.selected || button.isToday === 1
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colOnPrimary
            }
        }
    }
}

