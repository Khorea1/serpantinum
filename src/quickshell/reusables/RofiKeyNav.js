.pragma library

// Shared "rofi-style" secondary navigation for selection widgets
// (a search input paired with a result list), unified across the shell:
//
//   row-up:   "Up,Control+k"
//   row-down: "Down,Control+j"
//
// Native Up/Down is handled by each widget's own Keys.onUpPressed /
// Keys.onDownPressed as before. This helper only covers the Ctrl+J / Ctrl+K
// secondary bindings, so every selection widget (launcher, clipboard, file
// picker, dropdown, ...) reacts to them the same way instead of each one
// reimplementing (or forgetting to implement) the modifier check.
//
// Usage, inside a Keys.onPressed handler on the search input:
//
//   Keys.onPressed: function(event) {
//       if (RofiKeyNav.handlePressed(event, moveSelectionDown, moveSelectionUp)) {
//           event.accepted = true;
//       }
//   }
//
// `moveDown` / `moveUp` are zero-arg callbacks that advance/retreat the
// widget's own currentIndex (and take care of anything else the widget does
// on keyboard navigation, e.g. flagging keyboard-nav mode). This function
// only decides whether Ctrl+J / Ctrl+K was pressed and dispatches to them.
//
// Returns true if the event was handled.
function handlePressed(event, moveDown, moveUp) {
    if (!(event.modifiers & Qt.ControlModifier)) {
        return false;
    }

    if (event.key === Qt.Key_J) {
        moveDown();
        return true;
    }

    if (event.key === Qt.Key_K) {
        moveUp();
        return true;
    }

    return false;
}
