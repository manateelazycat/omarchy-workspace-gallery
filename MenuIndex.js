// Searchable index of Omarchy's command menu (the Super+Space one).
//
// Self-contained implementation. It deliberately does NOT import
// /usr/share/omarchy/shell/plugins/menu/MenuModel.js: QML resolves JS imports
// statically, Omarchy resolves its prefix from $OMARCHY_PATH, and on NixOS that
// is not /usr/share/omarchy -- so a fixed path would fail to load the entire
// plugin instead of degrading the search.
//
// It covers only what searching executable actions needs. Everything required to
// *navigate* the menu is intentionally left out: providers, app rows, alias
// routes and the `checked` marker.


// ── JSONC parsing ──────────────────────────────────────────────────────────

function stripJsonc(raw) {
    return String(raw || "")
        .replace(/^\s*\/\/[^\n]*(\n|$)/gm, "")
        .replace(/,(\s*[}\]])/g, "$1");
}

function normalizeAliases(value) {
    if (Array.isArray(value))
        return value.filter(function (v) { return v; });
    if (typeof value === "string" && value)
        return [value];
    return [];
}

// Dotted ids define the hierarchy: trigger.share.file belongs under
// trigger.share. Kind is inferred: action -> action, target -> link, otherwise
// a submenu.
function normalizeItem(id, raw) {
    var value = raw || {};
    var parent = value.parent;
    if (parent === undefined)
        parent = id.indexOf(".") >= 0 ? id.split(".").slice(0, -1).join(".") : "root";
    if (id === "root")
        parent = "";

    return {
        id: id,
        parent: parent,
        kind: value.action ? "action" : (value.target ? "link" : "menu"),
        label: value.label || id,
        description: value.description || "",
        action: value.action || "",
        aliases: normalizeAliases(value.aliases),
        when: value.when || ""
    };
}

function parseMenuJsonc(raw) {
    var stripped = stripJsonc(raw);
    if (!stripped.trim())
        return [];

    var parsed;
    try {
        parsed = JSON.parse(stripped);
    } catch (e) {
        return [];
    }
    if (typeof parsed !== "object" || parsed === null)
        return [];

    var source = (parsed.items && typeof parsed.items === "object" && !Array.isArray(parsed.items))
        ? parsed.items
        : parsed;

    var out = [];
    for (var id in source) {
        var entry = source[id];
        if (!entry || typeof entry !== "object" || Array.isArray(entry))
            continue;
        out.push(normalizeItem(id, entry));
    }
    return out;
}

// The user's jsonc overrides the default by id. Returns fresh objects rather
// than writing into the ones it is handed: those live in QML `var` properties,
// where the engine occasionally drops an in-place write.
function mergeMenuSources(defaultItems, userItems) {
    var items = {};
    var order = [];
    var sources = [defaultItems || [], userItems || []];

    for (var s = 0; s < sources.length; s++) {
        var list = sources[s];
        for (var i = 0; i < list.length; i++) {
            var entry = list[i];
            if (!entry || !entry.id)
                continue;
            if (!items[entry.id])
                order.push(entry.id);
            var prior = items[entry.id] || {};
            var merged = {};
            for (var a in prior)
                merged[a] = prior[a];
            for (var b in entry)
                merged[b] = entry[b];
            merged.id = entry.id;
            items[entry.id] = merged;
        }
    }
    for (var k = 0; k < order.length; k++)
        items[order[k]].order = k;

    return { items: items, itemOrder: order };
}

function item(items, id) {
    return items && items[id] ? items[id] : null;
}

// ── Hierarchy ──────────────────────────────────────────────────────────────

function depthFor(items, id) {
    var depth = 0;
    var current = item(items, id);
    var guard = 0;
    while (current && current.parent && current.parent !== "root" && guard < 32) {
        depth += 1;
        current = item(items, current.parent);
        guard += 1;
    }
    return depth;
}

function pathFor(items, id) {
    var labels = [];
    var current = item(items, id);
    var guard = 0;
    while (current && current.id !== "root" && guard < 32) {
        labels.unshift(current.label);
        current = item(items, current.parent);
        guard += 1;
    }
    return labels.join(" › ");
}

function parentPathFor(items, id) {
    var entry = item(items, id);
    if (!entry || !entry.parent || entry.parent === "root")
        return "";
    return pathFor(items, entry.parent);
}

// ── Matching ───────────────────────────────────────────────────────────────

function searchableToken(value) {
    return String(value || "").replace(/[._-]+/g, " ");
}

function leafIdFor(id) {
    var parts = String(id || "").split(".");
    return parts.length > 0 ? parts[parts.length - 1] : id;
}

function nameSearchText(entry) {
    if (!entry)
        return "";
    var aliases = [];
    var values = Array.isArray(entry.aliases) ? entry.aliases : [];
    for (var i = 0; i < values.length; i++)
        aliases.push(searchableToken(values[i]));
    return [entry.label, searchableToken(leafIdFor(entry.id)), aliases.join(" ")].join(" ").toLowerCase();
}

function termInSearchWords(term, text) {
    var words = String(text || "").toLowerCase().split(/\s+/);
    for (var i = 0; i < words.length; i++) {
        if (words[i] === term)
            return true;
    }
    return false;
}

