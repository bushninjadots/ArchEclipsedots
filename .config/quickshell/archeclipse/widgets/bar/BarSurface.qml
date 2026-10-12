import QtQuick
import QtQuick.Effects
import qs.theme
import qs.services

// The bar's own surface when the shell frame is off (Settings -> Bar ->
// Surface). One painter for the main pill and every detached section, so
// the no-frame look is consistent:
//   style   "solid"   — the classic opaque-ish plate
//           "glass"   — translucent, hairline light rim + top sheen
//           "outline" — nearly clear with an accent rim
//           "clear"   — nothing (widgets carry their own pills)
//   corners "rounded" | "sharp" | "capsule"
//   shadow  soft drop shadow under the plate
//   accent  a glowing accent line along the bar's inner edge
// Radii per corner come from the host (an attached bar is square on the
// screen-edge side unless it floats off the edge).
Item {
    id: root

    property real topLeftRadius: Theme.radius
    property real topRightRadius: Theme.radius
    property real bottomLeftRadius: Theme.radius
    property real bottomRightRadius: Theme.radius
    // Which side faces the content (gets the accent line): true = bottom.
    property bool innerBottom: Settings.barOrientation
    // Accent glow while something is "live" (a transient island is open).
    property bool live: false

    readonly property string style: Settings.barSurfaceStyle
    function cornerOf(r) {
        if (Settings.barSurfaceCorners === "sharp")
            return Math.min(r, 3);
        if (Settings.barSurfaceCorners === "capsule")
            return r > 0 ? Math.min(height / 2, 22) : 0;
        return r;
    }
    readonly property real tl: root.cornerOf(root.topLeftRadius)
    readonly property real tr: root.cornerOf(root.topRightRadius)
    readonly property real bl: root.cornerOf(root.bottomLeftRadius)
    readonly property real br: root.cornerOf(root.bottomRightRadius)

    visible: !ShellFrame.enabled && root.style !== "clear"

    RectangularShadow {
        visible: Settings.barSurfaceShadow
        anchors.fill: plate
        offset.y: root.innerBottom ? 4 : -4
        blur: 18
        spread: -2
        radius: Math.max(root.bl, root.br, root.tl, root.tr)
        color: Qt.rgba(0, 0, 0, root.style === "glass" ? 0.35 : 0.5)
    }

    Rectangle {
        id: plate
        anchors.fill: parent
        topLeftRadius: root.tl
        topRightRadius: root.tr
        bottomLeftRadius: root.bl
        bottomRightRadius: root.br
        color: root.style === "glass" ? Theme.rgba(Theme.background, 0.45)
            : root.style === "outline" ? Theme.rgba(Theme.background, 0.12)
            : Theme.surface
        border.width: root.style === "outline" ? 1.5 : 1
        border.color: root.style === "outline" ? Theme.rgba(Theme.accent, root.live ? 0.9 : 0.55)
            : root.style === "glass" ? Theme.rgba("#ffffff", 0.14)
            : Theme.rgba(Theme.foreground, 0.08)
        Behavior on border.color {
            ColorAnimation { duration: 220 }
        }

        // Glass: a faint sheen across the top half.
        Rectangle {
            visible: root.style === "glass"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 1
            height: parent.height / 2
            topLeftRadius: Math.max(0, root.tl - 1)
            topRightRadius: Math.max(0, root.tr - 1)
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.rgba("#ffffff", 0.07) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }

    // Accent line on the inner edge, brightest in the middle.
    Rectangle {
        visible: Settings.barSurfaceAccent
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.innerBottom ? parent.height - height - 1 : 1
        width: parent.width - Math.max(root.bl, root.br, 12) * 2
        height: 2
        radius: 1
        opacity: root.live ? 1 : 0.75
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.5; color: Theme.accent }
            GradientStop { position: 1; color: "transparent" }
        }
        Behavior on opacity {
            NumberAnimation { duration: 220 }
        }
    }
}
