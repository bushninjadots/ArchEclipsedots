import QtQuick
import Quickshell.Widgets

// Spun's vinyl record (src/disc.cpp, Disc::paintVinyl), ported to QML: the
// pressed body, its grooves and track gaps, the album art as the paper label
// with its ridges and spindle, and the fixed light sheen that stays put while
// the record turns under it. Drawn in Spun's 1000-unit space and scaled to fit.
// Spun © yappologistic, PolyForm Noncommercial 1.0.0 — see ./NOTICE.
Item {
    id: rec

    property string art: ""
    // Degrees; the host integrates the spin.
    property real angle: 0

    readonly property real k: Math.min(width, height) / 1000

    // The turning part: body, grooves, label. Painted once (and again only on
    // resize) — rotation is a transform, never a repaint, as in Spun.
    Item {
        id: turning
        anchors.fill: parent
        rotation: rec.angle

        Canvas {
            id: body
            anchors.fill: parent
            antialiasing: true
            renderTarget: Canvas.Image
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                var k = rec.k;
                if (k <= 0) return;
                ctx.save();
                ctx.translate((width - 1000 * k) / 2, (height - 1000 * k) / 2);
                ctx.scale(k, k);
                var c = 500;
                function ring(r, color, w) {
                    ctx.strokeStyle = color; ctx.lineWidth = w;
                    ctx.beginPath(); ctx.arc(c, c, r, 0, Math.PI * 2); ctx.stroke();
                }
                // the record, a ring with the spindle hole
                ctx.beginPath();
                ctx.arc(c, c, 497, 0, Math.PI * 2);
                ctx.arc(c, c, 16, 0, Math.PI * 2, true);
                var g = ctx.createRadialGradient(c, c, 0, c, c, 500);
                g.addColorStop(0, "#141519"); g.addColorStop(0.46, "#17181c");
                g.addColorStop(0.94, "#101114"); g.addColorStop(1, "#24252a");
                ctx.fillStyle = g;
                ctx.fill();
                // grooves, Spun's spacing (a fixed seed, so every paint matches)
                var seed = 44;
                function rnd() { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; }
                for (var r = 213; r < 488; r += 2.6 + rnd() * 1.8) {
                    ring(r, "rgba(180,185,195," + ((12 + Math.floor(rnd() * 16)) / 255) + ")", 0.65);
                    ring(r + 1.1, "rgba(0,0,0," + (90 / 255) + ")", 0.9);
                }
                ring(492, "rgba(1,2,3," + (180 / 255) + ")", 3);
                ring(495, "rgba(150,163,174," + (55 / 255) + ")", 0.8);
                // the gaps between tracks
                var gaps = [242, 310, 381, 452];
                for (var i = 0; i < gaps.length; i++)
                    ring(gaps[i], "rgba(2,3,5," + (115 / 255) + ")", 3);
                ctx.restore();
            }
        }

        // The paper label: the album art, cropped square and cut round.
        ClippingRectangle {
            width: 396 * rec.k
            height: width
            radius: width / 2
            anchors.centerIn: parent
            color: "#2b2d33"
            Image {
                anchors.fill: parent
                source: rec.art
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
                mipmap: true
                sourceSize.width: 512
                sourceSize.height: 512
            }
        }

        // label ridges + spindle (the paint after the label in paintVinyl)
        Canvas {
            anchors.fill: parent
            antialiasing: true
            renderTarget: Canvas.Image
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                var k = rec.k;
                if (k <= 0) return;
                ctx.translate((width - 1000 * k) / 2, (height - 1000 * k) / 2);
                ctx.scale(k, k);
                function ring(r, color, w) {
                    ctx.strokeStyle = color; ctx.lineWidth = w;
                    ctx.beginPath(); ctx.arc(500, 500, r, 0, Math.PI * 2); ctx.stroke();
                }
                ring(199, "rgba(0,0,0," + (120 / 255) + ")", 3);
                ring(72, "rgba(0,0,0," + (85 / 255) + ")", 1.8);
                ring(74, "rgba(255,255,255," + (28 / 255) + ")", 0.9);
                ring(178, "rgba(255,255,255," + (32 / 255) + ")", 1);
                // the spindle hole
                ctx.fillStyle = "#0b0c0f";
                ctx.beginPath(); ctx.arc(500, 500, 16, 0, Math.PI * 2); ctx.fill();
                ring(18, "rgba(0,0,0," + (170 / 255) + ")", 3);
                ring(21, "rgba(255,255,255," + (40 / 255) + ")", 1);
            }
        }
    }

    // The fixed light (Disc overlay): a conical sheen that does not turn, so
    // the record reads as spinning under a lamp.
    Canvas {
        anchors.fill: parent
        antialiasing: true
        renderTarget: Canvas.Image
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var k = rec.k;
            if (k <= 0) return;
            ctx.translate((width - 1000 * k) / 2, (height - 1000 * k) / 2);
            ctx.scale(k, k);
            ctx.beginPath();
            ctx.arc(500, 500, 497, 0, Math.PI * 2);
            ctx.arc(500, 500, 16, 0, Math.PI * 2, true);
            // QConicalGradient(center, 24°) runs counter-clockwise from 24°.
            var g = ctx.createConicalGradient(500, 500, 24 * Math.PI / 180);
            function a(x) { return x / 255; }
            g.addColorStop(0, "rgba(0,0,0,0)"); g.addColorStop(0.07, "rgba(0,0,0,0)");
            g.addColorStop(0.12, "rgba(203,216,229," + a(37) + ")"); g.addColorStop(0.155, "rgba(203,216,229," + a(10) + ")");
            g.addColorStop(0.22, "rgba(0,0,0,0)"); g.addColorStop(0.5, "rgba(0,0,0,0)");
            g.addColorStop(0.61, "rgba(244,233,214," + a(28) + ")"); g.addColorStop(0.67, "rgba(244,233,214," + a(5) + ")");
            g.addColorStop(0.73, "rgba(0,0,0,0)"); g.addColorStop(1, "rgba(0,0,0,0)");
            ctx.fillStyle = g;
            ctx.fill();
        }
    }
}
