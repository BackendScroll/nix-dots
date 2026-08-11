import qs.modules.common
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications

MaterialShape {
    id: root

    property var appIcon: ""
    property var summary: ""
    property var urgency:
        NotificationUrgency.Normal
    property bool isUrgent:
        urgency === NotificationUrgency.Critical
    property var image: ""
    property real materialIconScale: 0.57
    property real appIconScale: 0.8
    property real smallAppIconScale: 0.49
    property real materialIconSize:
        implicitSize * materialIconScale
    property real appIconSize:
        implicitSize * appIconScale
    property real smallAppIconSize:
        implicitSize * smallAppIconScale

    readonly property string imageSource:
        String(image ?? "")
    readonly property bool usableImage:
        imageSource.length > 0
        // qsimage notification handles expire with their source
        // notification. Avoid retaining an invalid provider handle.
        && !imageSource.startsWith("image://qsimage/")
    readonly property string resolvedAppIcon:
        String(appIcon ?? "").length > 0
            ? Quickshell.iconPath(
                String(appIcon),
                "application-x-executable"
            )
            : ""

    implicitSize: 38 * scale

    property list<var> urgentShapes: [
        MaterialShape.Shape.VerySunny,
        MaterialShape.Shape.SoftBurst
    ]

    shape:
        isUrgent
            ? urgentShapes[
                Math.floor(
                    Math.random()
                    * urgentShapes.length
                )
            ]
            : MaterialShape.Shape.Circle

    color:
        isUrgent
            ? Appearance.colors.colPrimaryContainer
            : Appearance.colors.colSecondaryContainer

    Loader {
        id: materialSymbolLoader

        active:
            !root.usableImage
            && root.resolvedAppIcon.length === 0
        anchors.fill: parent

        sourceComponent: MaterialSymbol {
            anchors.fill: parent
            text: {
                const defaultIcon =
                    NotificationUtils
                        .findSuitableMaterialSymbol("");
                const guessedIcon =
                    NotificationUtils
                        .findSuitableMaterialSymbol(
                            root.summary
                        );

                return (
                    root.urgency
                    === NotificationUrgency.Critical
                    && guessedIcon === defaultIcon
                )
                    ? "priority_high"
                    : guessedIcon;
            }
            color:
                root.isUrgent
                    ? Appearance.colors
                        .colOnPrimaryContainer
                    : Appearance.colors
                        .colOnSecondaryContainer
            iconSize: root.materialIconSize
            horizontalAlignment:
                Text.AlignHCenter
            verticalAlignment:
                Text.AlignVCenter
        }
    }

    Loader {
        id: appIconLoader

        active:
            !root.usableImage
            && root.resolvedAppIcon.length > 0
        anchors.centerIn: parent

        sourceComponent: IconImage {
            implicitSize: root.appIconSize
            asynchronous: true
            source: root.resolvedAppIcon
        }
    }

    Loader {
        id: notifImageLoader

        active: root.usableImage
        anchors.fill: parent

        sourceComponent: Item {
            anchors.fill: parent

            StyledImage {
                id: notifImage

                anchors.fill: parent
                readonly property int size:
                    Math.max(1, parent.width)
                source: root.imageSource
                fillMode: Image.PreserveAspectCrop
                cache: false
                antialiasing: true
                asynchronous: true

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: notifImage.size
                        height: notifImage.size
                        radius:
                            Appearance.rounding.full
                    }
                }
            }

            Loader {
                active:
                    root.resolvedAppIcon.length > 0
                anchors {
                    bottom: parent.bottom
                    right: parent.right
                }

                sourceComponent: IconImage {
                    implicitSize:
                        root.smallAppIconSize
                    asynchronous: true
                    source: root.resolvedAppIcon
                }
            }
        }
    }
}