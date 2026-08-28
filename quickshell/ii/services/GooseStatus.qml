pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

// Reads status.json, the single last-known-state file written by Goose's
// monitor hook emitter (home/dirkk/ai/default.nix) on every session-level
// event. Read-only: this service never writes back to the file. Tool-level
// events (PreToolUse/PostToolUse/etc.) are confirmed, live, to never fire
// under claude-acp/codex-acp, so state is only ever one of "idle",
// "thinking", "done" — see docs/ai/goose.md's "Monitor plugin" section.
Singleton {
    id: root

    readonly property bool hasSession: statusAdapter.session_id.length > 0
    readonly property string state: statusAdapter.state
    readonly property string provider: statusAdapter.provider
    readonly property string model: statusAdapter.model
    readonly property string sessionId: statusAdapter.session_id
    readonly property string ts: statusAdapter.ts
    readonly property string lastPrompt: statusAdapter.last_prompt
    readonly property string lastAssistantMessage: statusAdapter.last_assistant_message
    readonly property string workingDir: statusAdapter.working_dir

    Timer {
        id: reloadDebounce
        interval: 100
        repeat: false
        onTriggered: statusFileView.reload()
    }

    FileView {
        id: statusFileView
        path: Directories.gooseStatusPath
        watchChanges: true
        onFileChanged: reloadDebounce.restart()

        adapter: JsonAdapter {
            id: statusAdapter
            property string state: ""
            property string provider: ""
            property string model: ""
            property string session_id: ""
            property string ts: ""
            property string last_prompt: ""
            property string last_assistant_message: ""
            property string working_dir: ""
        }
    }
}
