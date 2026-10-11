import QtQuick

Item {
    id: root

    width: 116
    height: 78

    property color screenColor: "#b8f5df"
    property color dark: "#183d42"

    property string expression: "happy"

    property real lookX: 0
    property real lookY: 0
    property real targetLookX: 0
    property real targetLookY: 0

    property bool sleepy: false
    property bool lookingAtMouse: false

    property real eyeOpen: 1.0
    property real mouthOpen: 1.0
    property real mouthScale: 1.0
    property real faceBounce: 0

    property bool reacting: false

    function lookAt(x, y) {
        var dx = x - width / 2
        var dy = y - height / 2

        root.targetLookX = Math.max(-17, Math.min(17, dx * 0.32))
        root.targetLookY = Math.max(-5, Math.min(5, dy * 0.20))
    }

    function lookLeft() {
        root.targetLookX = -16
        root.targetLookY = 0
    }

    function lookRight() {
        root.targetLookX = 16
        root.targetLookY = 0
    }

    function lookUp() {
        root.targetLookX = 0
        root.targetLookY = -5
    }

    function lookDown() {
        root.targetLookX = 0
        root.targetLookY = 5
    }

    function resetLook() {
        root.targetLookX = 0
        root.targetLookY = 0
    }

    function animateExpression() {
        expressionAnimation.stop()
        expressionAnimation.start()

        root.reacting = true
        reactionHold.restart()
    }

    onExpressionChanged: animateExpression()

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: root.screenColor
        border.width: 2
        border.color: "#8bd8c2"

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 9
            radius: 8
            color: "white"
            opacity: 0.14
        }
    }

    // LEFT EYE
    Rectangle {
        id: leftEye

        x: 27 + root.lookX
        y: 25 + root.lookY + root.faceBounce

        width: root.expression === "surprised" ? 12 : 9

        height: {
            var normal = 19

            if (root.expression === "surprised")
                normal = 23
            else if (root.expression === "sad")
                normal = 16
            else if (root.expression === "angry")
                normal = 13
            else if (root.expression === "sleepy")
                normal = 5

            return normal * root.eyeOpen
        }

        radius: width / 2
        color: root.dark

        Behavior on x {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutQuad
            }
        }

        Behavior on y {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutQuad
            }
        }
    }

    // RIGHT EYE
    Rectangle {
        id: rightEye

        x: 80 + root.lookX
        y: 25 + root.lookY + root.faceBounce

        width: root.expression === "surprised" ? 12 : 9

        height: {
            var normal = 19

            if (root.expression === "surprised")
                normal = 23
            else if (root.expression === "sad")
                normal = 16
            else if (root.expression === "angry")
                normal = 13
            else if (root.expression === "sleepy")
                normal = 5

            return normal * root.eyeOpen
        }

        radius: width / 2
        color: root.dark

        Behavior on x {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutQuad
            }
        }

        Behavior on y {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutQuad
            }
        }
    }

    // ANGRY BROWS
    Rectangle {
        visible: root.expression === "angry"

        x: 22 + root.lookX
        y: 18 + root.lookY + root.faceBounce

        width: 18
        height: 4

        radius: 2
        rotation: 14
        color: root.dark
    }

    Rectangle {
        visible: root.expression === "angry"

        x: 76 + root.lookX
        y: 18 + root.lookY + root.faceBounce

        width: 18
        height: 4

        radius: 2
        rotation: -14
        color: root.dark
    }

    // MOUTH
    Item {
        id: mouth

        x: 38
        y: 47 + root.faceBounce

        width: 40
        height: 24

        scale: root.mouthScale

        transformOrigin: Item.Center

        // HAPPY
        Item {
            visible: root.expression === "happy"

            anchors.fill: parent

            Rectangle {
                x: 3
                y: 2
                width: 34
                height: 6
                radius: 3
                color: root.dark
            }

            Rectangle {
                x: 7
                y: 6
                width: 26
                height: 12 * root.mouthOpen
                radius: 7
                color: root.dark
            }

            Rectangle {
                x: 10
                y: 7
                width: 20
                height: 5
                radius: 2.5
                color: root.screenColor
            }
        }

        // NEUTRAL
        Item {
            visible: root.expression === "neutral"

            anchors.fill: parent

            Rectangle {
                x: 7
                y: 9
                width: 26
                height: 5
                radius: 2.5
                color: root.dark
            }
        }

        // SURPRISED
        Item {
            visible: root.expression === "surprised"

            anchors.fill: parent

            Rectangle {
                x: 11
                y: 1
                width: 18
                height: 21 * root.mouthOpen
                radius: 9
                color: root.dark
            }

            Rectangle {
                x: 15
                y: 5
                width: 10
                height: 13
                radius: 5
                color: root.screenColor
            }
        }

        // SAD
        Item {
            visible: root.expression === "sad"

            anchors.fill: parent

            Rectangle {
                x: 5
                y: 10
                width: 30
                height: 5
                radius: 2.5
                color: root.dark
            }

            Rectangle {
                x: 5
                y: 7
                width: 8
                height: 5
                radius: 2.5
                rotation: 18
                color: root.dark
            }

            Rectangle {
                x: 27
                y: 7
                width: 8
                height: 5
                radius: 2.5
                rotation: -18
                color: root.dark
            }
        }

        // ANGRY
        Item {
            visible: root.expression === "angry"

            anchors.fill: parent

            Rectangle {
                x: 4
                y: 6
                width: 32
                height: 6
                radius: 3
                color: root.dark
            }

            Rectangle {
                x: 10
                y: 12
                width: 20
                height: 4
                radius: 2
                color: root.screenColor
            }
        }

        // SLEEPY
        Item {
            visible: root.expression === "sleepy"

            anchors.fill: parent

            Rectangle {
                x: 6
                y: 9
                width: 28
                height: 4
                radius: 2
                color: root.dark
            }
        }
    }

    // EXPRESSION CHANGE POP
    SequentialAnimation {
        id: expressionAnimation

        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "mouthScale"

                from: 0.86
                to: 1.08

                duration: 100

                easing.type: Easing.OutBack
            }

            NumberAnimation {
                target: root
                property: "faceBounce"

                from: 2
                to: -1

                duration: 90

                easing.type: Easing.OutQuad
            }
        }

        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "mouthScale"

                to: 1

                duration: 130

                easing.type: Easing.OutBack
            }

            NumberAnimation {
                target: root
                property: "faceBounce"

                to: 0

                duration: 140

                easing.type: Easing.OutBounce
            }
        }
    }

    Timer {
        id: reactionHold

        interval: 500

        repeat: false

        onTriggered: {
            root.reacting = false
        }
    }

    // SURPRISE BREATH
    SequentialAnimation {
        id: surprisePulse

        running: root.expression === "surprised"

        loops: Animation.Infinite

        NumberAnimation {
            target: root
            property: "mouthOpen"

            from: 0.88
            to: 1.08

            duration: 450

            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            target: root
            property: "mouthOpen"

            from: 1.08
            to: 0.88

            duration: 450

            easing.type: Easing.InOutSine
        }
    }

    // HAPPY LITTLE SMILE PULSE
    SequentialAnimation {
        id: happyPulse

        running: root.expression === "happy"

        loops: Animation.Infinite

        PauseAnimation {
            duration: 1800
        }

        NumberAnimation {
            target: root
            property: "mouthOpen"

            from: 0.92
            to: 1.05

            duration: 180

            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            target: root
            property: "mouthOpen"

            from: 1.05
            to: 0.92

            duration: 180

            easing.type: Easing.InOutSine
        }
    }

    // SLEEPY BREATHING
    SequentialAnimation {
        id: sleepyPulse

        running: root.expression === "sleepy"

        loops: Animation.Infinite

        NumberAnimation {
            target: root
            property: "eyeOpen"

            from: 0.75
            to: 0.55

            duration: 1000

            easing.type: Easing.InOutSine
        }

        PauseAnimation {
            duration: 500
        }

        NumberAnimation {
            target: root
            property: "eyeOpen"

            from: 0.55
            to: 0.85

            duration: 1000

            easing.type: Easing.InOutSine
        }
    }

    // MOUSE GAZE
    Timer {
        interval: 16
        repeat: true
        running: root.lookingAtMouse

        onTriggered: {
            root.lookX = root.targetLookX
            root.lookY = root.targetLookY
        }
    }

    Behavior on lookX {
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutQuad
        }
    }

    Behavior on lookY {
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutQuad
        }
    }

    Behavior on targetLookX {
        NumberAnimation {
            duration: 260
            easing.type: Easing.InOutQuad
        }
    }

    Behavior on targetLookY {
        NumberAnimation {
            duration: 260
            easing.type: Easing.InOutQuad
        }
    }

    // IDLE LOOKING
    Timer {
        id: idleLook

        interval: 1800 + Math.random() * 2200

        repeat: true

        running: !root.lookingAtMouse

        onTriggered: {
            var r = Math.random()

            if (r < 0.18) {
                root.targetLookX = -16
                root.targetLookY = 0
            } else if (r < 0.36) {
                root.targetLookX = 16
                root.targetLookY = 0
            } else if (r < 0.52) {
                root.targetLookX = -10
                root.targetLookY = -5
            } else if (r < 0.68) {
                root.targetLookX = 10
                root.targetLookY = -5
            } else if (r < 0.80) {
                root.targetLookX = -9
                root.targetLookY = 5
            } else if (r < 0.92) {
                root.targetLookX = 9
                root.targetLookY = 5
            } else {
                root.targetLookX = 0
                root.targetLookY = 0
            }

            interval = 1800 + Math.random() * 2200
        }
    }

    onTargetLookXChanged: {
        if (!root.lookingAtMouse)
            root.lookX = root.targetLookX
    }

    onTargetLookYChanged: {
        if (!root.lookingAtMouse)
            root.lookY = root.targetLookY
    }

    // NATURAL BLINK
    SequentialAnimation {
        id: blink

        running:
            !root.sleepy &&
            root.expression !== "sleepy"

        loops: Animation.Infinite

        PauseAnimation {
            duration: 1800 + Math.random() * 2600
        }

        ParallelAnimation {
            NumberAnimation {
                target: leftEye
                property: "height"
                to: 2
                duration: 65
            }

            NumberAnimation {
                target: rightEye
                property: "height"
                to: 2
                duration: 65
            }
        }

        PauseAnimation {
            duration: 65
        }

        ParallelAnimation {
            NumberAnimation {
                target: leftEye
                property: "height"
                to: 19
                duration: 90
            }

            NumberAnimation {
                target: rightEye
                property: "height"
                to: 19
                duration: 90
            }
        }
    }

    // OCCASIONAL DOUBLE BLINK
    Timer {
        interval: 6500

        repeat: true

        running:
            !root.sleepy &&
            root.expression !== "sleepy"

        onTriggered: {
            if (Math.random() < 0.25)
                doubleBlink.start()
        }
    }

    SequentialAnimation {
        id: doubleBlink

        ParallelAnimation {
            NumberAnimation {
                target: leftEye
                property: "height"
                to: 2
                duration: 60
            }

            NumberAnimation {
                target: rightEye
                property: "height"
                to: 2
                duration: 60
            }
        }

        PauseAnimation {
            duration: 65
        }

        ParallelAnimation {
            NumberAnimation {
                target: leftEye
                property: "height"
                to: 19
                duration: 80
            }

            NumberAnimation {
                target: rightEye
                property: "height"
                to: 19
                duration: 80
            }
        }

        PauseAnimation {
            duration: 110
        }

        ParallelAnimation {
            NumberAnimation {
                target: leftEye
                property: "height"
                to: 2
                duration: 60
            }

            NumberAnimation {
                target: rightEye
                property: "height"
                to: 2
                duration: 60
            }
        }

        PauseAnimation {
            duration: 65
        }

        ParallelAnimation {
            NumberAnimation {
                target: leftEye
                property: "height"
                to: 19
                duration: 90
            }

            NumberAnimation {
                target: rightEye
                property: "height"
                to: 19
                duration: 90
            }
        }
    }
}
