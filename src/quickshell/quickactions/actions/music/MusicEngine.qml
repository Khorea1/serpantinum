import QtQuick
import Quickshell
import Quickshell.Io
import "../../../"

// QuickAction-local music engine.
// This is intentionally NOT a singleton: when the QuickAction Loader unloads
// Music.qml, this object is destroyed and its mpv bridge is shut down too.
Item {
    id: root

    property string musicDir: Quickshell.env("SERPANTINUM_MUSIC_DIR") || (Quickshell.env("HOME") + "/Music")

    readonly property string scanScript: Qt.resolvedUrl("scan.py").toString().replace("file://", "")
    readonly property string mpvScript: Qt.resolvedUrl("bridge.py").toString().replace("file://", "")

    property var library: []
    readonly property int libraryCount: library.length
    property bool scanned: false

    property string currentPath: ""
    property int currentIndex: -1
    property string mediaTitle: ""
    property string tagTitle: ""
    property string tagArtist: ""
    readonly property string title: tagTitle !== "" ? tagTitle : mediaTitle
    readonly property string artist: tagArtist
    property real position: 0
    property real duration: 0
    property bool paused: true
    property bool idle: true
    readonly property bool hasTrack: !idle && currentPath !== ""
    readonly property bool playing: hasTrack && !paused
    readonly property real progress: duration > 0 ? Math.min(1, position / duration) : 0

    property bool shuffle: false
    property int repeatMode: 0
    property string status: ""

    property bool active: false
    property bool playlistLoaded: false
    property string pendingPath: ""
    property var queue: []
    property bool shuttingDown: false
    readonly property int playlistReq: 4242

    function activate() {
        if (active || shuttingDown) return
        active = true
        rescan()
    }

    function shutdown() {
        if (shuttingDown) return
        shuttingDown = true
        active = false
        queue = []

        if (scanProc.running) scanProc.running = false
        if (mpvProc.running) mpvProc.running = false
    }

    Component.onDestruction: root.shutdown()

    function rescan() {
        if (!scanProc.running && !shuttingDown) scanProc.running = true
    }

    function fmt(sec) {
        let s = Math.max(0, Math.floor(sec || 0))
        let h = Math.floor(s / 3600)
        let m = Math.floor((s % 3600) / 60)
        let r = s % 60
        let rr = (r < 10 ? "0" : "") + r
        if (h > 0) return h + ":" + (m < 10 ? "0" : "") + m + ":" + rr
        return m + ":" + rr
    }

    function prettyName(p) {
        let b = p.split("/").pop().replace(/\.[^.]+$/, "")
        b = b.replace(/^\s*\d{1,3}\s*[-._)]\s*/, "")
        return b.replace(/_/g, " ")
    }

    function parentName(p) {
        let parts = p.split("/")
        if (parts.length < 2) return ""
        if (parts.slice(0, -1).join("/") === root.musicDir.replace(/\/+$/, "")) return ""
        return parts[parts.length - 2]
    }

    function parseLibrary(text) {
        if (shuttingDown) return
        let paths;
        try { paths = JSON.parse(text); } catch (e) {
            root.status = I18n.t("quickactions.music.scan_error");
            root.scanned = true;
            return;
        }
        root.library = paths.map(p => ({ path: p, name: root.prettyName(p), sub: root.parentName(p) }))
        root.scanned = true
        root.playlistLoaded = false
        root.updateIndex()
    }

    function updateIndex() {
        root.currentIndex = root.currentPath !== "" ? root.library.findIndex(e => e.path === root.currentPath) : -1
    }

    property bool linked: false

    function send(cmd, reqId) {
        if (!linked || shuttingDown) return
        let o = { command: cmd }
        if (reqId !== undefined) o.request_id = reqId
        mpvProc.write(JSON.stringify(o) + "\n")
    }

    function sendBatch(cmds) {
        if (!linked || shuttingDown) return
        mpvProc.write(cmds.map(c => JSON.stringify({ command: c })).join("\n") + "\n")
    }

    function ensure(cb) {
        if (shuttingDown) return
        if (linked) { cb(); return }
        root.queue.push(cb)
        if (!mpvProc.running) mpvProc.running = true
    }

    function handleOpened() {
        if (shuttingDown) return
        root.status = ""
        let props = ["time-pos", "duration", "pause", "path", "idle-active", "metadata", "media-title"]
        props.forEach((p, i) => root.send(["observe_property", i + 1, p]))
        root.applyRepeat()
        let q = root.queue
        root.queue = []
        q.forEach(fn => fn())
    }

    function handleClosed() {
        root.playlistLoaded = false
        root.idle = true
        root.paused = true
        root.currentPath = ""
        root.currentIndex = -1
        root.mediaTitle = ""
        root.tagTitle = ""
        root.tagArtist = ""
        root.position = 0
        root.duration = 0
    }

    function applyMeta(m) {
        let t = "", a = ""
        if (m) {
            for (const k in m) {
                let lk = k.toLowerCase()
                if (lk === "title") t = String(m[k])
                else if (lk === "artist") a = String(m[k])
                else if (lk === "album_artist" && a === "") a = String(m[k])
            }
        }
        root.tagTitle = t
        root.tagArtist = a
    }

    function handleLine(line) {
        let o
        try { o = JSON.parse(line) } catch (e) { return }

        if (o.bridge === "connected") { root.linked = true; root.handleOpened(); return }
        if (o.bridge === "error") {
            root.status = I18n.t(o.code === "missing_mpv" ? "quickactions.music.missing_mpv" : "quickactions.music.start_error");
            root.queue = [];
            return;
        }

        if (o.event === "property-change") {
            switch (o.name) {
            case "time-pos":
                root.position = (o.data === undefined || o.data === null) ? 0 : o.data
                break
            case "duration":
                root.duration = o.data || 0
                break
            case "pause":
                root.paused = !!o.data
                break
            case "path":
                root.currentPath = o.data || ""
                if (root.currentPath !== "") root.status = ""
                root.updateIndex()
                break
            case "idle-active": {
                let v = !!o.data
                if (v && !root.idle) root.playlistLoaded = false
                root.idle = v
                if (v) { root.position = 0; root.duration = 0 }
                break
            }
            case "metadata":
                root.applyMeta(o.data)
                break
            case "media-title":
                root.mediaTitle = o.data || ""
                break
            }
        } else if (o.event === "end-file") {
            if (o.reason === "error")
                root.status = I18n.t("quickactions.music.play_error") + (o.file_error ? " (" + o.file_error + ")" : "")
        } else if (o.request_id === root.playlistReq && o.error === "success") {
            let list = o.data || []
            if (list.length === 0) { root.status = I18n.t("quickactions.music.empty_playlist"); return }
            let idx = root.pendingPath !== "" ? list.findIndex(e => e.filename === root.pendingPath) : 0
            if (idx < 0) idx = 0
            root.send(["set_property", "pause", false])
            root.send(["playlist-play-index", idx])
        }
    }

    function startPlayback(path) {
        if (root.libraryCount === 0 || shuttingDown) return
        root.status = ""
        root.ensure(function () {
            if (!root.playlistLoaded) {
                let cmds = [["playlist-clear"]]
                root.library.forEach(e => cmds.push(["loadfile", e.path, "append"]))
                if (root.shuffle) cmds.push(["playlist-shuffle"])
                root.sendBatch(cmds)
                root.playlistLoaded = true
            }
            root.pendingPath = path
            root.send(["get_property", "playlist"], root.playlistReq)
        })
    }

    function playPath(p) { startPlayback(p) }

    function togglePlay() {
        if (!hasTrack) { startPlayback(""); return }
        send(["cycle", "pause"])
    }

    function next() {
        if (!hasTrack) { startPlayback(""); return }
        send(["playlist-next"])
    }

    function prev() {
        if (!hasTrack) { startPlayback(""); return }
        if (position > 3) send(["seek", 0, "absolute"])
        else send(["playlist-prev"])
    }

    function seek(sec) {
        if (hasTrack) send(["seek", sec, "absolute"])
    }

    function toggleShuffle() {
        shuffle = !shuffle
        if (linked && playlistLoaded) send([shuffle ? "playlist-shuffle" : "playlist-unshuffle"])
    }

    function cycleRepeat() {
        repeatMode = (repeatMode + 1) % 3
        applyRepeat()
    }

    function applyRepeat() {
        send(["set_property", "loop-playlist", repeatMode === 1 ? "inf" : "no"])
        send(["set_property", "loop-file", repeatMode === 2 ? "inf" : "no"])
    }

    Process {
        id: scanProc
        command: ["python3", root.scanScript, root.musicDir]
        stdout: StdioCollector {
            onStreamFinished: root.parseLibrary(this.text)
        }
    }

    Process {
        id: mpvProc
        command: ["python3", root.mpvScript]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => root.handleLine(data)
        }
        onRunningChanged: {
            if (!running) { root.linked = false; root.handleClosed() }
        }
        onExited: (code, st) => {
            if (code !== 0 && root.status === "" && !root.shuttingDown)
                root.status = I18n.t("quickactions.music.mpv_exit", { code: code })
        }
    }
}
