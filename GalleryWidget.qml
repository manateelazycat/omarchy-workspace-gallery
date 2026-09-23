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

    signal closeRequested(bool commitSelection, int workspaceId, var windowData, string monitorName)
    signal monitorActivated(string monitorName)

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
    readonly property int selectedWorkspaceId: GlobalStates.gallerySelectedWorkspaceByMonitor[root.monitor?.name ?? ""]
        ?? Math.max(1, root.monitor?.activeWorkspace?.id ?? 1)
    readonly property var selectedEntry: root.entries.find(entry => entry.id === root.selectedWorkspaceId)
        ?? root.entries[0]
        ?? null
    readonly property int selectedIndex: Math.max(0,
        root.entries.findIndex(entry => entry.id === root.selectedWorkspaceId))
    readonly property bool ownsGesture: (root.monitor?.name ?? "")
        === GlobalStates.galleryActiveMonitorName

    HoverHandler {
        onHoveredChanged: {
            if (hovered && root.monitor?.name)
                root.monitorActivated(root.monitor.name);
        }
    }

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
    property int clickedWorkspaceId: -1
    property int settleEasingType: Easing.OutCubic
    property var compactionHandoffGrab: null
    property url compactionHandoffUrl: ""
    readonly property bool workspaceInteractionEnabled: !root.swipeActive
        && !root.swipeSettling
        && !GlobalStates.overviewCompactionAnimating
        && !GlobalStates.overviewCompactionSyncing
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

    function clamp01(value) {
        return Math.max(0, Math.min(1, Number(value)));
    }

    function jellyProgress(value) {
        const t = root.clamp01(value);
        // A restrained back-ease: it overshoots once, then settles without the
        // mechanical feel of a plain cubic slide.
        const overshoot = 1.35;
        const shifted = t - 1;
        return 1 + (overshoot + 1) * shifted * shifted * shifted
            + overshoot * shifted * shifted;
    }

    function compactionVisualForWorkspace(workspaceId) {
        const neutral = { x: 0, y: 0, opacity: 1, rotation: 0, xScale: 1, yScale: 1, active: false };
        if (!GlobalStates.overviewCompactionAnimating)
            return neutral;

        const id = Number(workspaceId);
        const elapsed = Number(GlobalStates.overviewCompactionElapsed ?? 0);
        const timeline = GlobalStates.overviewCompactionTimeline
            ?? { emptyStages: [], shiftStages: [] };
        let x = 0;
        let y = 0;
        let opacity = 1;
        let rotation = 0;
        let xScale = 1;
        let yScale = 1;
        let active = false;

        for (const shift of timeline.shiftStages ?? []) {
            if (id <= Number(shift.afterWorkspaceId) || elapsed < Number(shift.start))
                continue;
            const t = root.clamp01((elapsed - Number(shift.start)) / Number(shift.duration));
            x -= Number(shift.slots) * (root.topCardWidth + root.cardGap)
                * root.jellyProgress(t);
            const pulse = Math.sin(Math.PI * t) * 0.045;
            xScale += pulse;
            yScale -= pulse * 0.72;
            active = true;
        }

        const empty = (timeline.emptyStages ?? []).find(stage =>
            Number(stage.workspaceId) === id);
        if (empty && elapsed >= Number(empty.start)) {
            const t = root.clamp01((elapsed - Number(empty.start)) / Number(empty.duration));
            const travel = root.jellyProgress(t);
            x -= root.topCardWidth * 0.24 * travel;
            y -= (root.topCardHeight + 18) * travel;
            rotation = -7 * Math.sin(Math.PI * t);
            const pulse = Math.sin(Math.PI * t);
            xScale += 0.075 * pulse;
            yScale -= 0.055 * pulse;
            opacity = t < 0.72 ? 1 : 1 - root.clamp01((t - 0.72) / 0.28);
            active = true;
        }

        return { x, y, opacity, rotation, xScale, yScale, active };
    }

    function captureCompactionHandoff() {
        topList.grabToImage(result => {
            root.compactionHandoffGrab = result;
            root.compactionHandoffUrl = result.url;
        });
    }

    function selectWorkspace(workspaceId, activateInput = true) {
        if (workspaceId < 1)
            return;
        const monitorName = root.monitor?.name ?? "";
        if (!monitorName || !root.entries.some(entry => entry.id === workspaceId))
            return;
        if (activateInput)
            GlobalStates.galleryActiveMonitorName = monitorName;
        GlobalStates.gallerySelectedWorkspaceByMonitor = Object.assign({},
            GlobalStates.gallerySelectedWorkspaceByMonitor,
            { [monitorName]: workspaceId });
        const index = root.entries.findIndex(entry => entry.id === workspaceId);
        if (index >= 0)
            topList.positionViewAtIndex(index, ListView.Contain);
    }

    function animateToWorkspace(workspaceId) {
        const targetIndex = root.entries.findIndex(entry => entry.id === workspaceId);
        if (targetIndex < 0)
            return;
        root.monitorActivated(root.monitor?.name ?? "");
        if (targetIndex === root.selectedIndex) {
            root.selectWorkspace(workspaceId);
            return;
        }
        if (root.swipeActive
                || GlobalStates.overviewCompactionAnimating
                || GlobalStates.overviewCompactionSyncing)
            return;
        root.clickedWorkspaceId = workspaceId;
        if (root.swipeSettling)
            return;

        const distance = Math.abs(targetIndex - root.selectedIndex);
        root.swipeStartIndex = root.selectedIndex;
        root.settlementIndex = targetIndex;
        root.swipeOffset = 0;
        settleAnimation.to = (root.selectedIndex - targetIndex) * root.pageSpan;
        settleAnimation.duration = Math.min(800, 260 + (distance - 1) * 125);
        root.settleEasingType = Easing.InOutCubic;
        root.swipeSettling = true;
        topList.positionViewAtIndex(targetIndex, ListView.Contain);
        settleAnimation.start();
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
        root.clickedWorkspaceId = -1;
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
        root.settleEasingType = Easing.OutCubic;
        root.swipeSettling = true;
        settleAnimation.start();
    }

    function startStep(delta) {
        if (root.swipeActive || root.swipeSettling || root.entries.length === 0)
            return;
        const targetIndex = root.selectedIndex + (delta > 0 ? 1 : -1);
        if (targetIndex < 0 || targetIndex >= root.entries.length)
            return;
        root.swipeStartIndex = root.selectedIndex;
        root.settlementIndex = targetIndex;
        root.swipeOffset = 0;
        settleAnimation.to = delta > 0 ? -root.pageSpan : root.pageSpan;
        settleAnimation.duration = 260;
        root.settleEasingType = Easing.OutCubic;
        root.swipeSettling = true;
        settleAnimation.start();
    }

    function requestStep(delta) {
        if (!root.ownsGesture)
            return;
        root.clickedWorkspaceId = -1;
        root.startStep(delta);
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
        root.clickedWorkspaceId = -1;
    }

    function activateWorkspace(workspaceId) {
        root.selectWorkspace(workspaceId);
        root.closeRequested(true, workspaceId, null, root.monitor?.name ?? "");
    }

    function activateWindow(windowData, workspaceId) {
        root.selectWorkspace(workspaceId);
        root.closeRequested(true, workspaceId, windowData, root.monitor?.name ?? "");
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
                root.selectWorkspace(fallback.id, false);
        }
    }

    Connections {
        target: GlobalStates
        function onOverviewCompactionHandoffChanged() {
            if (GlobalStates.overviewCompactionHandoff) {
                clearCompactionHandoffTimer.stop();
                root.captureCompactionHandoff();
            } else if (root.compactionHandoffUrl.toString().length > 0) {
                clearCompactionHandoffTimer.restart();
            }
        }
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
        easing.type: root.settleEasingType
        onFinished: root.finishSettlement()
    }

    Timer {
        id: clearCompactionHandoffTimer
        interval: 180
        repeat: false
        onTriggered: {
            root.compactionHandoffUrl = "";
            root.compactionHandoffGrab = null;
        }
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
        Component.onCompleted: topList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
        onCountChanged: topList.positionViewAtIndex(root.selectedIndex, ListView.Contain)

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
            readonly property var compactionVisual:
                root.compactionVisualForWorkspace(topCard.modelData.id)
            opacity: topCard.compactionVisual.opacity
            z: topCard.compactionVisual.active ? 20 + topCard.index : 0
            transform: [
                Translate {
                    x: topCard.compactionVisual.x
                    y: topCard.compactionVisual.y
                },
                Rotation {
                    origin.x: topCard.width / 2
                    origin.y: topCard.height / 2
                    angle: topCard.compactionVisual.rotation
                },
                Scale {
                    origin.x: topCard.width / 2
                    origin.y: topCard.height / 2
                    xScale: topCard.compactionVisual.xScale
                    yScale: topCard.compactionVisual.yScale
                }
            ]

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

            Item {
                id: topWindowLayer
                anchors.fill: parent
                // Preserve the old direct-delegate stacking order. Without an
                // explicit z the animation wrapper sits below the card-wide
                // MouseArea, so that area consumes presses before windows can
                // start their drag.
                z: 20

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
                        onActivated: root.animateToWorkspace(topCard.modelData.id)
                    }
                }
            }

            TapHandler {
                acceptedButtons: Qt.LeftButton
                gesturePolicy: TapHandler.DragThreshold
                onTapped: root.animateToWorkspace(topCard.modelData.id)
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

    Image {
        id: compactionHandoffImage
        x: topList.x
        y: topList.y
        width: topList.width
        height: topList.height
        z: 10000
        source: root.compactionHandoffUrl
        fillMode: Image.Stretch
        smooth: true
        cache: false
        opacity: GlobalStates.overviewCompactionHandoff ? 1 : 0
        visible: source.toString().length > 0 && opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: 140; easing.type: Easing.InOutQuad }
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
                readonly property bool inClickTravelRange: root.clickedWorkspaceId > 0
                    && root.swipeSettling
                    && root.settlementIndex >= 0
                    && index >= Math.min(anchorIndex, root.settlementIndex)
                    && index <= Math.max(anchorIndex, root.settlementIndex)
                x: (index - anchorIndex) * root.pageSpan + root.swipeOffset
                width: bottomViewport.width
                height: bottomViewport.height
                active: inClickTravelRange || Math.abs(index - anchorIndex) <= 1
                asynchronous: false

                sourceComponent: GalleryWorkspacePage {
                    entry: pageLoader.modelData
                    galleryRoot: root
                    screen: root.screen
                    wallpaperUrl: root.wallpaperUrl
                    interactionEnabled: root.workspaceInteractionEnabled
                    activationEnabled: !root.swipeActive
                        && !GlobalStates.overviewCompactionAnimating
                        && !GlobalStates.overviewCompactionSyncing
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
