function mostRecentClientForWorkspace(clients, workspaceId) {
    const targetId = Number(workspaceId);
    if (!Number.isInteger(targetId) || targetId < 1)
        return null;

    const candidates = (clients ?? []).filter(client =>
        Number(client?.workspace?.id) === targetId
            && client?.mapped
            && !client?.hidden
            && String(client?.address ?? "").length > 0);
    if (candidates.length === 0)
        return null;

    return candidates.reduce((best, client) => {
        if (!best)
            return client;
        const bestHistory = Number.isFinite(Number(best.focusHistoryID))
            ? Number(best.focusHistoryID) : Number.MAX_SAFE_INTEGER;
        const clientHistory = Number.isFinite(Number(client.focusHistoryID))
            ? Number(client.focusHistoryID) : Number.MAX_SAFE_INTEGER;
        return clientHistory < bestHistory ? client : best;
    }, null);
}

if (typeof module !== "undefined") {
    module.exports = {
        mostRecentClientForWorkspace
    };
}
