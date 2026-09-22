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

// Build a visual timeline for the gaps between occupied workspaces. Empty
// cards leave one-by-one; once the final card in a gap has cleared the row,
// every occupied card to its right shifts left as a group.
function buildAnimationPlan(sourceIds) {
    const occupied = (sourceIds ?? [])
        .map(Number)
        .filter(validWorkspaceId)
        .sort((a, b) => a - b);
    if (occupied.length === 0)
        return { emptyStages: [], shiftStages: [], duration: 0 };

    const occupiedSet = {};
    for (const id of occupied)
        occupiedSet[id] = true;

    const groups = [];
    let group = [];
    for (let id = 1; id < occupied[occupied.length - 1]; ++id) {
        if (!occupiedSet[id]) {
            group.push(id);
        } else if (group.length > 0) {
            groups.push(group);
            group = [];
        }
    }
    if (group.length > 0)
        groups.push(group);

    const emptyDuration = 380;
    const emptyStagger = emptyDuration / 2;
    const shiftDuration = 480;
    const phasePause = 70;
    const emptyStages = [];
    const shiftStages = [];
    let cursor = 0;

    for (const emptyIds of groups) {
        for (let index = 0; index < emptyIds.length; ++index) {
            emptyStages.push({
                workspaceId: emptyIds[index],
                start: cursor + index * emptyStagger,
                duration: emptyDuration
            });
        }
        const shiftStart = cursor + (emptyIds.length - 1) * emptyStagger + emptyDuration;
        shiftStages.push({
            afterWorkspaceId: emptyIds[emptyIds.length - 1],
            slots: emptyIds.length,
            start: shiftStart,
            duration: shiftDuration
        });
        cursor = shiftStart + shiftDuration + phasePause;
    }

    return {
        emptyStages,
        shiftStages,
        duration: Math.max(0, cursor - phasePause)
    };
}

if (typeof module !== "undefined") {
    module.exports = {
        buildPlan,
        buildAnimationPlan,
        remapIds
    };
}
