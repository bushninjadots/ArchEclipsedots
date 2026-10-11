import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.theme
import qs.services
import qs.widgets.bar.pill

// Islands bar face (Settings.barStyle !== "pill"), freeform linear form.
//
// The zone chrome is gone: the visible widgets come straight from the linear
// layout (Settings.barLayoutTop for the top edge, barLayoutBottom for the
// bottom) and render as two centred strips (top + bottom edges of the bar's
// pill) with each widget at its natural size. The outer pill / shell frame
// supplies the background surface.
//
// VISUAL RULING (recorded in the plan ledger): the old centre accent chip
// (surfaceActive capsule over the centre zone) is dropped because in linear
// mode the left/center/right groups no longer exist — a widget belongs where
// its linear position puts it. Defaults reproduce today's widget ORDER,
// spacing and membership via the zone→linear migration (left+center+right =
// top, bottom = bottom); only the inner capsule is gone.
Column {
    id: root
    spacing: 4

    // ---- linear sequence access (Settings bar layout model, Task 1) ----
    readonly property var linearTopIds: Array.isArray(Settings.barLayoutTop) ? Settings.barLayoutTop : []
    readonly property var linearBottomIds: Array.isArray(Settings.barLayoutBottom) ? Settings.barLayoutBottom : []

    // ---- edit-mode geometry (scene coords) ----
    function _collectCells(rep, ids, zone, out) {
        for (let i = 0; i < rep.count; i++) {
            const d = rep.itemAt(i);
            if (!d)
                continue;
            // The delegate may be a plain Loader or an Item wrapper whose child
            // is a Loader. Resolve to that Loader and use the delegate geometry.
            let ldr = d;
            if (typeof d.item === "undefined") {
                ldr = null;
                const kids = d.children;
                for (let k = 0; k < kids.length; k++) {
                    if (kids[k] && typeof kids[k].item !== "undefined") {
                        ldr = kids[k];
                        break;
                    }
                }
            }
            if (!ldr || !ldr.item)
                continue;
            const p = d.mapToItem(null, 0, 0);
            out.push({ id: ids[i], zone: zone, x: p.x, y: p.y, w: d.width, h: d.height });
        }
    }
    function editCells() {
        if (Settings.barStyle === "pill")
            return pillLoader.item && pillLoader.item.editCells ? pillLoader.item.editCells() : [];
        const out = [];
        root._collectCells(topRep, root.linearTopIds, "top", out);
        root._collectCells(bottomRep, root.linearBottomIds, "bottom", out);
        return out;
    }
    function _stripRect(row, zone) {
        const p = row.mapToItem(null, 0, 0);
        return { zone: zone, x: p.x, y: p.y, w: row.width, h: row.height };
    }
    function editZones() {
        if (Settings.barStyle === "pill")
            return pillLoader.item && pillLoader.item.editZones ? pillLoader.item.editZones() : [];
        const zones = [];
        if (topRow.visible)
            zones.push(root._stripRect(topRow, "top"));
        if (bottomRow.visible)
            zones.push(root._stripRect(bottomRow, "bottom"));
        return zones;
    }

    // ---- top edge strip (barLayoutTop order) ----
    Item {
        id: topRow
        visible: Settings.barStyle !== "pill"
        implicitWidth: topStrip.implicitWidth
        width: implicitWidth
        height: Theme.barContentHeight

        Row {
            id: topStrip
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacing

            Repeater {
                id: topRep
                model: root.linearTopIds
                delegate: Loader {
                    // No width binding: the Loader auto-sizes to the widget's
                    // natural size (widgets lack implicitWidth).
                    required property string modelData
                    sourceComponent: BarWidgets.component(modelData, "islands", "top")
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // Pill bar style face (Settings.barStyle === "pill"). The outer pill in
    // Bar.qml stays the surface; this is only the morphing content face.
    Loader {
        id: pillLoader
        active: Settings.barStyle === "pill"
        sourceComponent: pillComponent
    }
    Component {
        id: pillComponent
        PillBar {}
    }

    // ---- bottom edge strip (barLayoutBottom order) ----
    Row {
        id: bottomRow
        visible: Settings.barStyle !== "pill"
        width: topRow.width
        spacing: Theme.spacing

        Repeater {
            id: bottomRep
            model: root.linearBottomIds
            delegate: Loader {
                required property string modelData
                sourceComponent: BarWidgets.component(modelData, "islands", "bottom")
                width: bottomRow.width
            }
        }
    }
}