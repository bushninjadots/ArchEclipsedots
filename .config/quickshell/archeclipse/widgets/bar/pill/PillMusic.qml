import QtQuick
import qs.theme
import qs.services
import qs.widgets.bar

// Music widget for the pill bar style — the same islands MprisWidget,
// rehosted in the pill's expanded face so the transport and the cava
// visualiser arrive with the rest of the reveal. Mirrors DefaultBar's
// playerPill so the two bar styles stay behaviourally identical:
//   left   → toggle the player island (BarState)
//   right  → toggle the cava visualiser (vinyl + waveform)
//   middle → play / pause
//   wheel  → previous / next
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

    property var player: null
    readonly property bool active: player !== null

    visible: active
    implicitWidth: active ? music.implicitWidth + 16 : 0
    implicitHeight: Theme.barContentHeight
    color: "transparent"

    MprisWidget {
        id: music
        anchors.centerIn: parent
        fullMode: Settings.mprisVisualizer
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                Settings.mprisVisualizer = !Settings.mprisVisualizer;
                Settings.persist();
                return;
            }
            if (mouse.button === Qt.MiddleButton) {
                if (root.player)
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
