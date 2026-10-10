import QtQuick

// Spun's gold tonearm (qml/Tonearm.qml), the drawing only: the pivot rests at
// the record's edge, the arm swings onto the grooves while playing and walks
// across them with the track (6° at the start, 26° at the end), and lifts back
// to rest on pause with Spun's spring. In Spun's 440-unit platter space; the
// host scales it. Spun © yappologistic, PolyForm Noncommercial 1.0.0 — see ./NOTICE.
Item {
    id: arm

    property bool engaged: false
    property real progress: 0          // 0..1 through the track
    property color accent: "#c6a25a"
    property color surface: "#1d2024"
    property bool motion: true

    width: 440
    height: 440

    property real lowered: engaged ? 1 : 0
    property real armAngle: engaged ? 6 + 20 * Math.max(0, Math.min(1, progress)) : -4
    Behavior on armAngle {
        enabled: arm.motion
        SpringAnimation { spring: 6; damping: .55; epsilon: .01 }
    }
    Behavior on lowered {
        enabled: arm.motion
        NumberAnimation { duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2, 0, 0, 1, 1, 1] }
    }

    readonly property color gold: Qt.tint("#c6a25a", Qt.alpha(arm.accent, .12))
    readonly property color glint: Qt.lighter(gold, 1.5)
    readonly property color shade: Qt.darker(gold, 1.6)

    Item {
        x: 378; y: 100
        Rectangle { x: -21; y: -17; width: 42; height: 42; radius: 21; color: "#80000000" }
        Rectangle {
            x: -19; y: -19; width: 38; height: 38; radius: 19
            gradient: Gradient { GradientStop { position: 0; color: "#a0a5a5" } GradientStop { position: .12; color: "#555c5e" } GradientStop { position: .6; color: "#252a2e" } GradientStop { position: 1; color: "#101619" } }
            border.width: .8; border.color: "#747b7b"
            Rectangle { anchors.centerIn: parent; width: 31; height: 31; radius: 15.5; color: "#252b2d"; border.width: 1; border.color: "#121718" }
        }
        Rectangle {
            x: -13; y: -13; width: 26; height: 26; radius: 13
            color: arm.surface; border.width: 1; border.color: arm.shade
        }
        Item {
            rotation: arm.armAngle
            transformOrigin: Item.TopLeft
            // A displaced hard shadow makes the lift legible without a blur pass.
            Rectangle { x: 1 + (1 - arm.lowered) * 2; y: 5; width: 7; height: 187; radius: 3.5; color: "#48000000" }
            Rectangle { x: (1 - arm.lowered) * 2; y: 188; width: 14; height: 24; radius: 4; color: "#48000000" }
            Rectangle {
                x: -7; y: -14; width: 14; height: 22; radius: 5
                gradient: Gradient {
                    GradientStop { position: 0; color: arm.shade }
                    GradientStop { position: .4; color: arm.glint }
                    GradientStop { position: 1; color: arm.gold }
                }
            }
            Rectangle {
                x: -3; y: 0; width: 6; height: 187; radius: 3
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: arm.shade }
                    GradientStop { position: .36; color: arm.glint }
                    GradientStop { position: .65; color: arm.gold }
                    GradientStop { position: 1; color: arm.shade }
                }
            }
            Rectangle { x: -4; y: 178; width: 8; height: 10; radius: 2; color: arm.gold }
            Rectangle {
                x: -7; y: 185; width: 14; height: 24; radius: 4
                color: Qt.tint(arm.surface, Qt.alpha(arm.gold, .15))
                border.width: 1; border.color: arm.gold
                Rectangle { x: 4; y: 5; width: 6; height: 2; radius: 1; color: arm.gold }
                Rectangle { x: 4; y: 10; width: 6; height: 2; radius: 1; color: arm.gold }
                Rectangle { x: 2; y: 18; width: 10; height: 5; radius: 1; color: "#171b1d" }
                Rectangle { x: 6; y: 23; width: 1.2; height: 5; radius: .6; color: "#d5dcde" }
                Rectangle { x: 5.5; y: 27; width: 2; height: 1.5; radius: .5; color: "#d6c5a8" }
                Rectangle { x: 12; y: 4; width: 9; height: 2; radius: 1; rotation: -20; color: arm.gold }
                Repeater {
                    model: 2
                    Rectangle { required property int index; x: 2 + index * 8; y: 2; width: 2; height: 2; radius: 1; color: "#d1d4ca" }
                }
            }
        }
        Rectangle { x: -7; y: -7; width: 14; height: 14; radius: 7; color: arm.gold; border.width: 1; border.color: arm.glint }
        Rectangle { x: -3; y: -1; width: 6; height: 2; radius: 1; rotation: -35; color: arm.shade }
    }
}
