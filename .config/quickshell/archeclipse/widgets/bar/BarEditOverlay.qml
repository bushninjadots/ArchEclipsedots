import QtQuick
import qs.theme
import qs.services
import qs.widgets.shared

// Full-window bar layout editor (z=1000 over the bar surface).
//
// It owns no widget tree: the faces (DefaultBar / PillBar / DetachedBar)
// publish their section rects and widget cells (editZones/editCells), and
// this layer turns pointer + keyboard input into BarEditState commands.
//
//   drag a widget            move it (live preview: neighbours slide, a ghost
//                            marks the landing slot, the frame follows)
//   drag onto the shelf      hide it          drag from the shelf   add it
//   click a widget           select + inspector (section, order, frame shape)
//   ← / →                    nudge (hops into the next section at the ends)
//   ↑ / ↓                    previous / next section
//   Delete                   hide             Esc   drop selection / cancel
//   drag a section label     move a detached section (snaps to centre/edges)
Item {
    id: root
    anchors.fill: parent
    visible: BarEditState.active
    z: 1000

    // The bar face whose editCells()/editZones() we read.
    property var source: null
    property var trayIds: []

    readonly property bool detached: Settings.barStyle === "islands" && Settings.barIslandsDetached
    // Outer extent of the attached bar's sections (bottom edge for a top bar,
    // top edge for a bottom bar), so labels can sit clear of the whole bar.
    readonly property real barExtent: {
        let m = 0;
        for (const z of BarEditState.dropZones)
            m = Math.max(m, z.y + z.h);
        return m;
    }
    readonly property real barStart: {
        let m = root.height;
        for (const z of BarEditState.dropZones)
            m = Math.min(m, z.y);
        return m;
    }

    // Fade the editor in instead of popping it.
    opacity: 0
    NumberAnimation {
        id: fadeIn
        target: root
        property: "opacity"
        from: 0
        to: 1
        duration: 180
        easing.type: Easing.OutCubic
    }

    // ---- geometry refresh ----
    function refresh() {
        if (!root.source || !root.source.editCells) {
            BarEditState.setCells([]);
            BarEditState.setDropZones([]);
            root.trayIds = [];
            return;
        }
        BarEditState.setCells(root.source.editCells());
        BarEditState.setDropZones(root.source.editZones());
        root.trayIds = BarEditState.unplacedIds();
        const sh = panels.shelf;
        const p = sh.mapToItem(root, 0, 0);
        BarEditState.trayRect = { x: p.x, y: p.y, w: sh.width, h: sh.height };
    }
    onVisibleChanged: {
        // Never carry a stale press into a new session.
        surface.pressCell = null;
        if (visible) {
            root.refresh();
            fadeIn.restart();
        }
    }
    Component.onCompleted: root.refresh()
    Timer {
        interval: 120
        repeat: true
        running: root.visible
        onTriggered: root.refresh()
    }

    // ---- real-widget drag proxy (grabbed once per drag) ----
    property string proxySource: ""
    property var _grabResult: null
    function _captureProxy(id) {
        root.proxySource = "";
        const item = root.source && root.source.cellItem ? root.source.cellItem(id) : null;
        if (!item || item.width <= 0 || item.height <= 0)
            return;
        root._grabResult = item.grabToImage(function (result) {
            if (BarEditState.draggingId === id)
                root.proxySource = result.url;
            root._grabResult = null;
        }, Qt.size(item.width, item.height));
    }
    Connections {
        target: BarEditState
        function onDraggingIdChanged() {
            if (BarEditState.draggingId !== "")
                root._captureProxy(BarEditState.draggingId);
            else
                root.proxySource = "";
        }
    }

    // ---- pointer ----
    readonly property string hoverId: {
        if (BarEditState.draggingId !== "")
            return "";
        const c = BarEditState.cellAt(surface.mouseX, surface.mouseY, 4);
        return c ? c.id : "";
    }

    MouseArea {
        id: surface
        anchors.fill: parent
        enabled: BarEditState.active
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: BarEditState.draggingId !== "" || BarEditState.dragSection !== "" ? Qt.ClosedHandCursor
            : root.hoverId !== "" ? Qt.OpenHandCursor : Qt.ArrowCursor

        property var pressCell: null
        property real pressX: 0
        property real pressY: 0

        onPressed: mouse => {
            keyGrabber.forceActiveFocus();
            const c = BarEditState.cellAt(mouse.x, mouse.y, 4);
            if (mouse.button === Qt.RightButton) {
                BarEditState.select(c ? c.id : "", c ? c.zone : "");
                return;
            }
            pressCell = c;
            pressX = mouse.x;
            pressY = mouse.y;
            if (!c)
                BarEditState.select("", "");
        }
        onPositionChanged: mouse => {
            if (BarEditState.draggingId !== "") {
                root.refresh();
                BarEditState.updateDrag(mouse.x, mouse.y);
            } else if (BarEditState.dragSection !== "") {
                BarEditState.moveSection(mouse.x, mouse.y, root.width, root.height);
            } else if (pressCell && pressed && (Math.abs(mouse.x - pressX) > 5 || Math.abs(mouse.y - pressY) > 5)) {
                BarEditState.startDrag(pressCell.id, pressCell.zone, mouse.x, mouse.y);
                pressCell = null;
            }
        }
        onCanceled: {
            pressCell = null;
            if (BarEditState.draggingId !== "")
                BarEditState.abortDrag();
            if (BarEditState.dragSection !== "")
                BarEditState.commitSection();
        }
        onReleased: mouse => {
            if (BarEditState.draggingId !== "") {
                BarEditState.updateDrag(mouse.x, mouse.y);
                BarEditState.finishDrag();
            } else if (BarEditState.dragSection !== "") {
                BarEditState.commitSection();
            } else if (pressCell) {
                // A click (no drag): toggle selection.
                const same = BarEditState.selectedId === pressCell.id && BarEditState.selectedZone === pressCell.zone;
                BarEditState.select(same ? "" : pressCell.id, same ? "" : pressCell.zone);
            }
            pressCell = null;
        }
    }

    // ---- keyboard ----
    // The bar is a layer surface with OnDemand focus, so a focused item (not
    // a Shortcut) receives keys while editing.
    Item {
        id: keyGrabber
        width: 1
        height: 1
        focus: BarEditState.active
        Keys.onPressed: event => {
            const id = BarEditState.selectedId, zone = BarEditState.selectedZone;
            if (event.key === Qt.Key_Escape) {
                if (BarEditState.draggingId !== "")
                    BarEditState.abortDrag();
                else if (id !== "")
                    BarEditState.select("", "");
                else
                    BarEditState.cancel();
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                BarEditState.end();
            } else if (id === "") {
                return;
            } else if (event.key === Qt.Key_Left) {
                BarEditState.nudge(id, zone, -1);
            } else if (event.key === Qt.Key_Right) {
                BarEditState.nudge(id, zone, 1);
            } else if (event.key === Qt.Key_Up) {
                BarEditState.hop(id, zone, -1);
            } else if (event.key === Qt.Key_Down) {
                BarEditState.hop(id, zone, 1);
            } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                BarEditState.hide(id, zone);
            } else {
                return;
            }
            event.accepted = true;
        }
    }

    // ---- section outlines + labels ----
    Repeater {
        model: BarEditState.dropZones
        delegate: Item {
            id: zoneItem
            required property var modelData
            readonly property bool isTarget: BarEditState.draggingId !== "" && BarEditState.targetZone === modelData.zone
            x: modelData.x
            y: modelData.y
            width: modelData.w
            height: modelData.h

            Rectangle {
                anchors.fill: parent
                anchors.margins: -5
                color: zoneItem.isTarget ? Theme.rgba(Theme.accent, 0.08) : "transparent"
                border.color: Theme.accent
                border.width: zoneItem.isTarget ? 2 : 1
                radius: Theme.radius + 4
                opacity: zoneItem.isTarget ? 1 : (BarEditState.draggingId !== "" ? 0.5 : 0.25)
                Behavior on opacity {
                    NumberAnimation { duration: 140 }
                }
            }

            // Label chip on the far side from the bar edge; in detached mode
            // it is also the grip that moves the whole section.
            Rectangle {
                id: chip
                // Pill sections are stacked rows: label beside each row.
                // Otherwise the label sits on the side away from the edge.
                // Attached islands: every label goes past the whole bar (top
                // row labels would otherwise land on the workspace row), the
                // bottom row's label at its start so none collide.
                readonly property bool beside: BarEditState.style === "pill"
                readonly property bool upper: zoneItem.y + zoneItem.height / 2 < root.height / 2
                readonly property bool stacked: !root.detached && BarEditState.style === "islands"
                // The bottom row's label takes a second lane under the others.
                readonly property real lane: chip.stacked && zoneItem.modelData.zone === "bottom" ? height + 6 : 0
                x: chip.beside ? -width - 14
                    : (chip.stacked && zoneItem.modelData.zone === "bottom") ? 0 : (parent.width - width) / 2
                y: chip.beside ? (parent.height - height) / 2
                    : chip.stacked ? (chip.upper ? root.barExtent - zoneItem.y + 9 + chip.lane : root.barStart - zoneItem.y - height - 9 - chip.lane)
                    : (chip.upper ? parent.height + 9 : -height - 9)
                width: chipText.implicitWidth + 14
                height: chipText.implicitHeight + 6
                radius: height / 2
                color: zoneItem.isTarget ? Theme.accent : Theme.rgba(Theme.background, 0.92)
                border.color: Theme.rgba(Theme.accent, zoneItem.isTarget ? 1 : 0.5)
                border.width: 1
                opacity: zoneItem.isTarget || root.detached ? 1 : 0.75
                scale: zoneItem.isTarget ? 1.08 : 1
                Behavior on scale {
                    NumberAnimation { duration: 160; easing.type: Easing.OutBack }
                }
                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: (root.detached ? "☰  " : "")
                        + BarWidgets.zoneLabel(BarEditState.style, zoneItem.modelData.zone).toUpperCase()
                    color: zoneItem.isTarget ? Theme.surface : Theme.accent
                    font.pixelSize: Math.max(Theme.fontSize - 3, 8)
                    font.letterSpacing: 0.8
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: root.detached
                    cursorShape: root.detached ? Qt.SizeAllCursor : Qt.ArrowCursor
                    onPressed: mouse => {
                        const p = mapToItem(root, mouse.x, mouse.y);
                        BarEditState.beginSectionDrag(zoneItem.modelData.zone, p.x, p.y, zoneItem.modelData);
                    }
                    onPositionChanged: mouse => {
                        const p = mapToItem(root, mouse.x, mouse.y);
                        BarEditState.moveSection(p.x, p.y, root.width, root.height);
                    }
                    onReleased: BarEditState.commitSection()
                    onDoubleClicked: BarEditState.resetSection(zoneItem.modelData.zone)
                }
            }
        }
    }

    // Snap guide while a detached section is being moved.
    Rectangle {
        visible: BarEditState.dragSection !== ""
            && Math.abs(BarEditState.dragSectionX - (root.width - BarEditState.dragSectionW) / 2) < 0.5
        x: root.width / 2
        width: 1
        height: root.height
        color: Theme.accent
        opacity: 0.6
    }

    // Hover glow on the widget under the pointer.
    Rectangle {
        readonly property var r: BarEditState.cellRect(root.hoverId)
        visible: root.hoverId !== "" && r !== null && root.hoverId !== BarEditState.selectedId
        x: r ? r.x - 4 : 0
        y: r ? r.y - 4 : 0
        width: r ? r.w + 8 : 0
        height: r ? r.h + 8 : 0
        radius: Theme.radius
        color: Theme.rgba(Theme.accent, 0.10)
        border.color: Theme.accent
        border.width: 1
    }

    BarEditPanels {
        id: panels
        anchors.fill: parent
        trayIds: root.trayIds
        proxySource: root.proxySource
    }
}
