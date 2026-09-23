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
    readonly property string windowDropTargetKey: `${root.galleryRoot.monitor?.name ?? ""}:${root.closeOnActivate ? "large" : "small"}:${root.sourceWorkspaceId}:${root.address}`

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

    function publishWindowDropTarget() {
        if (!CrossMonitorDrag.active || root.width <= 0 || root.height <= 0)
            return;
        const point = root.mapToItem(null, 0, 0);
        CrossMonitorDrag.publishWindowTarget(
            root.windowDropTargetKey,
            root.address,
            root.sourceWorkspaceId,
            root.galleryRoot.monitorOriginX + point.x,
            root.galleryRoot.monitorOriginY + point.y,
            root.width,
            root.height);
    }

    function beginPointerDrag(pointerSceneX, pointerSceneY) {
        if (root.Drag.active)
            return;
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
    z: Drag.active ? 10000 : (root.layoutOverrideEnabled
        ? 30 + root.layoutZ
        : 20 + (root.windowData?.floating ? 2 : 0))

    onLiveWindowDataChanged: {
        if (root.liveWindowData)
            root.cachedWindowData = root.liveWindowData;
    }
    onXChanged: root.publishWindowDropTarget()
    onYChanged: root.publishWindowDropTarget()
    onWidthChanged: root.publishWindowDropTarget()
    onHeightChanged: root.publishWindowDropTarget()

    Connections {
        target: CrossMonitorDrag
        function onActiveChanged() {
            if (CrossMonitorDrag.active)
                root.publishWindowDropTarget();
        }
    }

    Component.onDestruction: CrossMonitorDrag.removeWindowTarget(root.windowDropTargetKey)

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
        preventStealing: true
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

        onReleased: mouse => {
            if (!root.pressed)
                return;
            if (!root.Drag.active) {
                root.pressed = false;
                return;
            }
            const point = dragArea.mapToItem(null, mouse.x, mouse.y);
            CrossMonitorDrag.updatePointer(
                root.galleryRoot.monitorOriginX + point.x,
                root.galleryRoot.monitorOriginY + point.y);
            const dropTarget = CrossMonitorDrag.hoveredTarget;
            const targetWorkspace = dropTarget?.id ?? -1;
            const targetIsTrailing = dropTarget?.isTrailing ?? false;
            const targetMonitor = dropTarget?.workspaceMonitorName ?? "";
            const placement = root.placementForTarget(dropTarget);
            const layoutAlreadyCommitted = CrossMonitorDrag.liveReordered;
            CrossMonitorDrag.end();
            root.pressed = false;
            root.Drag.active = false;
            root.restorePositionBinding();
            WorkspaceNavigation.commitWindowDrag(
                root.address,
                root.sourceWorkspaceId,
                targetWorkspace,
                targetIsTrailing,
                targetMonitor,
                placement,
                layoutAlreadyCommitted);
        }

        onCanceled: {
            root.pressed = false;
            root.Drag.active = false;
            root.restorePositionBinding();
            CrossMonitorDrag.end();
            WorkspaceNavigation.resetOverviewDragState();
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
