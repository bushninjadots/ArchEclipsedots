import QtQuick
import qs.theme
import qs.services

// The shell frame (Settings -> Bar -> Shell Style "Frame"), drawn inside the
// bar's own surface so the band and the top shell are one piece: the pill and
// side panels Bar.qml paints sit on it, and frame.frag draws the band, the
// fillets they grow out of, and — while music plays — their swell into it.
// Modelled on iNiR's Iris surround (IrisFrame / IrisField, GPL-3.0).
Item {
    id: root

    // { pill, left, right }, each { x, y, w, h, on } in this item's px.
    property var bodies: ({})
    // Freeform body list — array of { x, y, w, h, on, tl, tr, br, bl, radius }.
    // Preferred over `bodies`; when empty, bodies.pill/left/right are used.
    property var bodiesList: []
    property bool topBar: true

    // Resolved body list (bodiesList when non-empty, else legacy bodies).
    readonly property var bodyItems: {
        if (root.bodiesList && root.bodiesList.length > 0)
            return root.bodiesList;
        const l = [];
        for (const key of ["pill", "left", "right"]) {
            const b = root.bodies[key];
            if (b) l.push(b);
        }
        return l;
    }
    readonly property int bodyCount: Math.min(root.bodyItems.length, 64)

    visible: ShellFrame.enabled
    enabled: false

    // Bar.qml's pills round only the corners away from the bar edge.
    readonly property vector4d radii: root.topBar ? Qt.vector4d(0, 0, Theme.radius, Theme.radius)
                                                  : Qt.vector4d(Theme.radius, Theme.radius, 0, 0)

    function shapeOf(b) {
        if (!b || !b.on || b.w <= 0 || b.h <= 0)
            return Qt.vector4d(0, 0, 0, 0);
        return Qt.vector4d(b.x + b.w / 2, b.y + b.h / 2, b.w / 2, b.h / 2);
    }

    // Per-body radii: prefer the body's own tl/tr/br/bl (or radius); the edges
    // away from the bar round only when the body asks for them, else the
    // global topBar-aware radii apply.
    function radiiOf(b) {
        if (b && (b.tl !== undefined || b.br !== undefined || b.radius !== undefined)) {
            const r = (b.radius !== undefined) ? b.radius : Theme.radius;
            const tl = (b.tl !== undefined) ? b.tl : (root.topBar ? 0 : r);
            const tr = (b.tr !== undefined) ? b.tr : (root.topBar ? 0 : r);
            const br = (b.br !== undefined) ? b.br : (root.topBar ? r : 0);
            const bl = (b.bl !== undefined) ? b.bl : (root.topBar ? r : 0);
            return Qt.vector4d(tl, tr, br, bl);
        }
        return root.radii;
    }

    // The shader's array uniforms are fixed at 64 slots; pad with empties so
    // the size always matches bodyCount <= 64.
    readonly property var shapeArr: {
        const out = [];
        const list = root.bodyItems;
        for (let i = 0; i < 64; i++) {
            const b = i < root.bodyCount ? list[i] : null;
            if (!b || b.on === false || b.w <= 0 || b.h <= 0)
                out.push(Qt.vector4d(0, 0, 0, 0));
            else
                out.push(Qt.vector4d(b.x + b.w / 2, b.y + b.h / 2, b.w / 2, b.h / 2));
        }
        return out;
    }
    readonly property var radiiArr: {
        const out = [];
        const list = root.bodyItems;
        for (let i = 0; i < 64; i++) {
            const b = (i < root.bodyCount && typeof list[i] === "object") ? list[i] : null;
            out.push(b ? root.radiiOf(b) : Qt.vector4d(0, 0, 0, 0));
        }
        return out;
    }

    // The interior nothing reaches, so a moving swell redraws the edges only.
    readonly property vector4d quietRect: {
        const a = ShellFrame.amplitudes;
        const wave = Math.max(a.x, a.y, a.z, a.w, 0) + ShellFrame.topSwell;
        const edge = ShellFrame.band + wave + ShellFrame.fuse + ShellFrame.radius + ShellFrame.borderWidth + 8;
        let l = edge, t = edge, r = root.width - edge, b = root.height - edge;
        const m = ShellFrame.fuse + ShellFrame.bodySwell * 2.5 + 16;
        for (const s of root.bodyItems) {
            if (!s || !s.on) continue;
            const x0 = s.x - m, y0 = s.y - m, x1 = s.x + s.w + m, y1 = s.y + s.h + m;
            if (x1 <= l || x0 >= r || y1 <= t || y0 >= b) continue;
            const keep = [
                { a: (r - x1) * (b - t), l: x1, t: t, r: r, b: b },
                { a: (x0 - l) * (b - t), l: l, t: t, r: x0, b: b },
                { a: (r - l) * (b - y1), l: l, t: y1, r: r, b: b },
                { a: (r - l) * (y0 - t), l: l, t: t, r: r, b: y0 }
            ].reduce((best, c) => c.a > best.a ? c : best);
            l = keep.l; t = keep.t; r = keep.r; b = keep.b;
        }
        if (r - l < 64 || b - t < 64) return Qt.vector4d(0, 0, 0, 0);
        return Qt.vector4d(l, t, r, b);
    }

    ShaderEffect {
        anchors.fill: parent
        blending: true
        fragmentShader: Qt.resolvedUrl("frame.frag.qsb")

        property vector4d field: Qt.vector4d(width, height, ShellFrame.band, ShellFrame.radius)
        property color tint: ShellFrame.fill
        property vector4d edgeWave: ShellFrame.amplitudes
        property vector4d waveClock: Qt.vector4d(ShellFrame.phase, 0, 0, 0)
        property int bodyCount: root.bodyCount
        property var shape: root.shapeArr
        property var radii: root.radiiArr
        property vector4d fuse: Qt.vector4d(ShellFrame.fuse, 0, 0, 0)
        property vector4d light: Qt.vector4d(ShellFrame.level, 0.45, 2, 0)
        property color ink: Theme.accent
        property vector4d quiet: root.quietRect
        property vector4d organic: Qt.vector4d(ShellFrame.bodySwell, ShellFrame.topSwell, 0, 0)
        property color borderA: ShellFrame.borderA
        property color borderB: ShellFrame.borderB
        property vector4d borderInfo: Qt.vector4d(ShellFrame.borderWidth, ShellFrame.borderPhase, 0, 0)
    }
}
