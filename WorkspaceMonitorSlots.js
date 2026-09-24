function ownerForEmptyWorkspace(workspaceId, rules, monitors) {
    const id = Number(workspaceId);
    if (!Number.isInteger(id) || id < 1)
        return "";

    let owner = "";
    for (const rule of rules ?? []) {
        const selector = String(rule?.workspaceString ?? "");
        if (rule?.enabled === false || !/^\d+$/.test(selector) || Number(selector) !== id)
            continue;

        const monitorSelector = String(rule?.monitor ?? "");
        if (monitorSelector.length === 0)
            continue;
        const monitor = (monitors ?? []).find(mon => mon?.name === monitorSelector)
            ?? (monitorSelector.startsWith("desc:")
                ? (monitors ?? []).find(mon => String(mon?.description ?? "").startsWith(monitorSelector.slice(5)))
                : null);
        owner = monitor?.name ?? "";
    }
    return owner;
}

if (typeof module !== "undefined") {
    module.exports = { ownerForEmptyWorkspace };
}
