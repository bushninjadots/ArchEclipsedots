import Quickshell
import QtQuick
import "./components"
import "./controllers"

PanelWindow {
    id: root

    implicitWidth: 1800
    implicitHeight: 550

    color: "transparent"

    anchors {
        top: true
        left: true
    }

    margins {
        top: 60
        left: 0
    }

    property real bmoX: 100
    property real bmoY: 120

    property string facing: "front"
    property string pendingFacing: "front"

    property real turnScale: 1

    property bool dragging: false
    property bool hovered: false

    property real dragOffsetX: 0
    property real dragOffsetY: 0

    property string expression: "happy"

    BMOState {
        id: state
    }

    MovementController {
        id: movement

        target: bmo

        leftLimit: 80
        rightLimit: root.width - bmo.width - 80
        topLimit: 40
        bottomLimit: root.height - bmo.height - 40
    }

    BMOBody {
        id: bmo

        x: root.bmoX
        y: root.bmoY

        direction: "front"
        walking: state.isWalking && !root.dragging

        expression: root.expression

        transformOrigin: Item.Center

        transform: Scale {
            origin.x: bmo.width / 2
            origin.y: bmo.height / 2

            xScale: root.turnScale
            yScale: 1
        }
    }

    MouseArea {
        id: bmoMouse

        x: root.bmoX
        y: root.bmoY

        width: bmo.width
        height: bmo.height

        hoverEnabled: true

        z: 20

        cursorShape:
            root.dragging
                ? Qt.ClosedHandCursor
                : Qt.OpenHandCursor

        onEntered: {
            root.hovered = true

            bmo.faceItem.lookingAtMouse = true

            root.expression = "surprised"
        }

        onPositionChanged: function(mouse) {

            if (!root.dragging && bmo.faceItem) {
                var faceX =
                    mouse.x *
                    bmo.faceItem.width /
                    bmoMouse.width

                var faceY =
                    mouse.y *
                    bmo.faceItem.height /
                    bmoMouse.height

                bmo.faceItem.lookAt(faceX, faceY)
            }

            if (!root.dragging)
                return

            var newX =
                mouse.x +
                bmoMouse.x -
                root.dragOffsetX

            var newY =
                mouse.y +
                bmoMouse.y -
                root.dragOffsetY

            root.bmoX =
                Math.max(
                    20,
                    Math.min(
                        root.width - bmo.width - 20,
                        newX
                    )
                )

            root.bmoY =
                Math.max(
                    20,
                    Math.min(
                        root.height - bmo.height - 20,
                        newY
                    )
                )
        }

        onExited: {
            root.hovered = false

            if (bmo.faceItem) {
                bmo.faceItem.lookingAtMouse = false
                bmo.faceItem.resetLook()
            }

            expressionReturnTimer.restart()
        }

        onPressed: function(mouse) {
            bmo.controlsPressed = true

            root.dragging = true

            movement.stop()
            xMovement.stop()
            yMovement.stop()

            root.dragOffsetX = mouse.x
            root.dragOffsetY = mouse.y

            root.expression = "surprised"
        }

        onReleased: {
            bmo.controlsPressed = false

            root.dragging = false

            releaseBounce.start()

            root.expression = "happy"

            if (state.isWalking)
                state.setState("idle")
        }

        onCanceled: {
            bmo.controlsPressed = false

            root.dragging = false

            root.expression = "happy"

            if (state.isWalking)
                state.setState("idle")
        }

        onClicked: {
            if (!root.dragging) {
                root.expression = "happy"

                clickReaction.start()

                expressionReturnTimer.restart()
            }
        }
    }

    Timer {
        id: expressionReturnTimer

        interval: 1400
        repeat: false

        onTriggered: {

            if (root.dragging)
                return

            if (state.isSleeping) {
                root.expression = "sleepy"
            } else if (state.isCurious) {
                root.expression = "surprised"
            } else {
                root.expression = "happy"
            }
        }
    }

    /*
        CLICK HOP
    */

    SequentialAnimation {
        id: clickReaction

        NumberAnimation {
            target: root
            property: "bmoY"

            to: root.bmoY - 10

            duration: 100

            easing.type: Easing.OutQuad
        }

        NumberAnimation {
            target: root
            property: "bmoY"

            to: root.bmoY

            duration: 190

            easing.type: Easing.OutBounce
        }
    }

    /*
        DRAG RELEASE BOUNCE
    */

    SequentialAnimation {
        id: releaseBounce

        NumberAnimation {
            target: root
            property: "bmoY"

            to: root.bmoY - 5

            duration: 80

            easing.type: Easing.OutQuad
        }

        NumberAnimation {
            target: root
            property: "bmoY"

            to: root.bmoY

            duration: 180

            easing.type: Easing.OutBounce
        }
    }

    /*
        IDLE / PERSONALITY ANIMATION
    */

    AnimationController {
        id: animations

        bmo: bmo

        leftArm: bmo.leftArmItem
        rightArm: bmo.rightArmItem

        body: bmo.bodyItem

        face: bmo.faceItem

        active:
            !root.dragging &&
            (
                state.isIdle ||
                state.isCurious ||
                state.isHappy ||
                state.isSleeping
            )
    }

    /*
        STATE -> BEHAVIOUR
    */

    Connections {
        target: state

        function onWalkRequested() {

            if (root.dragging)
                return

            movement.chooseDestination()

            root.pendingFacing = "front"
            root.facing = "front"

            root.expression = "happy"

            movement.moving = true

            restartMovement()
        }

        function onIdleRequested() {

            movement.stop()

            xMovement.stop()
            yMovement.stop()

            root.expression = "happy"

            expressionReturnTimer.restart()
        }

        function onCuriousRequested() {

            movement.stop()

            xMovement.stop()
            yMovement.stop()

            root.expression = "surprised"

            expressionReturnTimer.restart()
        }

        function onHappyRequested() {

            movement.stop()

            xMovement.stop()
            yMovement.stop()

            root.expression = "happy"

            expressionReturnTimer.restart()
        }

        function onSleepRequested() {

            movement.stop()

            xMovement.stop()
            yMovement.stop()

            root.expression = "sleepy"
        }
    }

    /*
        MOVEMENT
    */

    NumberAnimation {
        id: xMovement

        target: root
        property: "bmoX"

        to: movement.destinationX

        duration: {
            var distance =
                Math.abs(
                    movement.destinationX -
                    root.bmoX
                )

            return Math.max(
                900,
                distance * 5
            )
        }

        easing.type: Easing.Linear

        onFinished: checkArrival()
    }

    NumberAnimation {
        id: yMovement

        target: root
        property: "bmoY"

        to: movement.destinationY

        duration: {
            var distance =
                Math.abs(
                    movement.destinationY -
                    root.bmoY
                )

            return Math.max(
                900,
                distance * 5
            )
        }

        easing.type: Easing.Linear

        onFinished: checkArrival()
    }

    function restartMovement() {

        if (!state.isWalking)
            return

        if (!movement.moving)
            return

        if (root.dragging)
            return

        xMovement.stop()
        yMovement.stop()

        xMovement.from = root.bmoX
        yMovement.from = root.bmoY

        xMovement.to = movement.destinationX
        yMovement.to = movement.destinationY

        xMovement.restart()
        yMovement.restart()
    }

    function checkArrival() {

        if (!state.isWalking)
            return

        if (root.dragging)
            return

        var xDone =
            Math.abs(
                root.bmoX -
                movement.destinationX
            ) < 3

        var yDone =
            Math.abs(
                root.bmoY -
                movement.destinationY
            ) < 3

        if (xDone && yDone) {

            movement.stop()

            xMovement.stop()
            yMovement.stop()

            root.expression = "happy"

            state.setState("idle")
        }
    }

    /*
        INITIAL STATE
    */

    Component.onCompleted: {

        root.bmoX = 100
        root.bmoY = 120

        root.facing = "front"
        root.pendingFacing = "front"

        root.turnScale = 1

        root.dragging = false
        root.hovered = false
        bmo.controlsPressed = false

        root.expression = "happy"

        console.log("BMO: READY")
    }
}
