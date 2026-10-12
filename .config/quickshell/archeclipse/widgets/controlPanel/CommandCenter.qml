import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.theme
import qs.services
import qs.widgets.shared

// Command center (the Arch button's island): who/where you are, how the
// machine is doing, quick toggles, sliders and session actions.
//   header   avatar (click: pick an image, right-click: account picture),
//            desktop name (click to rename), user@host · uptime, clock
//   status   battery · cpu · memory · temperature · network
//   toggles  Wi-Fi · Bluetooth · Do not disturb · Caffeine · Mic · Game
//            mode · Theme · Keyboard (right-click Wi-Fi/Bluetooth = island)
//   sliders  volume (icon mutes) · brightness
//   power    power mode (when power-profiles-daemon runs)
//   actions  settings · screenshot · lock · log out · reboot · power off
//            (the last three ask for a second click)
Item {
    id: root

    width: 560
    height: col.implicitHeight + 32

    // ControlIsland holds itself open while these are true.
    property bool _volPressed: false
    property bool _briPressed: false
    readonly property bool adjusting: root._volPressed || root._briPressed
    readonly property bool popupOpen: false

    // ---- identity ----
    readonly property string user: Quickshell.env("USER") || "user"
    property string host: ""
    FileView {
        path: "/etc/hostname"
        onLoaded: root.host = text().trim()
    }
    readonly property string displayName: Settings.desktopName !== "" ? Settings.desktopName
        : (root.host !== "" ? root.host.charAt(0).toUpperCase() + root.host.slice(1) : "ArchEclipse")
    readonly property var avatarSources: {
        const out = [];
        const p = Settings.profilePicture;
        if (p !== "")
            out.push(p.startsWith("/") ? "file://" + p : p);
        out.push("file:///var/lib/AccountsService/icons/" + root.user);
        out.push("file://" + Quickshell.env("HOME") + "/.face");
        return out;
    }
    property int avatarIndex: 0
    onAvatarSourcesChanged: root.avatarIndex = 0

    property real uptimeSec: 0
    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        onLoaded: root.uptimeSec = Number(text().split(" ")[0]) || 0
    }
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: uptimeFile.reload()
    }
    readonly property string uptimeText: {
        const m = Math.floor(root.uptimeSec / 60), h = Math.floor(m / 60), d = Math.floor(h / 24);
        return d > 0 ? d + "d " + (h % 24) + "h" : h > 0 ? h + "h " + (m % 60) + "m" : m + "m";
    }
    property date now: new Date()
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    // Image picker for the avatar. Detached and answered over IPC: the
    // dialog takes the click, which closes this island (outside-click
    // dismiss) and would kill a child process with it.
    function pickAvatar() {
        Quickshell.execDetached(["bash", "-c",
            'p=$(zenity --file-selection --title="Choose a profile picture" --file-filter="Images | *.png *.jpg *.jpeg *.webp *.gif") '
            + '&& [ -n "$p" ] && qs -p "$1" ipc call bar setting profile.picture "$(jq -Rn --arg p "$p" \'$p\')"',
            "avatar", (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/quickshell/archeclipse"]);
    }

    // ---- audio / power state ----
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    PwObjectTracker {
        objects: [root.sink, root.source]
    }
    readonly property var bt: Bluetooth.defaultAdapter
    readonly property var wifiNet: {
        for (const d of (Networking.devices?.values ?? [])) {
            if (d && d.type === DeviceType.Wifi && d.networks?.values) {
                for (const n of d.networks.values) {
                    if (n && n.connected)
                        return n;
                }
            }
        }
        return null;
    }

    // Session actions that need a second click.
    property string confirming: ""
    Timer {
        id: confirmReset
        interval: 3000
        onTriggered: root.confirming = ""
    }
    function act(id, cmd, needsConfirm) {
        if (needsConfirm && root.confirming !== id) {
            root.confirming = id;
            confirmReset.restart();
            return;
        }
        root.confirming = "";
        BarState.deactivate("control");
        Quickshell.execDetached(["bash", "-c", cmd]);
    }

    // ---- arrangeable layout (iNiR's control center you arrange) ----
    // Pencil (top right) enters edit mode: drag tiles to reorder, ⇔ makes a
    // tile wide, × removes it, the library below adds hidden ones; each
    // section can be hidden or moved. Saved to Settings.ccTiles/ccSections.
    property bool editing: false
    readonly property var defaultTiles: ["wifi", "bluetooth", "focus", "caffeine", "mic", "game", "theme", "keyboard"]
    readonly property var allTiles: ["wifi", "bluetooth", "focus", "caffeine", "mic", "game", "theme", "keyboard", "nightlight", "record", "picker", "screenshot"]
    readonly property var tileNames: ({ wifi: "Wi-Fi", bluetooth: "Bluetooth", focus: "Focus", caffeine: "Caffeine", mic: "Mic",
        game: "Game mode", theme: "Theme", keyboard: "Keyboard", nightlight: "Night light", record: "Record", picker: "Colour picker", screenshot: "Screenshot" })
    readonly property var defaultSections: ["status", "toggles", "sliders", "screentime", "power", "actions"]
    readonly property var sectionNames: ({ status: "Status", toggles: "Toggles", sliders: "Sliders", screentime: "Screen time", power: "Power mode", actions: "Session" })
    ListModel { id: tileModel }
    ListModel { id: sectionModel }
    function loadLayout() {
        tileModel.clear();
        const t = Settings.ccTiles.length > 0 ? Settings.ccTiles : root.defaultTiles.map(id => ({ id, w: 1 }));
        for (const x of t)
            if (root.allTiles.indexOf(x.id) !== -1)
                tileModel.append({ tid: x.id, w: x.w === 2 ? 2 : 1 });
        sectionModel.clear();
        const have = {};
        for (const x of Settings.ccSections)
            if (root.defaultSections.indexOf(x.id) !== -1 && !have[x.id]) {
                have[x.id] = true;
                sectionModel.append({ sid: x.id, on: x.on !== false });
            }
        for (const id of root.defaultSections)
            if (!have[id])
                sectionModel.append({ sid: id, on: true });
    }
    function saveLayout() {
        const t = [], sc = [];
        for (let i = 0; i < tileModel.count; i++)
            t.push({ id: tileModel.get(i).tid, w: tileModel.get(i).w });
        for (let i = 0; i < sectionModel.count; i++)
            sc.push({ id: sectionModel.get(i).sid, on: sectionModel.get(i).on });
        Settings.updateSetting("commandCenter.tiles", t);
        Settings.updateSetting("commandCenter.sections", sc);
    }
    function resetLayout() {
        Settings.updateSetting("commandCenter.tiles", []);
        Settings.updateSetting("commandCenter.sections", []);
        root.loadLayout();
    }
    function hasTile(id) {
        for (let i = 0; i < tileModel.count; i++)
            if (tileModel.get(i).tid === id)
                return true;
        return false;
    }
    Component.onCompleted: root.loadLayout()

    Column {
        id: col
        x: 16
        y: 16
        width: root.width - 32
        spacing: 12

        Header {}
        Repeater {
            model: sectionModel
            delegate: Column {
                id: sec
                required property string sid
                required property bool on
                required property int index
                width: col.width
                spacing: 6
                visible: sec.on || root.editing
                opacity: sec.on ? 1 : 0.4
                // Edit bar: name · hide/show · move up/down.
                Row {
                    visible: root.editing
                    width: parent.width
                    height: 20
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: (root.sectionNames[sec.sid] || sec.sid).toUpperCase()
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeCaption
                        font.letterSpacing: 1
                    }
                    Item { width: parent.width - 220; height: 1 }
                    EditChip {
                        glyph: sec.on ? "\u{F0208}" : "\u{F0209}"
                        onClicked: { sectionModel.setProperty(sec.index, "on", !sec.on); root.saveLayout(); }
                    }
                    EditChip {
                        glyph: "\u{F005D}"
                        enabled: sec.index > 0
                        onClicked: { sectionModel.move(sec.index, sec.index - 1, 1); root.saveLayout(); }
                    }
                    EditChip {
                        glyph: "\u{F0045}"
                        enabled: sec.index < sectionModel.count - 1
                        onClicked: { sectionModel.move(sec.index, sec.index + 1, 1); root.saveLayout(); }
                    }
                }
                Loader {
                    width: col.width
                    sourceComponent: sec.sid === "status" ? cStatus : sec.sid === "toggles" ? cToggles
                        : sec.sid === "sliders" ? cSliders : sec.sid === "power" ? cPower : sec.sid === "screentime" ? cScreenTime : cActions
                }
            }
        }
        // Edit footer.
        Row {
            visible: root.editing
            spacing: 8
            anchors.right: parent.right
            EditChip {
                wide: true
                glyph: "\u{F0450}  Reset"
                onClicked: root.resetLayout()
            }
            EditChip {
                wide: true
                accent: true
                glyph: "\u{F012C}  Done"
                onClicked: { root.saveLayout(); root.editing = false; }
            }
        }
    }
    Component { id: cStatus; StatusStrip {} }
    Component { id: cToggles; Toggles {} }
    Component { id: cSliders; Sliders {} }
    Component { id: cPower; PowerModes {} }
    Component { id: cActions; Actions {} }
    Component { id: cScreenTime; ScreenTimeCard {} }

    // Pencil: enter / leave edit mode.
    EditChip {
        // Bottom-right corner of the header card (clear of the clock).
        x: root.width - width - 24
        y: 16 + 92 - height - 8
        z: 5
        accent: root.editing
        glyph: root.editing ? "\u{F012C}" : "\u{F03EB}"
        onClicked: {
            if (root.editing)
                root.saveLayout();
            root.editing = !root.editing;
        }
    }

    // Small round button used by the edit UI.
    component EditChip: Rectangle {
        id: ec
        property string glyph: ""
        property bool accent: false
        property bool wide: false
        signal clicked
        width: ec.wide ? ecText.implicitWidth + 20 : 22
        height: 22
        radius: 11
        opacity: ec.enabled ? 1 : 0.35
        color: ec.accent ? Theme.accent : (ecm.containsMouse ? Theme.rgba(Theme.foreground, 0.16) : Theme.rgba(Theme.foreground, 0.08))
        border.width: 1
        border.color: ec.accent ? Theme.accent : Theme.border
        Text {
            id: ecText
            anchors.centerIn: parent
            text: ec.glyph
            color: ec.accent ? Theme.background : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
        MouseArea {
            id: ecm
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ec.clicked()
        }
    }

    // ================================================================ header
    component Header: Rectangle {
        width: col.width
        height: 92
        radius: 16
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.rgba(Theme.accent, 0.26) }
            GradientStop { position: 1; color: Theme.rgba(Theme.accent, 0.04) }
        }
        border.width: 1
        border.color: Theme.rgba(Theme.accent, 0.3)

        // Avatar with an accent ring.
        Rectangle {
            id: ring
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 64
            height: 64
            radius: 32
            color: "transparent"
            border.width: 2
            border.color: Theme.accent
            scale: avMouse.pressed ? 0.94 : (avMouse.containsMouse ? 1.04 : 1)
            Behavior on scale {
                NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2 }
            }
            ClippingRectangle {
                anchors.centerIn: parent
                width: 56
                height: 56
                radius: 28
                color: Theme.surfaceActive
                Image {
                    id: avatar
                    anchors.fill: parent
                    source: root.avatarIndex < root.avatarSources.length ? root.avatarSources[root.avatarIndex] : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    mipmap: true
                    sourceSize.width: 128
                    sourceSize.height: 128
                    onStatusChanged: if (status === Image.Error) root.avatarIndex++
                }
                Text {
                    anchors.centerIn: parent
                    visible: avatar.status !== Image.Ready
                    text: root.user.charAt(0).toUpperCase()
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 26
                    font.bold: true
                }
            }
            Rectangle {
                visible: avMouse.containsMouse
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 20
                height: 20
                radius: 10
                color: Theme.accent
                Text {
                    anchors.centerIn: parent
                    text: "\u{F03EB}"
                    color: Theme.background
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }
            MouseArea {
                id: avMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: m => {
                    if (m.button === Qt.RightButton)
                        Settings.updateSetting("profile.picture", "");
                    else
                        root.pickAvatar();
                }
            }
            AppTooltip {
                text: "Click: choose a picture · right-click: account picture"
                visible: avMouse.containsMouse
            }
        }

        Column {
            anchors.left: ring.right
            anchors.leftMargin: 14
            anchors.right: clockCol.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            // Desktop name: click to rename (Enter saves, Esc cancels).
            Item {
                width: parent.width
                height: 26
                Text {
                    id: nameText
                    visible: !nameEdit.visible
                    width: parent.width
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.displayName
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: 20
                    font.bold: true
                    elide: Text.ElideRight
                    MouseArea {
                        id: nameMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.IBeamCursor
                        onClicked: {
                            nameEdit.text = root.displayName;
                            nameEdit.visible = true;
                            nameEdit.forceActiveFocus();
                            nameEdit.selectAll();
                        }
                    }
                    AppTooltip {
                        text: "Click to rename this desktop"
                        visible: nameMouse.containsMouse
                    }
                }
                TextInput {
                    id: nameEdit
                    visible: false
                    width: parent.width
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.fg
                    selectionColor: Theme.rgba(Theme.accent, 0.4)
                    font.family: Theme.fontFamily
                    font.pixelSize: 20
                    font.bold: true
                    maximumLength: 32
                    onAccepted: {
                        Settings.updateSetting("profile.desktopName", text.trim() === root.host ? "" : text.trim());
                        visible = false;
                    }
                    Keys.onEscapePressed: visible = false
                    onActiveFocusChanged: if (!activeFocus) visible = false
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.bottom
                        height: 2
                        radius: 1
                        color: Theme.accent
                    }
                }
            }
            Text {
                text: root.user + "@" + (root.host || "localhost") + "  ·  up " + root.uptimeText
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        Column {
            id: clockCol
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Text {
                anchors.right: parent.right
                text: Qt.formatTime(root.now, "HH:mm")
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 26
                font.bold: true
            }
            Text {
                anchors.right: parent.right
                text: Qt.formatDate(root.now, "dddd d MMM")
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    // ================================================================ status
    component StatusStrip: Row {
        spacing: 6
        readonly property var st: SysInfo.systemResources
        Repeater {
            model: {
                const st = parent.st;
                const out = [];
                const b = UPower.displayDevice;
                if (b && b.isLaptopBattery)
                    out.push({ icon: b.state === UPowerDeviceState.Charging ? "\u{F0084}" : "\u{F0079}", text: Math.round(b.percentage * 100) + "%",
                        hot: b.percentage < 0.15 && b.state !== UPowerDeviceState.Charging });
                if (st) {
                    out.push({ icon: "\u{F0EE0}", text: Math.round(st.cpuLoad ?? 0) + "%", hot: (st.cpuLoad ?? 0) > 85 });
                    if (st.ramTotalGB)
                        out.push({ icon: "\u{F035B}", text: Math.round(st.ramUsedGB / st.ramTotalGB * 100) + "%", hot: st.ramUsedGB / st.ramTotalGB > 0.9 });
                    if (st.cpuTempC !== null && st.cpuTempC !== undefined)
                        out.push({ icon: "\u{F050F}", text: Math.round(st.cpuTempC) + "°", hot: st.cpuTempC > 85 });
                }
                out.push({ icon: root.wifiNet ? "\u{F0928}" : "\u{F092F}", text: root.wifiNet ? root.wifiNet.name : "Offline", hot: false });
                return out;
            }
            delegate: Rectangle {
                required property var modelData
                height: 26
                width: Math.min(150, chipRow.implicitWidth + 18)
                radius: 13
                color: modelData.hot ? Qt.rgba(0.94, 0.33, 0.31, 0.16) : Theme.rgba(Theme.foreground, 0.05)
                border.width: 1
                border.color: modelData.hot ? Qt.rgba(0.94, 0.33, 0.31, 0.5) : Theme.border
                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        text: modelData.icon
                        color: modelData.hot ? "#ef5350" : Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                    Text {
                        width: Math.min(implicitWidth, 110)
                        elide: Text.ElideRight
                        text: modelData.text
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }
        }
    }

    // ================================================================ toggles
    component Toggles: Column {
        id: tg
        width: col.width
        spacing: 10
        readonly property real tileW: (width - 24) / 4
        Flow {
            id: flow
            width: parent.width
            spacing: 8
            move: Transition {
                NumberAnimation { properties: "x,y"; duration: 220; easing.type: Easing.OutCubic }
            }
            Repeater {
                model: tileModel
                delegate: Item {
                    id: slot
                    required property string tid
                    required property int w
                    required property int index
                    readonly property bool available: tileLoader.item ? tileLoader.item.available : false
                    visible: slot.available || root.editing
                    width: slot.w === 2 ? tg.tileW * 2 + 8 : tg.tileW
                    height: 56
                    z: dragArea.pressed ? 10 : 0
                    Behavior on width {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                    Loader {
                        id: tileLoader
                        anchors.fill: parent
                        opacity: slot.available ? 1 : 0.4
                        sourceComponent: root.tileComponent(slot.tid)
                        // Edit mode: a gentle wiggle, like a home screen.
                        rotation: 0
                        SequentialAnimation on rotation {
                            running: root.editing && !dragArea.pressed
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.8; duration: 140 + (slot.index % 3) * 20 }
                            NumberAnimation { to: -0.8; duration: 280 }
                            NumberAnimation { to: 0; duration: 140 }
                        }
                        scale: dragArea.pressed ? 1.05 : 1
                        Behavior on scale {
                            NumberAnimation { duration: 140 }
                        }
                    }
                    // Edit: drag to reorder (live, over another tile).
                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        visible: root.editing
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        onPositionChanged: m => {
                            if (!pressed)
                                return;
                            const p = slot.mapToItem(flow, m.x, m.y);
                            const c = flow.childAt(p.x, p.y);
                            if (c && c !== slot && c.index !== undefined && c.tid !== undefined)
                                tileModel.move(slot.index, c.index, 1);
                        }
                        onReleased: root.saveLayout()
                    }
                    // Edit badges: remove · wide/narrow.
                    Row {
                        visible: root.editing
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: -6
                        spacing: 4
                        EditChip {
                            glyph: slot.w === 2 ? "\u{F0615}" : "\u{F0616}"
                            onClicked: { tileModel.setProperty(slot.index, "w", slot.w === 2 ? 1 : 2); root.saveLayout(); }
                        }
                        EditChip {
                            glyph: "\u{F0156}"
                            onClicked: { tileModel.remove(slot.index, 1); root.saveLayout(); }
                        }
                    }
                }
            }
        }
        // Edit: the library of tiles not on the grid.
        Flow {
            visible: root.editing
            width: parent.width
            spacing: 6
            Repeater {
                model: {
                    tileModel.count;
                    return root.allTiles.filter(id => !root.hasTile(id));
                }
                delegate: EditChip {
                    required property string modelData
                    wide: true
                    glyph: "+  " + (root.tileNames[modelData] || modelData)
                    onClicked: { tileModel.append({ tid: modelData, w: 1 }); root.saveLayout(); }
                }
            }
        }
    }

    function tileComponent(id) {
        return ({ wifi: tWifi, bluetooth: tBluetooth, focus: tFocus, caffeine: tCaffeine, mic: tMic, game: tGame,
            theme: tTheme, keyboard: tKeyboard, nightlight: tNight, record: tRecord, picker: tPicker, screenshot: tShot })[id] || null;
    }
    // Night light: hyprsunset running or not (polled while open).
    property bool nightOn: false
    Process {
        id: nightProbe
        command: ["pgrep", "-x", "hyprsunset"]
        onExited: code => root.nightOn = code === 0
    }
    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!nightProbe.running) nightProbe.running = true
    }
    Component {
        id: tWifi
        Tile {
            icon: Networking.wifiEnabled ? "\u{F0928}" : "\u{F092E}"
            label: "Wi-Fi"
            sub: !Networking.wifiEnabled ? "Off" : (root.wifiNet ? root.wifiNet.name : "On")
            on: Networking.wifiEnabled
            onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
            onMore: BarState.activate("network", 0)
        }
    }
    Component {
        id: tBluetooth
        Tile {
            available: !!root.bt
            icon: root.bt?.enabled ? "\u{F00AF}" : "\u{F00B2}"
            label: "Bluetooth"
            sub: !root.bt?.enabled ? "Off" : ((root.bt?.devices?.values ?? []).filter(d => d.connected).map(d => d.name)[0] ?? "On")
            on: root.bt?.enabled ?? false
            onToggled: if (root.bt) root.bt.enabled = !root.bt.enabled
            onMore: BarState.activate("bluetooth", 0)
        }
    }
    Component {
        id: tFocus
        Tile {
            icon: Settings.notifDnd ? "\u{F009B}" : "\u{F009A}"
            label: "Focus"
            sub: Settings.notifDnd ? "Do not disturb" : "Notifications on"
            on: Settings.notifDnd
            onToggled: Settings.updateSetting("notifications.dnd", !Settings.notifDnd)
        }
    }
    Component {
        id: tCaffeine
        Tile {
            icon: "\u{F0176}"
            label: "Caffeine"
            sub: Caffeine.awake ? "Staying awake" : "Off"
            on: Caffeine.awake
            onToggled: Caffeine.toggle()
        }
    }
    Component {
        id: tMic
        Tile {
            available: !!root.source?.audio
            icon: root.source?.audio?.muted ? "\u{F036D}" : "\u{F036C}"
            label: "Mic"
            sub: root.source?.audio?.muted ? "Muted" : Math.round((root.source?.audio?.volume ?? 0) * 100) + "%"
            on: !(root.source?.audio?.muted ?? true)
            onToggled: if (root.source?.audio) root.source.audio.muted = !root.source.audio.muted
        }
    }
    Component {
        id: tGame
        Tile {
            icon: "\u{F0297}"
            label: "Game mode"
            sub: Settings.gameModeEnabled ? "On" : "Off"
            on: Settings.gameModeEnabled
            onToggled: Settings.applyGameMode(!Settings.gameModeEnabled)
        }
    }
    Component {
        id: tTheme
        Tile {
            icon: GlobalTheme.currentTheme ? "\u{F05A8}" : "\u{F0594}"
            label: "Theme"
            sub: GlobalTheme.currentTheme ? "Light" : "Dark"
            on: !GlobalTheme.currentTheme
            onToggled: GlobalTheme.setTheme(!GlobalTheme.currentTheme)
        }
    }
    Component {
        id: tKeyboard
        Tile {
            available: KeyboardLayout.layout !== ""
            icon: "\u{F030C}"
            label: "Keyboard"
            sub: KeyboardLayout.layoutName || KeyboardLayout.layout
            on: false
            onToggled: KeyboardLayout.nextLayout()
        }
    }
    Component {
        id: tNight
        Tile {
            icon: "\u{F0594}"
            label: "Night light"
            sub: root.nightOn ? "Warm · 4000K" : "Off"
            on: root.nightOn
            onToggled: {
                Quickshell.execDetached(["bash", "-c", root.nightOn ? "pkill -x hyprsunset" : "setsid -f hyprsunset -t 4000 >/dev/null 2>&1"]);
                root.nightOn = !root.nightOn;
            }
        }
    }
    Component {
        id: tRecord
        Tile {
            icon: ScreenRecorder.isRecording ? "\u{F04DB}" : "\u{F044A}"
            label: "Record"
            sub: ScreenRecorder.isRecording ? "Recording · click to stop" : "Screen"
            on: ScreenRecorder.isRecording
            onToggled: {
                if (!ScreenRecorder.isRecording)
                    BarState.deactivate("control");
                ScreenRecorder.toggleRecording("");
            }
            onMore: {
                BarState.deactivate("control");
                ScreenRecorder.toggleRecording("area");
            }
        }
    }
    Component {
        id: tPicker
        Tile {
            icon: "\u{F0E40}"
            label: "Colour picker"
            sub: "Copies the hex"
            onToggled: {
                BarState.deactivate("control");
                Quickshell.execDetached(["bash", "-c", "sleep 0.3; c=$(hyprpicker -a -f hex) && notify-send -a 'Colour picker' \"$c\" 'Copied to clipboard'"]);
            }
        }
    }
    Component {
        id: tShot
        Tile {
            icon: "\u{F0104}"
            label: "Screenshot"
            sub: "Area · right-click: screen"
            onToggled: {
                BarState.deactivate("control");
                Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/screenshot.sh", "--area"]);
            }
            onMore: {
                BarState.deactivate("control");
                Quickshell.execDetached(["bash", "-c", "sleep 0.4; ~/.config/hypr/scripts/screenshot.sh --now"]);
            }
        }
    }

    // One quick toggle: icon disc + label + state; right-click = more.
    component Tile: Rectangle {
        id: tile
        property string icon: ""
        property string label: ""
        property string sub: ""
        property bool on: false
        property bool available: true
        signal toggled
        signal more
        implicitHeight: 56
        radius: 14
        color: tile.on ? Theme.rgba(Theme.accent, tm.containsMouse ? 0.3 : 0.2) : (tm.containsMouse ? Theme.rgba(Theme.foreground, 0.09) : Theme.rgba(Theme.foreground, 0.05))
        border.width: 1
        border.color: tile.on ? Theme.rgba(Theme.accent, 0.55) : Theme.border
        scale: tm.pressed ? 0.95 : 1
        Behavior on scale {
            NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 2 }
        }
        Behavior on color {
            ColorAnimation { duration: 160 }
        }
        Rectangle {
            id: disc
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 32
            height: 32
            radius: 16
            color: tile.on ? Theme.accent : Theme.rgba(Theme.foreground, 0.08)
            Behavior on color {
                ColorAnimation { duration: 160 }
            }
            Text {
                anchors.centerIn: parent
                text: tile.icon
                color: tile.on ? Theme.background : Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: 16
            }
        }
        Column {
            anchors.left: disc.right
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            Text {
                width: parent.width
                text: tile.label
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: tile.sub
                color: tile.on ? Theme.accent : Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeCaption
                elide: Text.ElideRight
            }
        }
        MouseArea {
            id: tm
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: m => m.button === Qt.RightButton ? tile.more() : tile.toggled()
        }
    }

    // ================================================================ sliders
    component Sliders: Column {
        width: col.width
        spacing: 8
        SliderRow {
            visible: !!root.sink?.audio
            icon: root.sink?.audio?.muted ? "\u{F075F}" : (root.sink?.audio?.volume ?? 0) > 0.5 ? "\u{F057E}" : "\u{F0580}"
            label: "Volume"
            value: root.sink?.audio?.volume ?? 0
            to: 1.0
            dimmed: root.sink?.audio?.muted ?? false
            onIconClicked: if (root.sink?.audio) root.sink.audio.muted = !root.sink.audio.muted
            onMoved: v => {
                if (root.sink?.audio) {
                    root.sink.audio.muted = false;
                    root.sink.audio.volume = v;
                }
            }
            onPressedChanged: root._volPressed = pressed
            onMore: Quickshell.execDetached(["pavucontrol"])
        }
        SliderRow {
            visible: Brightness.hasBacklight
            icon: Brightness.screen > 0.66 ? "\u{F00E0}" : Brightness.screen > 0.33 ? "\u{F00DF}" : "\u{F00DE}"
            label: "Brightness"
            value: Brightness.screen
            to: 1.0
            onMoved: v => Brightness.setScreen(Math.max(0.01, v))
            onPressedChanged: root._briPressed = pressed
        }
    }
    component SliderRow: Rectangle {
        id: sr
        property string icon: ""
        property string label: ""
        property real value: 0
        property real to: 1
        property bool dimmed: false
        readonly property bool pressed: slider.pressed
        signal moved(real v)
        signal iconClicked
        signal more
        width: col.width
        height: 44
        radius: 14
        color: Theme.rgba(Theme.foreground, 0.05)
        border.width: 1
        border.color: Theme.border
        Rectangle {
            id: ic
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 30
            height: 30
            radius: 15
            color: im.containsMouse ? Theme.rgba(Theme.accent, 0.25) : Theme.rgba(Theme.accent, 0.14)
            Text {
                anchors.centerIn: parent
                text: sr.icon
                color: sr.dimmed ? Theme.muted : Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: 16
            }
            MouseArea {
                id: im
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: m => m.button === Qt.RightButton ? sr.more() : sr.iconClicked()
            }
        }
        Text {
            id: lbl
            anchors.left: ic.right
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 76
            text: sr.label
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
        AppSlider {
            id: slider
            anchors.left: lbl.right
            anchors.right: pct.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            from: 0
            to: sr.to
            stepSize: 0.01
            opacity: sr.dimmed ? 0.5 : 1
            onMoved: sr.moved(slider.value)
        }
        Binding {
            target: slider
            property: "value"
            value: sr.value
            when: !slider.pressed
        }
        Text {
            id: pct
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            horizontalAlignment: Text.AlignRight
            text: Math.round(sr.value * 100) + "%"
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    // ================================================================ power modes
    component PowerModes: Row {
        visible: PpdState.available
        width: col.width
        spacing: 6
        Repeater {
            model: [{ v: PowerProfile.PowerSaver, label: "\u{F032A}  Saver" },
                    { v: PowerProfile.Balanced, label: "\u{F05D1}  Balanced" },
                    { v: PowerProfile.Performance, label: "\u{F04C5}  Performance" }]
            delegate: Rectangle {
                required property var modelData
                readonly property bool on: PowerProfiles.profile === modelData.v
                width: (col.width - 12) / 3
                height: 32
                radius: 10
                color: on ? Theme.rgba(Theme.accent, 0.22) : (pmm.containsMouse ? Theme.rgba(Theme.foreground, 0.08) : Theme.rgba(Theme.foreground, 0.04))
                border.width: 1
                border.color: on ? Theme.accent : Theme.border
                Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    color: parent.on ? Theme.accent : Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
                MouseArea {
                    id: pmm
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: PowerProfiles.profile = modelData.v
                }
            }
        }
    }

    // ================================================================ screen time
    // Today's focused time per app (ScreenTime) and the last 7 days.
    component ScreenTimeCard: Rectangle {
        id: stc
        width: col.width
        height: stCol.implicitHeight + 24
        radius: 14
        color: Theme.rgba(Theme.foreground, 0.05)
        border.width: 1
        border.color: Theme.border
        readonly property var apps: ScreenTime.top.slice(0, 4)
        readonly property int maxSecs: stc.apps.length > 0 ? stc.apps[0].secs : 1
        Column {
            id: stCol
            x: 14
            y: 12
            width: parent.width - 28
            spacing: 8
            Row {
                width: parent.width
                spacing: 8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{F0954}"
                    color: Theme.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: 16
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 24 - weekBars.width - 16
                    Text {
                        text: ScreenTime.fmt(ScreenTime.total)
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 2
                        font.bold: true
                    }
                    Text {
                        text: "Screen time today"
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeCaption
                    }
                }
                // The week as seven bars, today highlighted.
                Row {
                    id: weekBars
                    anchors.bottom: parent.bottom
                    spacing: 4
                    readonly property var days: {
                        const w = ScreenTime.week.slice();
                        if (w.length > 0)
                            w[w.length - 1] = { day: w[w.length - 1].day, secs: Math.max(w[w.length - 1].secs, ScreenTime.total) };
                        return w;
                    }
                    readonly property int peak: Math.max(1, ...weekBars.days.map(d => d.secs))
                    Repeater {
                        model: weekBars.days
                        delegate: Column {
                            required property var modelData
                            required property int index
                            spacing: 2
                            Item {
                                width: 8
                                height: 30
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: Math.max(2, parent.height * modelData.secs / weekBars.peak)
                                    radius: 3
                                    color: index === weekBars.days.length - 1 ? Theme.accent : Theme.rgba(Theme.foreground, 0.22)
                                    Behavior on height {
                                        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                                    }
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "SMTWTFS".charAt(new Date(modelData.day + "T12:00:00").getDay())
                                color: Theme.muted
                                font.family: Theme.fontFamily
                                font.pixelSize: 8
                            }
                        }
                    }
                }
            }
            Text {
                visible: stc.apps.length === 0
                text: "Nothing counted yet today."
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }
            Repeater {
                model: stc.apps
                delegate: Row {
                    required property var modelData
                    width: stCol.width
                    spacing: 8
                    IconImage {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 16
                        source: Quickshell.iconPath(ScreenTime.icon(modelData.app), true)
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 96
                        text: ScreenTime.label(modelData.app)
                        color: Theme.fg
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 16 - 96 - 56 - 24
                        height: 6
                        radius: 3
                        color: Theme.rgba(Theme.foreground, 0.08)
                        Rectangle {
                            width: parent.width * modelData.secs / stc.maxSecs
                            height: parent.height
                            radius: 3
                            color: Theme.accent
                            Behavior on width {
                                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                            }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 56
                        horizontalAlignment: Text.AlignRight
                        text: ScreenTime.fmt(modelData.secs)
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }
        }
    }

    // ================================================================ actions
    component Actions: Item {
        width: col.width
        height: 40
        Row {
            anchors.left: parent.left
            spacing: 6
            ActionBtn {
                icon: "\u{F0493}"
                tip: "Settings"
                onClicked: {
                    Settings.leftPanelWidget = "SettingsWidget";
                    BarState.deactivate("control");
                    BarState.activate("left", 0);
                }
            }
            ActionBtn {
                icon: "\u{F0104}"
                tip: "Screenshot (area)"
                onClicked: {
                    BarState.deactivate("control");
                    Quickshell.execDetached([Quickshell.env("HOME") + "/.config/hypr/scripts/screenshot.sh", "--area"]);
                }
            }
        }
        Row {
            anchors.right: parent.right
            spacing: 6
            ActionBtn {
                icon: "\u{F033E}"
                tip: "Lock"
                onClicked: root.act("lock", "loginctl lock-session", false)
            }
            ActionBtn {
                icon: "\u{F0343}"
                tip: root.confirming === "logout" ? "Click again to log out" : "Log out"
                armed: root.confirming === "logout"
                onClicked: root.act("logout", "loginctl terminate-session \"$XDG_SESSION_ID\"", true)
            }
            ActionBtn {
                icon: "\u{F0709}"
                tip: root.confirming === "reboot" ? "Click again to restart" : "Restart"
                armed: root.confirming === "reboot"
                onClicked: root.act("reboot", "systemctl reboot", true)
            }
            ActionBtn {
                icon: "\u{F0425}"
                tip: root.confirming === "poweroff" ? "Click again to power off" : "Power off"
                armed: root.confirming === "poweroff"
                danger: true
                onClicked: root.act("poweroff", "systemctl poweroff", true)
            }
        }
    }
    component ActionBtn: Rectangle {
        id: ab
        property string icon: ""
        property string tip: ""
        property bool armed: false
        property bool danger: false
        signal clicked
        width: ab.armed ? 96 : 40
        height: 40
        radius: 20
        color: ab.armed ? Qt.rgba(0.94, 0.33, 0.31, 0.85)
            : abm.containsMouse ? (ab.danger ? Qt.rgba(0.94, 0.33, 0.31, 0.22) : Theme.rgba(Theme.accent, 0.2)) : Theme.rgba(Theme.foreground, 0.06)
        border.width: 1
        border.color: ab.armed ? "#ef5350" : Theme.border
        scale: abm.pressed ? 0.92 : 1
        Behavior on width {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 2 }
        }
        Behavior on color {
            ColorAnimation { duration: 160 }
        }
        Text {
            anchors.centerIn: parent
            text: ab.armed ? ab.icon + "  Sure?" : ab.icon
            color: ab.armed ? "white" : (ab.danger && abm.containsMouse ? "#ef5350" : Theme.fg)
            font.family: Theme.fontFamily
            font.pixelSize: ab.armed ? Theme.fontSizeSmall : 16
        }
        MouseArea {
            id: abm
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ab.clicked()
        }
        AppTooltip {
            text: ab.tip
            visible: abm.containsMouse
        }
    }
}
