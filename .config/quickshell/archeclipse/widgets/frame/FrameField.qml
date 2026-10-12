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

    // Legacy shader bodies { pill, left, right } in this item's px.
    property var bodies: ({})
    // Every body to melt into the frame, in draw order.
    property var bodiesList: []
    property bool topBar: true

    // Must match BODY_SLOTS in frame.frag (shapes/radii travel as individual
    // shapeN/radiiN uniforms; a vec4 array in a ShaderEffect block does not
    // upload on every backend Qt targets — iNiR packs its shapes the same way).
    readonly property int bodySlots: 24

    // Centre x / half-width of the bar, where the music lifts the band.
    property real pullX: width / 2
    property real pullHalf: 0

    // Target body list (bodiesList when non-empty, else legacy bodies).
    readonly property var targetItems: {
        if (root.bodiesList && root.bodiesList.length > 0)
            return root.bodiesList;
        const l = [];
        for (const key of ["pill", "left", "right"]) {
            const b = root.bodies[key];
            if (b) l.push(b);
        }
        return l;
    }

    // ---- morphing ----
    // Bodies carry a `key`; the drawn list eases each key toward its target
    // (Settings.frameMorph: spring / smooth / instant). A new key grows out of
    // the band (or its own centre when floating) and a vanished key retracts
    // before it is dropped, so sections never pop in or out.
    readonly property string morph: Settings.animationsEnabled ? Settings.frameMorph : "instant"
    property var _state: ({})          // key -> { b: body, v: velocities, dying }
    property var bodyItems: []
    property bool _settled: true
    property string _sig: ""

    function _keyOf(b, i) {
        return b.key !== undefined ? b.key : ("#" + i);
    }
    // Collapsed form of a body: flattened onto the band edge it touches,
    // else shrunk to its centre.
    function _collapsed(b) {
        const c = Object.assign({}, b);
        if (b.y <= 1) {
            c.h = 0.5;
        } else if (b.y + b.h >= root.height - 1) {
            c.y = root.height - 0.5;
            c.h = 0.5;
        } else {
            c.x = b.x + b.w / 2;
            c.y = b.y + b.h / 2;
            c.w = 0.5;
            c.h = 0.5;
        }
        return c;
    }
    readonly property var _fields: ["x", "y", "w", "h"]

    function _step(dt) {
        const targets = root.targetItems;
        const st = root._state;
        const seen = {};
        const instant = root.morph === "instant";
        for (let i = 0; i < targets.length; i++) {
            const t = targets[i];
            if (!t || t.on === false || t.w <= 0 || t.h <= 0)
                continue;
            const k = root._keyOf(t, i);
            seen[k] = true;
            if (!st[k] || instant)
                st[k] = { b: instant ? Object.assign({}, t) : root._collapsed(t), v: { x: 0, y: 0, w: 0, h: 0 }, order: i };
            st[k].target = t;
            st[k].dying = false;
            st[k].order = i;
        }
        for (const k in st) {
            if (!seen[k]) {
                if (instant) {
                    delete st[k];
                    continue;
                }
                if (!st[k].dying) {
                    st[k].dying = true;
                    st[k].target = root._collapsed(st[k].b);
                }
            }
        }
        let settled = true;
        const out = [];
        for (const k in st) {
            const e = st[k];
            const t = e.target;
            const b = e.b;
            // Corners/flags follow the target immediately.
            for (const f of ["tl", "tr", "br", "bl", "radius", "fuse"])
                if (t[f] !== undefined) b[f] = t[f];
            b.on = true;
            let done = true;
            for (const f of root._fields) {
                const d = t[f] - b[f];
                if (root.morph === "spring") {
                    // Slightly under-damped spring: a soft overshoot.
                    const kS = 260, damp = 24;
                    e.v[f] += (d * kS - e.v[f] * damp) * dt;
                    b[f] += e.v[f] * dt;
                } else {
                    b[f] += d * Math.min(1, dt * 14);
                }
                if (Math.abs(t[f] - b[f]) > 0.25 || Math.abs(e.v[f]) > 2) {
                    settled = false;
                    done = false;
                } else if (!e.dying) {
                    b[f] = t[f];
                    e.v[f] = 0;
                }
            }
            // Panel solidity (0 = frame opacity, 1 = panel opacity) eases so
            // an island firms up as it opens and thins back as it closes.
            {
                const ts = e.dying ? 0 : (t.solid || 0);
                const cs = b.solid || 0;
                b.solid = instant ? ts : cs + (ts - cs) * Math.min(1, dt * 10);
                if (Math.abs(ts - b.solid) > 0.01) {
                    settled = false;
                    done = false;
                } else {
                    b.solid = ts;
                }
            }
            if (e.dying && done) {
                delete st[k];
                continue;
            }
            out.push({ o: e.order, b: Object.assign({}, b) });
        }
        out.sort((a, c) => a.o - c.o);
        root._settled = settled;
        // Only push when something moved: every assignment re-uploads all
        // shader body uniforms.
        const next = out.map(e => e.b);
        const sig = JSON.stringify(next);
        if (sig !== root._sig) {
            root._sig = sig;
            root.bodyItems = next;
        }
    }
    onTargetItemsChanged: if (root.morph === "instant" || !root.visible) root._step(0)
    FrameAnimation {
        running: root.visible
        onTriggered: root._step(Math.min(0.05, frameTime))
    }

    function _shapeSlot(i) {
        const b = root.bodyItems[i];
        if (!b || b.on === false || b.w <= 0 || b.h <= 0)
            return Qt.vector4d(0, 0, 0, 0);
        return Qt.vector4d(b.x + b.w / 2, b.y + b.h / 2, b.w / 2, b.h / 2);
    }
    // Per-body fillet depth into the band (body.fuse, default the shared one).
    function _fuseOf(i) {
        const b = root.bodyItems[i];
        if (!b || b.on === false || b.w <= 0 || b.h <= 0)
            return 0;
        return b.fuse !== undefined ? b.fuse : ShellFrame.fuse;
    }
    function _solidOf(i) {
        const b = root.bodyItems[i];
        if (!b || b.on === false || b.w <= 0 || b.h <= 0)
            return 0;
        return b.solid || 0;
    }
    function _solidSlot(n) {
        return Qt.vector4d(root._solidOf(n * 4), root._solidOf(n * 4 + 1), root._solidOf(n * 4 + 2), root._solidOf(n * 4 + 3));
    }
    function _fuseSlot(n) {
        return Qt.vector4d(root._fuseOf(n * 4), root._fuseOf(n * 4 + 1), root._fuseOf(n * 4 + 2), root._fuseOf(n * 4 + 3));
    }
    function _radiiSlot(i) {
        const b = root.bodyItems[i];
        if (!b || b.on === false || b.w <= 0 || b.h <= 0)
            return Qt.vector4d(0, 0, 0, 0);
        return root.radiiOf(b);
    }

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
        property vector4d shape0: root._shapeSlot(0)
        property vector4d radii0: root._radiiSlot(0)
        property vector4d shape1: root._shapeSlot(1)
        property vector4d radii1: root._radiiSlot(1)
        property vector4d shape2: root._shapeSlot(2)
        property vector4d radii2: root._radiiSlot(2)
        property vector4d shape3: root._shapeSlot(3)
        property vector4d radii3: root._radiiSlot(3)
        property vector4d shape4: root._shapeSlot(4)
        property vector4d radii4: root._radiiSlot(4)
        property vector4d shape5: root._shapeSlot(5)
        property vector4d radii5: root._radiiSlot(5)
        property vector4d shape6: root._shapeSlot(6)
        property vector4d radii6: root._radiiSlot(6)
        property vector4d shape7: root._shapeSlot(7)
        property vector4d radii7: root._radiiSlot(7)
        property vector4d shape8: root._shapeSlot(8)
        property vector4d radii8: root._radiiSlot(8)
        property vector4d shape9: root._shapeSlot(9)
        property vector4d radii9: root._radiiSlot(9)
        property vector4d shape10: root._shapeSlot(10)
        property vector4d radii10: root._radiiSlot(10)
        property vector4d shape11: root._shapeSlot(11)
        property vector4d radii11: root._radiiSlot(11)
        property vector4d shape12: root._shapeSlot(12)
        property vector4d radii12: root._radiiSlot(12)
        property vector4d shape13: root._shapeSlot(13)
        property vector4d radii13: root._radiiSlot(13)
        property vector4d shape14: root._shapeSlot(14)
        property vector4d radii14: root._radiiSlot(14)
        property vector4d shape15: root._shapeSlot(15)
        property vector4d radii15: root._radiiSlot(15)
        property vector4d shape16: root._shapeSlot(16)
        property vector4d radii16: root._radiiSlot(16)
        property vector4d shape17: root._shapeSlot(17)
        property vector4d radii17: root._radiiSlot(17)
        property vector4d shape18: root._shapeSlot(18)
        property vector4d radii18: root._radiiSlot(18)
        property vector4d shape19: root._shapeSlot(19)
        property vector4d radii19: root._radiiSlot(19)
        property vector4d shape20: root._shapeSlot(20)
        property vector4d radii20: root._radiiSlot(20)
        property vector4d shape21: root._shapeSlot(21)
        property vector4d radii21: root._radiiSlot(21)
        property vector4d shape22: root._shapeSlot(22)
        property vector4d radii22: root._radiiSlot(22)
        property vector4d shape23: root._shapeSlot(23)
        property vector4d radii23: root._radiiSlot(23)
        property vector4d bodyFuse0: root._fuseSlot(0)
        property vector4d bodyFuse1: root._fuseSlot(1)
        property vector4d bodyFuse2: root._fuseSlot(2)
        property vector4d bodyFuse3: root._fuseSlot(3)
        property vector4d bodyFuse4: root._fuseSlot(4)
        property vector4d bodyFuse5: root._fuseSlot(5)
        property vector4d bodySolid0: root._solidSlot(0)
        property vector4d bodySolid1: root._solidSlot(1)
        property vector4d bodySolid2: root._solidSlot(2)
        property vector4d bodySolid3: root._solidSlot(3)
        property vector4d bodySolid4: root._solidSlot(4)
        property vector4d bodySolid5: root._solidSlot(5)
        // z: the opacity open panels (islands, side panels) fill at.
        property vector4d fuse: Qt.vector4d(ShellFrame.fuse, Settings.frameMerge, ShellFrame.panelAlpha, 0)
        property vector4d light: Qt.vector4d(ShellFrame.level, 0.45 + 0.35 * ShellFrame.flash, 2 + 1.5 * ShellFrame.flash, ShellFrame.sparkle)
        property color ink: Theme.accent
        property vector4d quiet: root.quietRect
        property vector4d organic: Qt.vector4d(ShellFrame.bodySwell, ShellFrame.topSwell, root.pullX, root.pullHalf)
        property color borderA: ShellFrame.borderA
        property color borderB: ShellFrame.borderB
        property vector4d borderInfo: Qt.vector4d(ShellFrame.borderWidth, ShellFrame.borderPhase, 0, 0)
    }
}
