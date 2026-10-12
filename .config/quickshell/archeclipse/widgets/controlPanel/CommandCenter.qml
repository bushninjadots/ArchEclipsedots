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

    Column {
        id: col
        x: 16
        y: 16
        width: root.width - 32
        spacing: 12

        Header {}
        StatusStrip {}
        Toggles {}
        Sliders {}
        PowerModes {}
        Actions {}
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
    component Toggles: Grid {
        id: grid
        width: col.width
        columns: 4
        spacing: 8
        readonly property real tileW: (width - spacing * 3) / 4
        Tile {
            icon: Networking.wifiEnabled ? "\u{F0928}" : "\u{F092E}"
            label: "Wi-Fi"
            sub: !Networking.wifiEnabled ? "Off" : (root.wifiNet ? root.wifiNet.name : "On")
            on: Networking.wifiEnabled
            onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
            onMore: BarState.activate("network", 0)
        }
        Tile {
            visible: !!root.bt
            icon: root.bt?.enabled ? "\u{F00AF}" : "\u{F00B2}"
            label: "Bluetooth"
            sub: !root.bt?.enabled ? "Off" : ((root.bt?.devices?.values ?? []).filter(d => d.connected).map(d => d.name)[0] ?? "On")
            on: root.bt?.enabled ?? false
            onToggled: if (root.bt) root.bt.enabled = !root.bt.enabled
            onMore: BarState.activate("bluetooth", 0)
        }
        Tile {
            icon: Settings.notifDnd ? "\u{F009B}" : "\u{F009A}"
            label: "Focus"
            sub: Settings.notifDnd ? "Do not disturb" : "Notifications on"
            on: Settings.notifDnd
            onToggled: Settings.updateSetting("notifications.dnd", !Settings.notifDnd)
        }
        Tile {
            icon: "\u{F0176}"
            label: "Caffeine"
            sub: Caffeine.awake ? "Staying awake" : "Off"
            on: Caffeine.awake
            onToggled: Caffeine.toggle()
        }
        Tile {
            visible: !!root.source?.audio
            icon: root.source?.audio?.muted ? "\u{F036D}" : "\u{F036C}"
            label: "Mic"
            sub: root.source?.audio?.muted ? "Muted" : Math.round((root.source?.audio?.volume ?? 0) * 100) + "%"
            on: !(root.source?.audio?.muted ?? true)
            onToggled: if (root.source?.audio) root.source.audio.muted = !root.source.audio.muted
        }
        Tile {
            icon: "\u{F0297}"
            label: "Game mode"
            sub: Settings.gameModeEnabled ? "On" : "Off"
            on: Settings.gameModeEnabled
            onToggled: Settings.applyGameMode(!Settings.gameModeEnabled)
        }
        Tile {
            icon: GlobalTheme.currentTheme ? "\u{F05A8}" : "\u{F0594}"
            label: "Theme"
            sub: GlobalTheme.currentTheme ? "Light" : "Dark"
            on: !GlobalTheme.currentTheme
            onToggled: GlobalTheme.setTheme(!GlobalTheme.currentTheme)
        }
        Tile {
            visible: KeyboardLayout.layout !== ""
            icon: "\u{F030C}"
            label: "Keyboard"
            sub: KeyboardLayout.layoutName || KeyboardLayout.layout
            on: false
            onToggled: KeyboardLayout.nextLayout()
        }
    }

    // One quick toggle: icon disc + label + state; right-click = more.
    component Tile: Rectangle {
        id: tile
        property string icon: ""
        property string label: ""
        property string sub: ""
        property bool on: false
        signal toggled
        signal more
        width: (col.width - 24) / 4
        height: 56
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