// Every term must appear in the name, or as a whole word of the description. A
// bare substring of the description is not enough: "in" should not pull in
// everything that says "install".
function matchesQuery(entry, query) {
    if (!entry || entry.id === "root")
        return false;

    var nameText = nameSearchText(entry);
    var descriptionText = String(entry.description || "").toLowerCase();
    var terms = String(query || "").toLowerCase().trim().split(/\s+/);

    for (var i = 0; i < terms.length; i++) {
        if (!terms[i])
            continue;
        if (nameText.indexOf(terms[i]) >= 0)
            continue;
        if (termInSearchWords(terms[i], descriptionText))
            continue;
        return false;
    }
    return true;
}

// Lower is better. An exact label wins, then a prefix, then a substring, and
// last the entries matching on description only. Ties break by depth and then
// declaration order, so the ranking is stable.
function searchScore(items, entry, query) {
    var needle = String(query || "").toLowerCase().trim();
    var label = String(entry.label || "").toLowerCase();
    var nameText = nameSearchText(entry);
    var descriptionText = String(entry.description || "").toLowerCase();
    var score = 80;

    if (label === needle)
        score = entry.parent === "root" ? 2 : 0;
    else if (label.indexOf(needle) === 0)
        score = 10;
    else if (label.indexOf(needle) >= 0)
        score = 30;
    else if (nameText.indexOf(needle) >= 0)
        score = 40;
    else if (descriptionText.indexOf(needle) >= 0)
        score = 60;

    return score * 1000 + depthFor(items, entry.id) * 25 + (entry.order || 0);
}

// ── Guards ─────────────────────────────────────────────────────────────────

// A single bash script that resolves every `when:` in one pass, printing
// "<id>:w:<0|1>" per line. Batching matters: there are ~144 conditions, and one
// process each would take far longer.
//
// Unlike Omarchy, no pacman-caching prelude is emitted: the helpers it relies on
// (omarchy-pkg-present, omarchy-cmd-present) exist as real binaries in
// $OMARCHY_PATH/bin, so the expressions run either way. Measured here at 2.87s
// against 2.22s for the optimised batch, with identical results across all 144
// guards. The difference goes unnoticed because this runs in the background and
// the answers are cached.
// Wraps a value so bash sees it literally, however the menu spells its ids.
// The explicit null check keeps this file on the same ES5 subset as the rest of
// it -- no nullish coalescing, matching its 46 `var` declarations.
function shellQuote(value) {
    var text = (value === null || value === undefined) ? "" : String(value);
    return "'" + text.replace(/'/g, "'\\''") + "'";
}

function guardScript(items) {
    var script = "";
    var ids = Object.keys(items || {});

    for (var i = 0; i < ids.length; i++) {
        var entry = items[ids[i]];
        if (!entry || !entry.when)
            continue;
        // The reply is parsed by splitting on the last two colons, so an id
        // carrying a colon or a newline could not be read back. Skipping it
        // leaves that row's guard unanswered, which shows the row -- better than
        // corrupting the reply for every other row in the batch.
        if (/[\n\r:]/.test(ids[i]))
            continue;
        // printf with a quoted payload rather than a bare echo: an id containing
        // a glob character would otherwise be expanded against the working
        // directory, emitting one line per matching file and desynchronising the
        // whole reply.
        script += "if { " + entry.when + "; } >/dev/null 2>&1; then printf '%s\\n' "
            + shellQuote(ids[i] + ":w:1") + "; else printf '%s\\n' "
            + shellQuote(ids[i] + ":w:0") + "; fi\n";
    }
    return script;
}

// Reads back what guardScript() emitted: one "<id>:<tag>:<0|1>" line per guard.
// Split from the right, because an id may contain dots and the tag never does.
// Only the "w" (when) tag is of interest; "c" (checked) drives the menu's tick.
function parseGuardReply(text) {
    var results = {};
    var lines = String(text || "").split("\n");

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (!line)
            continue;
        var colon = line.lastIndexOf(":");
        if (colon < 0)
            continue;
        var value = line.substring(colon + 1) === "1";
        var rest = line.substring(0, colon);
        var tagAt = rest.lastIndexOf(":");
        if (tagAt < 0)
            continue;
        if (rest.substring(tagAt + 1) === "w")
            results[rest.substring(0, tagAt)] = value;
    }
    return results;
}

// Importable from QML as a plain JS library and from Node for the test suite.
// Same shape Omarchy's own MenuModel.js uses; `module` is undefined under QML,
// so this block is simply skipped there.
if (typeof module !== "undefined") {
    module.exports = {
        stripJsonc: stripJsonc,
        normalizeAliases: normalizeAliases,
        normalizeItem: normalizeItem,
        parseMenuJsonc: parseMenuJsonc,
        mergeMenuSources: mergeMenuSources,
        item: item,
        depthFor: depthFor,
        pathFor: pathFor,
        parentPathFor: parentPathFor,
        searchableToken: searchableToken,
        leafIdFor: leafIdFor,
        nameSearchText: nameSearchText,
        termInSearchWords: termInSearchWords,
        matchesQuery: matchesQuery,
        searchScore: searchScore,
        shellQuote: shellQuote,
        guardScript: guardScript,
        parseGuardReply: parseGuardReply
    };
}
