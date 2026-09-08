pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: root

    signal wallpaperChanged(string screenName, string path, string transition)
    signal playbackChanged(string screenName, string state)
    signal wallpaperCleared(string screenName)

    property var screenWallpapers: ({})
    property var screenWallpaperPaths: ({})
    property var screenAwwwActive: ({})

    readonly property string backend: Config.getSetting("wallpaperBackend", "qml")

    readonly property bool anyAwwwActive: {
        if (backend !== "awww") return false;
        let keys = Object.keys(screenAwwwActive);
        for (let i = 0; i < keys.length; i++) {
            if (screenAwwwActive[keys[i]]) return true;
        }
        return false;
    }

    function _isVideo(p: string): bool {
        let lp = p.toLowerCase();
        return lp.endsWith(".mp4") || lp.endsWith(".mkv") ||
               lp.endsWith(".mov") || lp.endsWith(".webm");
    }

    function _awwwTransition(t: string): string {
        if (!t) return "fade";
        switch (t.toLowerCase()) {
            case "none": return "none";
            case "simple": return "simple";
            case "fade": return "fade";
            case "wipe": return "wipe";
            case "wave": return "wave";
            case "grow": return "grow";
            case "random": return "random";
            default: return "fade";
        }
    }

    function _awwwOutputFlag(screenName: string): string {
        if (!screenName || screenName === "all") return "--all";
        return "--outputs " + screenName;
    }

    function setWallpaper(screenName: string, path: string, transition: string): void {
        let cleanPath = String(path).trim();
        let isVid = _isVideo(cleanPath);

        // awww backend for images only — videos still go through QML
        if (backend === "awww" && !isVid) {
            let outputFlag = _awwwOutputFlag(screenName);
            let trans = _awwwTransition(transition);
            let awwwCmd = "awww img " + outputFlag + " --transition-type " + trans + " --transition-duration 1 '" + cleanPath + "'";
            Quickshell.execDetached(["bash", "-c", awwwCmd]);

            // Update in-memory state so picker/UI can read it
            let slash = cleanPath.lastIndexOf("/");
            let origName = cleanPath.substring(slash + 1);

            let wp = Object.assign({}, root.screenWallpapers);
            let wpp = Object.assign({}, root.screenWallpaperPaths);

            if (screenName === "all") {
                let screens = Quickshell.screens;
                for (let i = 0; i < screens.length; i++) {
                    let sn = screens[i].name;
                    wp[sn] = origName;
                    wpp[sn] = cleanPath;
                }
            } else {
                wp[screenName] = origName;
                wpp[screenName] = cleanPath;
            }

            root.screenWallpapers = wp;
            root.screenWallpaperPaths = wpp;

            // Mark awww as active per-screen so engine can go transparent
            let aw = Object.assign({}, root.screenAwwwActive);
            if (screenName === "all") {
                let screens = Quickshell.screens;
                for (let i = 0; i < screens.length; i++) {
                    aw[screens[i].name] = true;
                }
            } else {
                aw[screenName] = true;
            }
            root.screenAwwwActive = aw;

            // Persist state for restore on reload
            let wpCacheDir = (typeof Caching !== "undefined" && Caching.getCacheDir) ? Caching.getCacheDir("wallpaper") : "";
            if (wpCacheDir !== "") {
                let dot = cleanPath.lastIndexOf(".");
                let ext = (dot !== -1 && dot > slash) ? cleanPath.substring(dot) : "";
                let targets = [];
                if (screenName === "all") {
                    let screens = Quickshell.screens;
                    for (let i = 0; i < screens.length; i++) {
                        targets.push(screens[i].name);
                    }
                } else {
                    targets.push(screenName);
                }
                let copies = "";
                let stateWrites = "";
                let histFile = wpCacheDir + "/history.txt";
                for (let i = 0; i < targets.length; i++) {
                    let sn = targets[i];
                    let wpStatePath = wpCacheDir + "/current_" + sn;
                    let wpCopyDir = wpCacheDir + "/copy_" + sn;
                    let dest = wpCopyDir + "/wallpaper" + ext;
                    stateWrites += "printf '%s' '" + cleanPath + "' > '" + wpStatePath + "' && printf '%s' '" + origName + "' > '" + wpStatePath + "_name' && ";
                    copies += "mkdir -p '" + wpCopyDir + "' && cp -f '" + cleanPath + "' '" + dest + "' && ";
                }
                // Snapshot for lock screen (always generate for images)
                let snapshotPath = wpCacheDir + "/current_wallpaper.png";
                copies += "cp -f '" + cleanPath + "' '" + snapshotPath + "' && ";
                for (let i = 0; i < targets.length; i++) {
                    copies += "cp -f '" + cleanPath + "' '" + wpCacheDir + "/current_wallpaper_" + targets[i] + ".png' && ";
                }
                // History
                let histCmd = "( HIST='" + histFile + "'; if [ -f \"$HIST\" ]; then grep -v -F -x '" + origName + "' \"$HIST\" > \"$HIST.tmp\" 2>/dev/null || true; printf '%s\\n' '" + origName + "' | cat - \"$HIST.tmp\" > \"$HIST\" 2>/dev/null; rm -f \"$HIST.tmp\"; else printf '%s\\n' '" + origName + "' > \"$HIST\"; fi )";
                Quickshell.execDetached(["bash", "-c", stateWrites + copies + histCmd]);
            }

            return;
        }

        // QML backend (original) or video content — clear awww flag for this screen
        if (backend === "awww" && isVid) {
            let aw = Object.assign({}, root.screenAwwwActive);
            if (screenName === "all") {
                let screens = Quickshell.screens;
                for (let i = 0; i < screens.length; i++) delete aw[screens[i].name];
            } else {
                delete aw[screenName];
            }
            root.screenAwwwActive = aw;
        }
        root.wallpaperChanged(screenName, path, transition ? transition : "fade");
    }

    function getWallpaper(screenName: string): string {
        if (!screenName || screenName === "") {
            let keys = Object.keys(root.screenWallpapers);
            return keys.length > 0 ? root.screenWallpapers[keys[0]] : "";
        }
        return root.screenWallpapers[screenName] || "";
    }

    function getWallpaperPath(screenName: string): string {
        if (!screenName || screenName === "") {
            let keys = Object.keys(root.screenWallpaperPaths);
            return keys.length > 0 ? root.screenWallpaperPaths[keys[0]] : "";
        }
        return root.screenWallpaperPaths[screenName] || "";
    }

    function setPlayback(screenName: string, state: string): void {
        root.playbackChanged(screenName, state);
    }

    function clearWallpaper(screenName: string): void {
        root.wallpaperCleared(screenName);
    }

    IpcHandler {
        target: "wallpaper"

        function setWallpaper(screenName: string, path: string, transition: string): void {
            root.setWallpaper(screenName, path, transition);
        }

        function getWallpaper(screenName: string): string {
            return root.getWallpaper(screenName);
        }

        function getWallpaperPath(screenName: string): string {
            return root.getWallpaperPath(screenName);
        }

        function setPlayback(screenName: string, state: string): void {
            root.setPlayback(screenName, state);
        }

        function clearWallpaper(screenName: string): void {
            root.clearWallpaper(screenName);
        }
    }
}
