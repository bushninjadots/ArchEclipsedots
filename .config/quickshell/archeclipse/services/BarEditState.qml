pragma Singleton
import QtQuick
import Quickshell
import qs.theme
import qs.services

// Shared edit-mode state for the configurable bar layout.
//
// The Settings panel calls begin(style) from its "Edit layout" control; the
// bar (DefaultBar / PillBar / BarEditOverlay) reacts to `active` by locking
// open, outlining its zones and exposing its tray. Dragging a widget raises
// draggingId/dragFromZone for the floating proxy; a drop calls place() or
// remove(), which splice the model and persist it live through Settings.
Singleton {
    id: root

    // True while the user is rearranging the bar on the bar itself.
    property bool active: false

    // Which layout is being edited: "islands" | "pill".
    property string style: "islands"

    // Current drag payload (set by the overlay/proxy while a drag is live).
    property string draggingId: ""
    property string dragFromZone: ""

    // Pointer position of the floating proxy, in bar-surface coordinates.
    property real dragX: 0
    property real dragY: 0

    // Linear drag state (freeform). `draggingId`/`dragFromZone` above carry
    // the payload; these add the linear insert index and edge.
    property int dragIndex: -1
    property int dropIndex: -1
    property string dragEdge: "top"
    property string axis: "x"

    // Whole-section drag (detached islands). While dragSection is non-empty,
    // the matching DetachedPill follows dragSectionX/Y instead of its anchor.
    property string dragSection: ""
    property real dragSectionX: 0
    property real dragSectionY: 0
    property real dragGrabX: 0
    property real dragGrabY: 0
    property real dragSectionW: 0
    property real dragSectionH: 0

    function begin(style) {
        root.style = (style === "pill" || style === "islands") ? style : Settings.barStyle;
        root.cells = [];
        root.dropZones = [];
        root.active = true;
    }

    function end() {
        root.active = false;
        root.draggingId = "";
        root.dragFromZone = "";
        root.dragX = 0;
        root.dragY = 0;
        root.dragIndex = -1;
        root.dropIndex = -1;
        root.dragEdge = "top";
        root.dragSection = "";
        root.cells = [];
        root.dropZones = [];
    }

    // ---- linear (freeform) layout accessors ----
    function linearLayout(edge) {
        const arr = edge === "bottom" ? Settings.barLayoutBottom : Settings.barLayoutTop;
        return Array.isArray(arr) ? arr.slice() : [];
    }

    function setLinearLayout(edge, arr) {
        Settings.updateSetting(edge === "bottom" ? "bar.layout.bottom" : "bar.layout.top", (arr || []).slice());
    }

    // Index at which to insert given the current ordered cell rects and
    // pointer x (edge axis). Returns [0, cells.length].
    function insertionIndex(px, cells) {
        if (!cells || cells.length === 0)
            return 0;
        for (let i = 0; i < cells.length; i++) {
            const c = cells[i];
            if (px < c.x + c.w / 2)
                return i;
        }
        return cells.length;
    }

    function beginLinearDrag(id, index, edge, px, py) {
        root.active = true;
        root.draggingId = id;
        root.dragFromZone = edge;
        root.dragEdge = edge;
        root.dragIndex = index;
        root.dropIndex = index;
        root.axis = "x";
        root.dragX = px;
        root.dragY = py;
    }

    function moveLinear(px, py, cells) {
        root.dragX = px;
        root.dragY = py;
        root.dropIndex = root.insertionIndex(px, cells);
    }

    function commitLinear(cells) {
        if (!root.draggingId || root.dragIndex < 0)
            return;
        if (cells)
            root.dropIndex = root.insertionIndex(root.dragX, cells);
        const edge = root.dragEdge;
        const arr = root.linearLayout(edge);
        const from = arr.indexOf(root.draggingId);
        if (from !== -1)
            arr.splice(from, 1);
        let di = root.dropIndex;
        if (di < 0)
            di = arr.length;
        if (from !== -1 && from < di)
            di--;
        di = Math.max(0, Math.min(arr.length, di));
        arr.splice(di, 0, root.draggingId);
        root.setLinearLayout(edge, arr);
        root.clearLinearDrag();
    }

    function clearLinearDrag() {
        root.draggingId = "";
        root.dragFromZone = "";
        root.dragIndex = -1;
        root.dropIndex = -1;
        root.dragEdge = "top";
        root.dragX = 0;
        root.dragY = 0;
    }

    function _zones(style) {
        return style === "pill" ? ["rest", "core", "detail"] : ["left", "center", "right", "bottom"];
    }

    function _read(style) {
        return style === "pill" ? Settings.barLayoutPill : Settings.barLayoutIslands;
    }

    function _clone(style) {
        const src = root._read(style) || {};
        const next = {};
        for (const z of root._zones(style))
            next[z] = Array.isArray(src[z]) ? src[z].slice() : [];
        return next;
    }

    function _write(style, obj) {
        Settings.updateSetting(style === "pill" ? "bar.layout.pill" : "bar.layout.islands", obj);
    }

    // Insert `id` into `zone` at `index` (or append). When `fromZone` is given
    // and differs, the widget is moved out of it. Dedupes within the target
    // zone only, so a pill widget may live in both rest and core as designed.
    function place(id, zone, index, fromZone) {
        if (!id || !zone)
            return;
        const style = root.style;
        if (!BarWidgets.allowed(id, style, zone))
            return;
        const next = root._clone(style);
        if (fromZone && fromZone !== zone && Array.isArray(next[fromZone])) {
            const fi = next[fromZone].indexOf(id);
            if (fi >= 0)
                next[fromZone].splice(fi, 1);
        }
        const arr = next[zone];
        const existing = arr.indexOf(id);
        if (existing >= 0)
            arr.splice(existing, 1);
        let at = (index === undefined || index === null || index < 0) ? arr.length : Math.floor(index);
        at = Math.max(0, Math.min(at, arr.length));
        next[zone].splice(at, 0, id);
        root._write(style, next);
    }

    // Remove `id` from `zone` (drag back to the tray).
    function remove(id, zone) {
        if (!id || !zone)
            return;
        const style = root.style;
        const next = root._clone(style);
        const arr = next[zone];
        const i = arr ? arr.indexOf(id) : -1;
        if (i >= 0) {
            arr.splice(i, 1);
            root._write(style, next);
        }
    }

    // ---- Geometry registration (window/scene coordinates) ----------------
    //
    // The bar faces publish where each placed widget and each empty zone
    // currently sits so the full-window overlay can hit-test drops without
    // reaching into the bar's item tree.
    property var cells: []      // [{ id, zone, x, y, w, h }]
    property var dropZones: []  // [{ zone, x, y, w, h }]

    function setCells(list) {
        const v = list || [];
        if (JSON.stringify(v) === JSON.stringify(root.cells))
            return;
        root.cells = v;
    }

    function setDropZones(list) {
        const v = list || [];
        if (JSON.stringify(v) === JSON.stringify(root.dropZones))
            return;
        root.dropZones = v;
    }

    // Commit the live drag at a scene point: move into a zone when over one,
    // remove when dropped outside every zone from a placed zone, else cancel.
    function dropAt(px, py) {
        if (!root.draggingId)
            return;
        const id = root.draggingId;
        const from = root.dragFromZone;
        const zone = root.zoneAt(px, py);
        if (zone)
            root.place(id, zone, root.indexForZone(zone, px), from);
        else if (from)
            root.remove(id, from);
        root.draggingId = "";
        root.dragFromZone = "";
    }

    // ---- Whole-section (detached pill) drag -------------------------------
    function beginSectionDrag(section, px, py, rect) {
        root.dragSection = section;
        root.dragSectionW = rect.w;
        root.dragSectionH = rect.h;
        root.dragGrabX = px - rect.x;
        root.dragGrabY = py - rect.y;
        root.dragSectionX = rect.x;
        root.dragSectionY = rect.y;
    }

    // Move the dragged pill, clamped to the surface (maxX/maxY = surface size).
    function moveSection(px, py, maxX, maxY) {
        if (root.dragSection === "")
            return;
        let nx = px - root.dragGrabX;
        let ny = py - root.dragGrabY;
        nx = Math.max(0, Math.min(nx, maxX - root.dragSectionW));
        ny = Math.max(0, Math.min(ny, maxY - root.dragSectionH));
        root.dragSectionX = nx;
        root.dragSectionY = ny;
    }

    // Persist the dragged pill's new top-left as bar.islands.pos[section].
    function commitSection() {
        if (root.dragSection === "")
            return;
        const next = Object.assign({}, Settings.barIslandsPos);
        next[root.dragSection] = { x: Math.round(root.dragSectionX), y: Math.round(root.dragSectionY) };
        Settings.updateSetting("bar.islands.pos", next);
        root.dragSection = "";
    }

    // Rect (with w/h) of the zone under a scene point, or null.
    function zoneRectAt(px, py) {
        for (const z of root.dropZones) {
            if (px >= z.x && px <= z.x + z.w && py >= z.y && py <= z.y + z.h)
                return z;
        }
        return null;
    }

    // Zone under a scene point, or "" when the drop lands outside every zone.
    function zoneAt(px, py) {
        for (const z of root.dropZones) {
            if (px >= z.x && px <= z.x + z.w && py >= z.y && py <= z.y + z.h)
                return z.zone;
        }
        return "";
    }

    // Placed cell under a scene point, or null.
    function cellAt(px, py) {
        for (const c of root.cells) {
            if (px >= c.x && px <= c.x + c.w && py >= c.y && py <= c.y + c.h)
                return c;
        }
        return null;
    }

    // Insertion index for a drop at `px` inside `zone`, derived from the
    // horizontal midpoints of the widgets currently placed in that zone.
    function indexForZone(zone, px) {
        let idx = 0;
        for (const c of root.cells) {
            if (c.zone !== zone)
                continue;
            if (px > c.x + c.w / 2)
                idx++;
        }
        return idx;
    }

    // Catalog ids valid for the active style but not placed in any zone
    // (the tray contents).
    function unplacedIds() {
        const style = root.style;
        const model = root._read(style);
        const zones = root._zones(style);
        const placed = ({});
        for (const zone of zones) {
            for (const id of (model[zone] || []))
                placed[id] = true;
        }
        const out = [];
        for (const e of BarWidgets.catalog) {
            if (placed[e.id])
                continue;
            for (const zone of zones) {
                if (BarWidgets.allowed(e.id, style, zone)) {
                    out.push(e.id);
                    break;
                }
            }
        }
        return out;
    }

    // Tray test: is (px,py) inside the tray band drawn by the overlay?
    property real trayTop: 0
    property real trayBottom: 0
    function inTray(py) {
        return root.trayBottom > root.trayTop && py >= root.trayTop && py <= root.trayBottom;
    }
}
