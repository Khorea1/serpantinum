const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const context = vm.createContext({});
const source = path.join(__dirname, '../src/quickshell/quickactions/QuickactionsNavigation.js');
vm.runInContext(fs.readFileSync(source, 'utf8'), context);

test('monitor selectors route to one precise screen without fallback', () => {
    const left = { name: 'DP-1' };
    const right = { name: 'HDMI-A-1' };
    const screens = [left, right];
    assert.equal(context.resolveScreen(screens, left, 'HDMI-A-1'), right);
    assert.equal(context.resolveScreen(screens, right, 'cursor'), right);
    assert.equal(context.resolveScreen(screens, left, 'DP-9'), null);
    assert.equal(context.resolveScreen(screens, null, 'cursor'), null);
    assert.equal(context.resolveScreen(screens, left, ''), null);
    assert.equal(context.resolveScreen([left, { name: 'DP-1' }], left, 'DP-1'), null);
    assert.equal(context.resolveScreen([left, { name: 'DP-1' }], left, 'cursor'), left);
    assert.equal(context.resolveScreen([left, { name: 'DP-1' }], { name: 'DP-1' }, 'cursor'), null);
});

test('next and previous sections preserve orientation and bounds', () => {
    assert.equal(context.sectionIndex(1, 4, 'left', 1), 2);
    assert.equal(context.sectionIndex(1, 4, 'right', 1), 0);
    assert.equal(context.sectionIndex(1, 4, 'right', -1), 2);
    assert.equal(context.sectionIndex(0, 4, 'top', -1), 0);
    assert.equal(context.sectionIndex(3, 4, 'bottom', 1), 3);
    assert.equal(context.sectionIndex(0, 0, 'left', 1), 0);
});

test('movement visits valid edges and never overlaps a bar edge', () => {
    const bounds = { left: 50, right: 950, top: 20, bottom: 680 };
    for (const blocked of ['top', 'right', 'bottom', 'left']) {
        for (const direction of [-1, 1]) {
            let edge = blocked === 'left' ? 'right' : 'left';
            let position = 350;
            for (let i = 0; i < 32; i++) {
                const next = context.movedPosition(edge, position, bounds, blocked, direction);
                assert.ok(next);
                assert.notEqual(next.edge, blocked);
                assert.ok(next.position >= (next.edge === 'left' || next.edge === 'right' ? bounds.top : bounds.left));
                assert.ok(next.position <= (next.edge === 'left' || next.edge === 'right' ? bounds.bottom : bounds.right));
                edge = next.edge;
                position = next.position;
            }
        }
    }
    assert.equal(context.movedPosition('invalid', 0, bounds, 'top', 1), null);
    assert.equal(context.movedPosition('left', 0, bounds, 'top', 0), null);
});
