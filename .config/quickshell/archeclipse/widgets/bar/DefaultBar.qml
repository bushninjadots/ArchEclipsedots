import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.theme
import qs.services
import qs.widgets.bar.pill

// Islands bar face (Settings.barStyle !== "pill").
//
// The visual chrome is unchanged: a coloured centre pill (bandwidth |
// control | clock), fixed-width left/right zones so the pill keeps symmetric
// clearance, and a full-width workspace strip at the bottom. What changed is
// that each zone's membership and order now come from the BarWidgets registry
// (Settings.barLayoutIslands) instead of being hard-coded.
Column {
    id: root
    spacing: 4

    // ---- edit-mode geometry (Task 7) ----
    // The overlay walks our live Loaders and maps them into window (scene)
    // coordinates so it can hit-test drags without owning the widget tree.
    function _collectCells(rep, ids, zone, out) {
        for (let i = 0; i < rep.count; i++) {
            const d = rep.itemAt(i);
            if (!d)
                continue;
            // The delegate may be a plain Loader (left/right/bottom) or an
            // Item wrapper whose child is a Loader (center's equal-width
            // cells). Resolve to that Loader and use the delegate's geometry.
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
    function _zoneRect(item, zone) {
        const p = item.mapToItem(null, 0, 0);
        return { zone: zone, x: p.x, y: p.y, w: item.width, h: item.height };
    }
    function editCells() {
        if (Settings.barStyle === "pill")
            return pillLoader.item && pillLoader.item.editCells ? pillLoader.item.editCells() : [];
        const out = [];
        _collectCells(centerRep, root.centerIds, "center", out);
        _collectCells(leftRep, root.leftIds, "left", out);
        _collectCells(rightRep, root.rightIds, "right", out);
        _collectCells(bottomRep, root.bottomIds, "bottom", out);
        return out;
    }
    function editZones() {
        if (Settings.barStyle === "pill")
            return pillLoader.item && pillLoader.item.editZones ? pillLoader.item.editZones() : [];
        return [
            _zoneRect(leftZone, "left"),
            _zoneRect(centerPill, "center"),
            _zoneRect(rightZone, "right"),
            _zoneRect(bottomRow, "bottom")
        ];
    }

    readonly property var leftIds: BarWidgets.layout("islands", "left")
    readonly property var centerIds: BarWidgets.layout("islands", "center")
    readonly property var rightIds: BarWidgets.layout("islands", "right")
    readonly property var bottomIds: BarWidgets.layout("islands", "bottom")

    Item {
        id: topRow
        visible: Settings.barStyle !== "pill"
        // Both side sections count as wide as the wider one, so the centered
        // pill always keeps at least Theme.spacing clearance from either side
        // instead of clipping into the wider section. The weather button
        // stretches to absorb any slack on the left.
        readonly property real leftMinWidth: leftRow.implicitWidth
        readonly property real rightMinWidth: utilities.implicitWidth
        readonly property real sideWidth: Math.max(leftMinWidth, rightMinWidth)
        implicitWidth: 2 * sideWidth + centerPill.width + Theme.spacing * 2
        width: implicitWidth
        height: Theme.barContentHeight

        // Center rectangle — bandwidth on the left, control panel button
        // dead-center, clock on the right. The model drives the children; the
        // two end cells are equalised so the control button stays dead-center
        // relative to the whole bar even when the end widgets differ in width.
        Rectangle {
            id: centerPill
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: centerRow.implicitWidth + 20
            height: Theme.barContentHeight
            radius: Theme.radius
            color: Theme.surfaceActive

            Row {
                id: centerRow
                anchors.centerIn: parent
                spacing: Theme.spacing
                height: parent.height
                // Equal-width side cells so the control button stays dead-
                // center relative to the whole bar even when the end widgets
                // (bandwidth, clock) differ in width. Each delegate is an Item
                // wrapper that keeps its widget at its natural size and pads
                // the two end cells out to the shared width — a bare Loader
                // with an explicit width would instead stretch (or zero) the
                // widget, which breaks widgets that only declare `width`.
                readonly property real sideCellWidth: {
                    const n = root.centerIds.length;
                    if (n < 2)
                        return 0;
                    const f = centerRep.itemAt(0);
                    const l = centerRep.itemAt(n - 1);
                    return Math.max(f ? f.naturalWidth : 0, l ? l.naturalWidth : 0);
                }

                Repeater {
                    id: centerRep
                    model: root.centerIds
                    delegate: Item {
                        id: cell
                        required property int index
                        required property string modelData

                        readonly property bool isEnd: root.centerIds.length >= 2
                            && (index === 0 || index === root.centerIds.length - 1)
                        // The Loader auto-sizes to the widget's natural size
                        // (its `width` when the widget declares no
                        // `implicitWidth`).
                        readonly property real naturalWidth: widget.implicitWidth
                        width: isEnd ? centerRow.sideCellWidth : naturalWidth
                        height: parent.height

                        Loader {
                            id: widget
                            anchors.centerIn: parent
                            sourceComponent: BarWidgets.component(cell.modelData, "islands", "center")
                        }
                    }
                }
            }
        }

        // left zone — fixed sideWidth; children stretch into the slack
        Item {
            id: leftZone
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: topRow.sideWidth
            height: parent.height

            RowLayout {
                id: leftRow
                anchors.fill: parent
                spacing: Theme.spacing

                Repeater {
                    id: leftRep
                    model: root.leftIds
                    delegate: Loader {
                        required property string modelData
                        sourceComponent: BarWidgets.component(modelData, "islands", "left")
                        Layout.fillWidth: true
                    }
                }
            }
        }

        // right zone — fixed sideWidth like the left, content right-aligned so
        // the center pill keeps symmetric spacing on both sides
        Item {
            id: rightZone
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: topRow.sideWidth
            height: parent.height

            Row {
                id: utilities
                spacing: Theme.spacing
                height: parent.height
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                Repeater {
                    id: rightRep
                    model: root.rightIds
                    delegate: Loader {
                        required property string modelData
                        sourceComponent: BarWidgets.component(modelData, "islands", "right")
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    } // topRow

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

    // bottom zone — full width of the bar content
    Row {
        id: bottomRow
        visible: Settings.barStyle !== "pill"
        width: topRow.implicitWidth
        spacing: Theme.spacing

        Repeater {
            id: bottomRep
            model: root.bottomIds
            delegate: Loader {
                required property string modelData
                sourceComponent: BarWidgets.component(modelData, "islands", "bottom")
                width: bottomRow.width
            }
        }
    }
}
