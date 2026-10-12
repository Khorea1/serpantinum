import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../"
import "DropShelfModel.js" as Model

// Adapted from Mustafa2624/serpantinum-plus (1a4d80b).
// Dragging uses CopyAction. Entries are removed only via explicit UI actions.

Item {
    id: root

    property int requestedLayoutTemplate: 1
    property bool isActiveTab: typeof isCurrentTarget !== "undefined" ? isCurrentTarget : true
    property string safeActiveEdge: typeof activeEdge !== "undefined" ? activeEdge : "left"

    function s(v) {
        return typeof scaleFunc === "function" ? scaleFunc(v) : v;
    }

    property real baseW: s(360)
    property real baseL: s(420)
    property real preferredWidth: (root.safeActiveEdge === "bottom" || root.safeActiveEdge === "top") ? baseL : baseW
    property real preferredExtraLength: (root.safeActiveEdge === "bottom" || root.safeActiveEdge === "top") ? baseW : baseL

    property real counterRotation: {
        if (root.safeActiveEdge === "right") return 180;
        if (root.safeActiveEdge === "bottom") return 90;
        if (root.safeActiveEdge === "top") return -90;
        return 0;
    }

    property var entries: []
    property string statusText: I18n.t("quickactions.dropshelf.empty_status")
    property var pendingCandidates: []
    property int candidateAttempts: 0
    readonly property int maxCandidateAttempts: 4
    property var undoEntries: []
    property bool canUndo: false
    property bool stateLoaded: false
    property bool stateDirectoryReady: false
    property bool pendingSave: false
    property bool saveInFlight: false
    readonly property int maxImageBytes: 12 * 1024 * 1024

    readonly property string stateDir: {
        const configured = Quickshell.env("XDG_STATE_HOME");
        return configured && configured.startsWith("/")
            ? configured + "/serpantinum/dropshelf"
            : (Quickshell.env("HOME") || "~") + "/.local/state/serpantinum/dropshelf";
    }
    readonly property string statePath: root.stateDir + "/shelf.json"
    readonly property string dataDir: {
        const configured = Quickshell.env("XDG_DATA_HOME");
        return configured && configured.startsWith("/")
            ? configured + "/serpantinum/dropshelf"
            : (Quickshell.env("HOME") || "~") + "/.local/share/serpantinum/dropshelf";
    }

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
    function mutedColor() { return alpha(ThemeBackend.text, 0.62); }
    function subtleColor() { return alpha(ThemeBackend.text, 0.08); }
    function hairlineColor() { return alpha(ThemeBackend.text, 0.18); }
    function bgColor() { return ThemeBackend.surface0 || alpha(ThemeBackend.text, 0.06); }
    function accentColor() { return ThemeBackend.mauve; }
    function radius() { return Math.max(0, s(ThemeBackend.borderRadius || 8)); }

    function updateStatus() {
        statusText = entries.length === 0
            ? I18n.t("quickactions.dropshelf.empty_status")
            : I18n.t("quickactions.dropshelf.count", { count: entries.length });
    }

    function loadState(text) {
        if (!stateDirectoryReady || pendingSave || saveInFlight) return;
        const restored = Model.parseState(text);
        if (stateLoaded && Model.serialize(entries) === Model.serialize(restored)) return;
        entries = restored;
        stateLoaded = true;
        undoEntries = [];
        canUndo = false;
        updateStatus();
    }

    function persist() {
        if (!stateLoaded) return;
        pendingSave = true;
        flushSave();
    }

    function flushSave() {
        if (!pendingSave || !stateDirectoryReady || !stateLoaded || saveInFlight) return;
        pendingSave = false;
        saveInFlight = true;
        stateFile.setText(Model.serialize(entries));
    }

    function rememberUndo() {
        undoEntries = entries.slice();
        canUndo = true;
    }

    function removeAt(index) {
        if (index < 0 || index >= entries.length) return;
        rememberUndo();
        entries = Model.removeAt(entries, index);
        updateStatus();
        persist();
    }

    function undoRemove() {
        if (!canUndo) return;
        entries = undoEntries;
        undoEntries = [];
        canUndo = false;
        updateStatus();
        persist();
    }

    function clearShelf() {
        if (entries.length === 0) return;
        rememberUndo();
        entries = [];
        statusText = I18n.t("quickactions.dropshelf.cleared");
        persist();
    }

    function imageMimeFormat(formats) {
        const preferred = ["image/gif", "image/webp", "image/png", "image/jpeg", "image/avif", "image/bmp"];
        for (let i = 0; i < preferred.length; i++)
            if (formats.indexOf(preferred[i]) !== -1) return preferred[i];
        return "";
    }

    function firstMimeText(drop, formats) {
        for (let i = 0; i < formats.length; i++) {
            if ((drop.formats || []).indexOf(formats[i]) === -1) continue;
            const value = String(drop.getDataAsString(formats[i]) || "").trim();
            if (value !== "") return value;
        }
        return "";
    }

    function anyTextMime(drop) {
        const formats = drop.formats || [];
        for (let i = 0; i < formats.length; i++) {
            const format = String(formats[i]);
            if (!/^text\//i.test(format) && format.toLowerCase().indexOf("url") === -1) continue;
            const value = String(drop.getDataAsString(format) || "").trim();
            if (value.indexOf("http://") !== -1 || value.indexOf("https://") !== -1)
                return value;
        }
        return "";
    }

    function addDrop(drop) {
        const urls = Model.localUrls(drop.urls || []);
        if (urls.length > 0) {
            const next = Model.addUrls(entries, urls);
            const added = next.length - entries.length;
            entries = next;
            statusText = added > 0 ? I18n.t("quickactions.dropshelf.added", { count: added }) : I18n.t("quickactions.dropshelf.already_added");
            persist();
            return true;
        }

        if (downloader.running || imageWriter.running) {
            statusText = I18n.t("quickactions.dropshelf.busy");
            return false;
        }

        const nativeUrl = firstMimeText(drop, [
            "application/x-moz-file-promise-url",
            "application/x-moz-url",
            "text/x-moz-url",
            "DownloadURL"
        ]) || anyTextMime(drop);

        const directLinks = Model.webUrls(
            drop.urls || [],
            drop.hasText ? drop.text : "",
            nativeUrl
        );

        pendingCandidates = Model.remoteImageCandidates(
            drop.urls || [],
            drop.hasText ? drop.text : "",
            drop.hasHtml ? drop.html : "",
            nativeUrl
        );
        candidateAttempts = 0;

        const imageFormat = imageMimeFormat(drop.formats || []);
        if (imageFormat !== "") {
            const bytes = drop.getDataAsArrayBuffer(imageFormat);
            if (bytes.byteLength > maxImageBytes) {
                statusText = I18n.t("quickactions.dropshelf.image_too_large");
                return false;
            }
            importBase64Image(imageFormat, Model.base64FromArrayBuffer(bytes));
            return true;
        }

        const imageCandidates = pendingCandidates.filter(function(candidate) {
            return Model.looksLikeImageSource(candidate);
        });

        if (imageCandidates.length > 0) {
            pendingCandidates = imageCandidates;
            tryNextCandidate();
            return true;
        }

        if (directLinks.length > 0) {
            const next = Model.addUrls(entries, directLinks);
            const added = next.length - entries.length;
            entries = next;
            statusText = added > 0
                ? I18n.t("quickactions.dropshelf.links_added", { count: added })
                : I18n.t("quickactions.dropshelf.already_added");
            persist();
            return true;
        }

        statusText = I18n.t("quickactions.dropshelf.invalid_drop");
        return false;
    }

    function tryNextCandidate() {
        if (candidateAttempts >= maxCandidateAttempts || pendingCandidates.length === 0) {
            pendingCandidates = [];
            statusText = I18n.t("quickactions.dropshelf.image_error");
            return;
        }
        const next = String(pendingCandidates.shift());
        candidateAttempts++;
        const data = Model.parseDataUri(next);
        if (data !== null) {
            importBase64Image(data.mime, data.base64);
            return;
        }
        startDownload(next);
    }

    function importFinished() {
        pendingCandidates = [];
        candidateAttempts = 0;
    }

    function importBase64Image(mime, base64) {
        if (base64.length > Math.ceil(maxImageBytes / 3) * 4) {
            statusText = I18n.t("quickactions.dropshelf.image_too_large");
            pendingCandidates = [];
            return;
        }
        const suffix = String(mime).split("/").pop().replace(/[^a-zA-Z0-9]/g, "") || "img";
        statusText = I18n.t("quickactions.dropshelf.saving_image");
        imageWriter.command = [
            "bash", "-c",
            "set -e; umask 077; ulimit -f 12288; mkdir -p -- \"$1\"; out=$(mktemp --tmpdir=\"$1\" dropshelf-XXXXXX.\"$2\"); trap 'rm -f -- \"$out\"' EXIT; base64 -d > \"$out\"; test \"$(stat -c%s -- \"$out\")\" -le 12582912; file -Lb --mime-type \"$out\" | grep -q '^image/'; trap - EXIT; printf '%s' \"$out\"",
            "serpantinum-dropshelf", root.dataDir, suffix
        ];
        imageWriter.stdinEnabled = true;
        imageWriter.running = true;
        imageWriter.write(base64);
        imageWriter.stdinEnabled = false;
    }

    function startDownload(url) {
        statusText = candidateAttempts > 1 ? I18n.t("quickactions.dropshelf.retrying_image") : I18n.t("quickactions.dropshelf.saving_image");
        downloader.command = [
            "bash", "-c",
            "set -e; umask 077; ulimit -f 12288; mkdir -p -- \"$1\"; out=$(mktemp --tmpdir=\"$1\" dropshelf-XXXXXX); trap 'rm -f -- \"$out\"' EXIT; curl -fL --max-time 30 --max-filesize 12582912 --proto '=http,https' --proto-redir '=http,https' -A 'Mozilla/5.0' -e \"$3\" -o \"$out\" -- \"$2\"; test \"$(stat -c%s -- \"$out\")\" -le 12582912; mime=$(file -Lb --mime-type \"$out\"); case \"$mime\" in image/*) ;; *) exit 65 ;; esac; ext=$(printf '%s' \"${mime#image/}\" | tr -cd 'a-zA-Z0-9'); final=\"${out}.${ext:-img}\"; mv -- \"$out\" \"$final\"; trap - EXIT; printf '%s' \"$final\"",
            "serpantinum-dropshelf", root.dataDir, url, Model.refererFor(url)
        ];
        downloader.running = true;
    }

    FileView {
        id: stateFile
        path: root.statePath
        preload: false
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onFileChanged: {
            if (!root.saveInFlight && !root.pendingSave) reload();
        }
        onLoaded: root.loadState(text())
        onLoadFailed: function(error) {
            if (error === FileViewError.FileNotFound) root.loadState("");
            else root.statusText = I18n.t("quickactions.dropshelf.save_error");
        }
        onSaved: {
            root.saveInFlight = false;
            root.flushSave();
        }
        onSaveFailed: function(error) {
            root.saveInFlight = false;
            root.pendingSave = true;
            root.statusText = I18n.t("quickactions.dropshelf.save_error");
        }
    }

    Process {
        id: stateInitProc
        command: ["mkdir", "-p", "-m", "0700", root.stateDir]
        onExited: function(exitCode) {
            root.stateDirectoryReady = exitCode === 0;
            if (exitCode !== 0) root.statusText = I18n.t("quickactions.dropshelf.save_error");
            else stateFile.reload();
        }
    }

    Component.onCompleted: {
        stateInitProc.running = true;
    }

    Process {
        id: downloader
        running: false
        stdout: StdioCollector { id: downloadOutput; waitForEnd: true }
        onExited: function(exitCode) {
            const path = String(downloadOutput.text || "").trim();
            if (exitCode !== 0 || path === "") {
                root.tryNextCandidate();
                return;
            }
            root.importFinished();
            const uri = Model.fileUriForPath(path);
            root.entries = Model.addUrls(root.entries, [uri]);
            root.statusText = I18n.t("quickactions.dropshelf.image_added");
            root.persist();
        }
    }

    Process {
        id: imageWriter
        running: false
        stdout: StdioCollector { id: imageWriterOutput; waitForEnd: true }
        onExited: function(exitCode) {
            const path = String(imageWriterOutput.text || "").trim();
            if (exitCode !== 0 || path === "") {
                root.tryNextCandidate();
                return;
            }
            root.importFinished();
            const uri = Model.fileUriForPath(path);
            root.entries = Model.addUrls(root.entries, [uri]);
            root.statusText = I18n.t("quickactions.dropshelf.image_added");
            root.persist();
        }
    }

    Item {
        id: rotatedRoot
        anchors.fill: parent
        rotation: root.counterRotation
        transformOrigin: Item.Center

        Rectangle {
            anchors.fill: parent
            radius: root.radius()
            color: alpha(ThemeBackend.surface0, 0.98)
            border.width: Math.max(1, root.s(1))
            border.color: hairlineColor()
            clip: true

            DropArea {
                id: dropArea
                anchors.fill: parent
                anchors.margins: root.s(2)
                enabled: root.stateLoaded && root.stateDirectoryReady

                onDropped: function(drop) {
                    if (!(drop.supportedActions & Qt.CopyAction)) {
                        root.statusText = I18n.t("quickactions.dropshelf.invalid_drop");
                        return;
                    }
                    if (root.addDrop(drop)) drop.accept(Qt.CopyAction);
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: root.s(5)
                    radius: Math.max(0, root.radius() - root.s(2))
                    color: dropArea.containsDrag ? alpha(accentColor(), 0.10) : "transparent"
                    border.width: dropArea.containsDrag ? root.s(2) : 0
                    border.color: accentColor()
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.s(14)
                    spacing: root.s(10)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.s(10)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: root.s(1)

                            Text {
                                Layout.fillWidth: true
                                text: I18n.t("quickactions.dropshelf.title")
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: root.s(18)
                                font.weight: Font.Black
                                font.bold: true
                                color: ThemeBackend.text
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.statusText
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: root.s(9)
                                font.weight: Font.Black
                                font.bold: true
                                color: mutedColor()
                                elide: Text.ElideRight
                            }
                        }

                        Row {
                            spacing: root.s(6)

                            Rectangle {
                                visible: root.canUndo
                                width: undoText.implicitWidth + root.s(18)
                                height: root.s(28)
                                radius: Math.max(0, root.radius() - root.s(2))
                                color: alpha(ThemeBackend.text, 0.07)
                                border.width: root.s(1)
                                border.color: hairlineColor()

                                Text {
                                    id: undoText
                                    anchors.centerIn: parent
                                    text: I18n.t("quickactions.dropshelf.undo")
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: root.s(9)
                                    font.weight: Font.Black
                                    color: ThemeBackend.text
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.undoRemove()
                                }
                            }

                            Rectangle {
                                visible: root.entries.length > 0
                                width: clearText.implicitWidth + root.s(18)
                                height: root.s(28)
                                radius: Math.max(0, root.radius() - root.s(2))
                                color: alpha(ThemeBackend.text, 0.07)
                                border.width: root.s(1)
                                border.color: hairlineColor()

                                Text {
                                    id: clearText
                                    anchors.centerIn: parent
                                    text: I18n.t("quickactions.dropshelf.clear")
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: root.s(9)
                                    font.weight: Font.Black
                                    color: ThemeBackend.text
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.clearShelf()
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: root.s(1)
                        color: hairlineColor()
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Column {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, root.s(280))
                            spacing: root.s(8)
                            visible: root.entries.length === 0

                            Text {
                                width: parent.width
                                text: dropArea.containsDrag ? "󰉋" : "󰉋"
                                horizontalAlignment: Text.AlignHCenter
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: root.s(38)
                                color: dropArea.containsDrag ? accentColor() : mutedColor()
                            }
                            Text {
                                width: parent.width
                                text: dropArea.containsDrag ? I18n.t("quickactions.dropshelf.release") : I18n.t("quickactions.dropshelf.drop_hint")
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: root.s(13)
                                font.weight: Font.Black
                                font.bold: true
                                color: ThemeBackend.text
                            }
                            Text {
                                width: parent.width
                                text: I18n.t("quickactions.dropshelf.description")
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: root.s(9)
                                color: mutedColor()
                            }
                        }

                        GridView {
                            id: shelfGrid
                            anchors.fill: parent
                            visible: root.entries.length > 0
                            clip: true
                            model: root.entries
                            cellWidth: width / Math.max(1, Math.floor(width / root.s(112)))
                            cellHeight: root.s(128)
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Item {
                                id: tile
                                required property var modelData
                                required property int index

                                width: shelfGrid.cellWidth
                                height: shelfGrid.cellHeight

                                readonly property string uri: String(modelData.uri || "")
                                readonly property string name: String(modelData.name || I18n.t("quickactions.dropshelf.file"))
                                readonly property bool linkItem: String(modelData.kind || "") === "link" || Model.isWebUrl(uri)
                                readonly property bool imageFile: !linkItem && Model.isImage(name)
                                property var grabResult: null

                                Rectangle {
                                    id: tileSurface
                                    anchors.fill: parent
                                    anchors.margins: root.s(5)
                                    radius: Math.max(0, root.radius() - root.s(1))
                                    color: tileMouse.containsMouse || tile.Drag.active ? subtleColor() : "transparent"
                                    border.width: root.s(1)
                                    border.color: tile.Drag.active ? accentColor() : hairlineColor()

                                    Image {
                                        id: thumbnail
                                        anchors.top: parent.top
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.topMargin: root.s(9)
                                        width: root.s(70)
                                        height: root.s(70)
                                        source: tile.imageFile ? tile.uri : ""
                                        visible: tile.imageFile && status === Image.Ready
                                        asynchronous: true
                                        cache: true
                                        fillMode: Image.PreserveAspectCrop
                                        sourceSize: Qt.size(width * 2, height * 2)
                                    }

                                    Text {
                                        anchors.centerIn: thumbnail
                                        visible: !thumbnail.visible
                                        text: tile.linkItem ? "󰌷" : "󰈔"
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: root.s(34)
                                        color: mutedColor()
                                    }

                                    Rectangle {
                                        visible: tile.linkItem
                                        anchors.top: parent.top
                                        anchors.left: parent.left
                                        anchors.margins: root.s(8)
                                        width: linkBadge.implicitWidth + root.s(10)
                                        height: root.s(20)
                                        radius: root.s(10)
                                        color: alpha(accentColor(), 0.14)
                                        border.width: root.s(1)
                                        border.color: alpha(accentColor(), 0.35)
                                        z: 2

                                        Text {
                                            id: linkBadge
                                            anchors.centerIn: parent
                                            text: I18n.t("quickactions.dropshelf.link_badge")
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: root.s(7)
                                            font.weight: Font.Black
                                            color: accentColor()
                                        }
                                    }

                                    Text {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: root.s(8)
                                        text: tile.name
                                        textFormat: Text.PlainText
                                        horizontalAlignment: Text.AlignHCenter
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: root.s(8)
                                        font.weight: Font.Black
                                        color: ThemeBackend.text
                                        elide: Text.ElideMiddle
                                    }

                                    Rectangle {
                                        id: removeButton
                                        width: root.s(22)
                                        height: width
                                        radius: width / 2
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: root.s(5)
                                        visible: tileMouse.containsMouse && !tile.Drag.active
                                        z: 2
                                        color: alpha(ThemeBackend.surface0, 0.92)
                                        border.width: root.s(1)
                                        border.color: hairlineColor()

                                        Text {
                                            anchors.centerIn: parent
                                            text: "×"
                                            font.pixelSize: root.s(14)
                                            font.weight: Font.Black
                                            color: ThemeBackend.text
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            z: 3
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.removeAt(tile.index)
                                        }
                                    }
                                }

                                Drag.active: tileMouse.drag.active
                                Drag.mimeData: ({ "text/uri-list": tile.uri + "\r\n" })
                                Drag.supportedActions: Qt.CopyAction
                                Drag.proposedAction: Qt.CopyAction
                                Drag.dragType: Drag.Automatic
                                Drag.imageSource: tile.imageFile ? tile.uri : ""
                                Drag.hotSpot.x: width / 2
                                Drag.hotSpot.y: height / 2

                                Drag.onDragFinished: function(dropAction) {
                                    tile.x = 0;
                                    tile.y = 0;
                                    // A copy or a cancelled drag must leave the item in the shelf.
                                }

                                MouseArea {
                                    id: tileMouse
                                    anchors.fill: parent
                                    z: 1
                                    hoverEnabled: true
                                    cursorShape: tile.linkItem ? Qt.PointingHandCursor : Qt.OpenHandCursor
                                    drag.target: tile
                                    preventStealing: true

                                    onPressed: {
                                        if (!tile.imageFile) {
                                            tileSurface.grabToImage(function(result) {
                                                tile.grabResult = result;
                                                tile.Drag.imageSource = result.url;
                                            });
                                        }
                                    }

                                    onDoubleClicked: Quickshell.execDetached(["xdg-open", tile.uri])
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
