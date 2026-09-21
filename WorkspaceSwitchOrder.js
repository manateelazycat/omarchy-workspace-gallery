function regularEntries(entries) {
    return (entries ?? [])
        .filter(entry => entry && !entry.isTrailingEmpty)
        .slice()
        .sort((a, b) => Number(a.id) - Number(b.id));
}

function trailingEntries(entries) {
    return (entries ?? []).filter(entry => entry && entry.isTrailingEmpty);
}

function pushUnique(target, seen, entry) {
    if (!entry)
        return;
    const id = Number(entry.id);
    if (id < 1 || seen[id])
        return;
    seen[id] = true;
    target.push(entry);
}

function orderedEntries(entries, currentWorkspaceId, previousWorkspaceId) {
    const regular = regularEntries(entries);
    const trailing = trailingEntries(entries);
    if (regular.length === 0)
        return trailing;

    const byId = {};
    for (const entry of regular)
        byId[Number(entry.id)] = entry;

    const currentId = Number(currentWorkspaceId);
    const previousId = Number(previousWorkspaceId);
    const current = byId[currentId] ?? regular[0];
    let preferred = previousId !== currentId ? byId[previousId] : null;

    if (!preferred) {
        preferred = regular.find(entry => Number(entry.id) > Number(current.id))
            ?? regular.find(entry => Number(entry.id) !== Number(current.id))
            ?? null;
    }

    const ordered = [];
    const seen = {};
    pushUnique(ordered, seen, current);
    pushUnique(ordered, seen, preferred);
    for (const entry of regular)
        pushUnique(ordered, seen, entry);
    for (const entry of trailing)
        pushUnique(ordered, seen, entry);
    return ordered;
}

if (typeof module !== "undefined") {
    module.exports = {
        orderedEntries
    };
}
