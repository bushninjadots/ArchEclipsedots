import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.services
import qs.widgets.shared

// Pill bar face (Settings.barStyle === "pill") — a single morphing island.
//
// Rest face: workspace dots + clock + live chip (media-forward).
// Hover expands in place into a two-tier reveal: a core row
// (music/bandwidth . clock . control), a hairline divider, and a detail row
// beneath it (weather . resources . status). The outer ArchEclipse pill
// (Bar.qml) is the surface; this item is only the content face, so the pill
// grows in place.
//
// The two faces never share the screen: the rest face fades out over the
// first half of the transition and the expanded face fades in over the
// second, so an expansion can never overlap the content it replaces. The
// clocks opt out of their own date reveal for the same reason. Side islands,
// pulses and search keep using the untouched BarState machine.
//
// Both faces read the widget model (BarWidgets.layout) so the same widgets
// can be re-arranged per style from the Settings editor.
Item {
    id: root

    // Hover-driven expand. A short leave delay keeps the pill from folding
    // the instant the cursor skims its edge; an open popup pins it.
    property bool open: false
    readonly property bool expanded: open || BarState.popupCount > 0
    property real t: expanded ? 1 : 0

    Behavior on t {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    readonly property var restIds: BarWidgets.layout("pill", "rest")
    readonly property var coreIds: BarWidgets.layout("pill", "core")
    readonly property var detailIds: BarWidgets.layout("pill", "detail")

    // ---- edit-mode geometry (Task 7) ----
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
        _collectCells(restEditRep, root.restIds, "rest", out);
        _collectCells(coreEditRep, root.coreIds, "core", out);
        _collectCells(detailEditRep, root.detailIds, "detail", out);
        return out;
    }
    function editZones() {
        if (!BarEditState.active)
            return [];
        return [
            _zoneRect(restEditRow, "rest"),
            _zoneRect(coreEditRow, "core"),
            _zoneRect(detailEditRow, "detail")
        ];
    }

    // Rest face is the resting size; the expanded face grows to fit both
    // reveal rows stacked. In edit mode a dedicated stacked face is used.
    implicitWidth: (BarEditState.active ? editContent.implicitWidth : (expanded ? openContent.implicitWidth : restContent.implicitWidth)) + 28
    implicitHeight: (BarEditState.active ? editContent.implicitHeight : (expanded ? openContent.implicitHeight : restContent.implicitHeight)) + 10
    width: implicitWidth
    height: implicitHeight

    HoverHandler {
        id: pillHover
        onHoveredChanged: {
            if (hovered) {
                leaveTimer.stop();
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

    // ---- rest face: dots . clock . chip ----
    Row {
        id: restContent
        anchors.centerIn: parent
        spacing: 14
        visible: !BarEditState.active
        opacity: Math.max(0, 1 - root.t * 2)
        enabled: root.t < 0.5

        Repeater {
            model: root.restIds
            delegate: Loader {
                required property string modelData
                active: !BarEditState.active
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: BarWidgets.component(modelData, "pill", "rest")
            }
        }
    }

    // ---- expanded face: core row . divider . detail row ----
    Column {
        id: openContent
        anchors.centerIn: parent
        spacing: 10
        visible: !BarEditState.active
        opacity: Math.max(0, root.t * 2 - 1)
        scale: 0.98 + 0.02 * root.t
        enabled: root.t >= 0.5

        RowLayout {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 14

            Repeater {
                model: root.coreIds
                delegate: Loader {
                    required property string modelData
                    active: !BarEditState.active
                    Layout.alignment: Qt.AlignVCenter
                    sourceComponent: BarWidgets.component(modelData, "pill", "core")
                }
            }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 180
            height: 1
            color: Theme.border
            opacity: 0.6
        }

        RowLayout {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 14

            Repeater {
                model: root.detailIds
                delegate: Loader {
                    required property string modelData
                    active: !BarEditState.active
                    Layout.alignment: Qt.AlignVCenter
                    sourceComponent: BarWidgets.component(modelData, "pill", "detail")
                }
            }
        }
    }

    // ---- edit face: rest . core . detail stacked as drop targets ----
    Column {
        id: editContent
        visible: BarEditState.active
        anchors.centerIn: parent
        spacing: 10

        Row {
            id: restEditRow
            spacing: 14
            width: Math.max(childrenRect.width, 64)
            height: Math.max(childrenRect.height, Theme.barContentHeight)
            Repeater {
                id: restEditRep
                model: root.restIds
                delegate: Loader {
                    required property string modelData
                    active: BarEditState.active
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: BarWidgets.component(modelData, "pill", "rest")
                }
            }
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 180
            height: 1
            color: Theme.border
            opacity: 0.6
        }
        Row {
            id: coreEditRow
            spacing: 14
            width: Math.max(childrenRect.width, 64)
            height: Math.max(childrenRect.height, Theme.barContentHeight)
            Repeater {
                id: coreEditRep
                model: root.coreIds
                delegate: Loader {
                    required property string modelData
                    active: BarEditState.active
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: BarWidgets.component(modelData, "pill", "core")
                }
            }
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 180
            height: 1
            color: Theme.border
            opacity: 0.6
        }
        Row {
            id: detailEditRow
            spacing: 14
            width: Math.max(childrenRect.width, 64)
            height: Math.max(childrenRect.height, Theme.barContentHeight)
            Repeater {
                id: detailEditRep
                model: root.detailIds
                delegate: Loader {
                    required property string modelData
                    active: BarEditState.active
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: BarWidgets.component(modelData, "pill", "detail")
                }
            }
        }
    }
}
