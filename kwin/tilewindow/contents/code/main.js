// Layout config: processName -> position -> fn(sw, sh) => {x, y, width, height}
const layoutConfig = {
    "default": {
        "center_i": function(sw, sh) {
            const w = Math.round(sw * 11 / 16);
            const h = sh - 120;
            return { width: w, height: h, x: Math.round((sw - w) / 2), y: 23 };
        },
        "center_j": function(sw, sh) {
            const w = Math.round(sw * 3 / 5);
            const h = Math.round(sh * 17 / 20);
            return { width: w, height: h, x: Math.round((sw - w) / 2), y: Math.round((sh - h) / 2) };
        },
    },
    "kitty": {
        "center_i": function(sw, sh) {
            const w = 1567;
            const h = 1195;
            return { width: w, height: h, x: Math.round((sw - w) / 2), y: Math.round((sh - h) / 2) };
        },
        "center_j": function(sw, sh) {
            const w = 1139;
            const h = 940;
            return { width: w, height: h, x: Math.round((sw - w) / 2), y: Math.round((sh - h) / 2) };
        },
    },
};

function getWorkArea(window) {
    return workspace.clientArea(KWin.MaximizeArea, window.output, workspace.currentDesktop);
}

function getProcessName(window) {
    return window.resourceClass || "";
}

function getCenterLayout(processName, position, sw, sh) {
    const key = layoutConfig[processName] ? processName : "default";
    const appMap = layoutConfig[key];
    if (!appMap[position]) return null;
    return appMap[position](sw, sh);
}

function getSideRect(side, area) {
    const w = 1139;
    const h = 1218;
    const halfWidth = area.width / 2;
    const x = (side === "left")
        ? area.x + Math.round((halfWidth - w) / 2)
        : area.x + Math.round(halfWidth) + Math.round((halfWidth - w) / 2);
    const y = area.y + Math.round((area.height - h) / 2);
    return { x: x, y: y, width: w, height: h };
}

function isWindowSnappedTo(window, side, area) {
    if (!window) return false;
    const r = getSideRect(side, area);
    const geo = window.frameGeometry;
    const tolerance = 16;
    return Math.abs(geo.x - r.x) <= tolerance && Math.abs(geo.width - r.width) <= tolerance;
}

function findOtherWindowOnSide(side, area, excludeWindow) {
    const clients = workspace.windowList();
    for (let i = 0; i < clients.length; i++) {
        const w = clients[i];
        if (w === excludeWindow) continue;
        if (w.minimized) continue;
        if (!w.normalWindow) continue;
        if (w.output !== excludeWindow.output) continue;
        if (isWindowSnappedTo(w, side, area)) return w;
    }
    return null;
}

function findFullscreenWindow(area, excludeWindow) {
    const waArea = area.width * area.height;
    if (waArea <= 0) return null;
    const clients = workspace.windowList();
    for (let i = 0; i < clients.length; i++) {
        const w = clients[i];
        if (w === excludeWindow) continue;
        if (w.minimized) continue;
        if (!w.normalWindow) continue;
        if (w.output !== excludeWindow.output) continue;
        if (!w.caption) continue;
        const geo = w.frameGeometry;
        if (geo.width <= 0 || geo.height <= 0) continue;
        const ox = Math.max(0, Math.min(area.x + area.width, geo.x + geo.width) - Math.max(area.x, geo.x));
        const oy = Math.max(0, Math.min(area.y + area.height, geo.y + geo.height) - Math.max(area.y, geo.y));
        if ((ox * oy) / waArea > 0.8) return w;
    }
    return null;
}

function findOtherWindowAtRect(rx, ry, rw, rh, excludeWindow) {
    if (rw <= 0 || rh <= 0) return null;
    const targetCx = rx + rw / 2;
    const targetCy = ry + rh / 2;
    const centerTolerance = 30;
    const clients = workspace.windowList();
    for (let i = 0; i < clients.length; i++) {
        const w = clients[i];
        if (w === excludeWindow) continue;
        if (w.minimized) continue;
        if (!w.normalWindow) continue;
        if (w.output !== excludeWindow.output) continue;
        if (w.fullScreen) continue;
        const area = workspace.clientArea(KWin.MaximizeArea, w.output, workspace.currentDesktop);
        const geo = w.frameGeometry;
        if (geo.width >= area.width && geo.height >= area.height) continue;
        if (geo.width <= 0 || geo.height <= 0) continue;
        const cx = geo.x + geo.width / 2;
        const cy = geo.y + geo.height / 2;
        if (Math.abs(cx - targetCx) <= centerTolerance && Math.abs(cy - targetCy) <= centerTolerance)
            return w;
    }
    return null;
}

