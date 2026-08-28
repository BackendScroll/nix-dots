import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay

OverlayBackground {
    id: root

    property real padding: 16
    implicitWidth: 340
    implicitHeight: contentColumn.implicitHeight + padding * 2

    function truncate(text, max) {
        if (!text || text.length <= max) return text;
        return text.slice(0, max) + "…";
    }

    function stateLabel(state) {
        switch (state) {
            case "thinking": return Translation.tr("THINKING");
            case "done": return Translation.tr("DONE");
            case "idle": return Translation.tr("IDLE");
            default: return Translation.tr("NO SESSION");
        }
    }

    function stateContainerColor(state) {
        switch (state) {
            case "thinking": return Appearance.colors.colPrimaryContainer;
            case "done": return Appearance.colors.colTertiaryContainer;
            default: return Appearance.colors.colSurfaceContainerHigh;
        }
    }

    function stateOnContainerColor(state) {
        switch (state) {
            case "thinking": return Appearance.colors.colOnPrimaryContainer;
            case "done": return Appearance.colors.colOnTertiaryContainer;
            default: return Appearance.colors.colOnSurface;
        }
    }

    ColumnLayout {
        id: contentColumn
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.padding
        }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                text: GooseStatus.hasSession
                    ? Translation.tr("%1 · %2").arg(GooseStatus.provider).arg(GooseStatus.model)
                    : Translation.tr("No Goose session yet")
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
            }

            Rectangle {
                radius: height / 2
                color: root.stateContainerColor(GooseStatus.state)
                implicitWidth: statePill.implicitWidth + 16
                implicitHeight: statePill.implicitHeight + 6

                StyledText {
                    id: statePill
                    anchors.centerIn: parent
                    text: root.stateLabel(GooseStatus.state)
                    color: root.stateOnContainerColor(GooseStatus.state)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }

        StyledText {
            visible: GooseStatus.hasSession
            Layout.fillWidth: true
            text: Translation.tr("Session %1").arg(GooseStatus.sessionId)
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
            elide: Text.ElideRight
        }

        StyledText {
            visible: GooseStatus.hasSession && GooseStatus.workingDir.length > 0
            Layout.fillWidth: true
            text: GooseStatus.workingDir
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
            elide: Text.ElideMiddle
        }

        StyledText {
            visible: GooseStatus.hasSession && GooseStatus.lastPrompt.length > 0
            Layout.fillWidth: true
            text: Translation.tr("> %1").arg(root.truncate(GooseStatus.lastPrompt, 160))
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        StyledText {
            visible: GooseStatus.hasSession && GooseStatus.lastAssistantMessage.length > 0
            Layout.fillWidth: true
            text: root.truncate(GooseStatus.lastAssistantMessage, 300)
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
        }

        StyledText {
            visible: GooseStatus.hasSession
            Layout.fillWidth: true
            Layout.topMargin: 4
            text: Translation.tr("Updated %1").arg(GooseStatus.ts)
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }
}
