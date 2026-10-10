import QtQuick
import qs.theme

// Dumb renderer (iNiR CavaVisualizer port, wave look): one smooth filled
// curve over `points` (0..1 per band) with a lit crest on its top edge.
// Never claims a feed itself — the host passes levels in.
Canvas {
    id: root

    property var points: []
    property color tint: Theme.accent
    // Rest height fraction when there is no signal.
    readonly property real restFraction: 0.04

    onPointsChanged: requestPaint()
    onTintChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        var pts = root.points || [];
        var n = pts.length;
        if (n < 2 || width <= 0 || height <= 0)
            return;
        var base = height * (1 - root.restFraction);
        var step = width / (n - 1);
        var yAt = function (i) {
            var v = Math.max(0, Math.min(1, +pts[i] || 0));
            return base - v * (base - 1);
        };
        ctx.beginPath();
        ctx.moveTo(0, height);
        ctx.lineTo(0, yAt(0));
        for (var i = 0; i < n - 1; i++) {
            var mx = (i + 0.5) * step;
            var my = (yAt(i) + yAt(i + 1)) / 2;
            ctx.quadraticCurveTo(i * step, yAt(i), mx, my);
        }
        ctx.lineTo(width, yAt(n - 1));
        ctx.lineTo(width, height);
        ctx.closePath();
        ctx.fillStyle = Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.28);
        ctx.fill();

        // lit crest on the moving edge
        ctx.beginPath();
        ctx.moveTo(0, yAt(0));
        for (var j = 0; j < n - 1; j++) {
            var mx2 = (j + 0.5) * step;
            var my2 = (yAt(j) + yAt(j + 1)) / 2;
            ctx.quadraticCurveTo(j * step, yAt(j), mx2, my2);
        }
        ctx.lineTo(width, yAt(n - 1));
        ctx.strokeStyle = Qt.rgba(root.tint.r, root.tint.g, root.tint.b, 0.95);
        ctx.lineWidth = 1.6;
        ctx.lineJoin = "round";
        ctx.stroke();
    }
}
