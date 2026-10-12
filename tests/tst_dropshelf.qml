import QtQuick
import QtTest
import "../src/quickshell/quickactions/actions/DropShelfModel.js" as Shelf

TestCase {
    name: "DropShelfModel"

    function test_roundTripAndDeduplication() {
        const urls = ["file:///tmp/My%20file.txt", "https://example.org/photo.png", "file:///tmp/My%20file.txt"];
        const items = Shelf.addUrls([], urls);
        compare(items.length, 2);
        compare(Shelf.parseState(Shelf.serialize(items)).length, 2);
        compare(items[0].name, "My file.txt");
    }

    function test_rejectRemoteFileAndInvalidScheme() {
        compare(Shelf.isFileUri("file://other-host/private.txt"), false);
        compare(Shelf.isWebUrl("javascript:alert(1)"), false);
        compare(Shelf.localUrls(["file:///tmp/a", "file://other-host/a"]).length, 1);
    }

    function test_pathEncodingAndBadState() {
        compare(Shelf.fileUriForPath("/tmp/file #1?.png"), "file:///tmp/file%20%231%3F.png");
        compare(Shelf.webUrls([], "https://example.org/picture%23draft.png", "")[0], "https://example.org/picture%23draft.png");
        compare(Shelf.parseState("{incomplete").length, 0);
    }
}
