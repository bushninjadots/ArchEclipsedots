import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.widgets.shared

// Pill bar face (Settings.barStyle === "pill") — a single morphing island,
// freeform linear form (bar layout system, Task 8).
//
// The former rest/core/detail two-tier faces collapse into one flat track
// over barLayoutTop (the pill lives on the active bar edge; its content is
// the top-edge linear sequence regardless of orientation). The outer
// ArchEclipse pill (Bar.qml) is the surface; this item is only the content
// face, so the pill grows in place. Side islands, pulses and search keep
// using the untouched BarState machine.
//
// VISUAL RULING (recorded in the plan ledger): the hover two-tier expansion
// is retired in linear mode — there are no rest/core/detail groups left to
// reveal, and the single track IS the full pill face.
Item {
    id: root

    readonly property var linearIds: BarWidgets.layoutLinear("pill", "top")

    // ---- edit-mode geometry (scene coords) ----
    function _collectCells(rep, ids, zone, out) {
        for (let i = 0; i < rep.count; i++) {
            const l = rep.itemAt(i);
            if (!l || !l.item)
                continue;
            const p = l.mapToItem(null, 0, 0);
            out.push({ id: ids[i], zone: zone, x: p.x, y: p.y, w: l.width, h: l.height });
        }
    }
    function _zoneRect(item, zone) {
        const p = item.mapToItem(null, 0, 0);
        return { zone: zone, x: p.x, y: p.y, w: item.width, h: item.height };
    }
    function editCells() {
        if (!BarEditState.active)
            return [];
        const out = [];
        root._collectCells(trackEditRep, root.linearIds, "top", out);
        return out;
    }
    function editZones() {
        if (!BarEditState.active)
            return [];
        return [root._zoneRect(trackEditRow, "top")];
    }

    // The pill is sized by its track (plus the pill's 28/10 padding chrome).
    implicitWidth: (BarEditState.active ? trackEditRow.implicitWidth : trackRow.implicitWidth) + 28
    implicitHeight: (BarEditState.active ? trackEditRow.implicitHeight : trackRow.implicitHeight) + 10
    width: implicitWidth
    height: implicitHeight

    // ---- normal face: flat linear track ----
    Row {
        id: trackRow
        anchors.centerIn: parent
        spacing: 14
        visible: !BarEditState.active

        Repeater {
            id: trackRep
            model: root.linearIds
            delegate: Loader {
                required property string modelData
                active: !BarEditState.active
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: BarWidgets.component(modelData, "pill", "top")
            }
        }
    }

    // ---- edit face: the same track, interactive (overlay drives drags) ----
    Row {
        id: trackEditRow
        visible: BarEditState.active
        anchors.centerIn: parent
        spacing: 14
        width: Math.max(childrenRect.width, 64)
        height: Math.max(childrenRect.height, Theme.barContentHeight)

        Repeater {
            id: trackEditRep
            model: root.linearIds
            delegate: Loader {
                required property string modelData
                active: BarEditState.active
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: BarWidgets.component(modelData, "pill", "top")
            }
        }
    }
}