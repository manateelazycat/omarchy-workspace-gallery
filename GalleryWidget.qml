pragma ComponentBehavior: Bound
import "."
import qs.Commons
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Wayland._ToplevelManagement
import Quickshell.Hyprland
import "ColorUtils.js" as ColorUtils

Item {
    id: root

    required property var screen
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
    readonly property var monitorData: ServiceManager.workspace.monitors.find(m => m.id === root.monitor?.id)
    readonly property real monitorOriginX: root.monitorData?.x ?? 0
    readonly property real monitorOriginY: root.monitorData?.y ?? 0
    readonly property int modelRevision: ServiceManager.workspace.dataSerial
        + GlobalStates.overviewRefreshSerial
        + (ToplevelManager.toplevels.values?.length ?? 0)
    readonly property url wallpaperUrl: Wallpaper.readyUrl !== ""
        ? Wallpaper.readyUrl : Wallpaper.requestedUrl
    readonly property var entries: {
        const revision = root.modelRevision;
        void revision;
        const name = root.monitor?.name ?? "";
        const scoped = ServiceManager.workspace.overviewWorkspaceEntriesForMonitor(
            name, true, {}, true, true) ?? [];
        return scoped.length > 0
            ? scoped
            : (ServiceManager.workspace.overviewWorkspaceEntries ?? []);
    }
    readonly property var entryIds: root.entries.map(entry => entry.id)
    readonly property int selectedWorkspaceId: GlobalStates.overviewFocusedWorkspaceId > 0
        ? GlobalStates.overviewFocusedWorkspaceId
        : Math.max(1, root.monitor?.activeWorkspace?.id ?? 1)
    readonly property var selectedEntry: root.entries.find(entry => entry.id === root.selectedWorkspaceId)
        ?? root.entries[0]
        ?? null
    readonly property int selectedIndex: Math.max(0,
        root.entries.findIndex(entry => entry.id === root.selectedWorkspaceId))
    readonly property bool ownsGesture: (root.monitor?.name ?? "")
        === GlobalStates.overviewAnchorMonitorName

    readonly property real topHeight: height * 0.20
    readonly property real bottomY: topHeight
    readonly property real bottomHeight: height * 0.80
    readonly property real cardGap: 14
    readonly property real topCardHeight: Math.max(92, topHeight - 34)
    readonly property real topCardWidth: topCardHeight * usableLogicalWidth(root.monitorData)
        / Math.max(1, usableLogicalHeight(root.monitorData))
    readonly property real bottomMargin: 22
    readonly property real bottomCardX: bottomMargin
    readonly property real bottomCardY: bottomY + 12
    readonly property real bottomCardWidth: width - bottomMargin * 2
    readonly property real bottomCardHeight: Math.max(1, height - bottomCardY - bottomMargin)
    readonly property real pageGap: 24
    readonly property real pageSpan: bottomCardWidth + pageGap
    property real swipeOffset: 0
    property bool swipeActive: false
    property bool swipeSettling: false
    property real swipeVelocity: 0
    property real lastSwipeTimestamp: 0
    property int swipeStartIndex: -1
    property int settlementIndex: -1
    readonly property bool workspaceInteractionEnabled: !root.swipeActive && !root.swipeSettling
    readonly property int swipePreviewIndex: {
        if (root.swipeSettling && root.settlementIndex >= 0)
            return root.settlementIndex;
        if (!root.swipeActive || root.swipeStartIndex < 0 || Math.abs(root.swipeOffset) < 4)
            return root.selectedIndex;
        const candidate = root.swipeStartIndex + (root.swipeOffset < 0 ? 1 : -1);
        return candidate >= 0 && candidate < root.entries.length
            ? candidate : root.swipeStartIndex;
    }
    readonly property int highlightedWorkspaceId: root.entries[root.swipePreviewIndex]?.id
        ?? root.selectedWorkspaceId

    function usableLogicalWidth(mon) {
        const transform = mon?.transform ?? 0;
        const physical = (transform & 1) ? (mon?.height ?? root.screen.width) : (mon?.width ?? root.screen.width);
        const scale = Math.max(0.01, mon?.scale ?? 1);
        return Math.max(1, physical / scale - (mon?.reserved?.[0] ?? 0) - (mon?.reserved?.[2] ?? 0));
    }

    function usableLogicalHeight(mon) {
        const transform = mon?.transform ?? 0;
        const physical = (transform & 1) ? (mon?.width ?? root.screen.height) : (mon?.height ?? root.screen.height);
        const scale = Math.max(0.01, mon?.scale ?? 1);
        return Math.max(1, physical / scale - (mon?.reserved?.[1] ?? 0) - (mon?.reserved?.[3] ?? 0));
    }

    function effectiveWorkspaceId(win, address) {
        const pending = GlobalStates.overviewPendingWindowWorkspaceByAddress ?? {};
        return Number(pending[address] ?? pending[ServiceManager.workspace.normalizeAddress(address)]
            ?? win?.workspace?.id ?? -1);
    }

    function windowAddressesForWorkspace(workspaceId) {
        const revision = root.modelRevision;
        const pending = GlobalStates.overviewPendingWindowWorkspaceByAddress;
        void revision; void pending;
        return ToplevelManager.toplevels.values.map(toplevel => {
            const address = ServiceManager.workspace.normalizeAddress(toplevel.HyprlandToplevel?.address);
            const win = ServiceManager.workspace.clientByAddress(address);
            if (!win?.mapped || win?.hidden)
                return "";
            return root.effectiveWorkspaceId(win, address) === workspaceId ? address : "";
        }).filter(address => address.length > 0);
    }

    function selectWorkspace(workspaceId) {
        if (workspaceId < 1)
            return;
        GlobalStates.overviewFocusedWorkspaceId = workspaceId;
        const index = root.entries.findIndex(entry => entry.id === workspaceId);
        if (index >= 0)
            topList.positionViewAtIndex(index, ListView.Contain);
    }

    function navigate(delta) {
        if (root.entries.length === 0)
            return;
        let index = root.entries.findIndex(entry => entry.id === root.selectedWorkspaceId);
        if (index < 0)
            index = 0;
        index = (index + delta + root.entries.length) % root.entries.length;
        root.selectWorkspace(root.entries[index].id);
    }

    function beginSwipe(deltaX, timestamp) {
        if (!root.ownsGesture || root.swipeSettling || root.entries.length === 0)
            return;
        settleAnimation.stop();
        root.swipeActive = true;
        root.swipeStartIndex = root.selectedIndex;
        root.swipeOffset = 0;
        root.swipeVelocity = 0;
        root.lastSwipeTimestamp = timestamp;
        root.applySwipeDelta(deltaX, timestamp);
    }

    function applySwipeDelta(deltaX, timestamp) {
        if (!root.ownsGesture || !root.swipeActive || root.swipeSettling)
            return;
        const scaledDelta = Number(deltaX) * 3.2;
        const elapsed = Math.max(1, Number(timestamp) - root.lastSwipeTimestamp);
        const instantaneousVelocity = scaledDelta / elapsed;
        root.swipeVelocity = root.swipeVelocity * 0.72 + instantaneousVelocity * 0.28;
        root.lastSwipeTimestamp = Number(timestamp);

        let nextOffset = root.swipeOffset + scaledDelta;
        const movingToPrevious = nextOffset > 0;
        const targetIndex = root.swipeStartIndex + (movingToPrevious ? -1 : 1);
        if (targetIndex < 0 || targetIndex >= root.entries.length)
            nextOffset = nextOffset * 0.28;
        root.swipeOffset = Math.max(-root.pageSpan * 1.04,
            Math.min(root.pageSpan * 1.04, nextOffset));
        if (targetIndex >= 0 && targetIndex < root.entries.length)
            topList.positionViewAtIndex(targetIndex, ListView.Contain);
    }

    function endSwipe(cancelled) {
        if (!root.ownsGesture || !root.swipeActive)
            return;
        root.swipeActive = false;
        const direction = root.swipeOffset < 0 ? 1 : -1;
        const targetIndex = root.swipeStartIndex + direction;
        const targetExists = targetIndex >= 0 && targetIndex < root.entries.length;
        const passedDistance = Math.abs(root.swipeOffset) >= root.bottomCardWidth * 0.22;
        const passedVelocity = Math.abs(root.swipeVelocity) >= 0.58
            && Math.sign(root.swipeVelocity) === Math.sign(root.swipeOffset);
        const commit = !cancelled && targetExists && (passedDistance || passedVelocity);

        root.settlementIndex = commit ? targetIndex : root.swipeStartIndex;
        if (root.settlementIndex >= 0)
            topList.positionViewAtIndex(root.settlementIndex, ListView.Contain);
        settleAnimation.to = commit ? -direction * root.pageSpan : 0;
        settleAnimation.duration = commit ? 230 : 200;
        root.swipeSettling = true;
        settleAnimation.start();
    }

    function requestStep(delta) {
        if (!root.ownsGesture || root.swipeActive || root.swipeSettling || root.entries.length === 0)
            return;
        const targetIndex = root.selectedIndex + (delta > 0 ? 1 : -1);
        if (targetIndex < 0 || targetIndex >= root.entries.length)
            return;
        root.swipeStartIndex = root.selectedIndex;
        root.settlementIndex = targetIndex;
        root.swipeOffset = 0;
        settleAnimation.to = delta > 0 ? -root.pageSpan : root.pageSpan;
        settleAnimation.duration = 260;
        root.swipeSettling = true;
        settleAnimation.start();
    }

    function finishSettlement() {
        if (root.settlementIndex >= 0 && root.settlementIndex < root.entries.length
                && root.settlementIndex !== root.selectedIndex)
            root.selectWorkspace(root.entries[root.settlementIndex].id);
        root.swipeOffset = 0;
        root.swipeVelocity = 0;
        root.swipeStartIndex = -1;
        root.settlementIndex = -1;
        root.swipeSettling = false;
    }

    function activateWindow(windowData) {
        WorkspaceNavigation.focusWindow(windowData);
        GlobalStates.overviewOpen = false;
    }

    function registerDropTarget(item, entry) {
        const point = item.mapToItem(null, 0, 0);
        const targetMonitor = ServiceManager.workspace.monitors.find(
            monitor => monitor.name === (entry?.monitorName ?? "")) ?? root.monitorData;
        const reserved = targetMonitor?.reserved ?? [0, 0, 0, 0];
        CrossMonitorDrag.publishTarget(
            root.monitor?.name ?? "",
            entry?.monitorName ?? "",
            entry?.id ?? -1,
            entry?.isTrailingEmpty ?? false,
            root.monitorOriginX + point.x,
            root.monitorOriginY + point.y,
            item.width,
            item.height,
            (targetMonitor?.x ?? root.monitorOriginX) + (reserved[0] ?? 0),
            (targetMonitor?.y ?? root.monitorOriginY) + (reserved[1] ?? 0),
            root.usableLogicalWidth(targetMonitor),
            root.usableLogicalHeight(targetMonitor));
    }

    onEntriesChanged: {
        if (!root.entries.some(entry => entry.id === root.selectedWorkspaceId)) {
            const fallback = root.entries.find(entry => !entry.isTrailingEmpty) ?? root.entries[0];
            if (fallback)
                root.selectWorkspace(fallback.id);
        }
    }

    Connections {
        target: GlobalStates
        function onGallerySwipeStarted(deltaX, timestamp) {
            root.beginSwipe(deltaX, timestamp);
        }
        function onGallerySwipeUpdated(deltaX, timestamp) {
            root.applySwipeDelta(deltaX, timestamp);
        }
        function onGallerySwipeFinished(cancelled, timestamp) {
            void timestamp;
            root.endSwipe(cancelled);
        }
        function onGalleryStepRequested(delta) {
            root.requestStep(delta);
        }
    }

    NumberAnimation {
        id: settleAnimation
        target: root
        property: "swipeOffset"
        easing.type: Easing.OutCubic
        onFinished: root.finishSettlement()
    }

    Rectangle {
        anchors.fill: parent
        color: ColorUtils.transparentize(TuiStyle.bg, 0.06)
    }

    Rectangle {
        x: 0
        y: 0
        width: parent.width
        height: root.topHeight
        color: ColorUtils.transparentize(Appearance.colors.colSurfaceContainer, 0.08)
        border.width: 0
    }

    ListView {
        id: topList
        x: root.cardGap
        y: 12
        width: root.width - root.cardGap * 2
        height: root.topCardHeight
        orientation: ListView.Horizontal
        spacing: root.cardGap
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.entries

        delegate: Rectangle {
            id: topCard
            required property var modelData
            required property int index
            width: root.topCardWidth
            height: root.topCardHeight
            radius: 10
            clip: true
            color: Appearance.colors.colSurfaceContainerLow
            border.width: 0

            Image {
                anchors.fill: parent
                source: root.wallpaperUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: false
                cache: true
                opacity: topCard.modelData.isTrailingEmpty ? 0.55 : 0.82
            }

            Rectangle {
                anchors.fill: parent
                color: topDrop.containsDrag
                    ? ColorUtils.transparentize(TuiStyle.accent, 0.72)
                    : "transparent"
            }

            Repeater {
                model: ScriptModel { values: root.windowAddressesForWorkspace(topCard.modelData.id) }
                delegate: GalleryWindow {
                    required property string modelData
                    address: modelData
                    galleryRoot: root
                    screen: root.screen
                    sourceWorkspaceId: topCard.modelData.id
                    previewX: 0
                    previewY: 0
                    previewWidth: topCard.width
                    previewHeight: topCard.height
                    closeOnActivate: false
                    interactionEnabled: root.workspaceInteractionEnabled
                    onActivated: root.selectWorkspace(topCard.modelData.id)
                }
            }

            MouseArea {
                anchors.fill: parent
                z: 10
                onClicked: root.selectWorkspace(topCard.modelData.id)
            }

            DropArea {
                id: topDrop
                anchors.fill: parent
                z: 90
                onEntered: {
                    WorkspaceNavigation.setDragTarget(
                        topCard.modelData.id,
                        topCard.modelData.isTrailingEmpty ?? false,
                        topCard.modelData.monitorName ?? "");
                }
                onExited: WorkspaceNavigation.clearDragTarget(topCard.modelData.id)
            }

            Rectangle {
                anchors.fill: parent
                radius: 0
                color: "transparent"
                border.width: topCard.modelData.id === root.highlightedWorkspaceId ? 4 : 1
                border.color: topCard.modelData.id === root.highlightedWorkspaceId
                    ? TuiStyle.accent
                    : ColorUtils.transparentize(TuiStyle.fg, 0.55)
                z: 100
            }

            Connections {
                target: CrossMonitorDrag
                function onActiveChanged() {
                    if (CrossMonitorDrag.active)
                        root.registerDropTarget(topCard, topCard.modelData);
                }
            }
        }
    }

    Item {
        id: bottomViewport
        x: root.bottomCardX
        y: root.bottomCardY
        width: root.bottomCardWidth
        height: root.bottomCardHeight
        clip: true

        Repeater {
            model: root.entries
            delegate: Loader {
                id: pageLoader
                required property var modelData
                required property int index
                readonly property int anchorIndex: root.swipeStartIndex >= 0
                    ? root.swipeStartIndex : root.selectedIndex
                x: (index - anchorIndex) * root.pageSpan + root.swipeOffset
                width: bottomViewport.width
                height: bottomViewport.height
                active: Math.abs(index - anchorIndex) <= 1
                asynchronous: false

                sourceComponent: GalleryWorkspacePage {
                    entry: pageLoader.modelData
                    galleryRoot: root
                    screen: root.screen
                    wallpaperUrl: root.wallpaperUrl
                    interactionEnabled: root.workspaceInteractionEnabled
                }
            }
        }
    }

    Rectangle {
        id: dragProxy
        visible: CrossMonitorDrag.active
        x: CrossMonitorDrag.pointerX - root.monitorOriginX - width / 2
        y: CrossMonitorDrag.pointerY - root.monitorOriginY - height / 2
        width: CrossMonitorDrag.compactPreview
            ? Math.max(1, CrossMonitorDrag.sourceWidth / 3)
            : Math.max(110, CrossMonitorDrag.sourceWidth)
        height: CrossMonitorDrag.compactPreview
            ? Math.max(1, CrossMonitorDrag.sourceHeight / 3)
            : Math.max(72, CrossMonitorDrag.sourceHeight)
        z: 20000
        radius: 8
        color: Appearance.colors.colSurfaceContainerLow
        border.width: 2
        border.color: TuiStyle.accent
        opacity: 0.9

        Image {
            anchors.fill: parent
            anchors.margins: 2
            source: CrossMonitorDrag.previewUrl
            fillMode: Image.PreserveAspectCrop
            smooth: true
            cache: false
        }
    }
}
