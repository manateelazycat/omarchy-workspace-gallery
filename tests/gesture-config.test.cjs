const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const test = require("node:test");

const root = path.resolve(__dirname, "..");
const start = "-- >>> omarchy-workspace-gallery >>>";
const end = "-- <<< omarchy-workspace-gallery <<<";
const before = '-- Existing user configuration\nhl.input({ kb_layout = "us" })\n';
const after = '-- Keep later user bindings\nhl.bind("SUPER + F", hl.dsp.window.fullscreen())\n';
const legacyBlock = `${start}\n`
  + 'hl.unbind("SUPER + W")\n'
  + 'hl.bind("SUPER + W", hl.dsp.global("quickshell:workspaceGalleryCloseWindow"))\n'
  + `${end}\n`;

const fixture = (t, original = before) => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), "workspace-gallery test-"));
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  const target = path.join(home, ".config/hypr/input.lua");
  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, original);
  const env = { ...process.env, HOME: home, PYTHONDONTWRITEBYTECODE: "1" };
  const configure = (action, script = path.join(root, "scripts/gesture_config.py")) => {
    const result = spawnSync("python3", [script, action], {
      env, encoding: "utf8", timeout: 10000
    });
    assert.ifError(result.error);
    return result;
  };
  const commandForWindow = (activeAddress = "0xabc") => {
    const active = activeAddress === null ? "nil" : `{ address = ${JSON.stringify(activeAddress)} }`;
    const installed = fs.readFileSync(target, "utf8");
    const lua = `
local close_binding
hl = {
  layer_rule = function(_) end,
  unbind = function(_) end,
  gesture = function(_) end,
  get_window = function(selector) assert(selector == "active"); return ${active} end,
  bind = function(key, callback, _) if key == "SUPER + W" then close_binding = callback end end,
  dispatch = function(command) io.write(command) end,
  dsp = {
    global = function(name) return name end,
    exec_cmd = function(command) return command end,
  },
}
${installed.slice(installed.indexOf(start))}
close_binding()
`;
    const result = spawnSync("lua", ["-"], { input: lua, encoding: "utf8", timeout: 10000 });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stderr);
    return result.stdout;
  };
  const install = (script, activeAddress) => {
    const result = configure("install", script);
    assert.equal(result.status, 0, result.stderr);
    return commandForWindow(activeAddress);
  };
  return { home, target, env, configure, install };
};

test("install replaces legacy bindings once and uninstall preserves user configuration", t => {
  const original = before + legacyBlock + after;
  const f = fixture(t, original);
  f.install();
  const installed = fs.readFileSync(f.target, "utf8");
  assert.equal(installed.split(start).length - 1, 1);
  assert.ok(installed.startsWith(before + after));
  assert.ok(!installed.includes('hl.dsp.global("quickshell:workspaceGalleryCloseWindow")'));
  const backups = fs.readdirSync(path.dirname(f.target)).filter(name => name.startsWith("input.lua.bak-"));
  assert.equal(backups.length, 1);
  assert.equal(fs.readFileSync(path.join(path.dirname(f.target), backups[0]), "utf8"), original);

  f.install();
  assert.equal(fs.readFileSync(f.target, "utf8"), installed);
  const removed = f.configure("uninstall");
  assert.equal(removed.status, 0, removed.stderr);
  assert.equal(fs.readFileSync(f.target, "utf8"), before + after);
  assert.equal(f.configure("uninstall").status, 0);
  assert.equal(fs.readFileSync(f.target, "utf8"), before + after);
});

test("uninstall can recover a leftover legacy binding", t => {
  const f = fixture(t, before + legacyBlock + after);
  const result = f.configure("uninstall");
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.readFileSync(f.target, "utf8"), before + after);
});

test("an incomplete managed block is reported without changing the config", t => {
  const original = before + start + '\nhl.unbind("SUPER + W")\n';
  const f = fixture(t, original);
  for (const action of ["install", "uninstall"]) {
    const result = f.configure(action);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /without its closing marker/);
    assert.equal(fs.readFileSync(f.target, "utf8"), original);
    assert.deepEqual(fs.readdirSync(path.dirname(f.target)), ["input.lua"]);
  }
});

