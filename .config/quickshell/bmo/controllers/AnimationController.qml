import QtQuick

Item {
    id: root

    property Item bmo
    property Item leftArm
    property Item rightArm
    property Item body
    property Item face

    property bool active: false

    property bool sleeping: false

    property real baseBodyY: 0
    property real baseBodyRotation: 0

    visible: false

    // ------------------------------------------------------------
    // Main idle breathing
    // ------------------------------------------------------------

    SequentialAnimation {
        id: breathing

        running: root.active && !root.sleeping
        loops: Animation.Infinite

        ParallelAnimation {

            NumberAnimation {
                target: root.body
                property: "y"
                from: 0
                to: -2.5
                duration: 1250
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: root.body
                property: "rotation"
                from: -0.35
                to: 0.35
                duration: 1250
                easing.type: Easing.InOutSine
            }
        }

        ParallelAnimation {

            NumberAnimation {
                target: root.body
                property: "y"
                from: -2.5
                to: 0
                duration: 1250
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: root.body
                property: "rotation"
                from: 0.35
                to: -0.35
                duration: 1250
                easing.type: Easing.InOutSine
            }
        }
    }

    // ------------------------------------------------------------
    // Tiny arm relaxation while standing
    // ------------------------------------------------------------

    SequentialAnimation {
        id: armRelax

        running: root.active && !root.sleeping
        loops: Animation.Infinite

        ParallelAnimation {

            NumberAnimation {
                target: root.leftArm
                property: "swing"
                from: -2
                to: 3
                duration: 1500
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: root.rightArm
                property: "swing"
                from: 2
                to: -3
                duration: 1500
                easing.type: Easing.InOutSine
            }
        }

        ParallelAnimation {

            NumberAnimation {
                target: root.leftArm
                property: "swing"
                from: 3
                to: -2
                duration: 1500
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: root.rightArm
                property: "swing"
                from: -3
                to: 2
                duration: 1500
                easing.type: Easing.InOutSine
            }
        }
    }

    // ------------------------------------------------------------
    // Occasional little personality movement
    // ------------------------------------------------------------

    Timer {
        id: personalityTimer

        interval: 2600 + Math.random() * 3500
        repeat: true

        running: root.active && !root.sleeping

        onTriggered: {
            if (!root.body)
                return

            var r = Math.random()

            if (r < 0.35) {
                littleBounce.start()
            } else if (r < 0.65) {
                littleLean.start()
            } else if (r < 0.82 && root.face) {
                root.face.lookLeft()
            } else if (root.face) {
                root.face.lookRight()
            }

            interval = 2600 + Math.random() * 3500
        }
    }

    // ------------------------------------------------------------
    // Small bounce
    // ------------------------------------------------------------

    SequentialAnimation {
        id: littleBounce

        ParallelAnimation {
            NumberAnimation {
                target: root.body
                property: "y"
                from: 0
                to: -6
                duration: 130
                easing.type: Easing.OutQuad
            }

            NumberAnimation {
                target: root.body
                property: "rotation"
                from: 0
                to: -1
                duration: 130
                easing.type: Easing.OutQuad
            }
        }

        ParallelAnimation {
            NumberAnimation {
                target: root.body
                property: "y"
                from: -6
                to: 0
                duration: 260
                easing.type: Easing.OutBounce
            }

            NumberAnimation {
                target: root.body
                property: "rotation"
                from: -1
                to: 0
                duration: 260
                easing.type: Easing.OutBounce
            }
        }
    }

    // ------------------------------------------------------------
    // Tiny idle lean
    // ------------------------------------------------------------

    SequentialAnimation {
        id: littleLean

        NumberAnimation {
            target: root.body
            property: "rotation"
            from: 0
            to: -3
            duration: 300
            easing.type: Easing.InOutSine
        }

        PauseAnimation {
            duration: 180
        }

        NumberAnimation {
            target: root.body
            property: "rotation"
            from: -3
            to: 2
            duration: 500
            easing.type: Easing.InOutSine
        }

        PauseAnimation {
            duration: 120
        }

        NumberAnimation {
            target: root.body
            property: "rotation"
            from: 2
            to: 0
            duration: 300
            easing.type: Easing.InOutSine
        }
    }

    // ------------------------------------------------------------
    // Sleeping animation
    // ------------------------------------------------------------

    SequentialAnimation {
        id: sleepBreathing

        running: root.active && root.sleeping
        loops: Animation.Infinite

        ParallelAnimation {

            NumberAnimation {
                target: root.body
                property: "y"
                from: 0
                to: 2
                duration: 1900
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: root.body
                property: "rotation"
                from: 0
                to: -0.7
                duration: 1900
                easing.type: Easing.InOutSine
            }
        }

        ParallelAnimation {

            NumberAnimation {
                target: root.body
                property: "y"
                from: 2
                to: 0
                duration: 1900
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: root.body
                property: "rotation"
                from: -0.7
                to: 0
                duration: 1900
                easing.type: Easing.InOutSine
            }
        }
    }

    // ------------------------------------------------------------
    // React to BMO state changes
    // ------------------------------------------------------------

    Connections {
        target: bmo

        function onWalkingChanged() {
            if (bmo.walking) {
                breathing.stop()
                armRelax.stop()
                personalityTimer.stop()
                sleepBreathing.stop()

                root.body.y = 0
                root.body.rotation = 0
            } else {
                breathing.restart()
                armRelax.restart()
                personalityTimer.restart()
            }
        }
    }

    onActiveChanged: {
        if (!root.active) {
            breathing.stop()
            armRelax.stop()
            personalityTimer.stop()
            littleBounce.stop()
            littleLean.stop()
            sleepBreathing.stop()

            if (root.body) {
                root.body.y = 0
                root.body.rotation = 0
            }
        } else {
            if (root.sleeping)
                sleepBreathing.restart()
            else {
                breathing.restart()
                armRelax.restart()
                personalityTimer.restart()
            }
        }
    }

    onSleepingChanged: {
        if (root.sleeping) {
            breathing.stop()
            armRelax.stop()
            personalityTimer.stop()

            sleepBreathing.restart()
        } else {
            sleepBreathing.stop()

            if (root.active) {
                breathing.restart()
                armRelax.restart()
                personalityTimer.restart()
            }
        }
    }
}
