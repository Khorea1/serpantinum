const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const vm = require("node:vm");

const dir = path.resolve(__dirname, "../src/quickshell/bar/faces/expose");
const code = fs.readFileSync(path.join(dir, "ScreenLayout.js"), "utf8")
    .replace(/^\.pragma library\s*/m, "");
const layout = {};
vm.runInNewContext(code, layout, { filename: "ScreenLayout.js" });

function card(width, height) {
    return { lastIpcObject: { size: [width, height] } };
}

const empty = layout.fit([], 1280, 720, 18, 30);
assert.equal(empty.cardWidth, 0);

for (const count of [1, 2, 5, 13]) {
    const windows = Array.from({ length: count }, (_, i) => card(i % 2 ? 1080 : 1920, i % 2 ? 1920 : 1080));
    for (const [width, height] of [[1280, 720], [800, 1200], [300, 260]]) {
        const grid = layout.fit(windows, width, height, 18, 30);
        assert.ok(grid.columns >= 1 && grid.columns <= count);
        assert.equal(grid.rows, Math.ceil(count / grid.columns));
        assert.ok(grid.cardWidth > 0 && grid.cardHeight > 0);
        assert.ok(grid.columns * grid.cardWidth + (grid.columns - 1) * 18 <= width + 0.001);
        assert.ok(grid.rows * grid.cardHeight + (grid.rows - 1) * 18 <= height + 0.001);
    }
}
assert.equal(layout.aspectOf(card(1600, 900)), 16 / 9);
assert.equal(layout.aspectOf({}), 16 / 10);

// Check focus arguments without connecting to a compositor or changing focus.
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "serpantinum-expose-"));
try {
    const fake = path.join(scratch, "hyprctl");
    const capture = path.join(scratch, "args");
    fs.writeFileSync(fake, '#!/bin/sh\nprintf "%s\\n" "$@" > "$EXPOSE_TEST_ARGS"\n', { mode: 0o700 });
    const script = path.join(dir, "activate-window.sh");
    const env = { ...process.env, PATH: scratch + ":" + process.env.PATH, EXPOSE_TEST_ARGS: capture };

    const accepted = spawnSync("bash", [script, "0x01aB"], { env, encoding: "utf8" });
    assert.equal(accepted.status, 0, accepted.stderr);
    assert.deepEqual(fs.readFileSync(capture, "utf8").trim().split("\n"),
        ["dispatch", "focuswindow", "address:0x01aB"]);

    fs.unlinkSync(capture);
    const rejected = spawnSync("bash", [script, "0x0; touch /tmp/nope"], { env, encoding: "utf8" });
    assert.equal(rejected.status, 2);
    assert.equal(fs.existsSync(capture), false);
} finally {
    fs.rmSync(scratch, { recursive: true, force: true });
}

console.log("Exposé layout and focus dispatch tests passed");
