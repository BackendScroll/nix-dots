import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    property bool detach: false
    property bool pin: false
    property Component contentComponent: SidebarLeftContent {}
    property Item sidebarContent: null

    function attachContent(container) {
        if (!sidebarContent || !container)
            return;

        sidebarContent.parent = container;
        sidebarContent.anchors.fill = container;
    }

    function toggleDetach() {
        root.detach = !root.detach;
    }

    Process {
        id: pinWithFunnyHyprlandWorkaroundProc

        property var hook: null
        property int cursorX
        property int cursorY

        function doIt() {
            command = ["hyprctl", "cursorpos"];
            hook = output => {
                cursorX = parseInt(output.split(",")[0]);
                cursorY = parseInt(output.split(",")[1]);
                doIt2();
            };
            running = true;
        }

        function doIt2() {
            command = [
                "bash",
                "-c",
                "hyprctl dispatch 'hl.dsp.cursor.move({x=9999,y=9999})'"
            ];
            hook = () => doIt3();
            running = true;
        }

        function doIt3() {
            root.pin = !root.pin;
            command = [
                "bash",
                "-c",
                `sleep 0.01; hyprctl dispatch 'hl.dsp.cursor.move({x=${cursorX},y=${cursorY}})'`
            ];
            hook = null;
            running = true;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                if (pinWithFunnyHyprlandWorkaroundProc.hook)
                    pinWithFunnyHyprlandWorkaroundProc.hook(text);
            }
        }
    }

    function togglePin() {
        if (!root.pin)
            pinWithFunnyHyprlandWorkaroundProc.doIt();
        else
            root.pin = false;
    }

    Component.onCompleted: {
        // Give the content an explicit QML owner. The previous null owner
        // could leave a destroyed object referenced during shell teardown.
        root.sidebarContent = contentComponent.createObject(root, {
            "scopeRoot": root
        });
        root.attachContent(sidebarLoader.item?.contentParent);
    }

    Component.onDestruction: {
        if (sidebarLoader.item)
            GlobalFocusGrab.removeDismissable(sidebarLoader.item);

        // sidebarContent was created with root as its QObject owner, so QML
        // destroys it in the correct order. Do not manually destroy it while
        // the window tree is already tearing down.
        root.sidebarContent = null;
    }

    onDetachChanged: {
        const target = root.detach
            ? detachedSidebarLoader.item?.contentParent
            : sidebarLoader.item?.contentParent;

        root.attachContent(target);
    }

    Loader {
        id: sidebarLoader
        active: true

        onLoaded: {
            if (!root.detach)
                root.attachContent(item.contentParent);
        }

        sourceComponent: PanelWindow {
            id: panelWindow

            visible: !root.detach && GlobalStates.sidebarLeftOpen

            property bool extend: false
            property real sidebarWidth:
                panelWindow.extend
                    ? Appearance.sizes.sidebarWidthExtended
                    : Appearance.sizes.sidebarWidth
            property var contentParent: sidebarLeftBackground

            function hide() {
                GlobalStates.sidebarLeftOpen = false;
            }

            exclusionMode: ExclusionMode.Normal
            exclusiveZone:
                visible && root.pin
                    ? sidebarWidth
                    : 0
            implicitWidth:
                Appearance.sizes.sidebarWidthExtended
                + Appearance.sizes.elevationMargin
            WlrLayershell.namespace: "quickshell:sidebarLeft"
            WlrLayershell.keyboardFocus:
                visible
                    ? WlrKeyboardFocus.OnDemand
                    : WlrKeyboardFocus.None
            color: "transparent"

            anchors {
                top: true
                left: true
                bottom: true
            }

            mask: Region {
                item: sidebarLeftBackground
            }

            onVisibleChanged: {
                if (visible) {
                    GlobalFocusGrab.addDismissable(panelWindow);
                    root.sidebarContent?.focusActiveItem();
                } else {
                    GlobalFocusGrab.removeDismissable(panelWindow);
                }
            }

            Connections {
                target: GlobalFocusGrab

                function onDismissed() {
                    if (panelWindow.visible)
                        panelWindow.hide();
                }
            }

            StyledRectangularShadow {
                target: sidebarLeftBackground
                radius: sidebarLeftBackground.radius
            }

            Rectangle {
                id: sidebarLeftBackground

                anchors {
                    top: parent.top
                    left: parent.left
                    topMargin: Appearance.sizes.hyprlandGapsOut
                    leftMargin: Appearance.sizes.hyprlandGapsOut
                }

                width:
                    panelWindow.sidebarWidth
                    - Appearance.sizes.hyprlandGapsOut
                    - Appearance.sizes.elevationMargin
                height:
                    Math.max(
                        1,
                        parent.height
                        - Appearance.sizes.hyprlandGapsOut * 2
                    )
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                radius:
                    Appearance.rounding.screenRounding
                    - Appearance.sizes.hyprlandGapsOut
                    + 1

                Behavior on width {
                    animation:
                        Appearance.animation.elementMove.numberAnimation
                            .createObject(this)
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        panelWindow.hide();
                        event.accepted = true;
                        return;
                    }

                    if (event.modifiers === Qt.ControlModifier) {
                        if (event.key === Qt.Key_O)
                            panelWindow.extend = !panelWindow.extend;
                        else if (event.key === Qt.Key_D)
                            root.toggleDetach();
                        else if (event.key === Qt.Key_P)
                            root.togglePin();

                        event.accepted = true;
                    }
                }
            }
        }
    }

    Loader {
        id: detachedSidebarLoader
        active: true

        onLoaded: {
            if (root.detach)
                root.attachContent(item.contentParent);
        }

        sourceComponent: FloatingWindow {
            id: detachedSidebarRoot

            property var contentParent: detachedSidebarBackground

            visible: root.detach && GlobalStates.sidebarLeftOpen
            color: "transparent"

            implicitWidth: Math.max(
                720,
                Appearance.sizes.sidebarWidthExtended
            )
            implicitHeight: 760

            onVisibleChanged: {
                if (visible)
                    root.sidebarContent?.focusActiveItem();

                // Only a user closing the detached window should close the
                // sidebar. Switching back to attached mode must not.
                if (
                    root.detach
                    && !visible
                    && GlobalStates.sidebarLeftOpen
                ) {
                    GlobalStates.sidebarLeftOpen = false;
                }
            }

            Rectangle {
                id: detachedSidebarBackground

                anchors.fill: parent
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                radius: Appearance.rounding.normal

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        GlobalStates.sidebarLeftOpen = false;
                        event.accepted = true;
                        return;
                    }

                    if (
                        event.modifiers === Qt.ControlModifier
                        && event.key === Qt.Key_D
                    ) {
                        root.toggleDetach();
                        event.accepted = true;
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "sidebarLeft"

        function toggle(): void {
            GlobalStates.sidebarLeftOpen =
                !GlobalStates.sidebarLeftOpen;
        }

        function close(): void {
            GlobalStates.sidebarLeftOpen = false;
        }

        function open(): void {
            GlobalStates.sidebarLeftOpen = true;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggle"
        description: "Toggles left sidebar on press"

        onPressed:
            GlobalStates.sidebarLeftOpen =
                !GlobalStates.sidebarLeftOpen
    }

    GlobalShortcut {
        name: "sidebarLeftOpen"
        description: "Opens left sidebar on press"

        onPressed: GlobalStates.sidebarLeftOpen = true
    }

    GlobalShortcut {
        name: "sidebarLeftClose"
        description: "Closes left sidebar on press"

        onPressed: GlobalStates.sidebarLeftOpen = false
    }

    GlobalShortcut {
        name: "sidebarLeftToggleDetach"
        description: "Detach left sidebar into a window/Attach it back"

        onPressed: root.toggleDetach()
    }
}
