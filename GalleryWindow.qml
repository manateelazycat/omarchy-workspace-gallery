pragma ComponentBehavior: Bound
import "."
import QtQuick
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Wayland._ToplevelManagement

OverviewWindow {
    id: root

    required property string address
    required property var galleryRoot
    required property var screen
    required property int sourceWorkspaceId
    required property real previewX
    required property real previewY
    required property real previewWidth
    required property real previewHeight
    required property bool closeOnActivate
    property bool interactionEnabled: true

    signal activated(var windowData)

    property var liveWindowData: ServiceManager.workspace.clientByAddress(root.address)
    property var cachedWindowData: null
    property var modelToplevel: {
        const values = ToplevelManager.toplevels.values;
        for (let i = 0; i < values.length; ++i) {
            if (ServiceManager.workspace.normalizeAddress(values[i].HyprlandToplevel?.address) === root.address)
                return values[i];
        }
        return null;
    }
    property int monitorId: root.windowData?.monitor ?? -1
    property var sourceMonitor: ServiceManager.workspace.monitors.find(m => m.id === root.monitorId)
    property bool movedDuringPress: false
    property real pressSceneX: 0
    property real pressSceneY: 0
    property real pressLocalX: 0
    property real pressLocalY: 0
    property bool liveReordered: false
    property string liveSwapTargetAddress: ""

    function placementForTarget(dropTarget) {
        if (!dropTarget || dropTarget.w <= 0 || dropTarget.h <= 0
                || dropTarget.workW <= 0 || dropTarget.workH <= 0)
            return null;
        const normalizedX = Math.max(0, Math.min(1,
            (CrossMonitorDrag.pointerX - dropTarget.x) / dropTarget.w));
        const normalizedY = Math.max(0, Math.min(1,
            (CrossMonitorDrag.pointerY - dropTarget.y) / dropTarget.h));
        return {
            dropX: dropTarget.workX + normalizedX * dropTarget.workW,
            dropY: dropTarget.workY + normalizedY * dropTarget.workH,
            restoreX: CrossMonitorDrag.pointerX,
            restoreY: CrossMonitorDrag.pointerY
        };
    }

    function updateLiveLayout() {
        const dropTarget = CrossMonitorDrag.hoveredTarget;
        if (!dropTarget || dropTarget.id !== root.sourceWorkspaceId) {
            root.liveSwapTargetAddress = "";
            return;
        }
        const placement = root.placementForTarget(dropTarget);
        const result = WorkspaceNavigation.reorderWindowDrag(
            root.address,
            root.sourceWorkspaceId,
            placement,
            root.liveSwapTargetAddress);
        root.liveSwapTargetAddress = result.address;
        if (result.changed)
            root.liveReordered = true;
    }

    function beginPointerDrag(pointerSceneX, pointerSceneY) {
        if (root.Drag.active)
            return;
        root.liveReordered = false;
        root.liveSwapTargetAddress = "";
        root.snapshotPreview();
        WorkspaceNavigation.beginWindowDrag(root.sourceWorkspaceId);
        CrossMonitorDrag.begin(
            root.address,
            root.sourceWorkspaceId,
            root.galleryRoot.monitor?.name ?? "",
            root.width,
            root.height,
            root.galleryRoot.monitorOriginX + pointerSceneX,
            root.galleryRoot.monitorOriginY + pointerSceneY,
            root.closeOnActivate);
        const generation = CrossMonitorDrag.generation;
        root.grabPreview(result => CrossMonitorDrag.setPreview(result, generation));
        root.movedDuringPress = true;
        root.Drag.active = true;
        root.Drag.source = root;
        root.Drag.hotSpot.x = root.pressLocalX;
        root.Drag.hotSpot.y = root.pressLocalY;
    }

    toplevel: root.modelToplevel
    captureActive: GlobalStates.overviewOpen
    monitorData: root.sourceMonitor
    widgetMonitor: root.galleryRoot.monitorData
    windowData: root.liveWindowData ?? root.cachedWindowData
    visible: !!root.windowData && root.windowData.mapped && !root.windowData.hidden
    xOffset: root.previewX
    yOffset: root.previewY
    workspaceWidth: root.previewWidth
    workspaceHeight: root.previewHeight
    scaleX: root.previewWidth / Math.max(1, root.galleryRoot.usableLogicalWidth(root.sourceMonitor))
    scaleY: root.previewHeight / Math.max(1, root.galleryRoot.usableLogicalHeight(root.sourceMonitor))
    scale: Math.min(scaleX, scaleY)
    opacity: root.Drag.active && root.closeOnActivate
        ? 0
        : (root.anyPreviewContent || root.showingFreeze || root.captureAttempt >= 8 ? 1 : 0)
    topLeftRadius: 5
    topRightRadius: 5
    bottomLeftRadius: 5
    bottomRightRadius: 5
    z: Drag.active ? 10000 : 20 + (root.windowData?.floating ? 2 : 0)

    onLiveWindowDataChanged: {
        if (root.liveWindowData)
            root.cachedWindowData = root.liveWindowData;
    }

    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: height / 2

    MouseArea {
        id: dragArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        drag.target: parent
        drag.threshold: 8
        enabled: root.interactionEnabled

        onEntered: root.hovered = true
        onExited: root.hovered = false

        onPositionChanged: mouse => {
            if (!root.pressed)
                return;
            const point = dragArea.mapToItem(null, mouse.x, mouse.y);
            if (!root.Drag.active
                    && (Math.abs(point.x - root.pressSceneX) > dragArea.drag.threshold
                        || Math.abs(point.y - root.pressSceneY) > dragArea.drag.threshold))
                root.beginPointerDrag(point.x, point.y);
            if (!root.Drag.active)
                return;
            CrossMonitorDrag.updatePointer(
                root.galleryRoot.monitorOriginX + point.x,
                root.galleryRoot.monitorOriginY + point.y);
            root.updateLiveLayout();
        }

        onPressed: mouse => {
            if (mouse.button !== Qt.LeftButton)
                return;
            const point = dragArea.mapToItem(null, mouse.x, mouse.y);
            root.movedDuringPress = false;
            root.pressSceneX = point.x;
            root.pressSceneY = point.y;
            root.pressLocalX = mouse.x;
            root.pressLocalY = mouse.y;
            root.pressed = true;
        }

        onReleased: {
            if (!root.pressed)
                return;
            if (!root.Drag.active) {
                root.pressed = false;
                return;
            }
            const dropTarget = CrossMonitorDrag.hoveredTarget;
            const targetWorkspace = dropTarget?.id
                ?? GlobalStates.overviewDraggingTargetWorkspace;
            const targetIsTrailing = dropTarget?.isTrailing
                ?? GlobalStates.overviewDraggingTargetIsTrailing;
            const targetMonitor = dropTarget?.workspaceMonitorName
                ?? GlobalStates.overviewDraggingTargetMonitor;
            const placement = root.placementForTarget(dropTarget);
            const layoutAlreadyCommitted = root.liveReordered;
            CrossMonitorDrag.end();
            root.pressed = false;
            root.Drag.active = false;
            root.x = Qt.binding(() => root.xOffset + root.localX);
            root.y = Qt.binding(() => root.yOffset + root.localY);
            WorkspaceNavigation.commitWindowDrag(
                root.address,
                root.sourceWorkspaceId,
                targetWorkspace,
                targetIsTrailing,
                targetMonitor,
                placement,
                layoutAlreadyCommitted);
            root.liveReordered = false;
            root.liveSwapTargetAddress = "";
        }

        onClicked: event => {
            if (!root.windowData)
                return;
            if (root.movedDuringPress) {
                event.accepted = true;
                return;
            }
            if (event.button === Qt.MiddleButton) {
                Hyprland.dispatch(`hl.dsp.window.close({window = "address:${root.address}"})`);
                event.accepted = true;
                return;
            }
            if (event.button === Qt.LeftButton && !root.Drag.active) {
                root.activated(root.windowData);
                event.accepted = true;
            }
        }
    }
}
