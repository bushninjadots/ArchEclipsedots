import QtQuick
import qs.theme
import qs.services

// Detached-islands surface (bar layout system, Task 8).
//
// One floating pill per section (left/center/right/bottom), each placed by an
// absolute top-left from Settings.barIslandsPos or, when that is unset (-1),
// by the section's default anchor: left/center/right hug the bar edge and
// bottom hugs the opposite edge. Bar.qml hosts this inside its full-output
// surface and masks input to the pill rects, so the desktop between pills
// stays clickable.
Item {
    id: root

    // Stable handles for Bar.qml's input mask.
    readonly property Item pillLeft: leftPill
    readonly property Item pillCenter: centerPill
    readonly property Item pillRight: rightPill
    readonly property Item pillBottom: bottomPill

    readonly property int edgeMargin: 8
    readonly property int barMargin: 6

    function _stored(section) {
        const p = (Settings.barIslandsPos || {})[section];
        return p || ({ x: -1, y: -1 });
    }

    // Default top-left for a section that has never been positioned.
    function defaultPos(section, w, h) {
        const top = Settings.barOrientation;
        const yBar = top ? root.barMargin : root.height - h - root.barMargin;
        const yFar = top ? root.height - h - root.edgeMargin : root.edgeMargin;
        if (section === "left")
            return { x: root.edgeMargin, y: yBar };
        if (section === "right")
            return { x: root.width - w - root.edgeMargin, y: yBar };
        if (section === "bottom")
            return { x: Math.round((root.width - w) / 2), y: yFar };
        return { x: Math.round((root.width - w) / 2), y: yBar };
    }

    // Stored position wins per-axis; -1/undefined falls back to the default.
    function resolvePos(section, w, h) {
        const p = root._stored(section);
        const d = root.defaultPos(section, w, h);
        return {
            x: (p.x !== undefined && p.x >= 0) ? p.x : d.x,
            y: (p.y !== undefined && p.y >= 0) ? p.y : d.y
        };
    }

    DetachedPill {
        id: leftPill
        section: "left"
        x: BarEditState.dragSection === "left" ? BarEditState.dragSectionX : root.resolvePos("left", width, height).x
        y: BarEditState.dragSection === "left" ? BarEditState.dragSectionY : root.resolvePos("left", width, height).y
    }
    DetachedPill {
        id: centerPill
        section: "center"
        x: BarEditState.dragSection === "center" ? BarEditState.dragSectionX : root.resolvePos("center", width, height).x
        y: BarEditState.dragSection === "center" ? BarEditState.dragSectionY : root.resolvePos("center", width, height).y
    }
    DetachedPill {
        id: rightPill
        section: "right"
        x: BarEditState.dragSection === "right" ? BarEditState.dragSectionX : root.resolvePos("right", width, height).x
        y: BarEditState.dragSection === "right" ? BarEditState.dragSectionY : root.resolvePos("right", width, height).y
    }
    DetachedPill {
        id: bottomPill
        section: "bottom"
        stretch: true
        // Mirror the attached bottom strip width: the top row content width.
        width: 2 * Math.max(leftPill.width, rightPill.width) + centerPill.width + Theme.spacing * 2
        x: BarEditState.dragSection === "bottom" ? BarEditState.dragSectionX : root.resolvePos("bottom", width, height).x
        y: BarEditState.dragSection === "bottom" ? BarEditState.dragSectionY : root.resolvePos("bottom", width, height).y
    }

    // ---- edit-mode geometry (scene coords), mirrors DefaultBar's API ----
    function editCells() {
        return [].concat(leftPill.cells(), centerPill.cells(), rightPill.cells(), bottomPill.cells());
    }
    // Rendered widget item (the delegate Loader's `item`) for a placed id
    // across the four section pills, or null when not placed. Mirrors
    // editCells(); BarEditOverlay grabs it for the real-widget drag proxy.
    function cellItem(id) {
        const sections = [leftPill, centerPill, rightPill, bottomPill];
        for (let i = 0; i < sections.length; i++) {
            const item = sections[i].cellItem(id);
            if (item)
                return item;
        }
        return null;
    }
    function editZones() {
        return [leftPill.zoneRect(), centerPill.zoneRect(), rightPill.zoneRect(), bottomPill.zoneRect()];
    }
    // Section bodies for the shell frame (non-empty sections only).
    function frameSections() {
        const out = [];
        for (const p of [leftPill, centerPill, rightPill, bottomPill]) {
            if (!p.visible || !p.hasContent)
                continue;
            out.push({ zone: p.section, x: p.x, y: p.y, w: p.width, h: p.height });
        }
        return out;
    }
}
