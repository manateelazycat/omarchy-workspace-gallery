pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// Bridges pointer state between the per-monitor overview surfaces. Qt's
// Drag/DropArea pair is not reliable once a drag crosses a window boundary.
// Resolve targets in shared global logical coordinates. Poll the compositor
// while dragging because the source surface can stop receiving motion when
// the pointer crosses onto another monitor's layer surface.
Singleton {
    id: root

    property bool active: false
    property string windowAddress: ""
    property int sourceWorkspaceId: -1
    property string sourceMonitorName: ""
    property real pointerX: 0
    property real pointerY: 0
    property int pointerRevision: 0
    property int generation: 0
    property var targets: ({})
    property var windowTargets: ({})
    property bool liveReordered: false
    property string liveSwapTargetAddress: ""

    property real sourceWidth: 0
    property real sourceHeight: 0
    property bool compactPreview: false
    property var previewGrab: null
    readonly property string previewUrl: root.previewGrab
        ? String(root.previewGrab.url ?? "")
        : ""

    Timer {
        interval: 40
        repeat: true
        running: root.active
        onTriggered: {
            if (!cursorProcess.running)
                cursorProcess.running = true;
        }
    }

    Process {
        id: cursorProcess
        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.active)
                    return;
                try {
                    const position = JSON.parse(text);
                    if (Number.isFinite(position.x) && Number.isFinite(position.y))
                        root.updatePointer(position.x, position.y);
                } catch (error) {
                    console.warn("[WorkspaceGallery] Failed to read cursor position:", error);
                }
            }
        }
    }

    function begin(address, workspaceId, monitorName, w, h, px, py, compact) {
        root.generation += 1;
        root.windowAddress = String(address ?? "");
        root.sourceWorkspaceId = workspaceId ?? -1;
        root.sourceMonitorName = String(monitorName ?? "");
        root.sourceWidth = w ?? 0;
        root.sourceHeight = h ?? 0;
        root.compactPreview = compact === true;
        root.previewGrab = null;
        root.pointerX = px ?? 0;
        root.pointerY = py ?? 0;
        root.targets = ({});
        root.windowTargets = ({});
        root.liveReordered = false;
        root.liveSwapTargetAddress = "";
        root.active = true;
    }

    function publishTarget(key, surfaceMonitorName, workspaceMonitorName, workspaceId, isTrailing,
            x, y, w, h, hitX, hitY, hitW, hitH, workX, workY, workW, workH) {
        if (!root.active || workspaceId === undefined || workspaceId === null)
            return;
        const next = Object.assign({}, root.targets);
        next[key] = {
            id: workspaceId,
            isTrailing: isTrailing === true,
            surfaceMonitorName: String(surfaceMonitorName ?? ""),
            workspaceMonitorName: String(workspaceMonitorName ?? ""),
            x,
            y,
            w,
            h,
            hitX,
            hitY,
            hitW,
            hitH,
            workX,
            workY,
            workW,
            workH
        };
        root.targets = next;
    }

    function removeTarget(key) {
        if (!key || !root.targets[key])
            return;
        const next = Object.assign({}, root.targets);
        delete next[key];
        root.targets = next;
    }

    function updatePointer(gx, gy) {
        if (root.active) {
            root.pointerX = gx;
            root.pointerY = gy;
            root.pointerRevision += 1;
        }
    }

    function publishWindowTarget(key, address, workspaceId, x, y, w, h) {
        if (!root.active || !key || !address || workspaceId < 1 || w <= 0 || h <= 0)
            return;
        const next = Object.assign({}, root.windowTargets);
        next[key] = {
            address: String(address),
            workspaceId,
            x,
            y,
            w,
            h
        };
        root.windowTargets = next;
    }

    function removeWindowTarget(key) {
        if (!key || !root.windowTargets[key])
            return;
        const next = Object.assign({}, root.windowTargets);
        delete next[key];
        root.windowTargets = next;
    }

    readonly property var hoveredTarget: {
        if (!root.active)
            return null;
        const keys = Object.keys(root.targets);
        for (let i = 0; i < keys.length; ++i) {
            const target = root.targets[keys[i]];
            if (root.pointerX >= target.hitX && root.pointerX <= target.hitX + target.hitW
                && root.pointerY >= target.hitY && root.pointerY <= target.hitY + target.hitH)
                return target;
        }
        return null;
    }

    readonly property var hoveredWindowTarget: {
        if (!root.active)
            return null;
        const keys = Object.keys(root.windowTargets);
        for (let i = keys.length - 1; i >= 0; --i) {
            const target = root.windowTargets[keys[i]];
            if (target.address === root.windowAddress)
                continue;
            if (root.pointerX >= target.x && root.pointerX <= target.x + target.w
                    && root.pointerY >= target.y && root.pointerY <= target.y + target.h)
                return target;
        }
        return null;
    }

    function setPreview(grabResult, forGeneration) {
        if (root.active && forGeneration === root.generation)
            root.previewGrab = grabResult ?? null;
    }

    function end() {
        root.active = false;
        root.windowAddress = "";
        root.sourceWorkspaceId = -1;
        root.sourceMonitorName = "";
        root.compactPreview = false;
        root.liveReordered = false;
        root.liveSwapTargetAddress = "";
        root.generation += 1;
        root.previewGrab = null;
        root.targets = ({});
        root.windowTargets = ({});
    }
}
