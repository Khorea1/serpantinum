pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../../"
import "../../quickactions/QuickactionsNavigation.js" as Navigation

Item {
    id: controller

    signal setIndexRequested(var screen, string index)
    signal showSystemUsageRequested(var screen)
    signal quickActionRequested(var screen, string action)

    function quickAction(action, monitor) {
        let settings = Config.getSetting("general", {});
        if (settings.quickactions === false || settings.performance) return "disabled";
        let screen = Navigation.resolveScreen(Quickshell.screens, Quickshell.cursorScreen, monitor);
        if (!screen) return "invalid monitor (use a screen name or cursor)";
        controller.quickActionRequested(screen, action);
        return "sent";
    }

    function targetScreen(screen) {
        if (screen) return screen;
        if (Quickshell.cursorScreen) return Quickshell.cursorScreen;
        return Quickshell.screens && Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }

    function setIndex(index, screen) {
        let target = targetScreen(screen);
        if (target) controller.setIndexRequested(target, index);
    }

    function showSystemUsage(screen) {
        let target = targetScreen(screen);
        if (target) controller.showSystemUsageRequested(target);
    }

    IpcHandler {
        target: "floating"

        function setIndex(index: string) {
            controller.setIndex(index, null);
        }

        function showSystemUsage() {
            controller.showSystemUsage(null);
        }

        function forceReload() {
            Quickshell.reload(true)
        }
    }

    // Exactly one IPC target for all screens. Panels receive routed signals.
    IpcHandler {
        target: "quickactions"

        function toggle(monitor: string): string { return controller.quickAction("toggle", monitor); }
        function show(monitor: string): string { return controller.quickAction("show", monitor); }
        function hide(monitor: string): string { return controller.quickAction("hide", monitor); }
        function nextSection(monitor: string): string { return controller.quickAction("nextSection", monitor); }
        function previousSection(monitor: string): string { return controller.quickAction("previousSection", monitor); }
        function expand(monitor: string): string { return controller.quickAction("expand", monitor); }
        function collapse(monitor: string): string { return controller.quickAction("collapse", monitor); }
        function moveForward(monitor: string): string { return controller.quickAction("moveForward", monitor); }
        function moveBackward(monitor: string): string { return controller.quickAction("moveBackward", monitor); }
    }
}
