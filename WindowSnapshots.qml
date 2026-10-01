pragma Singleton
pragma ComponentBehavior: Bound
import "."
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland._ToplevelManagement

// One clean capture per toplevel, shared by its small and large workspace card.
// Stage a complete set before showing the gallery, then swap updates together.
Singleton {
    id: root

    property var urls: ({})
    property var stagedUrls: ({})
    property var expectedKeys: []
    property var requested: ({})
    property var queue: []
    property var current: null
    property var files: []
    property int generation: 0
    property bool ready: false
    property bool awaitingClients: false
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    property string snapshotDir: ""
    property bool storageReady: false
    property int captureSerial: 0

    Component.onCompleted: {
        createSnapshotDir.running = true;
        if (ServiceManager.workspace.clientsLoaded)
            root.prepare();
        else
            root.awaitingClients = true;
    }

    Component.onDestruction: {
        if (root.snapshotDir.length > 0)
            Quickshell.execDetached(["rm", "-rf", "--", root.snapshotDir]);
    }

    function prepare() {
        root.generation += 1;
        root.stagedUrls = ({});
        root.requested = ({});
        root.queue = [];
        if (!ServiceManager.workspace.clientsLoaded) {
            root.awaitingClients = true;
            root.ready = false;
            return;
        }
        root.awaitingClients = false;
        const windows = [];
        for (const toplevel of ToplevelManager.toplevels.values) {
            const address = ServiceManager.workspace.normalizeAddress(
                toplevel.HyprlandToplevel?.address);
            const window = ServiceManager.workspace.clientByAddress(address);
            if (window?.mapped && !window.hidden && window.stableId)
                windows.push({ address, stableId: window.stableId });
        }
        root.expectedKeys = windows.map(window => window.address);
        root.ready = root.expectedKeys.every(address => !!root.urls[address]);
        for (const window of windows)
            root.request(window.address, window.stableId);
        if (windows.length === 0)
            root.publish();
    }

    function removeOldFiles() {
        const displayed = new Set(Object.values(root.urls).map(url =>
            String(url).split("?")[0].replace(/^file:\/\//, "")));
        const keep = [];
        const remove = [];
        for (const file of root.files) {
            if (displayed.has(file.path) || file.generation === root.generation)
                keep.push(file);
            else
                remove.push(file.path);
        }
        root.files = keep;
        if (remove.length > 0)
            Quickshell.execDetached(["rm", "-f", ...remove]);
    }

    function request(address, stableId) {
        const key = String(address ?? "");
        const id = String(stableId ?? "");
        if (key.length === 0 || id.length === 0)
            return;
        if (root.generation === 0)
            root.prepare();
        if (root.requested[key])
            return;
        root.requested = Object.assign({}, root.requested, { [key]: true });
        root.queue.push({ key, id, generation: root.generation });
        root.startNext();
    }

    function startNext() {
        if (!root.storageReady || root.current || captureProcess.running)
            return;
        if (root.snapshotDir.length === 0) {
            root.queue = [];
            root.publish();
            return;
        }
        if (root.queue.length === 0) {
            root.publish();
            return;
        }
        root.current = root.queue.shift();
        root.captureSerial += 1;
        root.current.path = `${root.snapshotDir}/${root.generation}-${root.captureSerial}.png`;
        root.files.push({ path: root.current.path, generation: root.current.generation });
        // Pass arguments separately: window IDs and paths never become shell code.
        captureProcess.command = ["sh", "-c", 'umask 077; exec grim "$@"',
            "workspace-gallery-capture", "-t", "png", "-l", "1", "-T",
            root.current.id, root.current.path];
        captureProcess.running = true;
    }

    function publish() {
        if (root.current || captureProcess.running || root.queue.length > 0)
            return;
        if (Object.keys(root.stagedUrls).length > 0)
            root.urls = Object.assign({}, root.urls, root.stagedUrls);
        root.stagedUrls = ({});
        root.ready = true;
        cleanupTimer.restart();
    }

    // mktemp creates an unpredictable, exclusive 0700 directory even in /tmp.
    // Each plugin instance gets its own directory; never reuse a public path.
    Process {
        id: createSnapshotDir
        command: ["mktemp", "-d", "--", `${root.runtimeDir}/omarchy-workspace-gallery.XXXXXXXXXX`]
        stdout: StdioCollector {
            onStreamFinished: {
                root.snapshotDir = text.trim();
                root.storageReady = true;
                if (root.snapshotDir.length === 0)
                    console.warn("[WorkspaceGallery] Could not create private screenshot storage");
                root.startNext();
            }
        }
    }

    Process {
        id: captureProcess
        onExited: (exitCode, exitStatus) => {
            const job = root.current;
            root.current = null;
            if (job && exitCode === 0 && job.generation === root.generation) {
                root.stagedUrls = Object.assign({}, root.stagedUrls,
                    { [job.key]: `file://${job.path}?v=${job.generation}` });
            } else if (job && job.generation !== root.generation) {
                root.files = root.files.filter(file => file.path !== job.path);
                Quickshell.execDetached(["rm", "-f", job.path]);
            }
            nextCaptureTimer.restart();
        }
    }

    Timer {
        id: nextCaptureTimer
        interval: 20
        onTriggered: root.startNext()
    }

    Timer {
        id: cleanupTimer
        interval: 1200
        onTriggered: root.removeOldFiles()
    }

    Connections {
        target: ServiceManager.workspace
        function onClientsLoadedChanged() {
            if (root.awaitingClients && ServiceManager.workspace.clientsLoaded)
                root.prepare();
        }
    }
}
