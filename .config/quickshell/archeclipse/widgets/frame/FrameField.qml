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
    property bool topBar: true

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

    // The interior nothing reaches, so a moving swell redraws the edges only.
    readonly property vector4d quietRect: {
        const a = ShellFrame.amplitudes;
        const wave = Math.max(a.x, a.y, a.z, a.w, 0) + ShellFrame.topSwell;
        const edge = ShellFrame.band + wave + ShellFrame.fuse + ShellFrame.radius + ShellFrame.borderWidth + 8;
        let l = edge, t = edge, r = root.width - edge, b = root.height - edge;
        const m = ShellFrame.fuse + ShellFrame.bodySwell * 2.5 + 16;
        for (const s of [root.bodies.pill, root.bodies.left, root.bodies.right]) {
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
        property vector4d shape0: root.shapeOf(root.bodies.pill)
        property vector4d radii0: root.radii
        property vector4d shape1: root.shapeOf(root.bodies.left)
        property vector4d radii1: root.radii
        property vector4d shape2: root.shapeOf(root.bodies.right)
        property vector4d radii2: root.radii
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
