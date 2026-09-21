pragma ComponentBehavior: Bound
import "."
import QtQuick
import Quickshell.Hyprland
import Quickshell.Wayland

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

        onEntered: root.hovered = true
        onExited: root.hovered = false

        onPositionChanged: mouse => {
            if (!root.pressed)
                return;
            const point = dragArea.mapToItem(null, mouse.x, mouse.y);
            if (Math.abs(point.x - root.pressSceneX) > 8 || Math.abs(point.y - root.pressSceneY) > 8)
                root.movedDuringPress = true;
            CrossMonitorDrag.updatePointer(
                root.galleryRoot.monitorOriginX + point.x,
                root.galleryRoot.monitorOriginY + point.y);
        }

        onPressed: mouse => {
            if (mouse.button !== Qt.LeftButton)
                return;
            root.snapshotPreview();
            WorkspaceNavigation.beginWindowDrag(root.sourceWorkspaceId);
            const point = dragArea.mapToItem(null, mouse.x, mouse.y);
            root.movedDuringPress = false;
            root.pressSceneX = point.x;
            root.pressSceneY = point.y;
            CrossMonitorDrag.begin(
                root.address,
                root.sourceWorkspaceId,
                root.galleryRoot.monitor?.name ?? "",
                root.width,
                root.height,
                root.galleryRoot.monitorOriginX + point.x,
                root.galleryRoot.monitorOriginY + point.y);
            const generation = CrossMonitorDrag.generation;
            root.grabPreview(result => CrossMonitorDrag.setPreview(result, generation));
            root.pressed = true;
            root.Drag.active = true;
            root.Drag.source = root;
            root.Drag.hotSpot.x = mouse.x;
            root.Drag.hotSpot.y = mouse.y;
        }

        onReleased: {
            if (!root.pressed)
                return;
            const targetWorkspace = GlobalStates.overviewDraggingTargetWorkspace;
            const targetIsTrailing = GlobalStates.overviewDraggingTargetIsTrailing;
            const targetMonitor = GlobalStates.overviewDraggingTargetMonitor;
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
                targetMonitor);
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
