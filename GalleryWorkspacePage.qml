pragma ComponentBehavior: Bound
import "."
import qs.Commons
import QtQuick
import Quickshell
import "ColorUtils.js" as ColorUtils

Rectangle {
    id: page

    required property var entry
    required property var galleryRoot
    required property var screen
    required property url wallpaperUrl
    property bool interactionEnabled: true
    property bool activationEnabled: true
    readonly property var windowAddresses: page.entry
        ? page.galleryRoot.windowAddressesForWorkspace(page.entry.id)
        : []
    readonly property real singleWindowVerticalInset: page.windowAddresses.length === 1
        ? Math.max(12, Math.min(24, page.height * 0.035))
        : 0

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

    MouseArea {
        anchors.fill: parent
        z: 10
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        enabled: page.activationEnabled
        onClicked: {
            if (page.entry)
                page.galleryRoot.activateWorkspace(page.entry.id);
        }
    }

    Repeater {
        model: ScriptModel {
            values: page.windowAddresses
        }
        delegate: GalleryWindow {
            required property string modelData
            address: modelData
            galleryRoot: page.galleryRoot
            screen: page.screen
            sourceWorkspaceId: page.entry?.id ?? -1
            previewX: 0
            previewY: page.singleWindowVerticalInset
            previewWidth: page.width
            previewHeight: Math.max(1, page.height - page.singleWindowVerticalInset * 2)
            closeOnActivate: true
            interactionEnabled: page.interactionEnabled
            onActivated: windowData => page.galleryRoot.activateWindow(windowData, page.entry.id)
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
