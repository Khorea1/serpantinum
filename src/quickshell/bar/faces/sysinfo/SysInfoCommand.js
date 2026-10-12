.pragma library

// Only argv arrays are accepted; strings would require a shell interpreter.
function resolve(barSettings) {
    const command = barSettings ? barSettings.sysinfoCommand : null;
    if (!Array.isArray(command) || command.length === 0) return [];
    if (!command.every(arg => typeof arg === "string" && arg.length > 0)) return [];
    return command.slice();
}
