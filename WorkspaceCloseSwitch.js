function rememberWorkspace(historyByMonitor, monitorName, workspaceId) {
    const name = String(monitorName ?? "");
    const id = Number(workspaceId);
    if (!name || !Number.isInteger(id) || id < 1)
        return historyByMonitor ?? {};
    const history = (historyByMonitor ?? {})[name] ?? [];
    if (history[0] === id)
        return historyByMonitor;
    return Object.assign({}, historyByMonitor, {
        [name]: [id, ...history.filter(previous => previous !== id)].slice(0, 100)
    });
}

function normalizeAddress(address) {
    const value = String(address ?? "").toLowerCase();
    return value && !value.startsWith("0x") ? `0x${value}` : value;
}

function destinationAfterClose(clients, monitors, monitorName, workspaceId, closedAddress, historyByMonitor) {
    const sourceId = Number(workspaceId);
    const name = String(monitorName ?? "");
    const closed = normalizeAddress(closedAddress);
    if (!name || !Number.isInteger(sourceId) || sourceId < 1 || !closed)
        return -1;

    const snapshot = clients ?? [];
    // A close event may precede the clients snapshot. Do not switch on an old one.
    if (snapshot.some(client => normalizeAddress(client?.address) === closed))
        return -1;
    const visible = snapshot.filter(client => client?.mapped && !client?.hidden);
    if (visible.some(client => Number(client?.workspace?.id) === sourceId))
        return -1;

    const monitor = (monitors ?? []).find(item => item?.name === name);
    if (!monitor)
        return -1;
    const occupied = new Set(visible
        .filter(client => Number(client?.monitor) === Number(monitor.id))
        .map(client => Number(client?.workspace?.id))
        .filter(id => Number.isInteger(id) && id > 0 && id !== sourceId));
    if (occupied.size === 0)
        return -1;

    // The monitor's most recently visited occupied workspace gives A-B-A
    // switching. If it became empty, walk older visits before numeric fallback.
    for (const id of (historyByMonitor ?? {})[name] ?? []) {
        if (occupied.has(Number(id)))
            return Number(id);
    }
    const ids = Array.from(occupied).sort((a, b) => a - b);
    return ids.filter(id => id < sourceId).pop() ?? ids[ids.length - 1];
}

if (typeof module !== "undefined") {
    module.exports = { rememberWorkspace, destinationAfterClose };
}
