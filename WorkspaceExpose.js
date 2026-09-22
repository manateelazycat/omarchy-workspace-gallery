function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value));
}

function intersectionRatio(a, b) {
    const left = Math.max(a.x, b.x);
    const top = Math.max(a.y, b.y);
    const right = Math.min(a.x + a.width, b.x + b.width);
    const bottom = Math.min(a.y + a.height, b.y + b.height);
    if (right <= left || bottom <= top)
        return 0;
    const intersection = (right - left) * (bottom - top);
    return intersection / Math.max(1, Math.min(a.width * a.height, b.width * b.height));
}

function maximumOverlap(windows) {
    let maximum = 0;
    for (let left = 0; left < windows.length; ++left) {
        for (let right = left + 1; right < windows.length; ++right)
            maximum = Math.max(maximum, intersectionRatio(windows[left], windows[right]));
    }
    return maximum;
}

function fitInRegion(win, region, fill) {
    const sourceWidth = Math.max(1, Number(win.width));
    const sourceHeight = Math.max(1, Number(win.height));
    const availableWidth = Math.max(1, region.width * fill);
    const availableHeight = Math.max(1, region.height * fill);
    const scale = Math.min(availableWidth / sourceWidth, availableHeight / sourceHeight);
    const width = sourceWidth * scale;
    const height = sourceHeight * scale;
    return {
        x: region.x + (region.width - width) / 2,
        y: region.y + (region.height - height) / 2,
        width,
        height
    };
}

function centerDistance(win, region) {
    const dx = win.x + win.width / 2 - (region.x + region.width / 2);
    const dy = win.y + win.height / 2 - (region.y + region.height / 2);
    return dx * dx + dy * dy;
}

function focusRank(win) {
    const rank = Number(win.focusHistoryId);
    return Number.isFinite(rank) && rank >= 0 ? rank : 1000000;
}

function gridRegions(count, x, y, width, height, gap) {
    const columns = Math.ceil(Math.sqrt(count * width / Math.max(1, height)));
    const rows = Math.ceil(count / columns);
    const cellWidth = (width - gap * (columns - 1)) / columns;
    const cellHeight = (height - gap * (rows - 1)) / rows;
    const regions = [];
    for (let index = 0; index < count; ++index) {
        const row = Math.floor(index / columns);
        const itemsInRow = Math.min(columns, count - row * columns);
        const rowWidth = itemsInRow * cellWidth + (itemsInRow - 1) * gap;
        const column = index - row * columns;
        regions.push({
            x: x + (width - rowWidth) / 2 + column * (cellWidth + gap),
            y: y + row * (cellHeight + gap),
            width: cellWidth,
            height: cellHeight
        });
    }
    return regions;
}

function peripheralRegions(x, y, width, height, gap) {
    const sideWidth = Math.max(1, width * 0.235);
    const centerWidth = Math.max(1, width - sideWidth * 2 - gap * 2);
    const centerHeight = Math.max(1, height * 0.58);
    const edgeHeight = Math.max(1, (height - centerHeight - gap * 2) / 2);
    const halfSideHeight = Math.max(1, (height - gap) / 2);
    const centerX = x + sideWidth + gap;
    const centerY = y + edgeHeight + gap;
    return {
        main: { x: centerX, y: centerY, width: centerWidth, height: centerHeight },
        slots: [
            { x, y, width: sideWidth, height: halfSideHeight },
            { x, y: y + halfSideHeight + gap, width: sideWidth, height: halfSideHeight },
            { x: x + width - sideWidth, y, width: sideWidth, height: halfSideHeight },
            { x: x + width - sideWidth, y: y + halfSideHeight + gap, width: sideWidth, height: halfSideHeight },
            { x: centerX, y, width: centerWidth, height: edgeHeight },
            { x: centerX, y: centerY + centerHeight + gap, width: centerWidth, height: edgeHeight }
        ]
    };
}

function buildLayout(inputWindows, viewportWidth, viewportHeight) {
    const windows = (inputWindows ?? []).filter(win => win && String(win.address ?? "").length > 0);
    const width = Math.max(1, Number(viewportWidth));
    const height = Math.max(1, Number(viewportHeight));
    const overlap = maximumOverlap(windows);
    const enabled = windows.length >= 3 || (windows.length === 2 && overlap >= 0.35);
    if (!enabled)
        return { enabled: false, overlap, rects: {} };

    const padding = clamp(Math.min(width, height) * 0.035, 18, 32);
    const gap = clamp(Math.min(width, height) * 0.022, 12, 22);
    const innerX = padding;
    const innerY = padding;
    const innerWidth = Math.max(1, width - padding * 2);
    const innerHeight = Math.max(1, height - padding * 2);
    const ordered = windows.slice().sort((a, b) => focusRank(a) - focusRank(b));
    const rects = {};

    if (windows.length === 2) {
        const primaryWidth = (innerWidth - gap) * 0.56;
        const regions = [
            { x: innerX, y: innerY, width: primaryWidth, height: innerHeight },
            { x: innerX + primaryWidth + gap, y: innerY,
                width: innerWidth - primaryWidth - gap, height: innerHeight }
        ];
        for (let index = 0; index < ordered.length; ++index) {
            const rect = fitInRegion(ordered[index], regions[index], 0.94);
            rect.z = index === 0 ? 100 : 10;
            rects[ordered[index].address] = rect;
        }
        return { enabled: true, overlap, rects };
    }

    if (windows.length <= 7) {
        const regions = peripheralRegions(innerX, innerY, innerWidth, innerHeight, gap);
        const main = ordered[0];
        const mainRect = fitInRegion(main, regions.main, 0.98);
        mainRect.z = 100;
        rects[main.address] = mainRect;

        const available = regions.slots.slice();
        for (let index = 1; index < ordered.length; ++index) {
            const win = ordered[index];
            let best = 0;
            for (let slot = 1; slot < available.length; ++slot) {
                if (centerDistance(win, available[slot]) < centerDistance(win, available[best]))
                    best = slot;
            }
            const region = available.splice(best, 1)[0];
            const rect = fitInRegion(win, region, 0.92);
            rect.z = 20 + ordered.length - index;
            rects[win.address] = rect;
        }
        return { enabled: true, overlap, rects };
    }

    const regions = gridRegions(ordered.length, innerX, innerY, innerWidth, innerHeight, gap);
    for (let index = 0; index < ordered.length; ++index) {
        const rect = fitInRegion(ordered[index], regions[index], 0.92);
        rect.z = 20 + ordered.length - index;
        rects[ordered[index].address] = rect;
    }
    return { enabled: true, overlap, rects };
}

if (typeof module !== "undefined") {
    module.exports = {
        buildLayout,
        intersectionRatio,
        maximumOverlap
    };
}
