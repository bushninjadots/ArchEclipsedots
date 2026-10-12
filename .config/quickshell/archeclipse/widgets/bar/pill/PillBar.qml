import QtQuick
import qs.theme
import qs.services
import qs.widgets.bar
import qs.widgets.shared

// Pill bar face (Settings.barStyle === "pill") — the original morphing island.
//
// Rest face: the "rest" section (default: workspace dots · clock · live chip).
// Hover expands in place into a two-tier reveal: the "core" row, a hairline
// divider, and the "detail" row. The outer ArchEclipse pill (Bar.qml) is the
// surface; this item is only the content face, so the pill grows in place.
// The two faces never share the screen: rest fades out over the first half of
// the transition, expanded fades in over the second.
//
// While editing, both faces are replaced by one stacked face showing all
// three sections at once as drop targets (rest · core · detail).
Item {
    id: root

    readonly property bool editing: BarEditState.active && BarEditState.style === "pill"

    // Hover-driven expand. A short leave delay keeps the pill from folding the
    // instant the cursor skims its edge; an open popup pins it.
    property bool open: false
    readonly property bool expanded: open || BarState.popupCount > 0
    property real t: expanded ? 1 : 0
    Behavior on t {
        Anim { type: Anim.DefaultSpatial }
    }

    // ---- edit-mode geometry (scene coords) ----
    readonly property var _strips: root.editing
        ? (editLoader.item ? [editLoader.item.rest, editLoader.item.core, editLoader.item.detail] : [])
        : [restStrip, coreStrip, detailStrip]

    function cellItem(id) {
        for (const s of root._strips) {
            const it = s.cellItem(id);
            if (it)
                return it;
        }
        return null;
    }
    function editCells() {
        const out = [];
        if (root.editing) {
            for (const s of root._strips)
                s.cells(out);
            return out;
        }
        // Normal mode: only the visible face publishes cells.
        if (root.t < 0.5)
            restStrip.cells(out);
        else {
            coreStrip.cells(out);
            detailStrip.cells(out);
        }
        return out;
    }
    function editZones() {
        if (!root.editing || !editLoader.item)
            return [];
        const e = editLoader.item;
        return [e.rest.zoneRect(e.restRow), e.core.zoneRect(e.coreRow), e.detail.zoneRect(e.detailRow)];
    }
    function frameSections() {
        return [];
    }

    readonly property real _w: root.editing ? (editLoader.item ? editLoader.item.implicitWidth : 0)
        : (root.expanded ? openContent.implicitWidth : restStrip.implicitWidth)
    readonly property real _h: root.editing ? (editLoader.item ? editLoader.item.implicitHeight : 0)
        : (root.expanded ? openContent.implicitHeight : restStrip.implicitHeight)
    implicitWidth: Math.max(root._w, 40) + 28
    implicitHeight: root._h + 10
    width: implicitWidth
    height: implicitHeight

    HoverHandler {
        id: pillHover
        enabled: !root.editing
        onHoveredChanged: {
            if (hovered) {
                leaveTimer.stop();
                // Click mode (Settings.barHoverReveal off): the rest face
                // opens on a click instead (TapHandler below).
                if (Settings.barHoverReveal)
                    root.open = true;
            } else {
                leaveTimer.restart();
            }
        }
    }

    Timer {
        id: leaveTimer
        interval: 250
        onTriggered: {
            if (!pillHover.hovered && BarState.popupCount <= 0)
                root.open = false;
        }
    }
    Connections {
        target: BarState
        function onPopupCountChanged() {
            if (BarState.popupCount <= 0 && !pillHover.hovered)
                leaveTimer.restart();
        }
    }

    // ---- rest face ----
    EditStrip {
        id: restStrip
        anchors.centerIn: parent
        visible: !root.editing
        style: "pill"
        zone: "rest"
        spacing: 14
        opacity: Math.max(0, 1 - root.t * 2)
        enabled: root.t < 0.5
    }

    // ---- expanded face: core row · divider · detail row ----
    Column {
        id: openContent
        anchors.centerIn: parent
        spacing: 10
        visible: !root.editing && root.t > 0.01
        opacity: Math.max(0, root.t * 2 - 1)
        scale: 0.98 + 0.02 * root.t
        enabled: root.t >= 0.5

        EditStrip {
            id: coreStrip
            anchors.horizontalCenter: parent.horizontalCenter
            style: "pill"
            zone: "core"
            spacing: 14
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: coreStrip.count > 0 && detailStrip.count > 0
            width: 180
            height: 1
            color: Theme.border
            opacity: 0.6
        }
        EditStrip {
            id: detailStrip
            anchors.horizontalCenter: parent.horizontalCenter
            style: "pill"
            zone: "detail"
            spacing: 14
        }
    }

    // ---- edit face: every section stacked as a drop target ----
    Loader {
        id: editLoader
        anchors.centerIn: parent
        active: root.editing
        sourceComponent: Column {
            readonly property alias rest: eRest
            readonly property alias core: eCore
            readonly property alias detail: eDetail
            readonly property alias restRow: restRow
            readonly property alias coreRow: coreRow
            readonly property alias detailRow: detailRow
            spacing: 14

            Item {
                id: restRow
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(eRest.width, 160)
                height: eRest.height
                EditStrip { id: eRest; anchors.centerIn: parent; style: "pill"; zone: "rest"; spacing: 14 }
            }
            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 180; height: 1; color: Theme.border; opacity: 0.6 }
            Item {
                id: coreRow
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(eCore.width, 160)
                height: eCore.height
                EditStrip { id: eCore; anchors.centerIn: parent; style: "pill"; zone: "core"; spacing: 14 }
            }
            Item {
                id: detailRow
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(eDetail.width, 160)
                height: eDetail.height
                EditStrip { id: eDetail; anchors.centerIn: parent; style: "pill"; zone: "detail"; spacing: 14 }
            }
        }
    }

    // Click-to-open (Settings.barHoverReveal off): while the pill rests, a
    // catcher above the face takes the first click and expands it; once open
    // the widgets get their clicks. (A handler on the pill itself would never
    // see clicks the widgets' own mouse areas accept.)
    MouseArea {
        anchors.fill: parent
        z: 100
        visible: !root.editing && !root.open && !Settings.barHoverReveal
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            leaveTimer.stop();
            root.open = true;
        }
    }
}
