pragma ComponentBehavior: Bound
import "."
import qs.Commons
import QtQuick
import Quickshell
import "ColorUtils.js" as ColorUtils
import "WorkspaceExpose.js" as WorkspaceExpose

Rectangle {
    id: page

    required property var entry
    required property var galleryRoot
    required property var screen
    required property url wallpaperUrl
    property bool interactionEnabled: true
    readonly property var windowAddresses: page.entry
        ? page.galleryRoot.windowAddressesForWorkspace(page.entry.id)
        : []
    readonly property real singleWindowVerticalInset: page.windowAddresses.length === 1
        ? Math.max(12, Math.min(24, page.height * 0.035))
        : 0
    readonly property var windowDescriptors: page.windowAddresses.map(address => {
        const win = ServiceManager.workspace.clientByAddress(address);
        const monitor = ServiceManager.workspace.monitors.find(mon => mon.id === win?.monitor)
            ?? page.galleryRoot.monitorData;
        const logicalWidth = page.galleryRoot.usableLogicalWidth(monitor);
        const logicalHeight = page.galleryRoot.usableLogicalHeight(monitor);
        const relativeX = (win?.at?.[0] ?? 0) - (monitor?.x ?? 0) - (monitor?.reserved?.[0] ?? 0);
        const relativeY = (win?.at?.[1] ?? 0) - (monitor?.y ?? 0) - (monitor?.reserved?.[1] ?? 0);
        return {
            address,
            x: Math.max(0, relativeX / logicalWidth * page.width),
            y: Math.max(0, relativeY / logicalHeight * page.height),
            width: Math.max(1, (win?.size?.[0] ?? logicalWidth * 0.5) / logicalWidth * page.width),
            height: Math.max(1, (win?.size?.[1] ?? logicalHeight * 0.5) / logicalHeight * page.height),
            focusHistoryId: win?.focusHistoryID ?? 1000000
        };
    })
    readonly property var exposeLayout: WorkspaceExpose.buildLayout(
        page.windowDescriptors, page.width, page.height)
    property bool exposeReady: false

    onExposeLayoutChanged: {
        if (page.exposeLayout.enabled)
            exposeStartTimer.restart();
        else
            page.exposeReady = false;
    }

    Component.onCompleted: exposeStartTimer.restart()

    Timer {
        id: exposeStartTimer
        interval: 0
        repeat: false
        onTriggered: page.exposeReady = page.exposeLayout.enabled
    }

    radius: 12
    clip: true
    color: Appearance.colors.colSurfaceContainerLow
    border.width: 2
    border.color: TuiStyle.accent

    Image {
        anchors.fill: parent
        source: page.wallpaperUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        cache: true
        opacity: page.entry?.isTrailingEmpty ? 0.58 : 0.9
    }

    Rectangle {
        anchors.fill: parent
        color: pageDrop.containsDrag
            ? ColorUtils.transparentize(TuiStyle.accent, 0.76)
            : "transparent"
    }

    Repeater {
        model: ScriptModel {
            values: page.windowAddresses
        }
        delegate: GalleryWindow {
            required property string modelData
            readonly property var exposeRect: page.exposeLayout.rects[modelData] ?? null
            address: modelData
            galleryRoot: page.galleryRoot
            screen: page.screen
            sourceWorkspaceId: page.entry?.id ?? -1
            previewX: 0
            previewY: page.singleWindowVerticalInset
            previewWidth: page.width
            previewHeight: Math.max(1, page.height - page.singleWindowVerticalInset * 2)
            layoutOverrideEnabled: page.exposeReady && !!exposeRect
            geometryAnimationEnabled: true
            layoutX: exposeRect?.x ?? localX
            layoutY: exposeRect?.y ?? localY
            layoutWidth: exposeRect?.width ?? targetWindowWidth
            layoutHeight: exposeRect?.height ?? targetWindowHeight
            layoutZ: exposeRect?.z ?? 0
            closeOnActivate: true
            interactionEnabled: page.interactionEnabled
            onActivated: windowData => page.galleryRoot.activateWindow(windowData)
        }
    }

    DropArea {
        id: pageDrop
        anchors.fill: parent
        z: 90
        enabled: page.interactionEnabled
        onEntered: {
            if (!page.entry)
                return;
            WorkspaceNavigation.setDragTarget(
                page.entry.id,
                page.entry.isTrailingEmpty ?? false,
                page.entry.monitorName ?? "");
        }
        onExited: {
            if (page.entry)
                WorkspaceNavigation.clearDragTarget(page.entry.id);
        }
    }

    Connections {
        target: CrossMonitorDrag
        function onActiveChanged() {
            if (CrossMonitorDrag.active && page.entry)
                page.galleryRoot.registerDropTarget(page, page.entry);
        }
    }
}
