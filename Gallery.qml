pragma ComponentBehavior: Bound
import "."
import qs.Commons
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Hyprland._GlobalShortcuts 0.0

Scope {
    id: galleryScope

    property string lockedScreenName: ""
    property real outsideSwipeDistance: 0
    property real verticalSwipeDistance: 0
    property bool closing: false
    property bool commitSelectionAfterClose: false
    property int closingWorkspaceId: -1
    property string closingMonitorName: ""
    property var closingSelectionByMonitor: ({})
    property var closingWindowData: null
    property real revealProgress: 0

    function activeMonitorName() {
        return GlobalStates.galleryActiveMonitorName
            || galleryScope.lockedScreenName
            || Hyprland.focusedMonitor?.name
            || "";
    }

    function selectedWorkspaceId(monitorName) {
        const name = monitorName || galleryScope.activeMonitorName();
        const selected = GlobalStates.gallerySelectedWorkspaceByMonitor[name];
        if (selected > 0)
            return selected;
        const monitor = ServiceManager.workspace.monitors.find(mon => mon.name === name)
            ?? Hyprland.monitors.find(mon => mon.name === name);
        return ServiceManager.workspace.monitorActiveWorkspaceId(monitor) || 1;
    }

    function activateMonitor(monitorName) {
        if (monitorName)
            GlobalStates.galleryActiveMonitorName = monitorName;
    }

    function open(payload) {
        closeAnimation.stop();
        galleryScope.closing = false;
        galleryScope.commitSelectionAfterClose = false;
        galleryScope.closingWorkspaceId = -1;
        galleryScope.closingMonitorName = "";
        galleryScope.closingSelectionByMonitor = ({});
        galleryScope.closingWindowData = null;
        const anchor = Hyprland.focusedMonitor?.name ?? "";
        galleryScope.lockedScreenName = anchor;
        GlobalStates.overviewAnchorMonitorName = anchor;
        GlobalStates.galleryActiveMonitorName = anchor;
        const selected = {};
        for (const screen of Quickshell.screens) {
            const monitor = Hyprland.monitorFor(screen);
            if (monitor?.name)
                selected[monitor.name] = ServiceManager.workspace.monitorActiveWorkspaceId(monitor) || 1;
        }
        GlobalStates.gallerySelectedWorkspaceByMonitor = selected;
        GlobalStates.overviewFocusedWorkspaceId = galleryScope.selectedWorkspaceId(anchor);
        GlobalStates.overviewOpen = true;
        galleryScope.revealProgress = 0;
        openAnimation.restart();
    }

    function close(commitSelection = false, workspaceId = -1, windowData = null, monitorName = "") {
        if (!GlobalStates.overviewOpen || galleryScope.closing)
            return;
        GlobalStates.gallerySwipeFinished(true, 0);
        openAnimation.stop();
        galleryScope.commitSelectionAfterClose = commitSelection;
        galleryScope.closingMonitorName = monitorName || galleryScope.activeMonitorName();
        galleryScope.closingWindowData = windowData;
        galleryScope.closing = true;
        galleryScope.closingWorkspaceId = commitSelection
            ? (workspaceId > 0 ? workspaceId : galleryScope.selectedWorkspaceId(galleryScope.closingMonitorName))
            : -1;
        const selections = Object.assign({}, GlobalStates.gallerySelectedWorkspaceByMonitor);
        if (galleryScope.commitSelectionAfterClose && galleryScope.closingWorkspaceId > 0)
            selections[galleryScope.closingMonitorName] = galleryScope.closingWorkspaceId;
        galleryScope.closingSelectionByMonitor = selections;
        closeAnimation.restart();
    }

    function toggle() {
        if (GlobalStates.overviewOpen)
            galleryScope.close();
        else
            galleryScope.open({});
    }

    function selectRelative(delta) {
        if (!GlobalStates.overviewOpen) {
            Hyprland.dispatch(`hl.dsp.focus({ workspace = "e${delta > 0 ? "+1" : "-1"}" })`);
            return;
        }
        GlobalStates.galleryStepRequested(delta);
    }

    function handleSwipeEvent(data) {
        const parts = String(data ?? "").split(",");
        if (parts.length < 2)
            return;

        const channel = parts[0];
        const phase = parts[1];
        if (channel === "workspace-gallery-compact") {
            console.info("[WorkspaceGallery] compact gesture requested");
            if (phase === "trigger" && GlobalStates.overviewOpen)
                WorkspaceNavigation.compactWorkspaces();
            return;
        }
        if (channel === "workspace-gallery-vertical") {
            if (phase === "start") {
                galleryScope.verticalSwipeDistance = Number(parts[2] ?? 0);
            } else if (phase === "update") {
                galleryScope.verticalSwipeDistance += Number(parts[2] ?? 0);
            } else if (phase === "finish") {
                const cancelled = parts[2] === "true";
                if (!cancelled && galleryScope.verticalSwipeDistance <= -140
                        && !GlobalStates.overviewOpen) {
                    galleryScope.open({});
                } else if (!cancelled && galleryScope.verticalSwipeDistance >= 90
                        && GlobalStates.overviewOpen) {
                    galleryScope.close();
                }
                galleryScope.verticalSwipeDistance = 0;
            }
            return;
        }

        if (channel !== "workspace-gallery-swipe")
            return;

        if (phase === "start") {
            galleryScope.outsideSwipeDistance = 0;
            const delta = Number(parts[2] ?? 0);
            const timestamp = Number(parts[3] ?? 0);
            if (GlobalStates.overviewOpen)
                GlobalStates.gallerySwipeStarted(delta, timestamp);
            else
                galleryScope.outsideSwipeDistance = delta;
        } else if (phase === "update") {
            const delta = Number(parts[2] ?? 0);
            const timestamp = Number(parts[3] ?? 0);
            if (GlobalStates.overviewOpen)
                GlobalStates.gallerySwipeUpdated(delta, timestamp);
            else
                galleryScope.outsideSwipeDistance += delta;
        } else if (phase === "finish") {
            const cancelled = parts[2] === "true";
            const timestamp = Number(parts[3] ?? 0);
            if (GlobalStates.overviewOpen) {
                GlobalStates.gallerySwipeFinished(cancelled, timestamp);
            } else if (!cancelled && Math.abs(galleryScope.outsideSwipeDistance) >= 55) {
                galleryScope.selectRelative(galleryScope.outsideSwipeDistance < 0 ? 1 : -1);
            }
            galleryScope.outsideSwipeDistance = 0;
        }
    }

    function activateSelection() {
        galleryScope.close(true);
    }

    NumberAnimation {
        id: openAnimation
        target: galleryScope
        property: "revealProgress"
        to: 1
        duration: 240
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: closeAnimation
        target: galleryScope
        property: "revealProgress"
        to: 0
        duration: 220
        easing.type: Easing.InCubic
        onFinished: {
            WorkspaceNavigation.commitGallerySelections(
                galleryScope.closingSelectionByMonitor,
                galleryScope.closingMonitorName);
            const windowData = galleryScope.closingWindowData;
            GlobalStates.overviewOpen = false;
            galleryScope.closing = false;
            galleryScope.commitSelectionAfterClose = false;
            galleryScope.closingWorkspaceId = -1;
            galleryScope.closingMonitorName = "";
            galleryScope.closingSelectionByMonitor = ({});
            galleryScope.closingWindowData = null;
            if (windowData)
                Qt.callLater(() => WorkspaceNavigation.focusWindow(windowData));
        }
    }

    function closeSelectedWorkspaceWindow() {
        if (!GlobalStates.overviewOpen) {
            Hyprland.dispatch("hl.dsp.window.close()");
            return;
        }
        const workspaceId = galleryScope.selectedWorkspaceId(galleryScope.activeMonitorName());
        WorkspaceNavigation.closeMostRecentWindowInWorkspace(workspaceId);
    }

    function updateLiveWindowDrag() {
        if (!CrossMonitorDrag.active)
            return;
        const target = CrossMonitorDrag.hoveredWindowTarget;
        if (!target || target.workspaceId !== CrossMonitorDrag.sourceWorkspaceId
                || CrossMonitorDrag.hoveredTarget?.id !== CrossMonitorDrag.sourceWorkspaceId) {
            CrossMonitorDrag.liveSwapTargetAddress = "";
            return;
        }
        if (target.address === CrossMonitorDrag.liveSwapTargetAddress)
            return;
        const changed = WorkspaceNavigation.swapTiledWindows(
            CrossMonitorDrag.windowAddress,
            target.address,
            CrossMonitorDrag.sourceWorkspaceId,
            {
                restoreX: CrossMonitorDrag.pointerX,
                restoreY: CrossMonitorDrag.pointerY
            });
        CrossMonitorDrag.liveSwapTargetAddress = target.address;
        if (changed)
            CrossMonitorDrag.liveReordered = true;
    }

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen)
                return;
            CrossMonitorDrag.end();
            WorkspaceNavigation.resetOverviewDragState();
            GlobalStates.overviewPendingWorkspaceMonitorById = ({});
            GlobalStates.overviewPendingOccupiedWorkspaces = [];
            GlobalStates.overviewFocusedWorkspaceId = -1;
            GlobalStates.gallerySelectedWorkspaceByMonitor = ({});
            GlobalStates.galleryActiveMonitorName = "";
            galleryScope.lockedScreenName = "";
            GlobalStates.overviewAnchorMonitorName = "";
        }
    }

    Connections {
        target: CrossMonitorDrag
        function onPointerRevisionChanged() {
            galleryScope.updateLiveWindowDrag();
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "custom")
                galleryScope.handleSwipeEvent(event.data);
        }
    }

    Variants {
        model: Quickshell.screens

        LazyLoader {
            id: panelLoader
            required property ShellScreen modelData
            active: true

            component: PanelWindow {
                id: panelWindow
                screen: panelLoader.modelData
                visible: GlobalStates.overviewOpen || galleryScope.closing
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore

                WlrLayershell.namespace: "omarchy-workspace-gallery"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: GlobalStates.overviewOpen && !galleryScope.closing
                    ? WlrKeyboardFocus.OnDemand
                    : WlrKeyboardFocus.None

                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }

                Loader {
                    id: galleryLoader
                    anchors.fill: parent
                    active: GlobalStates.overviewOpen || galleryScope.closing
                    asynchronous: false
                    opacity: galleryScope.revealProgress
                    y: (1 - galleryScope.revealProgress) * 28
                    transform: Scale {
                        origin.x: galleryLoader.width / 2
                        origin.y: galleryLoader.height / 2
                        xScale: 0.96 + galleryScope.revealProgress * 0.04
                        yScale: 0.96 + galleryScope.revealProgress * 0.04
                    }
                    sourceComponent: GalleryWidget {
                        screen: panelWindow.screen
                        closing: galleryScope.closing
                        onMonitorActivated: monitorName => galleryScope.activateMonitor(monitorName)
                        onCloseRequested: (commitSelection, workspaceId, windowData, monitorName) =>
                            galleryScope.close(commitSelection, workspaceId, windowData, monitorName)
                    }
                }

                Item {
                    anchors.fill: parent
                    focus: true

                    Keys.onPressed: event => {
                        galleryScope.activateMonitor(panelWindow.screen?.name ?? "");
                        if (event.key === Qt.Key_Escape) {
                            galleryScope.activateSelection();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                            galleryScope.selectRelative(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                            galleryScope.selectRelative(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down) {
                            if (!event.isAutoRepeat)
                                WorkspaceNavigation.compactWorkspaces();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                            galleryScope.activateSelection();
                            event.accepted = true;
                        }
                    }
                }
            }
        }
    }

    GlobalShortcut {
        name: "workspaceGalleryToggle"
        description: "Toggle Workspace Gallery"
        onPressed: galleryScope.toggle()
    }

    GlobalShortcut {
        name: "workspaceGalleryOpen"
        description: "Open Workspace Gallery"
        onPressed: galleryScope.open({})
    }

    GlobalShortcut {
        name: "workspaceGalleryClose"
        description: "Close Workspace Gallery"
        onPressed: galleryScope.close()
    }

    GlobalShortcut {
        name: "workspaceGalleryNext"
        description: "Select the next gallery workspace"
        onPressed: galleryScope.selectRelative(1)
    }

    GlobalShortcut {
        name: "workspaceGalleryPrevious"
        description: "Select the previous gallery workspace"
        onPressed: galleryScope.selectRelative(-1)
    }

    GlobalShortcut {
        name: "workspaceGalleryCloseWindow"
        description: "Close the latest window in the selected gallery workspace"
        onPressed: galleryScope.closeSelectedWorkspaceWindow()
    }
}
