pragma Singleton
import QtQuick
import Quickshell
import qs.theme
import qs.services

// Shared edit-mode state for the configurable bar layout.
//
// Model: each bar style has fixed SECTIONS (BarWidgets.sections) holding an
// ordered list of widget ids — islands: left / center / right / bottom, pill:
// rest / core / detail. Any widget the style supports can be placed in any
// section; the defaults (Settings.defaultBarLayout*) are the original bars.
//
// Interaction:
//   - press + move on a placed widget (or a tray chip) starts a drag; while it
//     is live `preview` holds the layout as it would be if dropped now, and the
//     faces render from ids(style, zone) so neighbours slide aside and the
//     dragged widget shows as a faded ghost at its landing slot (the shell
//     frame follows the ghost, since it is a real rendered cell);
//   - click selects a widget (inspector popover + keyboard: arrows move it,
//     Up/Down hop sections, Delete hides it);
//   - every commit persists live through Settings.updateSetting; begin()
//     snapshots the layout so cancel() can restore it.
Singleton {
    id: root

    // True while the user is rearranging the bar on the bar itself.
    property bool active: false

    // Which layout is being edited: "islands" | "pill".
    property string style: "islands"

    // Persisted layout captured on begin(style), held so cancel() can restore
    // it verbatim. Null while no edit session is open.
    property var _snapshot: null
    readonly property bool canCancel: root._snapshot !== null

    // ---- selection (click a widget) ----
    property string selectedId: ""
    property string selectedZone: ""

    // ---- live widget drag ----
    property string draggingId: ""
    property string dragFromZone: ""     // "" = from the tray
    property real dragX: 0
    property real dragY: 0
    // Live drop target: zone "" = hide (back to the tray).
    property string targetZone: ""
    property int targetIndex: -1
    // Full zone map for the edited style while a drag is live.
    property var preview: ({})

    // ---- whole-section drag (detached islands) ----
    property string dragSection: ""
    property real dragSectionX: 0
    property real dragSectionY: 0
    property real dragGrabX: 0
    property real dragGrabY: 0
    property real dragSectionW: 0
    property real dragSectionH: 0

    // ---- geometry published by the faces (scene coords) ----
    property var cells: []      // [{ id, zone, x, y, w, h }]
    property var dropZones: []  // [{ zone, x, y, w, h, spacing }]
    // Tray rect drawn by the overlay ({x,y,w,h}); drops there hide a widget.
    property var trayRect: null

    function setCells(list) {
        const v = list || [];
        if (JSON.stringify(v) !== JSON.stringify(root.cells))
            root.cells = v;
    }
    function setDropZones(list) {
        const v = list || [];
        if (JSON.stringify(v) !== JSON.stringify(root.dropZones))
            root.dropZones = v;
    }

    // ------------------------------------------------------------ session
    function begin(style) {
        root._captureSnapshot();
        // Only the visible style can be edited on the bar; a request for the
        // other style switches the bar to it first.
        if ((style === "pill" || style === "islands") && style !== Settings.barStyle)
            Settings.updateSetting("bar.style", style);
        root.style = Settings.barStyle;
        root.cells = [];
        root.dropZones = [];
        root.selectedId = "";
        root.selectedZone = "";
        root.active = true;
    }

    function end() {
        root._snapshot = null;
        root._teardown();
    }

    // Restore the layout captured at begin() and leave edit mode.
    function cancel() {
        if (root._snapshot) {
            const s = root._snapshot;
            Settings.updateSetting("bar.layout.islands", root._deep(s.islands));
            Settings.updateSetting("bar.layout.pill", root._deep(s.pill));
            Settings.updateSetting("bar.layout.frame", root._deep(s.frame));
            Settings.updateSetting("bar.islands.pos", root._deep(s.pos));
            Settings.updateSetting("bar.style", s.barStyle);
            Settings.updateSetting("bar.islands.detached", s.detached);
        }
        root._snapshot = null;
        root._teardown();
    }

    // Undo everything since begin() but stay in edit mode.
    function revert() {
        if (!root._snapshot)
            return;
        const s = root._snapshot;
        root.abortDrag();
        Settings.updateSetting("bar.layout.islands", root._deep(s.islands));
        Settings.updateSetting("bar.layout.pill", root._deep(s.pill));
        Settings.updateSetting("bar.layout.frame", root._deep(s.frame));
        Settings.updateSetting("bar.islands.pos", root._deep(s.pos));
    }

    // Switch the edited (and shown) bar style without leaving edit mode.
    function switchStyle(style) {
        if (style !== "pill" && style !== "islands")
            return;
        root.abortDrag();
        root.select("", "");
        Settings.updateSetting("bar.style", style);
        root.style = style;
    }

    function _deep(v) {
        return JSON.parse(JSON.stringify(v || {}));
    }

    function _captureSnapshot() {
        root._snapshot = {
            islands: root._deep(Settings.barLayoutIslands),
            pill: root._deep(Settings.barLayoutPill),
            frame: root._deep(Settings.barLayoutFrame),
            pos: root._deep(Settings.barIslandsPos),
            barStyle: Settings.barStyle,
            detached: Settings.barIslandsDetached
        };
    }

    function _teardown() {
        root.active = false;
        root.abortDrag();
        root.dragSection = "";
        root.selectedId = "";
        root.selectedZone = "";
        root.cells = [];
        root.dropZones = [];
    }

    // ------------------------------------------------------------ model io
    function _zones(style) {
        return BarWidgets.zones(style);
    }

    // Clean clone of the committed layout: { zone: [ids] } for every zone.
    function _clone(style) {
        const next = {};
        for (const z of root._zones(style))
            next[z] = BarWidgets.layout(style, z).slice();
        return next;
    }

    function _write(style, obj) {
        Settings.updateSetting(style === "pill" ? "bar.layout.pill" : "bar.layout.islands", obj);
    }

    // Ids to RENDER for a section: the live preview while a drag is in flight
    // for that style, else the committed layout.
    function ids(style, zone) {
        if (root.draggingId !== "" && style === root.style) {
            const p = root.preview[zone];
            if (Array.isArray(p))
                return p;
        }
        return BarWidgets.layout(style, zone);
    }

    // Zone the id currently sits in (first match), or "".
    function zoneOf(id, style) {
        const st = style || root.style;
        for (const z of root._zones(st)) {
            if (BarWidgets.layout(st, z).indexOf(id) !== -1)
                return z;
        }
        return "";
    }

    // Layout `base` with `id` taken out of `fromZone` (islands: out of every
    // section) and inserted into `toZone` at `index` ("" = hidden).
    function _apply(base, id, fromZone, toZone, index) {
        const next = {};
        for (const z in base)
            next[z] = base[z].slice();
        if (!BarWidgets.multiPlace(root.style)) {
            for (const z in next) {
                const i = next[z].indexOf(id);
                if (i !== -1)
                    next[z].splice(i, 1);
            }
        } else if (fromZone && next[fromZone]) {
            const i = next[fromZone].indexOf(id);
            if (i !== -1)
                next[fromZone].splice(i, 1);
        }
        if (toZone && next[toZone]) {
            const arr = next[toZone];
            const e = arr.indexOf(id);
            if (e !== -1)
                arr.splice(e, 1);
            let at = (index === undefined || index === null || index < 0) ? arr.length : Math.floor(index);
            at = Math.max(0, Math.min(at, arr.length));
            arr.splice(at, 0, id);
        }
        return next;
    }

    // ------------------------------------------------------------ commands
    // Move `id` (from `fromZone`, "" = tray) to `toZone` at `index`
    // (-1 = end); toZone "" hides it. Persists immediately.
    function moveTo(id, fromZone, toZone, index) {
        if (!id)
            return;
        if (toZone && !BarWidgets.allowed(id, root.style, toZone))
            return;
        root._write(root.style, root._apply(root._clone(root.style), id, fromZone, toZone, index));
        if (root.selectedId === id)
            root.selectedZone = toZone;
        if (!toZone && root.selectedId === id)
            root.selectedId = "";
    }

    function hide(id, zone) {
        root.moveTo(id, zone, "", -1);
    }

    // Shift `id` one slot within its section; past either end it hops into
    // the neighbouring section (left end of the next / right end of the
    // previous), so arrows alone can walk a widget across the whole bar.
    function nudge(id, zone, delta) {
        const zs = root._zones(root.style);
        const arr = BarWidgets.layout(root.style, zone);
        const i = arr.indexOf(id);
        if (i === -1)
            return;
        const j = i + delta;
        if (j >= 0 && j < arr.length) {
            root.moveTo(id, zone, zone, j);
            return;
        }
        const zi = zs.indexOf(zone) + (delta < 0 ? -1 : 1);
        if (zi < 0 || zi >= zs.length)
            return;
        root.moveTo(id, zone, zs[zi], delta < 0 ? -1 : 0);
    }

    // Move to the previous/next section (keeps it at the near end).
    function hop(id, zone, delta) {
        const zs = root._zones(root.style);
        const zi = zs.indexOf(zone) + delta;
        if (zi < 0 || zi >= zs.length)
            return;
        root.moveTo(id, zone, zs[zi], -1);
    }

    function select(id, zone) {
        root.selectedId = id || "";
        root.selectedZone = zone || "";
    }

    // Catalog ids the edited style supports but has placed nowhere.
    function unplacedIds() {
        const style = root.style;
        const placed = ({});
        for (const z of root._zones(style)) {
            for (const id of BarWidgets.layout(style, z))
                placed[id] = true;
        }
        const out = [];
        for (const e of BarWidgets.catalog) {
            if (!placed[e.id] && BarWidgets.supports(e.id, style))
                out.push(e.id);
        }
        return out;
    }

    // ------------------------------------------------------------ live drag
    function startDrag(id, fromZone, px, py) {
        if (!id)
            return;
        root.draggingId = id;
        root.dragFromZone = fromZone || "";
        root.dragX = px;
        root.dragY = py;
        const base = root._clone(root.style);
        if (fromZone && base[fromZone]) {
            root.targetZone = fromZone;
            root.targetIndex = base[fromZone].indexOf(id);
        } else {
            root.targetZone = "";
            root.targetIndex = -1;
        }
        root.preview = root._apply(base, id, root.dragFromZone, root.targetZone, root.targetIndex);
    }

    function _inRect(r, px, py, m) {
        return r && px >= r.x - m && px <= r.x + r.w + m && py >= r.y - m && py <= r.y + r.h + m;
    }

    function _distRect(r, px, py) {
        const dx = Math.max(r.x - px, 0, px - (r.x + r.w));
        const dy = Math.max(r.y - py, 0, py - (r.y + r.h));
        return Math.sqrt(dx * dx + dy * dy);
    }

    // Insertion index in `zone` for pointer x, measured against the row as
    // it would sit WITHOUT the ghost: a section's anchoring decides which
    // neighbours the ghost displaced (left-hugging: those after it; right-
    // hugging: those before it; centred: both by half), and that shift is
    // undone. The answer then depends only on the pointer, so the landing
    // gap opens under the cursor and live reorder never oscillates.
    function _indexIn(zone, px) {
        const zc = root.cells.filter(c => c.zone === zone);
        let ghost = null;
        for (const c of zc) {
            if (c.id === root.draggingId)
                ghost = c;
        }
        let gap = Theme.spacing, align = "left";
        for (const z of root.dropZones) {
            if (z.zone === zone) {
                if (z.spacing !== undefined)
                    gap = z.spacing;
                if (z.align)
                    align = z.align;
            }
        }
        const pos = c => (c.tx !== undefined ? c.tx : c.x);
        const shift = ghost ? ghost.w + gap : 0;
        let idx = 0;
        for (const c of zc) {
            if (c === ghost)
                continue;
            let x = pos(c);
            if (ghost) {
                const after = pos(c) > pos(ghost);
                if (align === "right")
                    x += after ? 0 : shift;
                else if (align === "center")
                    x += after ? -shift / 2 : shift / 2;
                else
                    x -= after ? shift : 0;
            }
            if (px > x + c.w / 2)
                idx++;
        }
        return idx;
    }

    function updateDrag(px, py) {
        if (!root.draggingId)
            return;
        root.dragX = px;
        root.dragY = py;
        let zone = "";
        if (root.trayRect && root._inRect(root.trayRect, px, py, 6)) {
            zone = "";
        } else {
            // Nearest section within a generous grab margin, so the gaps
            // between sections still pick the closer one.
            let best = null, bestD = 36;
            for (const z of root.dropZones) {
                const d = root._distRect(z, px, py);
                if (d < bestD) {
                    best = z;
                    bestD = d;
                }
            }
            if (best) {
                zone = best.zone;
            } else {
                // Between sections: stay sticky to the current target unless
                // the pointer wandered well away from every section.
                let near = 1e9;
                for (const z of root.dropZones)
                    near = Math.min(near, root._distRect(z, px, py));
                zone = near < 72 ? root.targetZone : "";
            }
        }
        if (zone && !BarWidgets.allowed(root.draggingId, root.style, zone))
            zone = "";
        const index = zone ? root._indexIn(zone, px) : -1;
        if (zone === root.targetZone && index === root.targetIndex)
            return;
        root.targetZone = zone;
        root.targetIndex = index;
        root.preview = root._apply(root._clone(root.style), root.draggingId, root.dragFromZone, zone, index);
    }

    function finishDrag() {
        if (!root.draggingId)
            return;
        const id = root.draggingId;
        const changed = !(root.targetZone === root.dragFromZone
            && root.targetIndex === BarWidgets.layout(root.style, root.dragFromZone).indexOf(id));
        if (changed && (root.targetZone || root.dragFromZone))
            root._write(root.style, root.preview);
        if (root.targetZone)
            root.select(id, root.targetZone);
        else if (root.selectedId === id)
            root.select("", "");
        root.abortDrag();
    }

    function abortDrag() {
        root.draggingId = "";
        root.dragFromZone = "";
        root.targetZone = "";
        root.targetIndex = -1;
        root.preview = ({});
    }

    // ------------------------------------------------------------ hit tests
    function cellAt(px, py, margin) {
        const m = margin || 0;
        let best = null, bestD = 1e9;
        for (const c of root.cells) {
            if (!root._inRect(c, px, py, m))
                continue;
            const d = Math.abs(px - (c.x + c.w / 2)) + Math.abs(py - (c.y + c.h / 2));
            if (d < bestD) {
                best = c;
                bestD = d;
            }
        }
        return best;
    }

    function zoneRectAt(px, py) {
        for (const z of root.dropZones) {
            if (root._inRect(z, px, py, 0))
                return z;
        }
        return null;
    }

    function cellRect(id) {
        for (const c of root.cells) {
            if (c.id === id)
                return c;
        }
        return null;
    }

    // ------------------------------------------------------------ sections
    function beginSectionDrag(section, px, py, rect) {
        root.dragSection = section;
        root.dragSectionW = rect.w;
        root.dragSectionH = rect.h;
        root.dragGrabX = px - rect.x;
        root.dragGrabY = py - rect.y;
        root.dragSectionX = rect.x;
        root.dragSectionY = rect.y;
    }

    // Move the dragged section pill, clamped to the surface and snapped to
    // the screen centre line and edges (8px margin) within 10px.
    function moveSection(px, py, maxX, maxY) {
        if (root.dragSection === "")
            return;
        const w = root.dragSectionW, h = root.dragSectionH, m = 8, snap = 10;
        let nx = Math.max(0, Math.min(px - root.dragGrabX, maxX - w));
        let ny = Math.max(0, Math.min(py - root.dragGrabY, maxY - h));
        const cx = (maxX - w) / 2;
        if (Math.abs(nx - cx) < snap) nx = cx;
        if (Math.abs(nx - m) < snap) nx = m;
        if (Math.abs(nx - (maxX - w - m)) < snap) nx = maxX - w - m;
        if (Math.abs(ny - 6) < snap) ny = 6;
        if (Math.abs(ny - (maxY - h - m)) < snap) ny = maxY - h - m;
        root.dragSectionX = nx;
        root.dragSectionY = ny;
    }

    function commitSection() {
        if (root.dragSection === "")
            return;
        const next = Object.assign({}, Settings.barIslandsPos);
        next[root.dragSection] = { x: Math.round(root.dragSectionX), y: Math.round(root.dragSectionY) };
        Settings.updateSetting("bar.islands.pos", next);
        root.dragSection = "";
    }

    // Snap one detached section back to its default anchor.
    function resetSection(section) {
        const next = Object.assign({}, Settings.barIslandsPos);
        next[section] = { x: -1, y: -1 };
        Settings.updateSetting("bar.islands.pos", next);
    }

    // ------------------------------------------------------------ frames
    // Per-widget frame fit, persisted under bar.layout.frame: { [id]: { shape, radius } }.
    //   "frame"  — melts into the band as part of its section's body (default);
    //   "pill"   — own capsule, split out of the section body;
    //   "square" — square-cornered tab;
    //   "detach" — free-floating body with a gap round it.
    readonly property var widgetFrames: {
        const f = Settings.barLayoutFrame;
        return (f && typeof f === "object") ? f : {};
    }

    // Resolved per-widget look: frame fit + decoration + opacity, with the
    // global defaults (Settings.barWidget*) filled in. `own*` flags say
    // whether the widget overrides the default.
    function frameFor(id) {
        const f = root.widgetFrames[id] || {};
        const ownDeco = ["none", "outline", "filled"].includes(f.deco);
        const ownOpacity = Number.isFinite(Number(f.opacity));
        return {
            shape: f.shape ? f.shape : "frame",
            radius: Number.isFinite(Number(f.radius)) ? Number(f.radius) : -1,
            deco: ownDeco ? f.deco : Settings.barWidgetDeco,
            opacity: (ownOpacity ? Number(f.opacity) : Settings.barWidgetOpacity) / 100,
            ownDeco: ownDeco,
            ownOpacity: ownOpacity
        };
    }

    function _writeEntry(id, mutate) {
        if (!id)
            return;
        const next = Object.assign({}, root.widgetFrames);
        const e = Object.assign({}, next[id] || {});
        mutate(e);
        if (Object.keys(e).length === 0)
            delete next[id];
        else
            next[id] = e;
        Settings.updateSetting("bar.layout.frame", next);
    }

    function setFrame(id, shape, radius) {
        root._writeEntry(id, e => {
            if (shape !== undefined) {
                if (["detach", "square", "pill"].includes(shape))
                    e.shape = shape;
                else
                    delete e.shape;
            }
            if (radius !== undefined) {
                if (radius === null || radius < 0)
                    delete e.radius;
                else
                    e.radius = Math.max(0, Math.min(48, Math.round(radius)));
            }
        });
    }

    // Decoration override: "none" | "outline" | "filled", or null = default.
    function setDeco(id, deco) {
        root._writeEntry(id, e => {
            if (["none", "outline", "filled"].includes(deco))
                e.deco = deco;
            else
                delete e.deco;
        });
    }

    // Opacity override in percent (20..100), or null = default.
    function setOpacity(id, pct) {
        root._writeEntry(id, e => {
            if (pct === null || pct === undefined || !Number.isFinite(Number(pct)))
                delete e.opacity;
            else
                e.opacity = Math.max(20, Math.min(100, Math.round(Number(pct))));
        });
    }

    // Drop every per-widget override (shape, radius, decoration, opacity).
    function clearWidgetOverrides() {
        Settings.updateSetting("bar.layout.frame", {});
    }

    // ------------------------------------------------------------ reset
    // Reinstall the original (code-default) layout for `style` (default: the
    // edited style); the other style is untouched. Islands also returns the
    // detached sections to their anchors. Per-widget frame fits are cleared.
    function resetLayout(style) {
        const st = style || root.style;
        root.abortDrag();
        root.dragSection = "";
        if (st === "pill") {
            Settings.updateSetting("bar.layout.pill", root._deep(Settings.defaultBarLayoutPill));
        } else {
            Settings.updateSetting("bar.layout.islands", root._deep(Settings.defaultBarLayoutIslands));
            Settings.updateSetting("bar.islands.pos", root._deep(Settings.defaultBarIslandsPos));
        }
        Settings.updateSetting("bar.layout.frame", {});
    }
}
