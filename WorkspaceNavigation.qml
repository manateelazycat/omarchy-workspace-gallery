pragma Singleton
pragma ComponentBehavior: Bound
import "."

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "WorkspaceSwitchOrder.js" as WorkspaceSwitchOrder

Singleton {
    id: root

    property int pendingDragRefreshes: 0

    Timer {
        id: refreshAfterDragTimer
        interval: 90
        repeat: false
        onTriggered: {
            ServiceManager.workspace.updateAll();
            GlobalStates.refreshOverviewModel();
            root.pendingDragRefreshes -= 1;
            if (root.pendingDragRefreshes > 0)
                refreshAfterDragTimer.restart();
        }
    }
    function overviewModel() {
        if (OverviewSwitchingController.grabbed)
            return switchingModeModel();
        // The keyboard must walk exactly the cards on screen. Without this, in
        // per-monitor mode the arrow keys step onto workspaces belonging to another
        // monitor that this overlay does not draw.
        if (GlobalStates.overviewPerMonitor) {
            const anchor = GlobalStates.overviewAnchorMonitorName
                || Hyprland.focusedMonitor?.name
                || "";
            if (anchor.length > 0) {
                const scoped = ServiceManager.workspace.overviewWorkspaceEntriesForMonitor(anchor, true, {}, true, true);
                if (scoped.length > 0)
                    return scoped;
            }
        }
        return ServiceManager.workspace.overviewWorkspaceEntriesGroupedByMonitor();
    }

    function switchingModeModel() {
        const monitorName = GlobalStates.overviewAnchorMonitorName || Hyprland.focusedMonitor?.name || "";
        let model = ServiceManager.workspace.overviewWorkspaceEntriesForMonitor(monitorName, true, {}, true, false);
        if (model.length === 0)
            model = ServiceManager.workspace.overviewWorkspaceEntriesGlobal(true).filter(entry => !entry.isTrailingEmpty);

        const currentId = root.currentWorkspaceId();
        if (currentId > 0 && !model.some(entry => entry.id === currentId)) {
            const workspace = ServiceManager.workspace.workspaceDataForId(currentId);
            model = model.concat([{
                id: currentId,
                monitorName: workspace?.monitor ?? monitorName,
                monitorIndex: 0,
                monitorLabel: workspace?.monitor ?? monitorName,
                isTrailingEmpty: false
            }]);
        }

        return WorkspaceSwitchOrder.orderedEntries(
            model,
            currentId,
            GlobalStates.overviewPreviousWorkspaceId);
    }

    function gridColumnsForModel(model) {
        return Math.min(Math.max(model.length, 1), Config.options.overview.columns);
    }

    function indexForWorkspace(model, wsId) {
        const idx = model.findIndex(entry => entry.id === wsId);
        return idx >= 0 ? idx : 0;
    }

    function currentWorkspaceId() {
        const anchorName = GlobalStates.overviewOpen ? GlobalStates.overviewAnchorMonitorName : "";
        const monitor = anchorName.length > 0
            ? ServiceManager.workspace.monitors.find(mon => mon.name === anchorName)
            : (Hyprland.focusedMonitor ?? Hyprland.monitors[0]);
        if (!monitor)
            return ServiceManager.workspace.activeWorkspace?.id ?? 1;
        return ServiceManager.workspace.monitorActiveWorkspaceId(monitor) || ServiceManager.workspace.activeWorkspace?.id || 1;
    }

    function focusedWorkspaceId() {
        if (GlobalStates.overviewFocusedWorkspaceId > 0)
            return GlobalStates.overviewFocusedWorkspaceId;
        return root.currentWorkspaceId();
    }

    function selectWorkspace(wsId) {
        if (wsId < 1)
            return;
        GlobalStates.overviewFocusedWorkspaceId = wsId;
    }

    function dispatchFocusWorkspace(wsId) {
        if (wsId < 1)
            return;
        const ws = ServiceManager.workspace.workspaceDataForId(wsId);
        if (ws?.monitor)
            Hyprland.dispatch(`hl.dsp.focus({monitor="${ws.monitor}"})`);
        Hyprland.dispatch(`hl.dsp.focus({ workspace = ${wsId} })`);
    }

    function navigateByIndex(delta, includeTrailing) {
        const allowTrailing = includeTrailing ?? true;
        const model = allowTrailing
            ? root.overviewModel()
            : root.overviewModel().filter(entry => !entry.isTrailingEmpty);
        if (model.length === 0)
            return;

        const ws = root.focusedWorkspaceId();
        let idx = root.indexForWorkspace(model, ws);
        idx = (idx + delta + model.length) % model.length;
        root.selectWorkspace(model[idx].id);
    }

    function navigateGrid(deltaRow, deltaCol) {
        const model = root.overviewModel();
        const n = model.length;
        if (n === 0)
            return;

        const cols = root.gridColumnsForModel(model);
        if (deltaCol !== 0)
            root.navigateByIndex(deltaCol);
        else if (deltaRow !== 0)
            root.navigateByIndex(deltaRow * cols);
    }

    function focusedEntryIsTrailingEmpty() {
        const wsId = root.focusedWorkspaceId();
        if (wsId < 1)
            return false;
        const model = root.overviewModel();
        for (let i = 0; i < model.length; i++) {
            if (model[i].id === wsId)
                return !!model[i].isTrailingEmpty;
        }
        return false;
    }

    function focusedEntry() {
        const wsId = root.focusedWorkspaceId();
        if (wsId < 1)
            return null;
        const model = root.overviewModel();
        for (let i = 0; i < model.length; i++) {
            if (model[i].id === wsId)
                return model[i];
        }
        return null;
    }

    function focusMonitorForEntry(entry) {
        const monitorName = entry?.monitorName ?? "";
        if (monitorName.length > 0)
            Hyprland.dispatch(`hl.dsp.focus({monitor="${monitorName}"})`);
    }

    function commitSelectedWorkspace() {
        if (root.focusedEntryIsTrailingEmpty()) {
            const entry = root.focusedEntry();
            root.focusMonitorForEntry(entry);
            Hyprland.dispatch(`hl.dsp.focus({ workspace = ${entry.id} })`);
            if ((entry?.monitorName ?? "").length > 0)
                Hyprland.dispatch(`hl.dsp.workspace.move({ workspace = "${entry.id}", monitor = "${entry.monitorName}" })`);
            return;
        }

        if (GlobalStates.overviewFocusedWorkspaceId > 0)
            root.dispatchFocusWorkspace(GlobalStates.overviewFocusedWorkspaceId);
    }

    function resetOverviewDragState() {
        GlobalStates.overviewDraggingFromWorkspace = -1;
        GlobalStates.overviewDraggingTargetWorkspace = -1;
        GlobalStates.overviewDraggingTargetIsTrailing = false;
        GlobalStates.overviewDraggingTargetMonitor = "";
    }

    function beginWindowDrag(fromWorkspaceId) {
        GlobalStates.overviewDraggingFromWorkspace = fromWorkspaceId ?? -1;
    }

    function setDragTarget(workspaceId, isTrailing, workspaceMonitorName) {
        GlobalStates.overviewDraggingTargetWorkspace = workspaceId;
        GlobalStates.overviewDraggingTargetIsTrailing = isTrailing;
        GlobalStates.overviewDraggingTargetMonitor = String(workspaceMonitorName ?? "");
    }

    function clearDragTarget(workspaceId) {
        if (GlobalStates.overviewDraggingTargetWorkspace === workspaceId) {
            GlobalStates.overviewDraggingTargetWorkspace = -1;
            GlobalStates.overviewDraggingTargetIsTrailing = false;
            GlobalStates.overviewDraggingTargetMonitor = "";
        }
    }

    function tiledWindowAt(workspaceId, windowAddress, placement) {
        if (!placement || !Number.isFinite(placement.dropX) || !Number.isFinite(placement.dropY))
            return "";

        const sourceAddress = ServiceManager.workspace.normalizeAddress(windowAddress);
        const dropX = Number(placement.dropX);
        const dropY = Number(placement.dropY);
        const clients = ServiceManager.workspace.hyprlandClientsForWorkspace(workspaceId);
        for (let i = clients.length - 1; i >= 0; --i) {
            const client = clients[i];
            const address = ServiceManager.workspace.normalizeAddress(client?.address);
            if (!client?.mapped || client?.hidden || client?.floating || !address || address === sourceAddress)
                continue;
            const x = Number(client.at?.[0]);
            const y = Number(client.at?.[1]);
            const width = Number(client.size?.[0]);
            const height = Number(client.size?.[1]);
            if (![x, y, width, height].every(Number.isFinite))
                continue;
            if (dropX >= x && dropX <= x + width && dropY >= y && dropY <= y + height)
                return address;
        }
        return "";
    }

    function swapTiledWindows(windowAddress, targetAddress, workspaceId, placement) {
        if (!windowAddress || !targetAddress || !placement
                || !Number.isFinite(placement.restoreX) || !Number.isFinite(placement.restoreY))
            return false;
        const activeWorkspaceId = ServiceManager.workspace.activeWorkspace?.id ?? workspaceId;
        const restoreWorkspace = activeWorkspaceId !== workspaceId
            ? `hl.dispatch(hl.dsp.focus({ workspace = ${activeWorkspaceId} }))`
            : "";
        const restoreX = Math.round(placement.restoreX);
        const restoreY = Math.round(placement.restoreY);
        Hyprland.dispatch(`function()
            hl.dispatch(hl.dsp.focus({ window = "address:${windowAddress}" }))
            hl.dispatch(hl.dsp.cursor.move({ x = ${restoreX}, y = ${restoreY} }))
            hl.timer(function()
                hl.dispatch(hl.dsp.window.swap({ target = "address:${targetAddress}" }))
                ${restoreWorkspace}
                hl.dispatch(hl.dsp.cursor.move({ x = ${restoreX}, y = ${restoreY} }))
            end, { timeout = 1, type = "oneshot" })
        end`);
        GlobalStates.refreshOverviewModel();
        root.pendingDragRefreshes = 2;
        refreshAfterDragTimer.restart();
        return true;
    }

    function reorderWindowDrag(windowAddress, workspaceId, placement, previousTargetAddress) {
        const targetAddress = root.tiledWindowAt(workspaceId, windowAddress, placement);
        if (!targetAddress || targetAddress === previousTargetAddress)
            return { address: targetAddress, changed: false };
        return {
            address: targetAddress,
            changed: root.swapTiledWindows(windowAddress, targetAddress, workspaceId, placement)
        };
    }

    function dispatchPlacedWindowMove(windowAddress, currentWorkspaceId, targetWorkspace, placement) {
        const move = `hl.dispatch(hl.dsp.window.move({ workspace = ${targetWorkspace}, follow = false, window = "address:${windowAddress}" }))`;
        if (!placement || !Number.isFinite(placement.dropX) || !Number.isFinite(placement.dropY)) {
            if (targetWorkspace === currentWorkspaceId)
                return false;
            Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${targetWorkspace}, follow = false, window = "address:${windowAddress}" })`);
            return true;
        }

        const dropX = Math.round(placement.dropX);
        const dropY = Math.round(placement.dropY);
        const restoreX = Math.round(placement.restoreX);
        const restoreY = Math.round(placement.restoreY);
        if (targetWorkspace === currentWorkspaceId) {
            const swapTargetAddress = root.tiledWindowAt(targetWorkspace, windowAddress, placement);
            if (swapTargetAddress.length > 0) {
                return root.swapTiledWindows(windowAddress, swapTargetAddress, currentWorkspaceId, placement);
            }

            Hyprland.dispatch(`function()
                hl.dispatch(hl.dsp.window.move({ workspace = "special:workspace-gallery-staging", follow = false, window = "address:${windowAddress}" }))
                hl.timer(function()
                    hl.dispatch(hl.dsp.cursor.move({ x = ${dropX}, y = ${dropY} }))
                    ${move}
                    hl.dispatch(hl.dsp.cursor.move({ x = ${restoreX}, y = ${restoreY} }))
                end, { timeout = 16, type = "oneshot" })
            end`);
            return true;
        }

        Hyprland.dispatch(`function()
            hl.dispatch(hl.dsp.cursor.move({ x = ${dropX}, y = ${dropY} }))
            ${move}
            hl.dispatch(hl.dsp.cursor.move({ x = ${restoreX}, y = ${restoreY} }))
        end`);
        return true;
    }

    function commitWindowDrag(windowAddress, currentWorkspaceId, targetWorkspace, targetIsTrailing, targetMonitorHint, placement, layoutAlreadyCommitted) {
        root.resetOverviewDragState();
        if (!windowAddress || targetWorkspace === -1)
            return false;

        const draggedWindow = ServiceManager.workspace.clientByAddress(windowAddress);
        if (targetWorkspace === currentWorkspaceId && draggedWindow?.floating)
            return false;
        if (targetWorkspace === currentWorkspaceId && layoutAlreadyCommitted) {
            GlobalStates.refreshOverviewModel();
            root.pendingDragRefreshes = 2;
            refreshAfterDragTimer.restart();
            return true;
        }

        const sourceVisibleWindows = ServiceManager.workspace.hyprlandClientsForWorkspace(currentWorkspaceId)
            .filter(win => win.mapped && !win.hidden);
        const sourceIsEmptyAfterMove = targetWorkspace !== currentWorkspaceId
            && sourceVisibleWindows.length <= 1;

        // IDs of trailing cards may repeat per monitor. The caller resolves the
        // owning monitor from the rendered card before reaching this function.
        const targetMonitorName = String(targetMonitorHint ?? "");

        GlobalStates.setPendingWindowWorkspace(windowAddress, targetWorkspace);

        if (targetMonitorName.length > 0) {
            const pending = GlobalStates.overviewPendingWorkspaceMonitorById ?? {};
            const nextPending = Object.assign({}, pending);
            nextPending[targetWorkspace] = targetMonitorName;
            GlobalStates.overviewPendingWorkspaceMonitorById = nextPending;
        }

        if (targetIsTrailing) {
            const pendingOccupied = GlobalStates.overviewPendingOccupiedWorkspaces ?? [];
            const filtered = pendingOccupied.filter(entry => entry?.id !== targetWorkspace);
            filtered.push({
                id: targetWorkspace,
                monitorName: targetMonitorName,
                sourceWorkspaceId: currentWorkspaceId
            });
            GlobalStates.overviewPendingOccupiedWorkspaces = filtered;
            root.dispatchPlacedWindowMove(windowAddress, currentWorkspaceId, targetWorkspace, placement);
            if (targetMonitorName.length > 0)
                Hyprland.dispatch(`hl.dsp.workspace.move({ workspace = "${targetWorkspace}", monitor = "${targetMonitorName}" })`);
        } else {
            if (!root.dispatchPlacedWindowMove(windowAddress, currentWorkspaceId, targetWorkspace, placement))
                return false;
            if (targetMonitorName.length > 0)
                Hyprland.dispatch(`hl.dsp.workspace.move({ workspace = "${targetWorkspace}", monitor = "${targetMonitorName}" })`);
        }

        if (sourceIsEmptyAfterMove) {
            const suppressed = GlobalStates.overviewSuppressedEmptyWorkspaceIds ?? [];
            if (!suppressed.includes(currentWorkspaceId)) {
                const next = suppressed.slice();
                next.push(currentWorkspaceId);
                GlobalStates.overviewSuppressedEmptyWorkspaceIds = next;
            }
        }

        GlobalStates.refreshOverviewModel();
        root.pendingDragRefreshes = 4;
        refreshAfterDragTimer.restart();
        return true;
    }

    function focusWindow(windowData) {
        if (!windowData?.address)
            return;
        if (windowData?.workspace?.id > 0)
            GlobalStates.promoteWorkspaceMru(windowData.workspace.id);
        Hyprland.dispatch(`hl.dsp.focus({window = "address:${windowData.address}"})`);
    }
}
