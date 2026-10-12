// Runs with Node.js; QML's .pragma library directive is removed only for this test.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const modelPath = path.resolve(__dirname, '../src/quickshell/quickactions/actions/DropShelfModel.js');
const source = fs.readFileSync(modelPath, 'utf8').replace(/^\.pragma library\s*/u, '');
const model = vm.createContext({});
vm.runInContext(source, model, { filename: modelPath });

const local = 'file:///home/example/My%20File.txt';
const remote = 'https://example.com/images/test.png';
const items = model.addUrls([], [local, remote, local]);
assert.equal(items.length, 2);
assert.equal(items[0].name, 'My File.txt');
assert.equal(items[1].kind, 'link');
assert.equal(model.isFileUri('file://remote.example/file'), false);
assert.equal(model.isWebUrl('javascript:alert(1)'), false);
assert.equal(model.localUrls([local, 'file://remote.example/file', local]).length, 1);
assert.equal(model.fileUriForPath('/tmp/a #1?.png'), 'file:///tmp/a%20%231%3F.png');
assert.equal(model.fileUriForPath('relative/name.txt'), '');
assert.equal(model.webUrls([], 'https://example.org/picture%23draft.png', '')[0],
  'https://example.org/picture%23draft.png');

const restored = model.parseState(model.serialize(items));
assert.equal(restored.length, 2);
assert.equal(restored[0].uri, local);
assert.equal(restored[1].uri, remote);
assert.equal(model.removeAt(restored, 0).length, 1);
assert.equal(model.parseState('corrupt json').length, 0);
assert.equal(model.parseState(JSON.stringify({ items: [
  { uri: local }, { uri: local }, { uri: 'file://host/private' }, { uri: 'javascript:bad' }
] })).length, 1);

const oversized = Array.from({ length: 280 }, (_, i) => `file:///tmp/sample-${i}`);
assert.equal(model.addUrls([], oversized).length, 256);
assert.equal(model.parseState(model.serialize(model.addUrls([], oversized))).length, 256);
assert.equal(model.parseDataUri('data:image/png;base64,YQ==').mime, 'image/png');
assert.equal(model.parseDataUri('data:text/html;base64,YQ=='), null);
assert.equal(model.parseDataUri('data:image/png;base64,**'), null);

console.log('Drop Shelf model checks passed');
