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

test("bottom gallery uses a follow-finger workspace track", () => {
  const source = read("GalleryWidget.qml");
  assert.match(source, /property real swipeOffset/);
  assert.match(source, /function beginSwipe/);
  assert.match(source, /function applySwipeDelta/);
  assert.match(source, /function endSwipe/);
  assert.match(source, /NumberAnimation\s*\{/);
  assert.match(source, /GalleryWorkspacePage\s*\{/);
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
  const galleryWindow = read("GalleryWindow.qml");
  const navigation = read("WorkspaceNavigation.qml");
  assert.match(navigation, /function tiledWindowAt\(workspaceId, windowAddress, placement\)/);
  assert.match(navigation, /dropX >= x && dropX <= x \+ width/);
  assert.match(navigation, /function reorderWindowDrag\(windowAddress, workspaceId, placement, previousTargetAddress\)/);
  assert.match(navigation, /hl\.dsp\.focus\(\{ window = "address:\$\{windowAddress\}" \}\)/);
  assert.match(navigation, /hl\.dsp\.window\.swap\(\{ target = "address:\$\{targetAddress\}" \}\)/);
  assert.match(galleryWindow, /CrossMonitorDrag\.updatePointer[\s\S]*root\.updateLiveLayout\(\)/);
  assert.match(galleryWindow, /dropTarget\.id !== root\.sourceWorkspaceId/);
  assert.match(galleryWindow, /layoutAlreadyCommitted/);
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
  assert.match(source, /function activateSelection\(\) \{\s+WorkspaceNavigation\.commitSelectedWorkspace\(\);\s+galleryScope\.close\(\);/);
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
