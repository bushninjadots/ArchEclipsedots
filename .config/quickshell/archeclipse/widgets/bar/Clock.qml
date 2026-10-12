import QtQuick
import QtQuick.Controls
import Quickshell
import qs.theme
import qs.services

// Time always visible; the long date slides out on click (or on hover with
// Settings.barHoverReveal). Tight margins: 4px padding each side, 6px
// between time and date.
Rectangle {
    id: root

    width: row.implicitWidth
    height: Theme.barContentHeight
    radius: Theme.radius
    // Hover fill — set to "transparent" when embedded on an already-filled
    // surface (e.g. the DefaultBar center pill) so the revealed date never
    // paints a mismatched block behind it.
    property string hoverColor: Theme.surfaceHover
    // Opt-out for hosts that drive their own hover expansion (the pill bar
    // reveals a whole row on hover) — the date reveal would overlap it.
    property bool revealDate: true
    // Click-toggled date (when hover reveal is off).
    property bool dateOpen: false
    property Item _timerChip: null
    readonly property bool showDate: root.revealDate && (Settings.barHoverReveal ? hover.hovered : root.dateOpen)
    color: hover.hovered ? hoverColor : "transparent"

    property string timeText: Settings.fmt(new Date(), Settings.dateFormat)
    SystemClock {
        precision: SystemClock.Minutes
        onDateChanged: root.timeText = Settings.fmt(new Date(), Settings.dateFormat)
    }

    Behavior on color {
        ColorAnimation {
            duration: 200
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        // ---- live: who's on the mic / camera / screen, and the timer ----
        // (LiveActivity; after impasto's island.) Hover for names; click
        // the timer to cancel it.
        Row {
            id: live
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            visible: liveRep.count > 0
            Repeater {
                id: liveRep
                model: {
                    const l = [];
                    if (LiveActivity.screenLive)
                        l.push({ k: "screen", icon: "\u{F1483}", tint: "#e5604d", tip: "Sharing your screen: " + LiveActivity.screen.join(", ") });
                    if (LiveActivity.cameraLive)
                        l.push({ k: "camera", icon: "\u{F05A0}", tint: "#4fb37a", tip: "Camera in use: " + LiveActivity.camera.join(", ") });
                    if (LiveActivity.micLive)
                        l.push({ k: "mic", icon: "\u{F036C}", tint: "#e0a03a", tip: "Microphone in use: " + LiveActivity.mic.join(", ") });
                    if (LiveActivity.timerLive)
                        l.push({ k: "timer", icon: "\u{F051B}", tint: "", tip: (LiveActivity.timerLabel !== "" ? LiveActivity.timerLabel + " · " : "") + "click to cancel" });
                    return l;
                }
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool isTimer: modelData.k === "timer"
                    anchors.verticalCenter: parent.verticalCenter
                    height: 18
                    width: chipRow.implicitWidth + 10
                    radius: 9
                    color: isTimer ? Theme.rgba(Theme.accent, 0.16) : Qt.alpha(modelData.tint, 0.18)
                    border.width: 1
                    border.color: isTimer ? Theme.rgba(Theme.accent, 0.45) : Qt.alpha(modelData.tint, 0.55)
                    // Fade in like a status light coming on.
                    opacity: 0
                    Component.onCompleted: {
                        opacity = 1;
                        if (isTimer)
                            root._timerChip = chip;
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 260 }
                    }
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.modelData.icon
                            color: chip.isTimer ? Theme.accent : chip.modelData.tint
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            // Capture lights breathe so they're noticed.
                            SequentialAnimation on opacity {
                                running: !chip.isTimer
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.45; duration: 900; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                            }
                        }
                        Text {
                            visible: chip.isTimer
                            anchors.verticalCenter: parent.verticalCenter
                            text: LiveActivity.fmtLeft(LiveActivity.timerLeft)
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            font.features: { "tnum": 1 }
                        }
                    }
                    // Timer progress along the chip's bottom edge.
                    Rectangle {
                        visible: chip.isTimer
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: 6
                        anchors.bottomMargin: 2
                        width: (parent.width - 12) * LiveActivity.timerProgress
                        height: 1.5
                        radius: 1
                        color: Theme.accent
                    }
                    HoverHandler {
                        id: chipHover
                    }
                    ToolTip.visible: chipHover.hovered
                    ToolTip.delay: 300
                    ToolTip.text: chip.modelData.tip
                }
            }
        }

        Text {
            id: clockLabel
            anchors.verticalCenter: parent.verticalCenter
            text: root.timeText
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        // Revealer: clipped date expands on hover, collapses on leave.
        Item {
            id: dateClip
            anchors.verticalCenter: parent.verticalCenter
            width: root.showDate ? dateText.implicitWidth : 0
            height: dateText.implicitHeight
            clip: true
            visible: width > 0

            Behavior on width {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.InOutQuad
                }
            }

            Text {
                id: dateText
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(new Date(), "dddd · d MMM")
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            // A click on the timer chip cancels it.
            const tc = root._timerChip;
            if (LiveActivity.timerLive && tc) {
                const p = tc.mapFromItem(root, mouse.x, mouse.y);
                if (p.x >= 0 && p.x <= tc.width) {
                    LiveActivity.cancelTimer();
                    return;
                }
            }
            // Click mode: left toggles the date, right cycles the format.
            if (!Settings.barHoverReveal && root.revealDate && mouse.button === Qt.LeftButton) {
                root.dateOpen = !root.dateOpen;
                return;
            }
            const idx = Settings.dateFormats.indexOf(Settings.dateFormat);
            const next = Settings.dateFormats[(idx + 1) % Settings.dateFormats.length];
            Settings.dateFormat = next;
            root.timeText = Settings.fmt(new Date(), next);
        }
    }

    HoverHandler {
        id: hover
    }
}
