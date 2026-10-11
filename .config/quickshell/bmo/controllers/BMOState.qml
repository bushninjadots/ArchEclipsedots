import QtQuick

Item {
    id: root

    property string state: "idle"

    property bool isIdle: state === "idle"
    property bool isWalking: state === "walking"
    property bool isCurious: state === "curious"
    property bool isHappy: state === "happy"
    property bool isSleeping: state === "sleeping"

    signal walkRequested()
    signal idleRequested()
    signal curiousRequested()
    signal happyRequested()
    signal sleepRequested()

    function setState(nextState) {
        if (root.state === nextState)
            return

        root.state = nextState

        switch (nextState) {
        case "idle":
            idleRequested()
            break

        case "walking":
            walkRequested()
            break

        case "curious":
            curiousRequested()
            break

        case "happy":
            happyRequested()
            break

        case "sleeping":
            sleepRequested()
            break
        }
    }

    /*
        First idle period after startup.
    */

    Timer {
        id: firstWalk

        interval: 2200
        repeat: false
        running: true

        onTriggered: {
            if (root.state === "idle")
                root.setState("walking")
        }
    }

    /*
        Main personality decision.

        BMO spends most of his time idle, occasionally walks,
        occasionally gets curious, and rarely sleeps.
    */

    Timer {
        id: idleDecision

        interval: 4200
        repeat: true
        running: root.state === "idle"

        onTriggered: {
            var r = Math.random()

            if (r < 0.52) {
                root.setState("idle")
            } else if (r < 0.72) {
                root.setState("curious")
            } else if (r < 0.90) {
                root.setState("walking")
            } else {
                root.setState("happy")
            }
        }
    }

    /*
        Curious state lasts briefly.
    */

    Timer {
        id: curiousTimer

        interval: 1700
        repeat: false
        running: root.state === "curious"

        onTriggered: {
            root.setState("idle")
        }
    }

    /*
        Happy reaction.
    */

    Timer {
        id: happyTimer

        interval: 1400
        repeat: false
        running: root.state === "happy"

        onTriggered: {
            root.setState("idle")
        }
    }

    /*
        Walking duration.
    */

    Timer {
        id: walkTimer

        interval: 3800 + Math.random() * 4200
        repeat: false
        running: root.state === "walking"

        onTriggered: {
            if (Math.random() < 0.25)
                root.setState("curious")
            else
                root.setState("idle")
        }
    }

    /*
        Long idle period can eventually make him sleepy.
    */

    Timer {
        id: sleepTimer

        interval: 15000
        repeat: false
        running: root.state === "idle"

        onTriggered: {
            if (Math.random() < 0.30)
                root.setState("sleeping")
            else
                restart()
        }
    }

    /*
        Sleeping lasts several seconds.
    */

    Timer {
        id: wakeTimer

        interval: 6500
        repeat: false
        running: root.state === "sleeping"

        onTriggered: {
            root.setState("happy")
        }
    }

    /*
        When externally forced into idle, reset the sleep timer.
    */

    onStateChanged: {
        if (root.state === "idle") {
            sleepTimer.restart()
        } else {
            sleepTimer.stop()
        }

        if (root.state === "walking") {
            walkTimer.restart()
        } else {
            walkTimer.stop()
        }

        if (root.state === "curious") {
            curiousTimer.restart()
        } else {
            curiousTimer.stop()
        }

        if (root.state === "happy") {
            happyTimer.restart()
        } else {
            happyTimer.stop()
        }

        if (root.state === "sleeping") {
            wakeTimer.restart()
        } else {
            wakeTimer.stop()
        }
    }

    Component.onCompleted: {
        root.state = "idle"
    }
}
