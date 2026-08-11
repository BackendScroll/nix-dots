import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebEngine
import Quickshell

Item {
    id: root

    readonly property var aiConfig: Config.options.sidebar.ai
    readonly property bool systemDarkMode:
        Appearance.m3colors.darkmode

    readonly property string activeBackend:
        aiConfig.frontend === "comfyui" ? "comfyui" : "open-webui"

    readonly property string openWebUiUrl:
        normalizedUrl(aiConfig.openWebUiUrl, "http://127.0.0.1:8080")

    readonly property string comfyUiUrl:
        normalizedUrl(aiConfig.comfyUiUrl, "http://127.0.0.1:8188")

    readonly property string activeUrl:
        activeBackend === "comfyui" ? comfyUiUrl : openWebUiUrl

    readonly property var activePage:
        activeBackend === "comfyui" ? comfyUiLoader.item : openWebUiLoader.item

    readonly property var activeView: activePage?.view ?? null

    property bool openWebUiVisited: false
    property bool comfyUiVisited: false

    readonly property var aiWebProfile: AiWebProfile.profile

    function opaqueColor(color) {
        // Chromium currently asserts if the WebEngine background alpha is
        // neither fully opaque nor fully transparent.
        return Qt.rgba(color.r, color.g, color.b, 1.0);
    }

    function normalizedUrl(configuredUrl, fallbackUrl) {
        const value = String(configuredUrl ?? "").trim();

        if (value.length === 0)
            return fallbackUrl;

        if (/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(value))
            return value;

        return `http://${value}`;
    }

    function selectBackend(backend) {
        const selected = backend === "comfyui" ? "comfyui" : "open-webui";

        if (selected === "comfyui")
            comfyUiVisited = true;
        else
            openWebUiVisited = true;

        if (aiConfig.frontend !== selected)
            aiConfig.frontend = selected;
    }

    function reloadActive() {
        activeView?.reload();
    }

    function goHome() {
        if (activeView)
            activeView.url = activeUrl;
    }

    function openExternally() {
        Quickshell.execDetached(["xdg-open", activeUrl]);
    }

    function closeSidebar() {
        // Hiding the layer surface preserves both WebEngine pages and their
        // shared profile. It avoids destroying Chromium while handling input.
        GlobalStates.sidebarLeftOpen = false;
    }

    function stopWebViews() {
        openWebUiLoader.item?.view?.stop();
        comfyUiLoader.item?.view?.stop();
    }

    Component.onCompleted: {
        if (activeBackend === "comfyui")
            comfyUiVisited = true;
        else
            openWebUiVisited = true;
    }

    onActiveBackendChanged: {
        if (activeBackend === "comfyui")
            comfyUiVisited = true;
        else
            openWebUiVisited = true;
    }

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: event => {
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_1) {
            root.selectBackend("open-webui");
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_2) {
            root.selectBackend("comfyui");
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R) {
            root.reloadActive();
            event.accepted = true;
        } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Left) {
            if (root.activeView?.canGoBack)
                root.activeView.goBack();

            event.accepted = true;
        } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Right) {
            if (root.activeView?.canGoForward)
                root.activeView.goForward();

            event.accepted = true;
        }
    }

    component HeaderIconButton: RippleButton {
        required property string iconName
        property string tooltipText: ""

        implicitWidth: 36
        implicitHeight: 36
        buttonRadius: Appearance.rounding.small

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            text: iconName
            iconSize: 20
            color: Appearance.colors.colOnLayer1
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        StyledToolTip {
            text: parent.tooltipText
        }
    }

    component BackendButton: RippleButton {
        required property string backend
        required property string iconName
        required property string title
        property string subtitle: ""

        Layout.fillWidth: true
        implicitHeight: 42
        toggled: root.activeBackend === backend
        buttonRadius: Appearance.rounding.small

        onClicked: root.selectBackend(backend)

        contentItem: RowLayout {
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 10
            }

            spacing: 7

            MaterialSymbol {
                text: iconName
                iconSize: 20
                fill: root.activeBackend === backend ? 1 : 0
                color: root.activeBackend === backend
                    ? Appearance.colors.colOnPrimary
                    : Appearance.colors.colOnLayer1
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: title
                    elide: Text.ElideRight
                    font {
                        pixelSize: Appearance.font.pixelSize.small
                        weight: Font.Medium
                    }
                    color: root.activeBackend === backend
                        ? Appearance.colors.colOnPrimary
                        : Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: subtitle.length > 0
                    text: subtitle
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.activeBackend === backend
                        ? Appearance.colors.colOnPrimary
                        : Appearance.colors.colSubtext
                }
            }
        }
    }

    component BrowserPage: Item {
        id: browserPage

        required property string pageUrl
        required property real pageZoom

        property alias view: webView
        property bool loadFailed: false
        property string errorText: ""
        property bool hasLoadedSuccessfully: false

        clip: true

        WebEngineView {
            id: webView

            anchors.fill: parent
            profile: root.aiWebProfile
            url: browserPage.pageUrl
            zoomFactor: browserPage.pageZoom
            backgroundColor:
                root.opaqueColor(Appearance.colors.colLayer1)

            settings.forceDarkMode:
                root.aiConfig.followSystemTheme
                && root.systemDarkMode
            settings.focusOnNavigationEnabled: true

            onLoadingChanged: loadRequest => {
                if (loadRequest.status === WebEngineView.LoadStartedStatus) {
                    browserPage.loadFailed = false;
                    browserPage.errorText = "";
                } else if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                    browserPage.loadFailed = false;
                    browserPage.hasLoadedSuccessfully = true;
                    browserPage.errorText = "";
                } else if (loadRequest.status === WebEngineView.LoadFailedStatus) {
                    browserPage.loadFailed = true;
                    browserPage.errorText =
                        loadRequest.errorString?.length > 0
                            ? loadRequest.errorString
                            : "The local service did not respond.";
                }
            }

            onNewWindowRequested: request => {
                Quickshell.execDetached([
                    "xdg-open",
                    request.requestedUrl.toString()
                ]);
            }

            onRenderProcessTerminated: (
                terminationStatus,
                exitCode
            ) => {
                browserPage.loadFailed = true;
                browserPage.errorText =
                    `Web renderer stopped (${terminationStatus}, ${exitCode}).`;
            }
        }

        Rectangle {
            anchors.fill: parent
            visible: browserPage.loadFailed
            color: Appearance.colors.colLayer1

            ColumnLayout {
                anchors {
                    centerIn: parent
                    leftMargin: 24
                    rightMargin: 24
                }

                width: Math.min(parent.width - 48, 380)
                spacing: 10

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "cloud_off"
                    iconSize: 48
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: "Local AI service unavailable"
                    font {
                        pixelSize: Appearance.font.pixelSize.large
                        weight: Font.Medium
                    }
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: browserPage.errorText
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WrapAnywhere
                    text: browserPage.pageUrl
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    RippleButton {
                        buttonText: "Retry"
                        onClicked: webView.reload()
                    }

                    RippleButton {
                        buttonText: "Open externally"
                        onClicked: Quickshell.execDetached([
                            "xdg-open",
                            browserPage.pageUrl
                        ])
                    }
                }
            }
        }

        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }

            visible: webView.loading
            height: 2
            color: Qt.rgba(
                Appearance.colors.colPrimary.r,
                Appearance.colors.colPrimary.g,
                Appearance.colors.colPrimary.b,
                0.25
            )

            Rectangle {
                height: parent.height
                width: parent.width * webView.loadProgress / 100
                color: Appearance.colors.colPrimary

                Behavior on width {
                    NumberAnimation {
                        duration: 120
                    }
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: headerColumn.implicitHeight + 12
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            ColumnLayout {
                id: headerColumn

                anchors {
                    fill: parent
                    margins: 6
                }

                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    BackendButton {
                        backend: "open-webui"
                        iconName: "forum"
                        title: "Open WebUI"
                        subtitle: "127.0.0.1:8080"
                    }

                    BackendButton {
                        backend: "comfyui"
                        iconName: "palette"
                        title: "ComfyUI"
                        subtitle: "127.0.0.1:8188"
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    HeaderIconButton {
                        iconName: "arrow_back"
                        tooltipText: "Back"
                        enabled: root.activeView?.canGoBack ?? false
                        onClicked: root.activeView?.goBack()
                    }

                    HeaderIconButton {
                        iconName: "arrow_forward"
                        tooltipText: "Forward"
                        enabled: root.activeView?.canGoForward ?? false
                        onClicked: root.activeView?.goForward()
                    }

                    HeaderIconButton {
                        iconName: "home"
                        tooltipText: "Home"
                        onClicked: root.goHome()
                    }

                    HeaderIconButton {
                        iconName: "refresh"
                        tooltipText: "Reload"
                        onClicked: root.reloadActive()
                    }

                    HeaderIconButton {
                        iconName: root.systemDarkMode
                            ? "dark_mode"
                            : "light_mode"
                        tooltipText: root.aiConfig.followSystemTheme
                            ? (
                                root.systemDarkMode
                                    ? "Following system dark theme"
                                    : "Following system light theme"
                            )
                            : "System theme following is disabled"
                        enabled: false
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 6
                        Layout.rightMargin: 6
                        text: root.activeUrl
                        elide: Text.ElideMiddle
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }

                    HeaderIconButton {
                        iconName: "open_in_new"
                        tooltipText: "Open externally"
                        onClicked: root.openExternally()
                    }

                    HeaderIconButton {
                        iconName: "close"
                        tooltipText: "Close sidebar"
                        onClicked: root.closeSidebar()
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            clip: true

            StackLayout {
                anchors.fill: parent
                currentIndex: root.activeBackend === "comfyui" ? 1 : 0

                Loader {
                    id: openWebUiLoader

                    active:
                        root.openWebUiVisited
                        && (
                            root.aiConfig.keepWebViewsLoaded
                            || root.activeBackend === "open-webui"
                        )

                    sourceComponent: BrowserPage {
                        pageUrl: root.openWebUiUrl
                        pageZoom: root.aiConfig.openWebUiZoom
                    }
                }

                Loader {
                    id: comfyUiLoader

                    active:
                        root.comfyUiVisited
                        && (
                            root.aiConfig.keepWebViewsLoaded
                            || root.activeBackend === "comfyui"
                        )

                    sourceComponent: BrowserPage {
                        pageUrl: root.comfyUiUrl
                        pageZoom: root.aiConfig.comfyUiZoom
                    }
                }
            }
        }
    }
}
