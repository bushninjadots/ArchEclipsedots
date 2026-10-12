import QtQuick
import Quickshell
import qs.theme
import qs.services
import qs.widgets.bar.pill
import qs.widgets.shared

// Islands bar face (Settings.barStyle !== "pill") — the original layout:
// fixed-width left/right sections so the centre capsule (bandwidth | control
// | clock, accent-tinted) stays dead-centre, and a full-width workspace row
// beneath. Every section is an EditStrip over BarEditState.ids("islands",
// zone), so membership/order come from the layout model and a live drag
// previews in place.
Column {
    id: root
    spacing: 4

    // ---- edit-mode geometry (scene coords) ----
    function cellItem(id) {
        if (Settings.barStyle === "pill")
            return pillLoader.item && pillLoader.item.cellItem ? pillLoader.item.cellItem(id) : null;
        for (const s of [leftStrip, centerStrip, rightStrip, bottomStrip]) {
            const it = s.cellItem(id);
            if (it)
                return it;
        }
        return null;
    }
    function editCells() {
        if (Settings.barStyle === "pill")
            return pillLoader.item && pillLoader.item.editCells ? pillLoader.item.editCells() : [];
        const out = [];
        leftStrip.cells(out);
        centerStrip.cells(out);
        rightStrip.cells(out);
        bottomStrip.cells(out);
        return out;
    }
    function editZones() {
        if (Settings.barStyle === "pill")
            return pillLoader.item && pillLoader.item.editZones ? pillLoader.item.editZones() : [];
        return [
            leftStrip.zoneRect(leftZone),
            centerStrip.zoneRect(centerPill),
            rightStrip.zoneRect(rightZone),
            bottomStrip.zoneRect(bottomRow)
        ];
    }
    // Section bodies for the shell frame: rect of each non-empty section in
    // scene coords ({ zone, x, y, w, h }).
    function frameSections() {
        if (Settings.barStyle === "pill")
            return [];
        const out = [];
        const add = (it, zone, strip) => {
            if (strip.count === 0 || it.width <= 0)
                return;
            const p = it.mapToItem(null, 0, 0);
            out.push({ zone: zone, x: p.x, y: p.y, w: it.width, h: it.height });
        };
        add(leftStrip, "left", leftStrip);
        add(centerPill, "center", centerStrip);
        add(rightStrip, "right", rightStrip);
        add(bottomStrip, "bottom", bottomStrip);
        return out;
    }

    Item {
        id: topRow
        visible: Settings.barStyle !== "pill"
        // Both side sections count as wide as the wider one, so the centred
        // capsule keeps Theme.spacing clearance from either side.
        readonly property real sideWidth: Math.max(leftStrip.naturalWidthHint, rightStrip.implicitWidth)
        implicitWidth: 2 * sideWidth + (centerPill.visible ? centerPill.width : 0) + Theme.spacing * 2
        width: implicitWidth
        height: Theme.barContentHeight

        // Centre capsule — equal-width end cells keep the middle widget
        // dead-centre relative to the whole bar.
        Rectangle {
            id: centerPill
            visible: centerStrip.count > 0 || BarEditState.active
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: centerStrip.width + 20
            height: Theme.barContentHeight
            radius: Theme.radius
            // The accent capsule is the classic look; with widget pills on it
            // would double up, so the pills take over.
            color: centerStrip.count > 0 && Settings.barWidgetDeco === "none" ? Theme.surfaceActive : "transparent"
            Behavior on color {
                CAnim {}
            }

            EditStrip {
                id: centerStrip
                anchors.centerIn: parent
                style: "islands"
                zone: "center"
                equalEnds: true
            }
        }

        // Left section — fixed sideWidth; a stretchable widget (weather)
        // absorbs the slack, like the original bar.
        Item {
            id: leftZone
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: topRow.sideWidth
            height: parent.height

            EditStrip {
                id: leftStrip
                // Width the content needs before any slack is handed out.
                readonly property real naturalWidthHint: leftStrip.naturalContentWidth > 0
                    ? leftStrip.naturalContentWidth : (BarEditState.active ? leftStrip.emptyWidth : 0)
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                style: "islands"
                zone: "left"
                fillSlack: true
                fillWidth: leftZone.width
            }
        }

        // Right section — same fixed width, content hugging the right edge.
        Item {
            id: rightZone
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: topRow.sideWidth
            height: parent.height

            EditStrip {
                id: rightStrip
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                style: "islands"
                zone: "right"
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

    // Bottom section — full width of the bar content. A lone widget (the
    // workspace strip) stretches across it; several widgets centre.
    Item {
        id: bottomRow
        visible: Settings.barStyle !== "pill" && (bottomStrip.count > 0 || BarEditState.active)
        width: topRow.width
        height: bottomStrip.height

        EditStrip {
            id: bottomStrip
            anchors.horizontalCenter: parent.horizontalCenter
            style: "islands"
            zone: "bottom"
            stretchSingle: true
            fillWidth: bottomRow.width
        }
    }
}
