import QtQuick

Item {
    id: root

    // Match the BMO body coordinate space directly.
    // The controls are positioned relative to this 160x210 design space.
    width: 160
    height: 210

    property color dark: "#183d42"
    property color tealDark: "#328f87"
    property color red: "#d95b63"
    property color blue: "#5c9ed6"
    property color yellow: "#e8c95c"

    /*
        D-PAD
    */

    Item {
        id: dpad

        x: 30
        y: 116

        width: 38
        height: 38

        Rectangle {
            x: 12
            y: 0

            width: 14
            height: 38

            radius: 3

            color: root.dark
        }

        Rectangle {
            x: 0
            y: 12

            width: 38
            height: 14

            radius: 3

            color: root.dark
        }

        Rectangle {
            x: 14
            y: 14

            width: 10
            height: 10

            radius: 2

            color: root.tealDark
        }
    }

    /*
        RED BUTTON
    */

    Rectangle {
        x: 102
        y: 116

        width: 18
        height: 18

        radius: 9

        color: root.red

        border.width: 2
        border.color: Qt.darker(root.red, 1.18)

        Rectangle {
            x: 4
            y: 3

            width: 7
            height: 3

            radius: 2

            color: "white"
            opacity: 0.20
        }
    }

    /*
        BLUE BUTTON
    */

    Rectangle {
        x: 124
        y: 128

        width: 14
        height: 14

        radius: 7

        color: root.blue

        border.width: 2
        border.color: Qt.darker(root.blue, 1.18)

        Rectangle {
            x: 3
            y: 2

            width: 6
            height: 2

            radius: 1

            color: "white"
            opacity: 0.20
        }
    }

    /*
        YELLOW BUTTON
    */

    Rectangle {
        x: 91
        y: 144

        width: 8
        height: 8

        radius: 4

        color: root.yellow
    }

    /*
        SPEAKER
    */

    Column {
        x: 91
        y: 163

        spacing: 4

        Repeater {
            model: 3

            Rectangle {
                width: 27
                height: 3

                radius: 1.5

                color: root.dark
                opacity: 0.55
            }
        }
    }

    /*
        LOWER DETAIL
    */

    Row {
        x: 35
        y: 168

        spacing: 5

        Repeater {
            model: 4

            Rectangle {
                width: 4
                height: 4

                radius: 2

                color: root.dark
                opacity: 0.35
            }
        }
    }
}
