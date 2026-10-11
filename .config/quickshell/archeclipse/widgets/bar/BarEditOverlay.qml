import QtQuick
import qs.theme
import qs.services

// Full-window edit surface (Task 7). While BarEditState.active it draws a
// dashed outline per drop zone, a tray of the widgets not placed in the
// current style, and a floating proxy for live drags. It owns no widget tree:
// it reads geometry published by DefaultBar/PillBar (editCells/editZones) and
// commits drops through BarEditState.place/remove.
Item {
    id: root
    anchors.fill: parent
    visible: BarEditState.active
    z: 1000

    // The bar content item (DefaultBar) whose editCells()/editZones() we read.
    property var source: null
    property var trayIds: []

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
    }
    onVisibleChanged: if (visible) root.refresh()
    Component.onCompleted: root.refresh()
    Timer {
        interval: 150
        repeat: true
        running: root.visible
        onTriggered: root.refresh()
    }

    // ---- dashed zone outlines ----
    Repeater {
        model: BarEditState.dropZones
        delegate: Item {
            required property var modelData
            x: modelData.x
            y: modelData.y
            width: modelData.w
            height: modelData.h

            Rectangle {
                anchors.fill: parent
                anchors.margins: -4
                color: "transparent"
                border.color: Theme.accent
                border.width: 1
                radius: Theme.radius
                opacity: 0.9
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: -22
                width: zoneLabel.implicitWidth + 12
                height: zoneLabel.implicitHeight + 4
                radius: 6
                color: Theme.surfaceActive
                Text {
                    id: zoneLabel
                    anchors.centerIn: parent
                    text: modelData.zone
                    color: Theme.accent
                    font.pixelSize: Math.max(Theme.fontSize - 2, 9)
                }
            }
        }
    }

    // ---- drag surface: a press on a placed widget starts a move ----
    MouseArea {
        id: surface
        anchors.fill: parent
        enabled: BarEditState.active
        onPressed: {
            const cell = BarEditState.cellAt(mouse.x, mouse.y);
            if (cell) {
                BarEditState.draggingId = cell.id;
                BarEditState.dragFromZone = cell.zone;
                BarEditState.dragX = mouse.x;
                BarEditState.dragY = mouse.y;
                return;
            }
            // Detached islands: pressing a pill's background moves the whole pill.
            if (Settings.barIslandsDetached && BarEditState.style === "islands") {
                const z = BarEditState.zoneRectAt(mouse.x, mouse.y);
                if (z)
                    BarEditState.beginSectionDrag(z.zone, mouse.x, mouse.y, z);
            }
        }
        onPositionChanged: {
            if (BarEditState.draggingId) {
                BarEditState.dragX = mouse.x;
                BarEditState.dragY = mouse.y;
            } else if (BarEditState.dragSection !== "") {
                BarEditState.moveSection(mouse.x, mouse.y, root.width, root.height);
            }
        }
        onReleased: {
            if (BarEditState.draggingId)
                BarEditState.dropAt(mouse.x, mouse.y);
            else if (BarEditState.dragSection !== "")
                BarEditState.commitSection();
        }
    }

    // ---- tray: widgets allowed by the registry but placed nowhere ----
    Rectangle {
        id: tray
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height - height - 16
        width: Math.min(trayRow.implicitWidth + 24, root.width - 40)
        height: Theme.barContentHeight + 20
        radius: Theme.radius
        color: Theme.surface
        border.color: Theme.border
        border.width: 1

        Row {
            id: trayRow
            anchors.centerIn: parent
            spacing: 8
            Repeater {
                model: root.trayIds
                delegate: Rectangle {
                    id: chip
                    required property string modelData
                    width: chipLabel.implicitWidth + 18
                    height: Theme.barContentHeight
                    radius: height / 2
                    color: chipMouse.containsMouse ? Theme.surfaceHover : Theme.surfaceActive
                    border.color: Theme.border
                    border.width: 1
                    Text {
                        id: chipLabel
                        anchors.centerIn: parent
                        text: BarWidgets.icon(chip.modelData) + "  " + BarWidgets.label(chip.modelData)
                        color: Theme.fg
                        font.pixelSize: Theme.fontSize
                    }
                    MouseArea {
                        id: chipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: {
                            BarEditState.draggingId = chip.modelData;
                            BarEditState.dragFromZone = "";
                            const p = root.mapFromItem(chip, mouse.x, mouse.y);
                            BarEditState.dragX = p.x;
                            BarEditState.dragY = p.y;
                        }
                        onPositionChanged: {
                            const p = root.mapFromItem(chip, mouse.x, mouse.y);
                            BarEditState.dragX = p.x;
                            BarEditState.dragY = p.y;
                        }
                        onReleased: {
                            const p = root.mapFromItem(chip, mouse.x, mouse.y);
                            BarEditState.dropAt(p.x, p.y);
                        }
                    }
                }
            }
        }
    }

    // ---- floating proxy ----
    Rectangle {
        visible: BarEditState.draggingId !== ""
        x: BarEditState.dragX - width / 2
        y: BarEditState.dragY - height / 2
        width: proxyLabel.implicitWidth + 20
        height: Theme.barContentHeight
        radius: height / 2
        color: Theme.accent
        Text {
            id: proxyLabel
            anchors.centerIn: parent
            text: BarWidgets.icon(BarEditState.draggingId) + "  " + BarWidgets.label(BarEditState.draggingId)
            color: Theme.surface
            font.pixelSize: Theme.fontSize
        }
    }

    // ---- Done ----
    Rectangle {
        id: doneBtn
        anchors.horizontalCenter: parent.horizontalCenter
        y: 16
        width: doneLabel.implicitWidth + 24
        height: Theme.barContentHeight
        radius: height / 2
        color: doneMouse.containsMouse ? Theme.surfaceHover : Theme.surfaceActive
        border.color: Theme.accent
        border.width: 1
        Text {
            id: doneLabel
            anchors.centerIn: parent
            text: "Done"
            color: Theme.accent
            font.pixelSize: Theme.fontSize
        }
        MouseArea {
            id: doneMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: BarEditState.end()
        }
    }
}
