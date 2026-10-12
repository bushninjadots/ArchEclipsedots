import QtQuick
import qs.theme
import qs.services
import qs.widgets.bar
import qs.widgets.shared

// Islands-bar media slot. Extracted from DefaultBar.playerPill so the layout
// registry can place the MPRIS widget like any other bar component.
//
//   left   → toggle the player island (BarState)
//   right  → toggle the cava visualiser (vinyl + waveform), persisted
//   middle → play / pause
//   wheel  → previous / next
//
// Hidden entirely when no real player is present (BarWidgets.firstPlayable).
Rectangle {
    id: root
    // Tells the bar vinyl (Peek mode) the music widget is hovered.
    HoverHandler {
        id: vinylPeekHover
        onHoveredChanged: BarState.mediaHovered = vinylPeekHover.hovered
    }
    Component.onDestruction: {
        if (vinylPeekHover.hovered)
            BarState.mediaHovered = false;
    }

    readonly property var player: BarWidgets.firstPlayable

    visible: player !== null
    implicitWidth: visible ? mprisWidget.implicitWidth + 16 : 0
    implicitHeight: Theme.barContentHeight
    width: implicitWidth
    height: implicitHeight
    radius: Theme.radius
    color: "transparent"

    // Smooth width morph (visualizer toggle, track changes) on the shell's
    // shared spatial motion token.
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

    // Visualizer mode is user-toggled (right click on the pill, persisted).
    MprisWidget {
        id: mprisWidget
        anchors.centerIn: parent
        fullMode: Settings.mprisVisualizer
    }

    // No hover behavior by design: hovering changes nothing visually and opens
    // nothing. The MprisWidget's inner MouseAreas take the transport glyphs'
    // left clicks; this wrapper catches left click (open/close the now-playing
    // island), right click (toggle visualizer mode), middle-click (toggle
    // play/pause) and the wheel (skip).
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (!root.player)
                return;
            if (mouse.button === Qt.RightButton) {
                Settings.mprisVisualizer = !Settings.mprisVisualizer;
                Settings.persist();
                return;
            }
            if (mouse.button === Qt.MiddleButton) {
                root.player.togglePlaying();
                return;
            }
            if (BarState.state === "player")
                BarState.deactivate("player");
            else
                BarState.activate("player");
        }
        onWheel: wheel => {
            const p = root.player;
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
