pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtWebEngine
import Quickshell

Singleton {
    id: root

    property var persistentProfile: null

    // Always expose one usable profile. The default profile is shared by every
    // WebEngineView and provides a safe in-memory fallback if the persistent
    // storage path is already owned by another process.
    readonly property var profile:
        persistentProfile ?? WebEngine.defaultProfile

    WebEngineProfilePrototype {
        id: profilePrototype

        storageName: "quickshell-ai-sidebar"
        persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
        persistentPermissionsPolicy: WebEngineProfile.StoreOnDisk
    }

    Component.onCompleted: {
        root.persistentProfile = profilePrototype.instance();

        if (root.persistentProfile) {
            console.log("[AI Web Profile] Persistent profile initialized");
        } else {
            console.warn(
                "[AI Web Profile] Persistent storage is already in use; "
                + "falling back to the shared in-memory profile."
            );
        }
    }

    Connections {
        target: root.profile

        function onDownloadRequested(download) {
            download.accept();
        }
    }
}
