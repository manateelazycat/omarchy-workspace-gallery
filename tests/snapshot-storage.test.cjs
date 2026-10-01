const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const test = require("node:test");

const source = fs.readFileSync(path.join(__dirname, "..", "WindowSnapshots.qml"), "utf8");
const startSource = source.slice(source.indexOf("    function startNext()"),
  source.indexOf("    function publish()"));
const startNext = (root, captureProcess) => new Function("root", "captureProcess",
  `return (${startSource.trim()})`)(root, captureProcess);
const directoryCommand = root => new Function("root", `return ${source.match(
  /command: (\["mktemp"[^\n]+)/)[1]}`)(root);
const runWithPublicUmask = (command, options = {}) => spawnSync("sh",
  ["-c", 'umask 022; exec "$@"', "snapshot-test", ...command],
  { encoding: "utf8", ...options });

test("screenshots use private directories and files even with umask 0022", t => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), "gallery-storage-test-"));
  const directories = [];
  t.after(() => {
    for (const dir of directories)
      fs.rmSync(dir, { recursive: true, force: true });
    fs.rmSync(fixture, { recursive: true, force: true });
  });
  // Simulate grim's ordinary file creation without needing a running compositor.
  fs.writeFileSync(path.join(fixture, "grim"),
    '#!/bin/sh\nfor output do :; done\nprintf "%s\\n" "$@" > "$output"\n', { mode: 0o755 });

  for (const runtimeDir of [fixture, "/tmp"]) {
    const created = runWithPublicUmask(directoryCommand({ runtimeDir }));
    assert.equal(created.status, 0, created.stderr);
    const snapshotDir = created.stdout.trim();
    directories.push(snapshotDir);
    assert.equal(fs.statSync(snapshotDir).mode & 0o777, 0o700);

    let published = false;
    const id = 'window; $(touch injected) "quoted"';
    const root = {
      storageReady: true, snapshotDir, captureSerial: 0, current: null,
      generation: 1, files: [], queue: [{ key: "0x123", id, generation: 1 }],
      publish: () => { published = true; }
    };
    const captureProcess = { running: false };
    startNext(root, captureProcess)();
    assert.equal(captureProcess.running, true);
    assert.equal(published, false);
    const captured = runWithPublicUmask(captureProcess.command, {
      cwd: fixture, env: { ...process.env, PATH: `${fixture}:${process.env.PATH}` }
    });
    assert.equal(captured.status, 0, captured.stderr);
    assert.equal(fs.statSync(root.current.path).mode & 0o777, 0o600);
    assert.ok(fs.readFileSync(root.current.path, "utf8").split("\n").includes(id));
    assert.equal(fs.existsSync(path.join(fixture, "injected")), false);
    assert.equal(path.dirname(root.current.path), snapshotDir);
    assert.deepEqual(root.files, [{ path: root.current.path, generation: 1 }]);
  }
  assert.notEqual(directories[0], directories[1]);
});

test("capture waits for private storage and skips capture when creation fails", () => {
  let published = 0;
  const root = {
    storageReady: false, snapshotDir: "", current: null,
    queue: [{ key: "0x123", id: "123", generation: 1 }],
    publish: () => { published++; }
  };
  const captureProcess = { running: false };
  const next = startNext(root, captureProcess);
  next();
  assert.equal(root.queue.length, 1);
  assert.equal(published, 0);
  root.storageReady = true;
  next();
  assert.equal(root.queue.length, 0);
  assert.equal(published, 1);
  assert.equal(captureProcess.running, false);
  assert.equal(captureProcess.command, undefined);
});