for (const scenario of [
  { name: "loaded plugin closes only the window from its prepared dispatcher", ipcStatus: 0 },
  { name: "multiline gallery dispatchers survive the shell command", ipcStatus: 0, reply: 'function()\n  hl.dispatch(hl.dsp.window.close({ window = "address:0xdef" }))\nend' },
  { name: "unavailable IPC target closes the window captured at keypress", ipcStatus: 1 },
  { name: "unresponsive shell closes the window captured at keypress", ipcStatus: 124 },
  { name: "missing IPC executable still closes the original window", ipcStatus: null },
  { name: "fallback with no original active window does not close a later window", ipcStatus: 1, activeAddress: null },
  { name: "an empty gallery workspace does not close the active window", ipcStatus: 0, reply: "hl.dsp.no_op()" },
  { name: "native close failures are preserved", ipcStatus: 1, nativeStatus: 5 }
]) {
  test(scenario.name, t => {
    const f = fixture(t);
    const pluginDir = path.join(f.home, ".config/omarchy/plugins/io.github.manateelazycat.workspace-gallery");
    fs.mkdirSync(path.join(pluginDir, "scripts"), { recursive: true });
    fs.copyFileSync(path.join(root, "scripts/gesture_config.py"), path.join(pluginDir, "scripts/gesture_config.py"));
    const command = f.install(path.join(pluginDir, "scripts/gesture_config.py"), scenario.activeAddress);
    // Removing the checkout must not remove the native fallback.
    fs.rmSync(pluginDir, { recursive: true });
    const bin = path.join(f.home, "bin");
    fs.mkdirSync(bin);
    const ipcLog = path.join(f.home, "ipc.log");
    const nativeLog = path.join(f.home, "native.log");
    if (scenario.ipcStatus !== null) {
      fs.writeFileSync(path.join(bin, "omarchy-shell"), '#!/bin/sh\nprintf "%s\\n" "$*" >> "$GALLERY_TEST_IPC_LOG"\nprintf "%s\\n" "$GALLERY_TEST_IPC_REPLY"\nexit "$GALLERY_TEST_IPC_STATUS"\n', { mode: 0o755 });
    }
    fs.writeFileSync(path.join(bin, "hyprctl"), '#!/bin/sh\nprintf "%s\\n" "$*" >> "$GALLERY_TEST_NATIVE_LOG"\nexit "$GALLERY_TEST_NATIVE_STATUS"\n', { mode: 0o755 });
    const result = spawnSync("/bin/sh", ["-c", command], {
      env: {
        ...f.env, PATH: bin,
        GALLERY_TEST_IPC_LOG: ipcLog,
        GALLERY_TEST_IPC_STATUS: String(scenario.ipcStatus),
        GALLERY_TEST_IPC_REPLY: scenario.reply ?? 'hl.dsp.window.close({ window = "address:0xdef" })',
        GALLERY_TEST_NATIVE_LOG: nativeLog,
        GALLERY_TEST_NATIVE_STATUS: String(scenario.nativeStatus ?? 0)
      },
      encoding: "utf8", timeout: 10000
    });
    assert.ifError(result.error);
    assert.equal(result.status, scenario.nativeStatus ?? 0, result.stderr);
    if (scenario.ipcStatus !== null)
      assert.equal(fs.readFileSync(ipcLog, "utf8"), `workspace-gallery prepareCloseWindow ${scenario.activeAddress === null ? "" : "0xabc"}\n`);
    const expected = scenario.ipcStatus === 0
      ? scenario.reply ?? 'hl.dsp.window.close({ window = "address:0xdef" })'
      : scenario.activeAddress === null ? "hl.dsp.no_op()" : 'hl.dsp.window.close({ window = "address:0xabc" })';
    assert.equal(fs.readFileSync(nativeLog, "utf8"), `dispatch ${expected}\n`);
  });
}
