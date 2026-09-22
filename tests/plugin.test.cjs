const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "..");
const read = name => fs.readFileSync(path.join(root, name), "utf8");

test("manifest identifies a panel-only Workspace Gallery plugin", () => {
  const manifest = JSON.parse(read("manifest.json"));
  assert.equal(manifest.id, "io.github.manateelazycat.workspace-gallery");
  assert.equal(manifest.name, "Workspace Gallery");
  assert.equal(manifest.license, "GPL-3.0-only");
  assert.deepEqual(manifest.kinds, ["panel"]);
  assert.equal(manifest.entryPoints.panel, "Gallery.qml");
});

test("gallery preserves the requested 20/80 screen split", () => {
  const source = read("GalleryWidget.qml");
  assert.match(source, /topHeight:\s*height \* 0\.20/);
  assert.match(source, /bottomHeight:\s*height \* 0\.80/);
  assert.match(source, /ListView\s*\{/);
  assert.match(source, /GalleryWindow\s*\{/);
  assert.match(source, /DropArea\s*\{/);
});

test("vertical and horizontal three-finger gestures are live and distance-aware", () => {
  const source = read("scripts/gesture_config.py");
  for (const direction of ["vertical", "horizontal"])
    assert.match(source, new RegExp(`direction = \\"${direction}\\"`));
  for (const phase of ["start", "update", "finish"])
    assert.match(source, new RegExp(`${phase} = function\\(e\\)`));
  assert.match(source, /hl\.dsp\.event\("workspace-gallery-swipe/);
  assert.match(source, /hl\.dsp\.event\("workspace-gallery-vertical/);

  const gallery = read("Gallery.qml");
  assert.match(gallery, /verticalSwipeDistance <= -140/);
  assert.match(gallery, /verticalSwipeDistance >= 90/);
});

test("Super+A toggles the gallery and arrow keys select workspaces", () => {
  const config = read("scripts/gesture_config.py");
  assert.match(config, /hl\.bind\("SUPER \+ A", hl\.dsp\.global\("quickshell:workspaceGalleryToggle"\)/);

  const gallery = read("Gallery.qml");
  assert.match(gallery, /name: "workspaceGalleryToggle"[\s\S]*onPressed: galleryScope\.toggle\(\)/);
  assert.match(gallery, /event\.key === Qt\.Key_Left[\s\S]*galleryScope\.selectRelative\(-1\)/);
  assert.match(gallery, /event\.key === Qt\.Key_Right[\s\S]*galleryScope\.selectRelative\(1\)/);
});

test("all gallery close paths use a progressive exit animation", () => {
  const gallery = read("Gallery.qml");
  const widget = read("GalleryWidget.qml");
  assert.match(gallery, /function close\(commitSelection = false\)/);
  assert.match(gallery, /id: closeAnimation[\s\S]*property: "revealProgress"[\s\S]*duration: 220/);
  assert.match(gallery, /visible: GlobalStates\.overviewOpen \|\| galleryScope\.closing/);
  assert.match(gallery, /opacity: galleryScope\.revealProgress/);
  assert.match(gallery, /y: \(1 - galleryScope\.revealProgress\) \* 28/);
  assert.match(gallery, /galleryScope\.close\(true\)/);
  assert.match(widget, /signal closeRequested\(bool commitSelection\)/);
  assert.match(widget, /root\.closeRequested\(false\)/);
});

test("Super+W closes the latest window from the workspace selected in the gallery", () => {
  const config = read("scripts/gesture_config.py");
  const gallery = read("Gallery.qml");
  const navigation = read("WorkspaceNavigation.qml");

  assert.match(config, /hl\.unbind\("SUPER \+ W"\)/);
  assert.match(config, /hl\.bind\("SUPER \+ W", hl\.dsp\.global\("quickshell:workspaceGalleryCloseWindow"\)/);
  assert.match(gallery, /name: "workspaceGalleryCloseWindow"[\s\S]*galleryScope\.closeSelectedWorkspaceWindow\(\)/);
  assert.match(gallery, /GlobalStates\.overviewFocusedWorkspaceId[\s\S]*WorkspaceNavigation\.closeMostRecentWindowInWorkspace\(workspaceId\)/);
  assert.match(gallery, /if \(!GlobalStates\.overviewOpen\)[\s\S]*hl\.dsp\.window\.close\(\)/);
  assert.match(navigation, /WorkspaceWindowSelection\.mostRecentClientForWorkspace/);
});

test("selected-workspace close prefers the most recently focused visible client", () => {
  const selection = require(path.join(root, "WorkspaceWindowSelection.js"));
  const clients = [
    { address: "0xold", mapped: true, hidden: false, focusHistoryID: 8, workspace: { id: 4 } },
    { address: "0xnew", mapped: true, hidden: false, focusHistoryID: 1, workspace: { id: 4 } },
    { address: "0xhidden", mapped: true, hidden: true, focusHistoryID: 0, workspace: { id: 4 } },
    { address: "0xother", mapped: true, hidden: false, focusHistoryID: 0, workspace: { id: 1 } }
  ];
  assert.equal(selection.mostRecentClientForWorkspace(clients, 4)?.address, "0xnew");
  assert.equal(selection.mostRecentClientForWorkspace(clients, 2), null);
});

test("Down and a two-finger pinch compact occupied workspaces", () => {
  const gestures = read("scripts/gesture_config.py");
  const gallery = read("Gallery.qml");
  const navigation = read("WorkspaceNavigation.qml");

  assert.match(gestures, /fingers = 2,[\s\S]*direction = "pinch"/);
  assert.match(gestures, /finish = function\(e\)[\s\S]*workspace-gallery-compact,trigger/);
  assert.match(gestures, /workspace-gallery-compact,trigger/);
  assert.match(gallery, /channel === "workspace-gallery-compact"[\s\S]*WorkspaceNavigation\.compactWorkspaces\(\)/);
  assert.match(gallery, /event\.key === Qt\.Key_Down[\s\S]*WorkspaceNavigation\.compactWorkspaces\(\)/);
  assert.match(navigation, /function compactWorkspaces\(\)/);
  assert.match(navigation, /command: \["hyprctl", "clients", "-j"\]/);
  assert.match(navigation, /command: \["hyprctl", "monitors", "-j"\]/);
  assert.match(navigation, /function executeWorkspaceCompaction\(clients, monitors\)/);
  assert.match(navigation, /hl\.dsp\.window\.move/);
});

test("workspace compaction preserves order and removes every numeric gap", () => {
  const compact = require(path.join(root, "WorkspaceCompact.js"));
  const clients = [1, 4, 4, 7, 9].map((workspace, index) => ({
    address: `0x${index + 1}`,
    mapped: true,
    workspace: { id: workspace },
    monitor: workspace === 7 ? 1 : 0
  }));
  const workspaces = [
    { id: 1, monitor: "eDP-1" },
    { id: 4, monitor: "eDP-1" },
    { id: 7, monitor: "HDMI-A-1" },
    { id: 9, monitor: "eDP-1" }
  ];
  const plan = compact.buildPlan(clients, workspaces, [
    { id: 0, name: "eDP-1" },
    { id: 1, name: "HDMI-A-1" }
  ]);

  assert.deepEqual(plan.mapping, { 1: 1, 4: 2, 7: 3, 9: 4 });
  assert.deepEqual(plan.moves.map(move => [move.sourceId, move.targetId]), [
    [4, 2], [7, 3], [9, 4]
  ]);
  assert.equal(plan.moves[1].monitorName, "HDMI-A-1");
  assert.deepEqual(plan.moves[0].addresses, ["0x2", "0x3"]);
  assert.deepEqual(compact.remapIds([9, 4, 1, 4], plan.mapping), [4, 2, 1]);
});

test("workspace compaction animates before committing compositor moves", () => {
  const states = read("GlobalStates.qml");
  const navigation = read("WorkspaceNavigation.qml");
  const gallery = read("GalleryWidget.qml");

  assert.match(states, /property bool overviewCompactionAnimating: false/);
  assert.match(states, /property bool overviewCompactionSyncing: false/);
  assert.match(states, /property bool overviewCompactionHandoff: false/);
  assert.match(states, /property real overviewCompactionElapsed: 0/);
  assert.match(navigation, /id: compactionTimelineAnimation[\s\S]*property: "overviewCompactionElapsed"/);
  assert.match(navigation, /onFinished: root\.preparePendingWorkspaceCompaction\(\)/);
  assert.match(navigation, /id: compactionHandoffCaptureTimer[\s\S]*interval: 80/);
  assert.match(navigation, /buildAnimationPlan\(plan\.sourceIds\)[\s\S]*compactionTimelineAnimation\.start\(\)/);
  assert.match(navigation, /function commitPendingWorkspaceCompaction\(\)[\s\S]*overviewCompactionSyncing = true[\s\S]*hl\.dsp\.window\.move/);
  assert.match(gallery, /function jellyProgress\(value\)/);
  assert.match(gallery, /y -= \(root\.topCardHeight \+ 18\) \* travel/);
  assert.match(gallery, /shift\.slots[\s\S]*root\.jellyProgress\(t\)/);
  assert.match(gallery, /topList\.grabToImage\(result =>/);
  assert.match(gallery, /id: compactionHandoffImage[\s\S]*overviewCompactionHandoff \? 1 : 0/);
  const bottomViewport = gallery.slice(gallery.indexOf("id: bottomViewport"), gallery.indexOf("id: dragProxy"));
  assert.doesNotMatch(bottomViewport, /overviewCompactionSyncing/);
});

test("empty workspace cards leave left-to-right at half-duration intervals", () => {
  const compact = require(path.join(root, "WorkspaceCompact.js"));
  const animation = compact.buildAnimationPlan([1, 5]);

  assert.deepEqual(animation.emptyStages.map(stage => [stage.workspaceId, stage.start]), [
    [2, 0], [3, 190], [4, 380]
  ]);
  assert.equal(animation.shiftStages.length, 1);
  assert.deepEqual(animation.shiftStages[0], {
    afterWorkspaceId: 4,
    slots: 3,
    start: 760,
    duration: 480
  });
  assert.equal(animation.duration, 1240);
});

test("top workspace taps coexist with window dragging", () => {
  const gallery = read("GalleryWidget.qml");
  assert.match(gallery, /id: topWindowLayer[\s\S]*z: 20[\s\S]*Repeater/);
  assert.match(gallery, /id: topWindowLayer[\s\S]*GalleryWindow[\s\S]*TapHandler \{/);
  assert.match(gallery, /gesturePolicy: TapHandler\.DragThreshold/);
  const topWindowLayer = gallery.slice(gallery.indexOf("id: topWindowLayer"), gallery.indexOf("TapHandler {", gallery.indexOf("id: topWindowLayer")));
  assert.doesNotMatch(topWindowLayer, /overviewCompactionSyncing|Behavior on opacity/);
});

test("bottom gallery uses a follow-finger workspace track", () => {
  const source = read("GalleryWidget.qml");
  assert.match(source, /property real swipeOffset/);
  assert.match(source, /function beginSwipe/);
  assert.match(source, /function applySwipeDelta/);
  assert.match(source, /function endSwipe/);
  assert.match(source, /NumberAnimation\s*\{/);
  assert.match(source, /GalleryWorkspacePage\s*\{/);
});

test("clicking a top workspace animates the large preview in its direction", () => {
  const source = read("GalleryWidget.qml");
  assert.match(source, /function animateToWorkspace\(workspaceId\)/);
  assert.match(source, /root\.clickedWorkspaceId = workspaceId/);
  assert.match(source, /settleAnimation\.to = \(root\.selectedIndex - targetIndex\) \* root\.pageSpan/);
  assert.match(source, /settleAnimation\.duration = Math\.min\(800, 260 \+ \(distance - 1\) \* 125\)/);
  assert.match(source, /root\.settleEasingType = Easing\.InOutCubic/);
  assert.match(source, /inClickTravelRange[\s\S]*Math\.min\(anchorIndex, root\.settlementIndex\)/);
  assert.doesNotMatch(source, /clickedWorkspaceStepTimer/);
  assert.match(source, /onTapped: root\.animateToWorkspace\(topCard\.modelData\.id\)/);
  assert.match(source, /onActivated: root\.animateToWorkspace\(topCard\.modelData\.id\)/);
});

test("a lone window has vertical breathing room in the large preview", () => {
  const page = read("GalleryWorkspacePage.qml");
  assert.match(page, /singleWindowVerticalInset: page\.windowAddresses\.length === 1/);
  assert.match(page, /Math\.max\(12, Math\.min\(24, page\.height \* 0\.035\)\)/);
  assert.match(page, /previewY: page\.singleWindowVerticalInset/);
  assert.match(page, /previewHeight: Math\.max\(1, page\.height - page\.singleWindowVerticalInset \* 2\)/);
});

test("large previews expose crowded windows without affecting simple pairs", () => {
  const expose = require(path.join(root, "WorkspaceExpose.js"));
  const separate = expose.buildLayout([
    { address: "a", x: 0, y: 0, width: 300, height: 300, focusHistoryId: 0 },
    { address: "b", x: 700, y: 0, width: 300, height: 300, focusHistoryId: 1 }
  ], 1000, 700);
  assert.equal(separate.enabled, false);

  const crowded = expose.buildLayout([
    { address: "a", x: 100, y: 100, width: 700, height: 500, focusHistoryId: 0 },
    { address: "b", x: 160, y: 140, width: 650, height: 480, focusHistoryId: 1 }
  ], 1000, 700);
  assert.equal(crowded.enabled, true);
  assert.ok(crowded.overlap >= 0.35);
  assert.ok(crowded.rects.a.width > crowded.rects.b.width);
  assert.equal(expose.intersectionRatio(crowded.rects.a, crowded.rects.b), 0);

  const group = expose.buildLayout([
    { address: "a", x: 100, y: 100, width: 700, height: 500, focusHistoryId: 0 },
    { address: "b", x: 120, y: 120, width: 500, height: 400, focusHistoryId: 1 },
    { address: "c", x: 140, y: 140, width: 500, height: 400, focusHistoryId: 2 }
  ], 1000, 700);
  assert.equal(group.enabled, true);
  for (const left of ["a", "b", "c"])
    for (const right of ["a", "b", "c"])
      if (left < right)
        assert.equal(expose.intersectionRatio(group.rects[left], group.rects[right]), 0);
});

test("large preview animates between spatial and expose geometry", () => {
  const page = read("GalleryWorkspacePage.qml");
  const window = read("OverviewWindow.qml");
  assert.match(page, /WorkspaceExpose\.buildLayout/);
  assert.match(page, /layoutOverrideEnabled: page\.exposeReady/);
  assert.match(page, /geometryAnimationEnabled: true/);
  assert.match(window, /property bool layoutOverrideEnabled/);
  assert.match(read("GalleryWindow.qml"), /root\.restorePositionBinding\(\)/);
  for (const property of ["x", "y", "width", "height"])
    assert.match(window, new RegExp(`Behavior on ${property}`));
});

test("workspace labels are hidden and swipe target drives the top highlight", () => {
  const gallery = read("GalleryWidget.qml");
  const page = read("GalleryWorkspacePage.qml");
  assert.doesNotMatch(gallery, /`Workspace \$\{topCard\.modelData\.id\}`/);
  assert.doesNotMatch(page, /`Workspace \$\{page\.entry/);
  assert.match(gallery, /highlightedWorkspaceId/);
  assert.match(gallery, /border\.width: topCard\.modelData\.id === root\.highlightedWorkspaceId \? 4 : 1/);
  assert.match(gallery, /anchors\.fill: parent\s+radius: 0\s+color: "transparent"/);
  assert.match(gallery, /z: 100/);
});

test("windows dragged from the large preview use a one-third-size proxy", () => {
  const window = read("GalleryWindow.qml");
  const widget = read("GalleryWidget.qml");
  const bridge = read("CrossMonitorDrag.qml");
  assert.match(window, /root\.Drag\.active && root\.closeOnActivate/);
  assert.match(window, /root\.closeOnActivate\);/);
  assert.match(bridge, /property bool compactPreview: false/);
  assert.match(widget, /CrossMonitorDrag\.sourceWidth \/ 3/);
  assert.match(widget, /CrossMonitorDrag\.sourceHeight \/ 3/);
});

test("drop coordinates are mapped into the real workspace before tiled insertion", () => {
  const galleryWindow = read("GalleryWindow.qml");
  const galleryWidget = read("GalleryWidget.qml");
  const navigation = read("WorkspaceNavigation.qml");
  const dragBridge = read("CrossMonitorDrag.qml");

  assert.match(galleryWindow, /normalizedX/);
  assert.match(galleryWindow, /dropTarget\.workX \+ normalizedX \* dropTarget\.workW/);
  assert.match(galleryWindow, /dropTarget\.workY \+ normalizedY \* dropTarget\.workH/);
  assert.match(galleryWidget, /root\.usableLogicalWidth\(targetMonitor\)/);
  assert.match(dragBridge, /workX,\s+workY,\s+workW,\s+workH/);
  assert.match(navigation, /hl\.dsp\.cursor\.move\(\{ x = \$\{dropX\}, y = \$\{dropY\} \}\)/);
  assert.match(navigation, /special:workspace-gallery-staging/);
  assert.match(navigation, /hl\.timer\(function\(\)/);
  assert.match(navigation, /timeout = 16, type = "oneshot"/);
  assert.match(navigation, /x = \$\{restoreX\}, y = \$\{restoreY\}/);
});

test("same-workspace drags reorder tiled windows before release", () => {
  const gallery = read("Gallery.qml");
  const galleryWindow = read("GalleryWindow.qml");
  const navigation = read("WorkspaceNavigation.qml");
  const dragBridge = read("CrossMonitorDrag.qml");
  assert.match(navigation, /function tiledWindowAt\(workspaceId, windowAddress, placement\)/);
  assert.match(navigation, /dropX >= x && dropX <= x \+ width/);
  assert.match(navigation, /hl\.dsp\.focus\(\{ window = "address:\$\{windowAddress\}" \}\)/);
  assert.match(navigation, /hl\.dsp\.window\.swap\(\{ target = "address:\$\{targetAddress\}" \}\)/);
  assert.match(navigation, /hl\.timer\(function\(\)[\s\S]*hl\.dsp\.window\.swap/);
  assert.match(navigation, /timeout = 1, type = "oneshot"/);
  assert.match(navigation, /hl\.dsp\.cursor\.move\(\{ x = \$\{restoreX\}, y = \$\{restoreY\} \}\)/);
  assert.match(dragBridge, /property var windowTargets: \(\{\}\)/);
  assert.match(dragBridge, /readonly property var hoveredWindowTarget/);
  assert.match(galleryWindow, /function publishWindowDropTarget\(\)/);
  assert.match(galleryWindow, /CrossMonitorDrag\.publishWindowTarget/);
  assert.match(gallery, /function updateLiveWindowDrag\(\)/);
  assert.match(gallery, /target\.workspaceId !== CrossMonitorDrag\.sourceWorkspaceId/);
  assert.match(gallery, /function onPointerRevisionChanged\(\)/);
  assert.match(galleryWindow, /const layoutAlreadyCommitted = CrossMonitorDrag\.liveReordered/);
});

test("a stationary click does not start the window drag animation", () => {
  const source = read("GalleryWindow.qml");
  const pressed = source.slice(source.indexOf("onPressed:"), source.indexOf("onReleased:"));
  const moved = source.slice(source.indexOf("onPositionChanged:"), source.indexOf("onPressed:"));
  assert.doesNotMatch(pressed, /CrossMonitorDrag\.begin/);
  assert.doesNotMatch(pressed, /root\.Drag\.active = true/);
  assert.match(moved, /dragArea\.drag\.threshold/);
  assert.match(moved, /root\.beginPointerDrag/);
  assert.match(source, /if \(!root\.Drag\.active\) \{\s+root\.pressed = false;\s+return;/);
});

test("Escape commits the selected workspace before closing the gallery", () => {
  const source = read("Gallery.qml");
  assert.match(source, /event\.key === Qt\.Key_Escape\) \{\s+galleryScope\.activateSelection\(\);/);
  assert.match(source, /function activateSelection\(\) \{\s+galleryScope\.close\(true\);/);
  assert.match(source, /if \(galleryScope\.commitSelectionAfterClose\)\s+WorkspaceNavigation\.commitSelectedWorkspace\(\);/);
});

test("high-frequency swipe events do not refresh the workspace data model", () => {
  assert.match(read("HyprlandData.qml"), /"custom"\]\.includes\(event\.name\)/);
});

test("plugin lifecycle never reloads Hyprland", () => {
  for (const name of fs.readdirSync(root).filter(name => name.endsWith(".qml"))) {
    const source = read(name);
    assert.doesNotMatch(source, /hyprctl[^\n]*reload|reload[^\n]*hyprctl/i, name);
  }
});

test("third-party origin and license are retained", () => {
  assert.match(read("THIRD_PARTY_NOTICES.md"), /Overview Workspaces/);
  assert.match(read("THIRD_PARTY_NOTICES.md"), /733355994c333f8ddf155030fc9f0cb2e07a32cb/);
  assert.match(read("LICENSE"), /GNU GENERAL PUBLIC LICENSE/);
  assert.match(read("LICENSES/MIT.txt"), /Copyright \(c\) 2026 HANCORE/);
});
