import QtQuick
import qs.theme
import qs.services
import qs.widgets.shared

// The layout editor's sheet: ONE docked card under the bar (above it for a
// bottom bar) holding everything —
//   toolbar   style switch · attach/detach · undo · original · cancel · done
//   library   every widget: placed ones show where they live (click selects
//             it on the bar), hidden ones can be dragged on or clicked to add
//   inspector the selected widget: section, order, frame fit, pill, opacity
// The whole sheet is also the "drop here to hide" target while dragging.
Item {
    id: root

    property var trayIds: []
    property string proxySource: ""
    // BarEditOverlay reads this rect as the hide target.
    property alias shelf: sheet

    readonly property bool topBar: Settings.barOrientation
    readonly property bool dragging: BarEditState.draggingId !== ""
    readonly property string sel: BarEditState.selectedId
    readonly property var look: BarEditState.frameFor(root.sel)

    // Clear of the bar's sections and their labels.
    readonly property real barReach: {
        let reach = 0;
        for (const z of BarEditState.dropZones) {
            if (root.topBar && z.y < root.height / 2)
                reach = Math.max(reach, z.y + z.h);
            else if (!root.topBar && z.y > root.height / 2)
                reach = Math.max(reach, root.height - z.y);
        }
        return reach + 40;
    }

    readonly property color panelColor: Theme.rgba(Theme.background, 0.97)

    // Sheet page: "widgets" (library + inspector) or "look" (bar-wide looks).
    readonly property string page: BarEditState.page
    readonly property bool framed: Settings.shellFrame
    readonly property var onOff: [{ value: true, label: "On" }, { value: false, label: "Off" }]
    readonly property var wsOptions: [{ value: "strip", label: "Strip", tip: "Full-width bars" },
                                      { value: "dots", label: "Dots" },
                                      { value: "numbers", label: "Numbers" },
                                      { value: "icons", label: "Apps", tip: "The app on each workspace" }]

    // ---------------------------------------------------------------- parts
    component Chip: Rectangle {
        id: chip
        property string text: ""
        property bool active: false
        property bool primary: false
        property bool danger: false
        property string tip: ""
        property bool compact: false
        signal clicked
        implicitWidth: chipText.implicitWidth + (chip.compact ? 16 : 24)
        implicitHeight: 28
        radius: height / 2
        color: chip.active ? Theme.rgba(Theme.accent, chipMouse.containsMouse ? 0.32 : 0.22)
            : chipMouse.containsMouse ? Theme.surfaceHover : Theme.rgba(Theme.foreground, 0.05)
        border.color: chip.active || chip.primary ? Theme.accent : Theme.rgba(Theme.foreground, chipMouse.containsMouse ? 0.25 : 0.12)
        border.width: 1
        scale: chipMouse.pressed ? 0.94 : 1
        Behavior on scale {
            NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 2 }
        }
        Behavior on color {
            CAnim {}
        }
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.text
            color: chip.danger && chipMouse.containsMouse ? "#ef5350"
                : chip.active || chip.primary ? Theme.accent : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
        AppTooltip {
            text: chip.tip
            visible: chip.tip !== "" && chipMouse.containsMouse
        }
    }

    component Caption: Text {
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Math.max(Theme.fontSize - 2, 9)
        font.letterSpacing: 0.6
    }

    // Segmented row of Chips bound to a value.
    component Choice: Row {
        id: choice
        property var options: []        // [{ value, label, tip }]
        property var value
        signal picked(var value)
        spacing: 4
        Repeater {
            model: choice.options
            delegate: Chip {
                required property var modelData
                compact: true
                text: modelData.label
                tip: modelData.tip || ""
                active: choice.value === modelData.value
                onClicked: choice.picked(modelData.value)
            }
        }
    }

    // ---------------------------------------------------------------- sheet
    Rectangle {
        id: sheet
        readonly property bool armed: root.dragging && BarEditState.dragFromZone !== "" && BarEditState.targetZone === ""
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(root.width - 48, Math.max(760, toolbar.needW + 36))
        height: body.implicitHeight + 28
        y: root.topBar ? root.barReach : root.height - root.barReach - height
        radius: Theme.cardRadius + 4
        color: sheet.armed ? Theme.rgba(Theme.accent, 0.16) : root.panelColor
        border.color: sheet.armed ? Theme.accent : Theme.rgba(Theme.accent, 0.45)
        border.width: sheet.armed ? 2 : 1
        clip: true
        Behavior on height {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on color {
            CAnim {}
        }

        // Entrance: slide out of the bar.
        transform: Translate {
            id: slide
        }
        Connections {
            target: BarEditState
            function onActiveChanged() {
                if (BarEditState.active)
                    enter.restart();
            }
        }
        ParallelAnimation {
            id: enter
            NumberAnimation { target: slide; property: "y"; from: root.topBar ? -18 : 18; to: 0; duration: 260; easing.type: Easing.OutCubic }
            NumberAnimation { target: sheet; property: "opacity"; from: 0; to: 1; duration: 200 }
        }

        // Swallow clicks so they never reach the bar surface behind; a click
        // on empty sheet space clears the selection.
        MouseArea {
            anchors.fill: parent
            onClicked: BarEditState.select("", "")
        }

        Column {
            id: body
            x: 18
            y: 14
            width: sheet.width - 36
            spacing: 12

            // ---- toolbar ----
            Item {
                id: toolbar
                // What both button rows need side by side (the sheet widens to it).
                readonly property real needW: tbLeft.implicitWidth + tbRight.implicitWidth + 24
                width: parent.width
                height: 30
                Row {
                    id: tbLeft
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "  Bar layout"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 1
                        font.bold: true
                    }
                    Choice {
                        anchors.verticalCenter: parent.verticalCenter
                        options: [{ value: "islands", label: "Islands", tip: "Sections along the edge" },
                                  { value: "pill", label: "Pill", tip: "One island that expands on hover" }]
                        value: BarEditState.style
                        onPicked: v => BarEditState.switchStyle(v)
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: 18
                        color: Theme.rgba(Theme.foreground, 0.12)
                    }
                    Choice {
                        anchors.verticalCenter: parent.verticalCenter
                        options: [{ value: "widgets", label: "\u{F0570}  Widgets", tip: "Place, order and style widgets" },
                                  { value: "look", label: "\u{F03D8}  Look", tip: "Frame, surface, pills, workspaces, music" }]
                        value: root.page
                        onPicked: v => BarEditState.page = v
                    }
                    Chip {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: BarEditState.style === "islands"
                        compact: true
                        text: Settings.barIslandsDetached ? "  Attach" : "  Detach"
                        tip: Settings.barIslandsDetached ? "Join the sections back into one bar"
                            : "Break the sections into floating pills — drag their labels to place them"
                        onClicked: Settings.updateSetting("bar.islands.detached", !Settings.barIslandsDetached)
                    }
                }
                Row {
                    id: tbRight
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    Chip {
                        compact: true
                        text: ""
                        tip: "Undo everything since you opened the editor"
                        onClicked: BarEditState.revert()
                    }
                    Chip {
                        compact: true
                        text: "  Original"
                        tip: "Restore the original " + BarEditState.style + " layout"
                        onClicked: BarEditState.resetLayout()
                    }
                    Chip {
                        text: "Cancel"
                        tip: "Esc"
                        onClicked: BarEditState.cancel()
                    }
                    Chip {
                        text: "  Done"
                        primary: true
                        tip: "Enter"
                        onClicked: BarEditState.end()
                    }
                }
            }

            // ---- library ----
            Column {
                width: parent.width
                spacing: 6
                visible: root.page === "widgets" || root.dragging
                Caption {
                    text: root.dragging && BarEditState.dragFromZone !== ""
                        ? (sheet.armed ? "RELEASE TO HIDE" : "DROP HERE TO HIDE")
                        : "WIDGETS  ·  drag onto the bar  ·  click a placed one to select it"
                    color: sheet.armed ? Theme.accent : Theme.muted
                }
                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: BarWidgets.catalog.filter(e => BarWidgets.supports(e.id, BarEditState.style))
                        delegate: Rectangle {
                            id: lib
                            required property var modelData
                            readonly property string wid: modelData.id
                            readonly property string where: BarEditState.zoneOf(lib.wid)
                            readonly property bool placed: lib.where !== ""
                            readonly property bool chosen: BarEditState.selectedId === lib.wid
                            width: libRow.implicitWidth + 20
                            height: 30
                            radius: height / 2
                            opacity: BarEditState.draggingId === lib.wid ? 0.35 : 1
                            color: lib.chosen ? Theme.rgba(Theme.accent, 0.25)
                                : libMouse.containsMouse ? Theme.surfaceHover
                                : lib.placed ? Theme.rgba(Theme.foreground, 0.05) : "transparent"
                            border.color: lib.chosen ? Theme.accent : Theme.rgba(Theme.foreground, lib.placed ? 0.14 : 0.22)
                            border.width: 1
                            scale: libMouse.pressed ? 0.94 : 1
                            Behavior on scale {
                                NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 2 }
                            }
                            Row {
                                id: libRow
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: lib.modelData.icon
                                    color: lib.placed ? Theme.accent : Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: lib.modelData.label
                                    color: lib.placed ? Theme.fg : Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                }
                                // Where it lives, or "+ add".
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 16
                                    width: whereText.implicitWidth + 10
                                    radius: 8
                                    color: lib.placed ? Theme.rgba(Theme.accent, 0.18) : Theme.rgba(Theme.foreground, 0.08)
                                    Text {
                                        id: whereText
                                        anchors.centerIn: parent
                                        text: lib.placed ? BarWidgets.zoneLabel(BarEditState.style, lib.where) : "+ add"
                                        color: lib.placed ? Theme.accent : Theme.muted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 9
                                    }
                                }
                            }
                            MouseArea {
                                id: libMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: BarEditState.draggingId !== "" ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                property bool moved: false
                                property real sx: 0
                                property real sy: 0
                                onPressed: mouse => {
                                    moved = false;
                                    sx = mouse.x;
                                    sy = mouse.y;
                                }
                                onPositionChanged: mouse => {
                                    // hoverEnabled also reports plain hover
                                    // moves: only a held button may drag.
                                    if (!pressed)
                                        return;
                                    const p = mapToItem(root, mouse.x, mouse.y);
                                    if (!moved && (Math.abs(mouse.x - sx) > 5 || Math.abs(mouse.y - sy) > 5)) {
                                        moved = true;
                                        BarEditState.startDrag(lib.wid, lib.where, p.x, p.y);
                                    }
                                    if (moved)
                                        BarEditState.updateDrag(p.x, p.y);
                                }
                                onCanceled: {
                                    if (moved)
                                        BarEditState.abortDrag();
                                    moved = false;
                                }
                                onReleased: mouse => {
                                    if (moved) {
                                        moved = false;
                                        const p = mapToItem(root, mouse.x, mouse.y);
                                        BarEditState.updateDrag(p.x, p.y);
                                        BarEditState.finishDrag();
                                        return;
                                    }
                                    if (lib.placed) {
                                        BarEditState.select(lib.chosen ? "" : lib.wid, lib.chosen ? "" : lib.where);
                                    } else {
                                        const home = BarWidgets.home(lib.wid, BarEditState.style);
                                        BarEditState.moveTo(lib.wid, "", home, -1);
                                        BarEditState.select(lib.wid, home);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---- inspector (selected widget) ----
            Rectangle {
                width: parent.width
                height: 1
                color: Theme.rgba(Theme.foreground, 0.08)
                visible: inspector.visible
            }
            Column {
                id: inspector
                width: parent.width
                spacing: 10
                visible: root.sel !== "" && !root.dragging && root.page === "widgets"

                Item {
                    width: parent.width
                    height: 30
                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: BarWidgets.icon(root.sel) + "  " + BarWidgets.label(root.sel)
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 1
                            font.bold: true
                        }
                        Choice {
                            anchors.verticalCenter: parent.verticalCenter
                            options: (BarWidgets.sections[BarEditState.style] || []).map(z => ({ value: z.id, label: z.label, tip: z.hint }))
                            value: BarEditState.selectedZone
                            onPicked: v => {
                                if (v !== BarEditState.selectedZone)
                                    BarEditState.moveTo(root.sel, BarEditState.selectedZone, v, -1);
                            }
                        }
                    }
                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Chip {
                            compact: true
                            text: ""
                            tip: "Move left  (←)"
                            onClicked: BarEditState.nudge(root.sel, BarEditState.selectedZone, -1)
                        }
                        Chip {
                            compact: true
                            text: ""
                            tip: "Move right  (→)"
                            onClicked: BarEditState.nudge(root.sel, BarEditState.selectedZone, 1)
                        }
                        Chip {
                            compact: true
                            danger: true
                            text: "  Hide"
                            tip: "Delete"
                            onClicked: BarEditState.hide(root.sel, BarEditState.selectedZone)
                        }
                    }
                }

                // Look: frame fit · pill · opacity (+ the widget's own options).
                Flow {
                    width: parent.width
                    spacing: 18
                    Column {
                        visible: root.framed
                        spacing: 4
                        Caption { text: "FRAME" }
                        Choice {
                            options: [{ value: "frame", label: "Melt", tip: "Part of its section's frame body" },
                                      { value: "pill", label: "Own", tip: "Its own capsule in the frame" },
                                      { value: "square", label: "Tab", tip: "Square-cornered tab" },
                                      { value: "detach", label: "Float", tip: "Floating, with a gap" }]
                            value: root.look.shape
                            onPicked: v => BarEditState.setFrame(root.sel, v, undefined)
                        }
                    }
                    Column {
                        spacing: 4
                        Caption { text: "PILL" }
                        Choice {
                            options: [{ value: "", label: "Default", tip: "Settings default (" + Settings.barWidgetDeco + ")" },
                                      { value: "none", label: "None" },
                                      { value: "outline", label: "Border" },
                                      { value: "filled", label: "Filled" }]
                            value: root.look.ownDeco ? root.look.deco : ""
                            onPicked: v => BarEditState.setDeco(root.sel, v || null)
                        }
                    }
                    Column {
                        spacing: 4
                        Caption { text: "OPACITY  " + Math.round(root.look.opacity * 100) + "%" + (root.look.ownOpacity ? "" : "  (default)") }
                        Row {
                            spacing: 6
                            AppSlider {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 150
                                from: 20
                                to: 100
                                stepSize: 5
                                value: Math.round(root.look.opacity * 100)
                                onMoved: value => BarEditState.setOpacity(root.sel, value)
                            }
                            Chip {
                                anchors.verticalCenter: parent.verticalCenter
                                compact: true
                                visible: root.look.ownOpacity
                                text: ""
                                tip: "Back to the default"
                                onClicked: BarEditState.setOpacity(root.sel, null)
                            }
                        }
                    }
                    // Widget-specific options.
                    Column {
                        visible: root.sel === "workspaces"
                        spacing: 4
                        Caption { text: "SWITCHER" }
                        Choice {
                            options: root.wsOptions
                            value: BarEditState.style === "pill" ? Settings.barWorkspacesPill : Settings.barWorkspacesIslands
                            onPicked: v => Settings.updateSetting(BarEditState.style === "pill" ? "bar.workspaces.pill" : "bar.workspaces.islands", v)
                        }
                    }
                    Column {
                        visible: root.sel === "media"
                        spacing: 4
                        Caption { text: "PLAYER" }
                        Row {
                            spacing: 8
                            Choice {
                                visible: BarEditState.style === "islands"
                                options: [{ value: false, label: "Compact" }, { value: true, label: "Visualiser" }]
                                value: Settings.mprisVisualizer
                                onPicked: v => {
                                    Settings.mprisVisualizer = v;
                                    Settings.persist();
                                }
                            }
                            Chip {
                                compact: true
                                active: Settings.barVinyl
                                text: "\u{F075A}  Vinyl"
                                tip: "Half record under the widget while a track plays"
                                onClicked: Settings.updateSetting("bar.vinyl.enabled", !Settings.barVinyl)
                            }
                        }
                    }
                    Caption {
                        visible: !root.framed
                        text: "frame is off · frame shapes return when it's on (Look)"
                        opacity: 0.7
                    }
                }
            }

            // ---- look page ----
            Flow {
                id: lookPage
                visible: root.page === "look" && !root.dragging
                width: parent.width
                spacing: 18

                Column {
                    spacing: 4
                    Caption { text: "FRAME" }
                    Choice {
                        options: root.onOff
                        value: root.framed
                        onPicked: v => Settings.updateSetting("frame.enable", v)
                    }
                }
                Column {
                    visible: !root.framed
                    spacing: 4
                    Caption { text: "SURFACE" }
                    Choice {
                        options: [{ value: "glass", label: "Glass" }, { value: "solid", label: "Solid" },
                                  { value: "outline", label: "Outline" }, { value: "clear", label: "Clear" }]
                        value: Settings.barSurfaceStyle
                        onPicked: v => Settings.updateSetting("bar.surface.style", v)
                    }
                }
                Column {
                    visible: !root.framed
                    spacing: 4
                    Caption { text: "CORNERS" }
                    Choice {
                        options: [{ value: "rounded", label: "Round" }, { value: "sharp", label: "Sharp" }, { value: "capsule", label: "Capsule" }]
                        value: Settings.barSurfaceCorners
                        onPicked: v => Settings.updateSetting("bar.surface.corners", v)
                    }
                }
                Column {
                    visible: !root.framed
                    spacing: 4
                    Caption { text: "DEPTH" }
                    Row {
                        spacing: 4
                        Chip {
                            compact: true
                            active: Settings.barSurfaceShadow
                            text: "Shadow"
                            onClicked: Settings.updateSetting("bar.surface.shadow", !Settings.barSurfaceShadow)
                        }
                        Chip {
                            compact: true
                            active: Settings.barSurfaceAccent
                            text: "Accent line"
                            onClicked: Settings.updateSetting("bar.surface.accent", !Settings.barSurfaceAccent)
                        }
                    }
                }
                Column {
                    visible: !root.framed && BarEditState.style === "islands" && !Settings.barIslandsDetached
                    spacing: 4
                    Caption { text: "FLOAT GAP" }
                    Choice {
                        options: [{ value: 0, label: "Flush" }, { value: 6, label: "6" }, { value: 12, label: "12" }, { value: 18, label: "18" }]
                        value: Settings.barEdgeGap
                        onPicked: v => Settings.updateSetting("bar.surface.edgeGap", v)
                    }
                }
                Column {
                    spacing: 4
                    Caption { text: "WIDGET PILLS" }
                    Choice {
                        options: [{ value: "none", label: "None" }, { value: "outline", label: "Border" }, { value: "filled", label: "Filled" }]
                        value: Settings.barWidgetDeco
                        onPicked: v => Settings.updateSetting("bar.widgets.deco", v)
                    }
                }
                Column {
                    spacing: 4
                    Caption { text: "WORKSPACES · " + (BarEditState.style === "pill" ? "PILL" : "ISLANDS") }
                    Choice {
                        options: root.wsOptions
                        value: BarEditState.style === "pill" ? Settings.barWorkspacesPill : Settings.barWorkspacesIslands
                        onPicked: v => Settings.updateSetting(BarEditState.style === "pill" ? "bar.workspaces.pill" : "bar.workspaces.islands", v)
                    }
                }
                Column {
                    visible: BarEditState.style === "pill"
                    spacing: 4
                    Caption { text: "SPECTRUM" }
                    Choice {
                        options: [{ value: "off", label: "Off" }, { value: "bars", label: "Bars" }, { value: "mirror", label: "Mirror" },
                                  { value: "wave", label: "Wave" }, { value: "glow", label: "Glow" }]
                        value: Settings.barSpectrum
                        onPicked: v => Settings.updateSetting("bar.spectrum.style", v)
                    }
                }
                Column {
                    spacing: 4
                    Caption { text: "MUSIC VINYL" }
                    Choice {
                        options: [{ value: "off", label: "Off" },
                                  { value: "playing", label: "Playing", tip: "Out while playing, tucks away after a pause" },
                                  { value: "track", label: "Always", tip: "Out whenever a track is loaded" },
                                  { value: "peek", label: "Peek", tip: "Slides out on play / new track, then tucks away" }]
                        value: Settings.barVinyl ? Settings.barVinylMode : "off"
                        onPicked: v => {
                            if (v === "off") {
                                Settings.updateSetting("bar.vinyl.enabled", false);
                            } else {
                                Settings.updateSetting("bar.vinyl.mode", v);
                                Settings.updateSetting("bar.vinyl.enabled", true);
                            }
                        }
                    }
                }
                Column {
                    spacing: 4
                    Caption { text: "OPEN ISLANDS" }
                    Choice {
                        options: [{ value: false, label: "Click", tip: "Islands and sliders open on click" },
                                  { value: true, label: "Hover", tip: "Open on hover after the reveal delay" }]
                        value: Settings.barHoverReveal
                        onPicked: v => Settings.updateSetting("bar.hoverReveal", v)
                    }
                }
            }

            // ---- key hints ----
            Caption {
                text: "← → reorder     ↑ ↓ section     Del hide     Esc cancel     Enter done"
                    + (Settings.barIslandsDetached && BarEditState.style === "islands" ? "     drag a section's label to move it" : "")
                opacity: 0.8
            }
        }
    }

    // ---------------------------------------------------------------- proxy
    // A snapshot of the dragged widget riding the pointer, tilted a little so
    // it reads as lifted; it reddens and shrinks over the hide target.
    Rectangle {
        id: proxy
        visible: root.dragging
        readonly property bool hasShot: root.proxySource !== ""
        readonly property bool hiding: BarEditState.targetZone === "" && BarEditState.dragFromZone !== ""
        x: BarEditState.dragX - width / 2
        y: BarEditState.dragY - height / 2
        z: 20
        width: hasShot ? proxyImage.implicitWidth + 14 : proxyLabel.implicitWidth + 22
        height: hasShot ? proxyImage.implicitHeight + 12 : 30
        radius: Math.min(Theme.radius, height / 2)
        color: root.panelColor
        border.color: proxy.hiding ? "#ef5350" : Theme.accent
        border.width: 1.5
        rotation: proxy.hiding ? -4 : 2
        scale: proxy.hiding ? 0.9 : 1.06
        opacity: proxy.hiding ? 0.75 : 1
        Behavior on rotation {
            NumberAnimation { duration: 160 }
        }
        Behavior on scale {
            NumberAnimation { duration: 160; easing.type: Easing.OutBack }
        }
        Image {
            id: proxyImage
            visible: proxy.hasShot
            anchors.centerIn: parent
            source: root.proxySource
            fillMode: Image.Pad
        }
        Text {
            id: proxyLabel
            visible: !proxy.hasShot
            anchors.centerIn: parent
            text: BarWidgets.icon(BarEditState.draggingId) + "  " + BarWidgets.label(BarEditState.draggingId)
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }
    }
}
