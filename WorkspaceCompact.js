function validWorkspaceId(value) {
    const id = Number(value);
    return Number.isInteger(id) && id >= 1 && id <= 100;
}

function buildPlan(clients, workspaces, monitors) {
    const clientsByWorkspace = {};
    for (const client of clients ?? []) {
        const sourceId = Number(client?.workspace?.id);
        if (!validWorkspaceId(sourceId) || !client?.mapped)
            continue;
        const address = String(client?.address ?? "");
        if (address.length === 0)
            continue;
        if (!clientsByWorkspace[sourceId])
            clientsByWorkspace[sourceId] = [];
        clientsByWorkspace[sourceId].push(address);
    }

    const workspaceById = {};
    for (const workspace of workspaces ?? []) {
        const id = Number(workspace?.id);
        if (validWorkspaceId(id))
            workspaceById[id] = workspace;
    }

    const monitorById = {};
    for (const monitor of monitors ?? [])
        monitorById[Number(monitor?.id)] = String(monitor?.name ?? "");

    const sourceIds = Object.keys(clientsByWorkspace)
        .map(Number)
        .sort((a, b) => a - b);
    const mapping = {};
    const moves = [];
    for (let index = 0; index < sourceIds.length; ++index) {
        const sourceId = sourceIds[index];
        const targetId = index + 1;
        mapping[sourceId] = targetId;
        if (sourceId === targetId)
            continue;

        const firstClient = (clients ?? []).find(client =>
            Number(client?.workspace?.id) === sourceId && client?.mapped);
        const monitorName = String(workspaceById[sourceId]?.monitor
            ?? monitorById[Number(firstClient?.monitor)]
            ?? "");
        moves.push({
            sourceId,
            targetId,
            monitorName,
            addresses: clientsByWorkspace[sourceId].slice()
        });
    }

    return { mapping, moves, sourceIds };
}

function remapIds(ids, mapping) {
    const result = [];
    const seen = {};
    for (const rawId of ids ?? []) {
        const id = Number(mapping?.[Number(rawId)] ?? rawId);
        if (!validWorkspaceId(id) || seen[id])
            continue;
        seen[id] = true;
        result.push(id);
    }
    return result;
}

if (typeof module !== "undefined") {
    module.exports = {
        buildPlan,
        remapIds
    };
}
