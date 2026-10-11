import QtQuick

Item {
    id: root

    property Item leftArm
    property Item rightArm
    property Item leftLeg
    property Item rightLeg
    property Item body

    property bool running: false

    property int stepDuration: 170

    visible: false

    SequentialAnimation {
        id: cycle
        running: root.running
        loops: Animation.Infinite

        // LEFT STEP
        ParallelAnimation {

            // Arms
            NumberAnimation {
                target: root.leftArm
                property: "swing"
                from: -24
                to: 24
                duration: root.stepDuration
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: root.leftArm
                property: "elbowBend"
                from: 14
                to: -20
                duration: root.stepDuration
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: root.rightArm
                property: "swing"
                from: 24
                to: -24
                duration: root.stepDuration
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: root.rightArm
                property: "elbowBend"
                from: -20
                to: 14
                duration: root.stepDuration
                easing.type: Easing.InOutSine
            }

            // Legs
            NumberAnimation {
                target: root.leftLeg
                property: "swing"
                from: 18
                to: -18
                duration: root.stepDuration
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: root.leftLeg
                property: "kneeBend"
                from: -12
                to: 30
                duration: root.stepDuration
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: root.rightLeg
                property: "swing"
                from: -18
                to: 18
                duration: root.stepDuration
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: root.rightLeg
                property: "kneeBend"
                from: 30
                to: -12
                duration: root.stepDuration
                easing.type: Easing.InOutSine
            }

            // Character weight
            NumberAnimation {
                target: root.body
                property: "y"
                from: 0
                to: -5
                duration: root.stepDuration
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: root.body
                property: "x"
                from: 0
                to: 1.8
                duration: root.stepDuration
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: root.body
                property: "rotation"
                from: -1.2
                to: 1.2
                duration: root.stepDuration
                easing.type: Easing.InOutSine
            }
        }

        // RIGHT STEP
        ParallelAnimation {

            // Arms
            NumberAnimation {
                target: root.leftArm
                property: "swing"
                from: 24
                to: -24
                duration: root.stepDuration
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: root.leftArm
                property: "elbowBend"
                from: -20
                to: 14
                duration: root.stepDuration
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: root.rightArm
                property: "swing"
                from: -24
                to: 24
                duration: root.stepDuration
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: root.rightArm
                property: "elbowBend"
                from: 14
                to: -20
                duration: root.stepDuration
                easing.type: Easing.InOutSine
            }

            // Legs
            NumberAnimation {
                target: root.leftLeg
                property: "swing"
                from: -18
                to: 18
                duration: root.stepDuration
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: root.leftLeg
                property: "kneeBend"
                from: 30
                to: -12
                duration: root.stepDuration
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: root.rightLeg
                property: "swing"
                from: 18
                to: -18
                duration: root.stepDuration
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: root.rightLeg
                property: "kneeBend"
                from: -12
                to: 30
                duration: root.stepDuration
                easing.type: Easing.InOutSine
            }

            // Character weight
            NumberAnimation {
                target: root.body
                property: "y"
                from: -5
                to: 0
                duration: root.stepDuration
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: root.body
                property: "x"
                from: 1.8
                to: -1.8
                duration: root.stepDuration
                easing.type: Easing.InOutSine
            }

            NumberAnimation {
                target: root.body
                property: "rotation"
                from: 1.2
                to: -1.2
                duration: root.stepDuration
                easing.type: Easing.InOutSine
            }
        }

        // Settle very slightly before the next stride.
        ParallelAnimation {
            NumberAnimation {
                target: root.body
                property: "x"
                to: 0
                duration: 45
                easing.type: Easing.OutQuad
            }

            NumberAnimation {
                target: root.body
                property: "rotation"
                to: 0
                duration: 45
                easing.type: Easing.OutQuad
            }
        }
    }
}
