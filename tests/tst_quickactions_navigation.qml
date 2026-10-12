import QtQuick
import QtTest
import "../src/quickshell/quickactions/QuickactionsNavigation.js" as Navigation

TestCase {
    name: "QuickactionsNavigation"

    function test_monitorRouting() {
        let first = { name: "DP-1" };
        let second = { name: "HDMI-A-1" };
        let screens = [first, second];
        compare(Navigation.resolveScreen(screens, first, "HDMI-A-1"), second);
        compare(Navigation.resolveScreen(screens, first, "cursor"), first);
        compare(Navigation.resolveScreen(screens, first, "DP-9"), null);
    }

    function test_navigation() {
        compare(Navigation.sectionIndex(1, 4, "right", 1), 0);
        compare(Navigation.sectionIndex(1, 4, "left", 1), 2);
    }

    function test_barEdgeIsSkipped() {
        let bounds = { left: 0, right: 1600, top: 0, bottom: 900 };
        for (let blocked of ["left", "right", "top", "bottom"]) {
            let result = Navigation.movedPosition("left", 450, bounds, blocked, 1);
            verify(result !== null);
            verify(result.edge !== blocked);
        }
    }
}
