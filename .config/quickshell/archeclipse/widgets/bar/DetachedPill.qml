import QtQuick
import qs.theme
import qs.services

// One floating section pill in detached-islands mode (bar layout system,
// Task 8). It renders the same zone contents the attached bar shows, but as
// its own rounded surface (attached mode draws the left/right zones on the
// shared bar pill; here every section is independent). DetachedBar positions
// it; Bar.qml masks input to the pill rect, so the desktop between pills stays
// clickable.
Rectangle {
    id: root

    // "left" | "center" | "right" | "bottom"
    property string section: "left"
    // Stretch sections (the bottom workspace strip, whose child sizes from its
    // parent's width) fill the pill and centre their child; the others hug
    // their content.
    property bool stretch: false

    readonly property var ids: BarWidgets.layout("islands", section)
    readonly property int pad: 10

    // An empty section draws nothing (and is masked out).
    visible: ids.length > 0
    implicitWidth: stretch ? 0 : (row.implicitWidth + pad * 2)
    implicitHeight: Theme.barContentHeight + 14
    width: implicitWidth
    height: implicitHeight
    radius: Theme.radius
    // Keep the centre section's active tint so it still reads as the control
    // cluster, matching the attached bar's centre pill.
    color: section === "center" ? Theme.surfaceActive : Theme.surface

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: stretch ? undefined : parent.horizontalCenter
        anchors.left: stretch ? parent.left : undefined
        anchors.leftMargin: stretch ? root.pad : 0
        // Hug by default; fill the pill in stretch sections.
        width: stretch ? (parent.width - root.pad * 2) : implicitWidth
        spacing: Theme.spacing

        Repeater {
            id: rep
            model: root.ids
            delegate: Loader {
                required property string modelData
                sourceComponent: BarWidgets.component(modelData, "islands", root.section)
                anchors.verticalCenter: parent.verticalCenter
                // Hug the widget's natural size by default. In stretch
                // sections (the bottom workspace strip, whose widget sizes
                // from its parent) the loader fills the row instead. An
                // unconditional `width: implicitWidth` would collapse widgets
                // that declare only `width`.
                Binding on width {
                    when: root.stretch
                    value: parent.width
                }
            }
        }
    }

    // ---- edit-mode geometry (scene coords), mirrors DefaultBar._collectCells ----
    function cells() {
        const out = [];
        for (let i = 0; i < rep.count; i++) {
            const l = rep.itemAt(i);
            if (!l || !l.item)
                continue;
            const p = l.mapToItem(null, 0, 0);
            out.push({ id: root.ids[i], zone: root.section, x: p.x, y: p.y, w: l.width, h: l.height });
        }
        return out;
    }
}
