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
  assert.match(gallery, /z: 100/);
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
  assert.ok(fs.statSync(path.join(root, "LICENSE")).size > 0);
});
