function resolveScreen(screens, cursorScreen, selector) {
    if (!selector) return null;
    if (selector === "cursor") {
        if (!cursorScreen) return null;
        let identical = Array.from(screens).find(screen => screen === cursorScreen);
        if (identical) return identical;
        let names = Array.from(screens).filter(screen => screen.name === cursorScreen.name);
        return names.length === 1 ? names[0] : null;
    }
    let matches = Array.from(screens).filter(screen => screen.name === selector);
    return matches.length === 1 ? matches[0] : null;
}

function sectionIndex(index, count, edge, direction) {
    if (count < 1) return index;
    let step = edge === "right" ? -direction : direction;
    return Math.max(0, Math.min(count - 1, index + step));
}

function movedPosition(edge, position, bounds, blockedEdge, direction) {
    if (direction !== 1 && direction !== -1) return null;
    let xSpan = Math.max(1, bounds.right - bounds.left);
    let ySpan = Math.max(1, bounds.bottom - bounds.top);
    let t;
    switch (edge) {
    case "top": t = (position - bounds.left) / xSpan; break;
    case "right": t = 1 + (position - bounds.top) / ySpan; break;
    case "bottom": t = 2 + (bounds.right - position) / xSpan; break;
    case "left": t = 3 + (bounds.bottom - position) / ySpan; break;
    default: return null;
    }

    // The bar consumes one edge; a keyboard move must never strand the panel there.
    for (let n = 1; n <= 16; ++n) {
        let next = ((t + direction * n * 0.25) % 4 + 4) % 4;
        let result;
        if (next < 1) result = { edge: "top", position: bounds.left + next * xSpan };
        else if (next < 2) result = { edge: "right", position: bounds.top + (next - 1) * ySpan };
        else if (next < 3) result = { edge: "bottom", position: bounds.right - (next - 2) * xSpan };
        else result = { edge: "left", position: bounds.bottom - (next - 3) * ySpan };
        if (result.edge !== blockedEdge) return result;
    }
    return null;
}
