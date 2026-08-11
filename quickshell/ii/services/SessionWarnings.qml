pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool packageManagerRunning: false
    property bool downloadRunning: false

    function refresh() {
        packageManagerRunning = false;
        downloadRunning = false;
        detectPackageManagerProc.running = false;
        detectPackageManagerProc.running = true;
        detectDownloadProc.running = false;
        detectDownloadProc.running = true;
    }

    Process {
        id: detectPackageManagerProc
        command: ["bash", "-c", "pidof yay paru dnf zypper apt apx xbps snap apk yum epsi pikman || ls /var/lib/pacman/db.lck"]
        onExited: (exitCode, exitStatus) => {
            root.packageManagerRunning = (exitCode === 0);
        }
    }

    Process {
        id: detectDownloadProc
        // aria2c runs as an always-on RPC daemon here (services.aria2), so
        // its presence in `pidof` says nothing about active downloads —
        // check its .aria2 in-progress marker file instead.
        command: ["bash", "-c", "pidof curl wget yt-dlp || ls ~/Downloads | grep -E '\.crdownload$|\.part$|\.aria2$'"]
        onExited: (exitCode, exitStatus) => {
            root.downloadRunning = (exitCode === 0);
        }
    }
}
