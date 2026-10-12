import QtQuick
import Quickshell.Hyprland
import qs.theme
import qs.services

// Compact workspace switcher with three looks (Settings -> Bar -> Workspaces):
//   "dots"    — a dot per workspace, the focused one stretched into a capsule
//   "numbers" — numbered chips
//   "icons"   — the app living on each workspace (number when empty)
// It shows workspaces 1..N where N grows with use (at least `minCount`), a
// highlight slides to the focused one, a new window on another workspace
// pings its slot, and the wheel walks workspaces. A dot after the last slot
// lights while the special (scratchpad) workspace holds windows; click it to
// toggle the scratchpad.
Item {
    id: root

    property string mode: "dots"
    property int minCount: 5
    property int maxCount: 10

    readonly property int focusedId: Hyprland.focusedWorkspace?.id ?? 1
    // Window count per workspace id.
    readonly property var counts: {
        Hyprland.toplevels.values;
        const m = {};
        for (const t of Hyprland.toplevels.values) {
            const id = t.workspace?.id ?? -1;
            if (id >= 1)
                m[id] = (m[id] || 0) + 1;
        }
        return m;
    }
    readonly property var firstClass: {
        Hyprland.toplevels.values;
        const m = {};
        for (const t of Hyprland.toplevels.values) {
            const id = t.workspace?.id ?? -1;
            if (id >= 1 && m[id] === undefined)
                m[id] = t.wayland?.appId || t.lastIpcObject?.class || "";
        }
        return m;
    }
    readonly property int count: {
        let n = Math.max(root.minCount, root.focusedId);
        for (const k in root.counts)
            n = Math.max(n, Number(k));
        return Math.min(root.maxCount, n);
    }
    readonly property bool specialUsed: {
        Hyprland.toplevels.values;
        return Hyprland.toplevels.values.some(t => ((t.workspace?.name ?? "") + "").startsWith("special"));
    }
    readonly property bool specialOpen: ((Hyprland.focusedWorkspace?.name ?? "") + "").startsWith("special")

    // Slot geometry per mode.
    readonly property real slotW: root.mode === "dots" ? 7 : 20
    readonly property real focusW: root.mode === "dots" ? 20 : 20
    readonly property real gap: root.mode === "dots" ? 5 : 3
    function slotX(i) {
        // i is 0-based; slots before the focused one are plain width.
        let x = 0;
        for (let k = 0; k < i; k++)
            x += (k + 1 === root.focusedId ? root.focusW : root.slotW) + root.gap;
        return x;
    }

    implicitWidth: root.slotX(root.count) - root.gap + (root.specialUsed ? 12 : 0)
    implicitHeight: Theme.barContentHeight
    Behavior on implicitWidth {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    // Pings: workspace id -> true while its slot pulses after a new window.
    property var _prev: ({})
    property var pings: ({})
    onCountsChanged: {
        const np = Object.assign({}, root.pings);
        let hit = false;
        for (const k in root.counts) {
            if ((root.counts[k] || 0) > (root._prev[k] || 0) && Number(k) !== root.focusedId && Object.keys(root._prev).length > 0) {
                np[k] = true;
                hit = true;
            }
        }
        root._prev = Object.assign({}, root.counts);
        if (hit) {
            root.pings = np;
            pingClear.restart();
        }
    }
    Timer {
        id: pingClear
        interval: 1600
        onTriggered: root.pings = ({})
    }

    // Sliding focus highlight (numbers / icons).
    Rectangle {
        visible: root.mode !== "dots" && root.focusedId <= root.count
        x: root.slotX(root.focusedId - 1)
        anchors.verticalCenter: parent.verticalCenter
        width: root.focusW
        height: 20
        radius: 7
        color: Theme.accent
        Behavior on x {
            NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        }
    }

    Repeater {
        model: root.count
        delegate: Item {
            id: slot
            required property int index
            readonly property int ws: index + 1
            readonly property bool focused: root.focusedId === ws
            readonly property bool occupied: (root.counts[ws] || 0) > 0
            readonly property bool pinged: !!root.pings[ws]
            x: root.slotX(index)
            width: focused ? root.focusW : root.slotW
            height: root.height
            Behavior on x {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
            Behavior on width {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            // ---- dots ----
            Rectangle {
                visible: root.mode === "dots"
                anchors.centerIn: parent
                width: parent.width
                height: slot.focused ? 7 : (slotMouse.containsMouse ? 7 : 6)
                radius: height / 2
                color: slot.focused || slot.pinged ? Theme.accent : slot.occupied ? Theme.fg : Theme.rgba(Theme.foreground, 0.25)
                Behavior on color {
                    ColorAnimation { duration: 200 }
                }
            }

            // ---- numbers / icons ----
            Text {
                visible: root.mode !== "dots"
                anchors.centerIn: parent
                readonly property string glyph: root.mode === "icons" && slot.occupied
                    ? WorkspaceIcons.forClientClass(root.firstClass[slot.ws] ?? "") : ""
                text: glyph !== "" ? glyph : String(slot.ws)
                color: slot.focused ? Theme.background : slot.pinged ? Theme.accent : slot.occupied ? Theme.fg : Theme.muted
                opacity: slot.focused || slot.occupied || slot.pinged ? 1 : 0.55
                font.family: Theme.fontFamily
                font.pixelSize: glyph !== "" ? Theme.fontSize + 1 : Theme.fontSizeSmall
                font.bold: slot.focused
                Behavior on color {
                    ColorAnimation { duration: 200 }
                }
            }
            // Occupied marker under an unfocused number.
            Rectangle {
                visible: root.mode === "numbers" && slot.occupied && !slot.focused
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -1
                width: 4
                height: 2
                radius: 1
                color: Theme.fg
                opacity: 0.6
            }
            // Ping: a ring that blooms out of a slot when a window lands.
            Rectangle {
                id: ring
                anchors.centerIn: parent
                width: 18
                height: 18
                radius: 9
                color: "transparent"
                border.width: 1.5
                border.color: Theme.accent
                opacity: 0
                scale: 0.5
                ParallelAnimation {
                    running: slot.pinged
                    loops: 2
                    NumberAnimation { target: ring; property: "opacity"; from: 0.9; to: 0; duration: 700 }
                    NumberAnimation { target: ring; property: "scale"; from: 0.5; to: 1.4; duration: 700; easing.type: Easing.OutCubic }
                }
            }

            MouseArea {
                id: slotMouse
                anchors.fill: parent
                anchors.margins: -2
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + slot.ws + " })")
            }
        }
    }

    // Scratchpad marker.
    Rectangle {
        visible: root.specialUsed
        x: root.slotX(root.count) + 2
        anchors.verticalCenter: parent.verticalCenter
        width: 6
        height: 6
        radius: 3
        color: "transparent"
        border.width: 1.5
        border.color: Theme.accent
        opacity: root.specialOpen ? 1 : 0.6
        MouseArea {
            anchors.fill: parent
            anchors.margins: -5
            cursorShape: Qt.PointingHandCursor
            onClicked: Hyprland.dispatch("hl.dsp.workspace.toggle_special()")
        }
    }

    // Preview strip (after iNiR's workspace edge strip): live thumbnails of
    // these workspaces in an island at the switcher — right-click, or hover
    // a moment with Settings.barHoverReveal. Click a card to go there, drag
    // a window onto another card to move it.
    function openStrip() {
        BarState.overviewStripCount = root.count;
        BarState.overviewStrip = true;
        BarState.activate("overview", 0);
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: {
            if (BarState.state === "overview")
                BarState.deactivate("overview");
            else
                root.openStrip();
        }
    }
    HoverHandler {
        id: stripHover
        onHoveredChanged: {
            if (stripHover.hovered && Settings.barHoverReveal)
                stripDwell.restart();
            else
                stripDwell.stop();
        }
    }
    Timer {
        id: stripDwell
        interval: 650
        onTriggered: if (stripHover.hovered && BarState.state !== "overview") root.openStrip()
    }

    // Wheel walks workspaces.
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + (event.angleDelta.y > 0 ? "e-1" : "e+1") + "\" })")
    }
}
