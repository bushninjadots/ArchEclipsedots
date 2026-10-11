import QtQuick

Item {
    id: root

    property Item target

    property real leftLimit: 80
    property real rightLimit: 1600

    property real topLimit: 40
    property real bottomLimit: 400

    property bool moving: false

    property real destinationX: 600
    property real destinationY: 200

    property string direction: "front"

    width: 1
    height: 1

    visible: false

    function chooseDestination() {

        if (!root.target) {
            console.log("BMO: no movement target")
            return
        }

        var maxX =
            Math.max(
                root.leftLimit,
                root.rightLimit
            )

        var maxY =
            Math.max(
                root.topLimit,
                root.bottomLimit
            )

        root.destinationX =
            root.leftLimit +
            Math.random() *
            (maxX - root.leftLimit)

        root.destinationY =
            root.topLimit +
            Math.random() *
            (maxY - root.topLimit)

        var dx =
            root.destinationX -
            root.target.x

        var dy =
            root.destinationY -
            root.target.y

        if (Math.abs(dx) > Math.abs(dy)) {

            if (dx >= 0)
                root.direction = "right"
            else
                root.direction = "left"

        } else {

            if (dy >= 0)
                root.direction = "front"
            else
                root.direction = "back"
        }

        console.log(
            "BMO walking:",
            Math.round(root.target.x),
            Math.round(root.target.y),
            "→",
            Math.round(root.destinationX),
            Math.round(root.destinationY),
            root.direction
        )

        root.moving = true
    }

    function stop() {
        root.moving = false
    }
}
