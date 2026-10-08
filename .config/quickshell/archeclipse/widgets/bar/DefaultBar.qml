import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import qs.theme
import qs.services
import qs.widgets.bar
import qs.widgets.shared
import qs.widgets.weather

// Center section (ex-Information) is inlined here directly:
// weather + resources on the left; center rectangle with
// bandwidth | control panel | clock; player pill first on the right,
// then battery/brightness/volume/tray.
// Top row holds all content; the workspace strip sits at the very bottom,
// stretched across the full bar width.
Column {
    id: root
    spacing: 4

    // media player state (ex-Information firstPlayable logic) — visibility
    // gate only now: title/EQ/transport live in MprisWidget.qml
    readonly property var firstPlayable: {
        Mpris.players.values;   // reactive dep
        for (const p of Mpris.players.values) {
            // touch reactive props so title / play-state changes re-fire
            const _t = p.trackTitle;
            const _s = p.playbackState;
            if ((_t ?? "").trim() !== "" || _s === MprisPlaybackState.Playing)
                return p;
        }
        return null;
    }

    // Fixed-width dynamic speed: always 4 chars (3-char numeric + 1-char
    // unit that scales B/K/M/G), so the bandwidth cell never shifts width
    // as speeds change. Monospace font keeps every string the same width.
    function fmtSpeed(bps) {
        if (bps < 1000)
            return String(Math.round(bps)).padStart(3, " ") + "B";
        const kb = bps / 1024;
        if (kb < 10)
            return kb.toFixed(1) + "K";
        if (kb < 1000)
            return String(Math.round(kb)).padStart(3, " ") + "K";
        const mb = kb / 1024;
        if (mb < 10)
            return mb.toFixed(1) + "M";
        if (mb < 1000)
            return String(Math.round(mb)).padStart(3, " ") + "M";
        const gb = mb / 1024;
        if (gb < 10)
            return gb.toFixed(1) + "G";
        return String(Math.round(gb)).padStart(3, " ") + "G";
    }

    Item {
        id: topRow
        // Both side sections count as wide as the wider one, so the
        // centered pill always keeps at least Theme.spacing clearance
        // from either side instead of clipping into the wider section.
        // The weather button stretches to absorb any slack on the left.
        readonly property real leftMinWidth: weatherButton.implicitWidth + Theme.spacing + resourceMonitor.implicitWidth
        readonly property real rightMinWidth: utilities.implicitWidth
        readonly property real sideWidth: Math.max(leftMinWidth, rightMinWidth)
        implicitWidth: 2 * sideWidth + centerPill.width + Theme.spacing * 2
        width: implicitWidth
        height: Theme.barContentHeight

        // Center rectangle — bandwidth on the left, control panel
        // button dead-center, clock on the right.
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
                // Equal-width side cells so the control button stays
                // dead-center relative to the whole bar even when
                // bandwidth and clock text widths differ.
                readonly property real sideCellWidth: Math.max(bandwidthRow.implicitWidth, clockItem.width)

                // bandwidth compact (up/down from SysInfo loop) — left
                Item {
                    width: centerRow.sideCellWidth
                    height: parent.height
                    Row {
                        id: bandwidthRow
                        spacing: 4
                        anchors.centerIn: parent
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.fmtSpeed(SysInfo.bandwidth[0] * 1024)
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.fmtSpeed(SysInfo.bandwidth[1] * 1024)
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }
                }

                // control panel toggle — center
                ControlPanelButton {
                    id: centerButton
                    anchors.verticalCenter: parent.verticalCenter
                }

                // clock — right, same cell width as bandwidth side
                Item {
                    width: centerRow.sideCellWidth
                    height: parent.height
                    Clock {
                        id: clockItem
                        anchors.centerIn: parent
                        hoverColor: "transparent"
                    }
                }
            }
        }

        // left zone — fixed sideWidth; weather stretches into the slack
        Item {
            id: leftZone
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: topRow.sideWidth
            height: parent.height

            RowLayout {
                anchors.fill: parent
                spacing: Theme.spacing

                ResourceMonitor {
                    id: resourceMonitor
                    Layout.fillWidth: true
                }
                WeatherButton {
                    id: weatherButton
                    Layout.fillWidth: true
                }
            }
        }

        // right zone — fixed sideWidth like the left, content right-aligned
        // so the center pill keeps symmetric spacing on both sides
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

                // media pill (ryoku-style MPRIS widget: transport buttons,
                // marquee title, animated EQ - ported standalone into
                // MprisWidget.qml) - first on the right
                Rectangle {
                    id: playerPill
                    visible: root.firstPlayable !== null
                    width: visible ? mprisWidget.implicitWidth + 16 : 0
                    height: Theme.barContentHeight
                    radius: Theme.radius
                    color: "transparent"
                    anchors.verticalCenter: parent.verticalCenter

                    // Smooth width morph (visualizer toggle, track changes) on
                    // the shell's shared spatial motion token.
                    Behavior on width {
                        Anim {
                            type: Anim.DefaultSpatial
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }
                    }

                    // Visualizer mode is user-toggled (right click on the
                    // pill, persisted), not hover-driven.
                    MprisWidget {
                        id: mprisWidget
                        anchors.centerIn: parent
                        fullMode: Settings.mprisVisualizer
                    }

                    // No hover behavior by design: hovering changes nothing
                    // visually and opens nothing. The MprisWidget's inner
                    // MouseAreas take the transport glyphs' left clicks; this
                    // wrapper catches left click (open/close the now-playing
                    // island), right click (toggle visualizer mode),
                    // middle-click (toggle play/pause) and the wheel (skip).
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            if (!root.firstPlayable)
                                return;
                            if (mouse.button === Qt.RightButton) {
                                Settings.mprisVisualizer = !Settings.mprisVisualizer;
                                Settings.persist();
                                return;
                            }
                            if (mouse.button === Qt.MiddleButton) {
                                root.firstPlayable.togglePlaying();
                                return;
                            }
                            if (BarState.state === "player")
                                BarState.deactivate("player");
                            else
                                BarState.activate("player");
                        }
                        onWheel: wheel => {
                            const p = root.firstPlayable;
                            if (!p || wheel.angleDelta.y === 0)
                                return;
                            if (wheel.angleDelta.y > 0 && p.canGoNext)
                                p.next();
                            else if (wheel.angleDelta.y < 0 && p.canGoPrevious)
                                p.previous();
                            wheel.accepted = true;
                        }
                    }
                }

                Battery {}
                Brightness {}
                Volume {}
                Tray {}
            }
        }
    } // topRow

    // bottom workspace strip — full width of the bar content
    Workspaces {
        width: topRow.implicitWidth
    }
}
