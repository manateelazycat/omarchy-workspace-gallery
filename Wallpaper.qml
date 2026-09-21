pragma Singleton
import "."
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string currentBackgroundLink:
        `${Quickshell.env("HOME") || ""}/.local/state/omarchy/current/background`
    property url requestedUrl: ""
    property url readyUrl: ""

    function setBackground(path) {
        const resolved = String(path || "").trim();
        if (!resolved) {
            root.requestedUrl = "";
            root.readyUrl = "";
            return;
        }

        const url = resolved.startsWith("file://") ? resolved : `file://${resolved}`;
        root.requestedUrl = url;
        root.readyUrl = url;
    }

    function refresh() {
        if (!readBackground.running)
            readBackground.running = true;
    }

    Process {
        id: readBackground
        command: ["readlink", "-f", root.currentBackgroundLink]
        stdout: StdioCollector {
            onStreamFinished: root.setBackground(text)
        }
    }

    Component.onCompleted: root.refresh()

    // The symlink only matters while the overview can display it; chase it
    // then instead of spawning readlink every 5 s for a hidden panel.
    Timer {
        interval: 5000
        repeat: true
        running: GlobalStates.overviewOpen === true
        onTriggered: root.refresh()
    }

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen)
                root.refresh();
        }
    }
}
