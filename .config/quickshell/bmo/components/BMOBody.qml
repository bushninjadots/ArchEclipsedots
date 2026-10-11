import QtQuick

Item {
    id: root

    width: 158
    height: 246

    property string direction: "front"
    property string expression: "happy"
    property bool walking: false
    property bool controlsPressed: false

    property color bodyColor: "#69c7bb"
    property color dark: "#183d42"
    property color screenColor: "#b8f5df"

    property bool dpadUp: false
    property bool dpadDown: false
    property bool dpadLeft: false
    property bool dpadRight: false
    property bool redPressed: false
    property bool yellowPressed: false

    signal controlPressed(string control)
    signal controlReleased(string control)

    function pressControl(control) {
        if (control === "up") dpadUp = true
        else if (control === "down") dpadDown = true
        else if (control === "left") dpadLeft = true
        else if (control === "right") dpadRight = true
        else if (control === "red") redPressed = true
        else if (control === "yellow") yellowPressed = true

        controlPressed(control)
    }

    function releaseControl(control) {
        if (control === "up") dpadUp = false
        else if (control === "down") dpadDown = false
        else if (control === "left") dpadLeft = false
        else if (control === "right") dpadRight = false
        else if (control === "red") redPressed = false
        else if (control === "yellow") yellowPressed = false

        controlReleased(control)
    }

    /*
     * ========================================================
     * BODY
     * ========================================================
     */

    Rectangle {
        id: body

        x: 10
        y: 0

        width: 138
        height: 188

        radius: 14

        color: root.bodyColor

        border.width: 3
        border.color: root.dark

        transformOrigin: Item.Center

        Behavior on rotation {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutQuad
            }
        }

        Behavior on y {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutQuad
            }
        }

        /*
         * ====================================================
         * FRONT
         * ====================================================
         */

        Item {
            id: frontVisual

            anchors.fill: parent

            visible: root.direction === "front"

            /*
             * SCREEN FRAME
             */

            Rectangle {
                x: 18
                y: 19

                width: 122
                height: 82

                radius: 10

                color: root.dark
            }

            /*
             * SCREEN
             */

            BMOFace {
                id: face

                x: 21
                y: 21

                width: 116
                height: 78

                screenColor: root.screenColor
                dark: root.dark
                expression: root.expression
            }

            /*
             * D-PAD
             */

            Item {
                id: dpad

                x: 25
                y: 124

                width: 41
                height: 41

                scale: root.controlsPressed ? 0.97 : 1.0

                Behavior on scale {
                    NumberAnimation {
                        duration: 70
                        easing.type: Easing.OutQuad
                    }
                }

                /*
                 * UP
                 */

                Rectangle {
                    x: 13
                    y: 0

                    width: 15
                    height: 21

                    radius: 4

                    color: root.dark

                    scale: root.dpadUp ? 0.90 : 1.0

                    transformOrigin: Item.Center

                    Behavior on scale {
                        NumberAnimation {
                            duration: 55
                            easing.type: Easing.OutQuad
                        }
                    }
                }

                /*
                 * DOWN
                 */

                Rectangle {
                    x: 13
                    y: 20

                    width: 15
                    height: 21

                    radius: 4

                    color: root.dark

                    scale: root.dpadDown ? 0.90 : 1.0

                    transformOrigin: Item.Center

                    Behavior on scale {
                        NumberAnimation {
                            duration: 55
                            easing.type: Easing.OutQuad
                        }
                    }
                }

                /*
                 * LEFT
                 */

                Rectangle {
                    x: 0
                    y: 13

                    width: 21
                    height: 15

                    radius: 4

                    color: root.dark

                    scale: root.dpadLeft ? 0.90 : 1.0

                    transformOrigin: Item.Center

                    Behavior on scale {
                        NumberAnimation {
                            duration: 55
                            easing.type: Easing.OutQuad
                        }
                    }
                }

                /*
                 * RIGHT
                 */

                Rectangle {
                    x: 20
                    y: 13

                    width: 21
                    height: 15

                    radius: 4

                    color: root.dark

                    scale: root.dpadRight ? 0.90 : 1.0

                    transformOrigin: Item.Center

                    Behavior on scale {
                        NumberAnimation {
                            duration: 55
                            easing.type: Easing.OutQuad
                        }
                    }
                }

                /*
                 * CENTER
                 */

                Rectangle {
                    x: 17
                    y: 17

                    width: 7
                    height: 7

                    radius: 3.5

                    color: "#10282c"
                }
            }

            /*
             * RED BUTTON
             */

            Rectangle {
                id: redButton

                x: 101
                y: 126

                width: 16
                height: 16

                radius: 8

                color: "#e96d7a"

                border.width: 2
                border.color: root.dark

                scale: root.redPressed ? 0.84 : 1.0

                Behavior on scale {
                    NumberAnimation {
                        duration: 70
                        easing.type: Easing.OutBack
                    }
                }

                Rectangle {
                    anchors.centerIn: parent

                    width: 7
                    height: 3

                    radius: 1.5

                    color: "white"

                    opacity: root.redPressed ? 0.08 : 0.18
                }
            }

            /*
             * YELLOW BUTTON
             */

            Rectangle {
                id: yellowButton

                x: 122
                y: 145

                width: 16
                height: 16

                radius: 8

                color: "#e8b95e"

                border.width: 2
                border.color: root.dark

                scale: root.yellowPressed ? 0.84 : 1.0

                Behavior on scale {
                    NumberAnimation {
                        duration: 70
                        easing.type: Easing.OutBack
                    }
                }

                Rectangle {
                    anchors.centerIn: parent

                    width: 7
                    height: 3

                    radius: 1.5

                    color: "white"

                    opacity: root.yellowPressed ? 0.08 : 0.18
                }
            }
        }

        /*
         * ====================================================
         * BACK
         * ====================================================
         */

        Item {
            anchors.fill: parent

            visible: root.direction === "back"

            Rectangle {
                x: 19
                y: 20

                width: 120
                height: 100

                radius: 8

                color: root.dark
            }

            Rectangle {
                x: 25
                y: 26

                width: 108
                height: 88

                radius: 6

                color: "#5bb3aa"
            }
        }
    }

    /*
     * ========================================================
     * D-PAD INTERACTION AREAS
     * ========================================================
     */

    MouseArea {
        x: 25
        y: 124

        width: 41
        height: 41

        enabled: root.direction === "front"

        acceptedButtons: Qt.LeftButton

        onPressed: function(mouse) {
            var localX = mouse.x
            var localY = mouse.y

            var dx = localX - 20.5
            var dy = localY - 20.5

            if (Math.abs(dx) > Math.abs(dy)) {
                if (dx < 0)
                    root.pressControl("left")
                else
                    root.pressControl("right")
            } else {
                if (dy < 0)
                    root.pressControl("up")
                else
                    root.pressControl("down")
            }
        }

        onReleased: {
            root.releaseControl("up")
            root.releaseControl("down")
            root.releaseControl("left")
            root.releaseControl("right")
        }

        onCanceled: {
            root.releaseControl("up")
            root.releaseControl("down")
            root.releaseControl("left")
            root.releaseControl("right")
        }
    }

    /*
     * ========================================================
     * BUTTON INTERACTION AREAS
     * ========================================================
     */

    MouseArea {
        x: 101
        y: 126

        width: 16
        height: 16

        enabled: root.direction === "front"

        onPressed: root.pressControl("red")
        onReleased: root.releaseControl("red")
        onCanceled: root.releaseControl("red")
    }

    MouseArea {
        x: 122
        y: 145

        width: 16
        height: 16

        enabled: root.direction === "front"

        onPressed: root.pressControl("yellow")
        onReleased: root.releaseControl("yellow")
        onCanceled: root.releaseControl("yellow")
    }
}
