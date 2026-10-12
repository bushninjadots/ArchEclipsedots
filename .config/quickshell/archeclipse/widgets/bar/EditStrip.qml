import QtQuick
import qs.theme
import qs.services
import qs.widgets.shared

// One bar SECTION rendered as an animated horizontal row of widgets.
//
// It renders BarEditState.ids(style, zone) — the committed layout, or the
// live drag preview — and reconciles an internal ListModel with it, so a
// reorder is a ListModel.move() and neighbours slide aside instead of the row
// being rebuilt. Delegates are placed by explicit x (sum of the preceding
// widths) with a Behavior, so moves animate and nothing is ever culled or
// scrolled out of place (a ListView did both). In edit mode each widget gets
// a lift, an outline, a ring when selected, and the dragged widget renders as
// a faded ghost at its
// landing slot. An empty section shows a "drop here" slot while editing so it
// stays a drop target.
//
// Non-interactive: BarEditOverlay owns every gesture; this item only renders
// and publishes geometry (cells()/zoneRect()).
Item {
    id: root

    property string style: "islands"
    property string zone: ""
    // Gap between neighbours (px).
    property int spacing: Theme.spacing
    // Give the first and last widget the same width so the middle one stays
    // dead-centre (the original islands centre capsule).
    property bool equalEnds: false
    // When the strip is given a width wider than its content, hand the slack
    // to the last stretchable widget (BarWidgets.stretches), else to none.
    property bool fillSlack: false
    // Stretch every widget to the strip width (single full-width widgets such
    // as the bottom workspace strip).
    property bool stretchSingle: false
    // Width the parent wants the row to fill (0 = hug content).
    property real fillWidth: 0
    // How the section is anchored ("left" | "center" | "right"): which
    // neighbours a ghost displaces, for stable drop-index hit tests.
    property string align: "left"
    // Width of the empty-section drop slot in edit mode.
    property int emptyWidth: 72

    readonly property var ids: BarEditState.ids(root.style, root.zone)
    readonly property bool editing: BarEditState.active && BarEditState.style === root.style
    readonly property bool empty: rep.count === 0

    // ---- per-delegate natural widths (for equalEnds / slack) ----
    property var _naturals: ({})
    function _setNatural(id, w) {
        if (root._naturals[id] === w)
            return;
        const n = Object.assign({}, root._naturals);
        n[id] = w;
        root._naturals = n;
    }
    // Natural width of a widget's cell: its own width plus its pill padding.
    function _nat(id) {
        return (root._naturals[id] || 0) + 2 * root.padOf(id);
    }
    readonly property real naturalContentWidth: {
        let sum = 0, shown = 0;
        const ids = root.ids;
        for (let i = 0; i < ids.length; i++) {
            const w = root._nat(ids[i]);
            if (w > 0) {
                sum += w;
                shown++;
            }
        }
        return sum + Math.max(0, shown - 1) * root.spacing;
    }
    readonly property real endWidth: {
        const ids = root.ids;
        // Only a row with a true middle needs balancing; two widgets would
        // just get a lopsided gap between them.
        if (!root.equalEnds || ids.length < 3)
            return 0;
        return Math.max(root._nat(ids[0]), root._nat(ids[ids.length - 1]));
    }
    readonly property string slackId: {
        if (!root.fillSlack)
            return "";
        const ids = root.ids;
        for (let i = ids.length - 1; i >= 0; i--) {
            if (BarWidgets.stretches(ids[i]))
                return ids[i];
        }
        return "";
    }
    readonly property real slack: {
        if (root.slackId === "" || root.fillWidth <= 0)
            return 0;
        let used = root.naturalContentWidth;
        if (root.endWidth > 0) {
            const ids = root.ids;
            used += 2 * root.endWidth - root._nat(ids[0]) - root._nat(ids[ids.length - 1]);
        }
        return Math.max(0, root.fillWidth - used);
    }

    // Horizontal padding a widget's decoration pill adds on each side.
    readonly property int decoPad: 7
    function padOf(id) {
        return BarEditState.frameFor(id).deco !== "none" && (root._naturals[id] || 0) > 0 ? root.decoPad : 0;
    }

    function cellWidth(id, index, natural) {
        // A widget that is currently hidden still needs a grab handle while
        // editing (a dimmed icon placeholder).
        if (natural <= 0)
            return root.editing ? root.placeholderWidth : 0;
        return root._bareWidth(id, index, natural + 2 * root.padOf(id));
    }
    readonly property int placeholderWidth: 30
    function _bareWidth(id, index, natural) {
        if (root.stretchSingle && root.fillWidth > 0 && root.ids.length === 1
                && BarWidgets.minWidth(id, root.style) > 0)
            return root.fillWidth;
        let w = natural;
        if (root.endWidth > 0 && (index === 0 || index === root.ids.length - 1))
            w = Math.max(w, root.endWidth);
        if (id === root.slackId)
            w += root.slack;
        return w;
    }

    // Left edge of slot `index` and the full row width, from the same widths
    // the delegates use.
    function xOf(index) {
        const ids = root.ids;
        let x = 0;
        for (let i = 0; i < index && i < ids.length; i++) {
            const w = root.cellWidth(ids[i], i, root._naturals[ids[i]] || 0);
            // Hidden (zero-width) widgets take no gap either.
            if (w > 0)
                x += w + root.spacing;
        }
        return x;
    }
    readonly property real contentWidth: {
        const x = root.xOf(root.ids.length);
        return x > 0 ? x - root.spacing : 0;
    }

    // Tallest delegate (never below the bar content height).
    property real _maxH: 0
    readonly property real contentHeight: Math.max(Theme.barContentHeight, root._maxH)
    function _updateH() {
        let h = 0;
        for (let i = 0; i < rep.count; i++) {
            const d = rep.itemAt(i);
            if (d)
                h = Math.max(h, d.implicitHeight);
        }
        root._maxH = h;
    }

    implicitWidth: root.empty ? (root.editing ? root.emptyWidth : 0) : root.contentWidth
    implicitHeight: root.contentHeight
    width: implicitWidth
    height: implicitHeight

    // ---- model <-> ids reconciliation ----
    function syncIds() {
        const next = Array.isArray(root.ids) ? root.ids : [];
        for (let i = model.count - 1; i >= 0; i--) {
            if (next.indexOf(model.get(i).wid) === -1)
                model.remove(i);
        }
        for (let i = 0; i < next.length; i++) {
            let cur = -1;
            for (let j = 0; j < model.count; j++) {
                if (model.get(j).wid === next[i]) {
                    cur = j;
                    break;
                }
            }
            if (cur === -1)
                model.insert(i, { wid: next[i] });
            else if (cur !== i)
                model.move(cur, i, 1);
        }
    }
    onIdsChanged: syncIds()
    Component.onCompleted: syncIds()

    ListModel {
        id: model
    }

    // Empty-section drop slot (edit mode only).
    Rectangle {
        anchors.fill: parent
        visible: root.empty && root.editing
        radius: Theme.radius
        color: BarEditState.draggingId !== "" && BarEditState.targetZone === root.zone
            ? Theme.rgba(Theme.accent, 0.18) : "transparent"
        border.color: Theme.accent
        border.width: 1
        opacity: 0.7
        Text {
            anchors.centerIn: parent
            text: "+"
            color: Theme.accent
            font.pixelSize: Theme.fontSize + 2
        }
    }

    Repeater {
        id: rep
        model: model

        delegate: Item {
            id: cell
            required property string wid
            required property int index

            readonly property bool ghost: BarEditState.draggingId === cell.wid
                && BarEditState.style === root.style
            readonly property bool selected: root.editing && BarEditState.selectedId === cell.wid
                && BarEditState.selectedZone === root.zone
            // The row only forces a width on widgets with no size of their own
            // (the islands workspace strip). Everything else keeps its natural
            // size; slack/equal-end padding widens the CELL, not the widget
            // (a forced width would feed back into widgets whose implicit
            // width depends on their width, e.g. the weather button).
            // A widget that hides itself (no player, no title, empty tray…)
            // takes no room and gets no pill.
            readonly property bool shown: !!inner.item && inner.item.visible !== false
            readonly property real _iw: cell.shown ? (inner.item.implicitWidth || 0) : 0
            readonly property bool forceWidth: cell.parentSized
            // Widgets with no size of their own (they fill their parent): the
            // islands workspace strip. Only these stretch across a lone row.
            readonly property bool parentSized: cell._iw <= 0 && BarWidgets.minWidth(cell.wid, root.style) > 0
            // Natural width: implicit size, else the widget's own width (when
            // the row is not forcing it), else its catalog minimum.
            readonly property real natural: {
                if (cell._iw > 0)
                    return cell._iw;
                if (cell.parentSized)
                    return BarWidgets.minWidth(cell.wid, root.style);
                return cell.shown ? inner.item.width : 0;
            }
            onNaturalChanged: root._setNatural(cell.wid, cell.natural)

            readonly property real targetWidth: root.cellWidth(cell.wid, cell.index, cell.natural)
            readonly property var look: BarEditState.frameFor(cell.wid)
            // Where the widget sits inside a cell wider than itself: the
            // slack widget hugs its start; balanced end cells push their
            // widget toward the middle so every gap between pills stays the
            // row spacing (the padding goes to the row's outer edges).
            readonly property string place: cell.wid === root.slackId ? "left"
                : root.endWidth > 0 && cell.index === 0 ? "right"
                : root.endWidth > 0 && cell.index === root.ids.length - 1 ? "left" : "center"
            function alignX(w, pad) {
                if (cell.place === "left")
                    return pad;
                if (cell.place === "right")
                    return cell.width - w - pad;
                return (cell.width - w) / 2;
            }
            implicitWidth: cell.targetWidth
            implicitHeight: inner.item ? Math.max(inner.item.implicitHeight || 0, inner.item.height || 0) : Theme.barContentHeight
            width: implicitWidth
            height: implicitHeight
            x: root.xOf(cell.index)
            y: (root.contentHeight - height) / 2
            onImplicitHeightChanged: root._updateH()
            // Slide on reorder, but not on first placement.
            property bool _placed: false
            Component.onCompleted: {
                root._setNatural(cell.wid, cell.natural);
                root._updateH();
                _placed = true;
            }
            Behavior on x {
                enabled: cell._placed
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
            opacity: cell.ghost ? 0.35 : 1
            scale: root.editing && !cell.ghost ? 1.04 : 1.0
            Behavior on scale {
                Anim { type: Anim.DefaultEffects }
            }
            Behavior on opacity {
                Anim { type: Anim.FastEffects }
            }

            // ---- shared action feel (normal mode) ----
            // Passive handlers: they observe the pointer without grabbing it,
            // so every widget keeps its own clicks while all of them answer
            // the same way — a soft glow on hover, a springy dip on press.
            HoverHandler {
                id: hover
                enabled: !root.editing
            }
            PointHandler {
                id: press
                enabled: !root.editing
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            }
            readonly property real pressScale: press.active ? 0.93 : 1
            Rectangle {
                // Hover glow, only for widgets without their own pill.
                x: cell.alignX(width, -6)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, (inner.width || 0) + 12)
                height: Math.max(cell.height + 4, Theme.barContentHeight + 2)
                radius: Math.min(Theme.radius, height / 2)
                visible: cell.natural > 0 && cell.look.deco === "none" && !cell.parentSized
                    && !BarWidgets.selfHover(cell.wid)
                color: Theme.rgba(Theme.foreground, 0.07)
                opacity: hover.hovered ? 1 : 0
                scale: cell.pressScale
                Behavior on opacity {
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 2 }
                }
            }

            // Edit-mode stand-in for a widget that is hidden right now.
            Text {
                anchors.centerIn: parent
                visible: root.editing && cell.natural <= 0
                text: BarWidgets.icon(cell.wid)
                color: Theme.muted
                opacity: 0.7
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 1
            }
            // Decoration pill behind the widget (Settings -> Bar -> Widgets, or
            // the editor inspector per widget).
            Rectangle {
                visible: cell.look.deco !== "none" && !cell.parentSized && cell.natural > 0
                anchors.verticalCenter: parent.verticalCenter
                x: cell.alignX(width, 0)
                width: (inner.width || 0) + root.decoPad * 2
                // A little air above and below the content.
                height: Math.max((inner.height || 0) + 4, Theme.barContentHeight + 4)
                radius: cell.look.radius >= 0 ? cell.look.radius : height / 2
                color: cell.look.deco === "filled"
                    ? (hover.hovered ? Theme.rgba(Theme.accent, 0.22) : Theme.surfaceActive)
                    : (hover.hovered ? Theme.rgba(Theme.accent, 0.10) : "transparent")
                scale: cell.pressScale
                Behavior on scale {
                    NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 2 }
                }
                Behavior on color {
                    CAnim {}
                }
                border.width: Settings.barWidgetBorder
                border.color: hover.hovered ? Theme.accent
                    : cell.look.deco === "filled" ? Theme.border : Theme.rgba(Theme.accent, 0.6)
                opacity: cell.look.opacity
                Behavior on opacity {
                    Anim { type: Anim.FastEffects }
                }
            }
            Loader {
                id: inner
                opacity: cell.look.opacity
                scale: cell.pressScale
                Behavior on scale {
                    NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 2 }
                }
                Behavior on opacity {
                    Anim { type: Anim.FastEffects }
                }
                // Placed by cell.place (see alignX).
                anchors.verticalCenter: parent.verticalCenter
                x: cell.alignX(width, root.padOf(cell.wid))
                width: cell.forceWidth ? cell.targetWidth : undefined
                sourceComponent: BarWidgets.component(cell.wid, root.style, root.zone)
            }

            // Edit chrome: hairline outline, solid ring when selected, dashed
            // look (accent fill) on the ghost landing slot.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -3
                visible: root.editing
                color: cell.ghost ? Theme.rgba(Theme.accent, 0.22) : "transparent"
                border.color: Theme.accent
                border.width: cell.selected ? 2 : 1
                radius: Theme.radius
                opacity: cell.selected || cell.ghost ? 1 : 0.35
            }
        }

        onItemRemoved: Qt.callLater(root._updateH)
    }

    // ---- edit geometry (scene coords) ----
    readonly property int count: rep.count

    // Rendered widget item for a placed id (drag-proxy grabs), or null.
    function cellItem(id) {
        for (let i = 0; i < rep.count; i++) {
            const d = rep.itemAt(i);
            if (d && d.wid === id) {
                for (const k of d.children) {
                    if (k && k.item !== undefined)
                        return k.item;
                }
                return null;
            }
        }
        return null;
    }

    // Published cells: [{ id, zone, x, y, w, h }] in row order.
    function cells(out) {
        const res = out || [];
        for (let i = 0; i < rep.count; i++) {
            const d = rep.itemAt(i);
            if (!d || d.width <= 0)
                continue;
            const p = d.mapToItem(null, 0, 0);
            // tx = the slot's settled x (the rendered x may still be sliding),
            // used for drop-index hit tests so they never chase an animation.
            const o = root.mapToItem(null, 0, 0);
            res.push({ id: d.wid, zone: root.zone, x: p.x, y: p.y, w: d.width, h: d.height, tx: o.x + root.xOf(i) });
        }
        return res;
    }

    // Section rect for drop hit-testing (`over` = an outer item to report
    // instead, e.g. the whole centre capsule or a fixed-width side zone).
    function zoneRect(over) {
        const it = over || root;
        const p = it.mapToItem(null, 0, 0);
        return { zone: root.zone, x: p.x, y: p.y, w: Math.max(it.width, 24), h: Math.max(it.height, Theme.barContentHeight), spacing: root.spacing, align: root.align };
    }
}