function moveWindowTo(window, geo) {
    window.frameGeometry = {
        x: geo.x,
        y: geo.y,
        width: geo.width,
        height: geo.height
    };
}

function resizeWindow(position) {
    const client = workspace.activeWindow;
    if (!client || !client.normalWindow) return;

    const area = getWorkArea(client);
    const processName = getProcessName(client);

    let newX, newY, newWidth, newHeight;

    if (position === "left" || position === "right") {
        const r = getSideRect(position, area);
        newX = r.x;
        newY = r.y;
        newWidth = r.width;
        newHeight = r.height;
    } else if (position === "center_i" || position === "center_j") {
        const layout = getCenterLayout(processName, position, area.width, area.height);
        if (!layout) return;
        newX = area.x + layout.x;
        newY = area.y + layout.y;
        newWidth = layout.width;
        newHeight = layout.height;
    } else {
        return;
    }

    if (position === "center_i" || position === "center_j") {
        const offsetStep = 20;
        const maxShifts = 6;
        let shifts = 0;
        while (shifts < maxShifts && findOtherWindowAtRect(newX, newY, newWidth, newHeight, client)) {
            newX += offsetStep;
            shifts++;
        }
    }

    if (newY + newHeight > area.y + area.height)
        newY = area.y + area.height - newHeight;
    if (newX + newWidth > area.x + area.width)
        newX = area.x + area.width - newWidth;

    client.setMaximize(false, false);
    moveWindowTo(client, { x: newX, y: newY, width: newWidth, height: newHeight });
}

function snapWithSwap(side) {
    const client = workspace.activeWindow;
    if (!client || !client.normalWindow) return;

    const area = getWorkArea(client);
    const otherSide = (side === "left") ? "right" : "left";

    let occupier = findOtherWindowOnSide(side, area, client);
    if (!occupier)
        occupier = findFullscreenWindow(area, client);

    if (occupier) {
        const r = getSideRect(otherSide, area);
        occupier.setMaximize(false, false);
        moveWindowTo(occupier, r);
    }

    resizeWindow(side);
}

// Ctrl+Meta+H: snap left with swap
registerShortcut("TileWindow: Snap Left", "TileWindow: Snap Left", "Ctrl+Meta+H", function() {
    snapWithSwap("left");
});

// Ctrl+Meta+L: snap right with swap
registerShortcut("TileWindow: Snap Right", "TileWindow: Snap Right", "Ctrl+Meta+L", function() {
    snapWithSwap("right");
});

// Ctrl+Meta+I: center_i layout (large centered)
registerShortcut("TileWindow: Center I", "TileWindow: Center I", "Ctrl+Meta+I", function() {
    resizeWindow("center_i");
});

// Ctrl+Meta+J: center_j layout (medium centered)
registerShortcut("TileWindow: Center J", "TileWindow: Center J", "Ctrl+Meta+J", function() {
    resizeWindow("center_j");
});

// Ctrl+Meta+K: maximize
registerShortcut("TileWindow: Maximize", "TileWindow: Maximize", "Ctrl+Meta+K", function() {
    const client = workspace.activeWindow;
    if (!client || !client.normalWindow) return;
    client.setMaximize(true, true);
});

// Ctrl+Meta+T: toggle always on top
registerShortcut("TileWindow: Toggle Always On Top", "TileWindow: Toggle Always On Top", "Ctrl+Meta+T", function() {
    const client = workspace.activeWindow;
    if (!client || !client.normalWindow) return;
    client.keepAbove = !client.keepAbove;
});

// Ctrl+Meta+W: show window info (debug)
registerShortcut("TileWindow: Window Info", "TileWindow: Window Info", "Ctrl+Meta+W", function() {
    const client = workspace.activeWindow;
    if (!client) return;
    const geo = client.frameGeometry;
    const area = getWorkArea(client);
    console.log("TileWindow: X:" + geo.x + " Y:" + geo.y + " W:" + geo.width + " H:" + geo.height + " | " + client.resourceClass + " | Area:" + area.width + "x" + area.height);
});
