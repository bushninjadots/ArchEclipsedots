import QtQuick
import qs.theme

// Dumb renderer (iNiR CavaVisualizer port): draws one vertical bar per
// entry of `points` (0..1 per band). Never claims a feed itself — the host
// passes levels in. Bar colour is the `tint` theme colour with a level-
// based alpha ramp; bars rest at ~2 % height when the signal is empty.
Item {
    id: root

    property var points: []
    property color tint: Theme.accent
    // 0 = auto (bars fill the width equally); >0 = fixed bar width
    property int barWidth: 0
    property real gap: 2

    // Rest height fraction when there is no signal.
    readonly property real restFraction: 0.02

    function alphaFor(v) {
        return v > 0.75 ? 1.0 : (v > 0.35 ? 0.75 : 0.45);
    }

    Row {
        id: barsRow
        anchors.fill: parent
        spacing: root.gap

        Repeater {
            model: (root.points || []).length

            Item {
                id: barWrapper
                required property int index
                width: root.barWidth > 0 ? root.barWidth
                     : Math.max(1, (root.width - ((root.points.length - 1) * root.gap)) / root.points.length)
                height: root.height

                readonly property real level: root.points[barWrapper.index] || 0

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    // pill-shaped bar: radius = half the (sub-pixel safe) width
                    radius: width / 2
                    height: Math.max(root.restFraction * parent.height, barWrapper.level * parent.height)
                    color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, root.alphaFor(barWrapper.level))

                    Behavior on height {
                        enabled: Settings.animationsEnabled
                        NumberAnimation {
                            duration: 80
                            easing.type: Easing.OutQuad
                        }
                    }
                }
            }
        }
    }
}
