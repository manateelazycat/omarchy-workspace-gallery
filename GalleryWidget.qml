pragma ComponentBehavior: Bound
import "."
import qs.Commons
import QtQuick
import Quickshell
import Quickshell.Wayland
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

    function activateWindow(windowData) {
        WorkspaceNavigation.focusWindow(windowData);
        GlobalStates.overviewOpen = false;
    }

    function registerDropTarget(item, entry) {
        const point = item.mapToItem(null, 0, 0);
        CrossMonitorDrag.publishTarget(
            root.monitor?.name ?? "",
            entry?.monitorName ?? "",
            entry?.id ?? -1,
            entry?.isTrailingEmpty ?? false,
            root.monitorOriginX + point.x,
            root.monitorOriginY + point.y,
            item.width,
            item.height);
    }

    onEntriesChanged: {
        if (!root.entries.some(entry => entry.id === root.selectedWorkspaceId)) {
            const fallback = root.entries.find(entry => !entry.isTrailingEmpty) ?? root.entries[0];
            if (fallback)
                root.selectWorkspace(fallback.id);
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

        delegate: Rectangle {
            id: topCard
            required property var modelData
            required property int index
            width: root.topCardWidth
            height: root.topCardHeight
            radius: 10
            clip: true
            color: Appearance.colors.colSurfaceContainerLow
            border.width: modelData.id === root.selectedWorkspaceId ? 3 : 1
            border.color: modelData.id === root.selectedWorkspaceId
                ? TuiStyle.accent
                : ColorUtils.transparentize(TuiStyle.fg, 0.55)

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
                    onActivated: root.selectWorkspace(topCard.modelData.id)
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 8
                width: topLabel.implicitWidth + 14
                height: topLabel.implicitHeight + 8
                radius: height / 2
                color: ColorUtils.transparentize(TuiStyle.bg, 0.18)
                z: 80

                StyledText {
                    id: topLabel
                    anchors.centerIn: parent
                    text: topCard.modelData.isTrailingEmpty ? "+" : `Workspace ${topCard.modelData.id}`
                    color: TuiStyle.fg
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
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

            Connections {
                target: CrossMonitorDrag
                function onActiveChanged() {
                    if (CrossMonitorDrag.active)
                        root.registerDropTarget(topCard, topCard.modelData);
                }
            }
        }
    }

    Rectangle {
        id: bottomCard
        x: root.bottomCardX
        y: root.bottomCardY
        width: root.bottomCardWidth
        height: root.bottomCardHeight
        radius: 12
        clip: true
        color: Appearance.colors.colSurfaceContainerLow
        border.width: 2
        border.color: TuiStyle.accent

        Image {
            anchors.fill: parent
            source: root.wallpaperUrl
            fillMode: Image.PreserveAspectCrop
            asynchronous: false
            cache: true
            opacity: root.selectedEntry?.isTrailingEmpty ? 0.58 : 0.9
        }

        Rectangle {
            anchors.fill: parent
            color: bottomDrop.containsDrag
                ? ColorUtils.transparentize(TuiStyle.accent, 0.76)
                : "transparent"
        }

        Repeater {
            model: ScriptModel {
                values: root.selectedEntry
                    ? root.windowAddressesForWorkspace(root.selectedEntry.id)
                    : []
            }
            delegate: GalleryWindow {
                required property string modelData
                address: modelData
                galleryRoot: root
                screen: root.screen
                sourceWorkspaceId: root.selectedEntry?.id ?? -1
                previewX: 0
                previewY: 0
                previewWidth: bottomCard.width
                previewHeight: bottomCard.height
                closeOnActivate: true
                onActivated: windowData => root.activateWindow(windowData)
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 14
            width: bottomLabel.implicitWidth + 18
            height: bottomLabel.implicitHeight + 10
            radius: height / 2
            color: ColorUtils.transparentize(TuiStyle.bg, 0.16)
            z: 80

            StyledText {
                id: bottomLabel
                anchors.centerIn: parent
                text: root.selectedEntry?.isTrailingEmpty
                    ? "New workspace"
                    : `Workspace ${root.selectedEntry?.id ?? ""}`
                color: TuiStyle.fg
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
            }
        }

        DropArea {
            id: bottomDrop
            anchors.fill: parent
            z: 90
            onEntered: {
                if (!root.selectedEntry)
                    return;
                WorkspaceNavigation.setDragTarget(
                    root.selectedEntry.id,
                    root.selectedEntry.isTrailingEmpty ?? false,
                    root.selectedEntry.monitorName ?? "");
            }
            onExited: {
                if (root.selectedEntry)
                    WorkspaceNavigation.clearDragTarget(root.selectedEntry.id);
            }
        }

        Connections {
            target: CrossMonitorDrag
            function onActiveChanged() {
                if (CrossMonitorDrag.active && root.selectedEntry)
                    root.registerDropTarget(bottomCard, root.selectedEntry);
            }
        }
    }

    Rectangle {
        id: dragProxy
        visible: CrossMonitorDrag.active
        x: CrossMonitorDrag.pointerX - root.monitorOriginX - width / 2
        y: CrossMonitorDrag.pointerY - root.monitorOriginY - height / 2
        width: Math.max(110, CrossMonitorDrag.sourceWidth)
        height: Math.max(72, CrossMonitorDrag.sourceHeight)
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
