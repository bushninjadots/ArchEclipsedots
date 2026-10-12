import QtQuick
import qs.theme
import qs.services
import qs.widgets.shared

// One floating section pill in detached-islands mode. It renders the same
// section the attached bar shows (an EditStrip over BarEditState.ids, so a
// live drag previews in place) as its own rounded surface. DetachedBar
// positions it; Bar.qml masks input to the pill rect, so the desktop between
// pills stays clickable.
Rectangle {
    id: root

    // "left" | "center" | "right" | "bottom"
    property string section: "left"
    // Stretch sections (the bottom workspace strip, whose child sizes from
    // its parent's width) fill the pill; the others hug their content.
    property bool stretch: false
    readonly property int pad: 10
    readonly property bool hasContent: strip.count > 0

    // An empty section draws nothing (and is masked out) — except while
    // editing, when it stays up as a drop target.
    visible: root.hasContent || BarEditState.active
    implicitWidth: stretch ? 0 : (strip.implicitWidth + pad * 2)
    implicitHeight: Math.max(Theme.barContentHeight, strip.implicitHeight) + 14
    width: implicitWidth
    height: implicitHeight
    radius: Theme.radius
    // In frame mode the shell frame paints the fill + border for the section,
    // so the surface stays transparent; otherwise the classic fills (centre
    // keeps its accent tint).
    color: ShellFrame.enabled || !root.hasContent ? "transparent"
        : (section === "center" && Settings.barWidgetDeco === "none" ? Theme.surfaceActive : Theme.surface)

    EditStrip {
        id: strip
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        style: "islands"
        zone: root.section
        // A pill at its default anchor grows from that anchor; a pill the
        // user placed keeps its left edge.
        align: {
            const p = (Settings.barIslandsPos || {})[root.section];
            if (p && p.x !== undefined && p.x >= 0)
                return "left";
            return root.section === "left" ? "left" : root.section === "right" ? "right" : "center";
        }
        equalEnds: root.section === "center"
        stretchSingle: root.stretch
        fillWidth: root.stretch ? root.width - root.pad * 2 : 0
    }

    // ---- edit-mode geometry (scene coords) ----
    function cellItem(id) {
        return strip.cellItem(id);
    }
    function cells() {
        return strip.cells([]);
    }
    function zoneRect() {
        return strip.zoneRect(root);
    }
}
