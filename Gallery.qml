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
    property var focusedScreen: Quickshell.screens.find(
        screen => screen.name === (galleryScope.lockedScreenName || Hyprland.focusedMonitor?.name))
        ?? Quickshell.screens[0]
        ?? null

    function currentWorkspaceId() {
        return WorkspaceNavigation.currentWorkspaceId();
    }

    function open(payload) {
        const anchor = Hyprland.focusedMonitor?.name ?? "";
        galleryScope.lockedScreenName = anchor;
        GlobalStates.overviewAnchorMonitorName = anchor;
        GlobalStates.overviewFocusedWorkspaceId = galleryScope.currentWorkspaceId();
        GlobalStates.overviewOpen = true;
    }

    function close() {
        GlobalStates.gallerySwipeFinished(true, 0);
        GlobalStates.overviewOpen = false;
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
        WorkspaceNavigation.commitSelectedWorkspace();
        galleryScope.close();
    }

    function isFocusedScreen(screen) {
        return screen?.name === galleryScope.focusedScreen?.name;
    }

    function updateLiveWindowDrag() {
        if (!CrossMonitorDrag.active)
            return;
        const target = CrossMonitorDrag.hoveredWindowTarget;
        if (!target || target.workspaceId !== CrossMonitorDrag.sourceWorkspaceId) {
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
                visible: GlobalStates.overviewOpen
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore

                WlrLayershell.namespace: "omarchy-workspace-gallery"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: galleryScope.isFocusedScreen(panelWindow.screen)
                    && GlobalStates.overviewOpen
                    ? WlrKeyboardFocus.Exclusive
                    : WlrKeyboardFocus.None

                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }

                Loader {
                    anchors.fill: parent
                    active: GlobalStates.overviewOpen
                    asynchronous: false
                    sourceComponent: GalleryWidget {
                        screen: panelWindow.screen
                    }
                }

                Item {
                    anchors.fill: parent
                    focus: galleryScope.isFocusedScreen(panelWindow.screen)

                    Keys.onPressed: event => {
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
}
