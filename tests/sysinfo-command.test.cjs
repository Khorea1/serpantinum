const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const code = fs.readFileSync(path.join(__dirname, '../src/quickshell/bar/faces/sysinfo/SysInfoCommand.js'), 'utf8').replace('.pragma library', '');
const context = vm.createContext({});
vm.runInContext(code, context);
const resolve = input => Array.from(context.resolve(input));

assert.deepEqual(resolve({sysinfoCommand: ['foot', '-e', 'btop']}), ['foot', '-e', 'btop']);
assert.deepEqual(resolve({sysinfoCommand: ['kitty', '-e', 'btop']}), ['kitty', '-e', 'btop']);
for (const invalid of [undefined, null, '', 'kitty -e btop', [], [42], ['foot', ''], ['foot', null]]) {
    assert.deepEqual(resolve({sysinfoCommand: invalid}), []);
}
assert.deepEqual(resolve(null), []);
const original = ['foot', '-e', 'btop'];
const resolved = resolve({sysinfoCommand: original});
resolved[0] = 'other';
assert.equal(original[0], 'foot');
console.log('sysinfo command argv validation: PASS');
