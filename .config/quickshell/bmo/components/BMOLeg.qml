import QtQuick

Item {
    id: root

    width: 58
    height: 94

    property color bodyColor: "#63d8c7"
    property color bodyDark: "#42b8aa"

    property real swing: 0
    property real kneeBend: 0

    property bool sideProfile: false
    property bool facingLeft: true
    property bool rear: false

    // ============================================================
    // FRONT / BACK LEG
    // ============================================================

    Item {
        id: normalLeg

        visible: !root.sideProfile
        anchors.fill: parent

        Item {
            id: thigh

            x: 14
            y: 0

            width: 27
            height: 47

            rotation: root.swing
            transformOrigin: Item.Top

            Rectangle {
                anchors.fill: parent

                radius: 11

                color: root.bodyColor
                border.width: 2
                border.color: root.bodyDark
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom

                width: 27
                height: 23

                radius: 11.5

                color: root.bodyColor
                border.width: 2
                border.color: root.bodyDark
            }

            Item {
                x: 2
                y: 39

                width: 24
                height: 51

                rotation: root.kneeBend
                transformOrigin: Item.Top

                Rectangle {
                    anchors.fill: parent

                    radius: 10

                    color: root.bodyColor
                    border.width: 2
                    border.color: root.bodyDark
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom

                    width: 44
                    height: 20

                    radius: 9

                    color: root.bodyColor
                    border.width: 2
                    border.color: root.bodyDark
                }
            }
        }
    }

    // ============================================================
    // SIDE PROFILE
    // ============================================================

    Item {
        id: sideLeg

        visible: root.sideProfile
        anchors.fill: parent

        z: root.rear ? 1 : 5

        // --------------------------------------------------------
        // REAR LEG
        //
        // Tucked toward the centre of the body so it cannot read
        // as a second complete leg beside the visible profile.
        // --------------------------------------------------------

        Item {
            id: rearProfile

            visible: root.rear
            anchors.fill: parent

            Item {
                id: rearThigh

                x: 30
                y: 5

                width: 17
                height: 35

                transformOrigin: Item.Top

                rotation:
                    root.swing * 0.45

                Rectangle {
                    anchors.fill: parent

                    radius: 8

                    color: "#4fb9ad"
                    border.width: 2
                    border.color: root.bodyDark
                }
            }

            Rectangle {
                x: 27
                y: 33

                width: 21
                height: 20

                radius: 10

                color: "#4fb9ad"
                border.width: 2
                border.color: root.bodyDark
            }

            Item {
                id: rearShin

                x: 31
                y: 48

                width: 16
                height: 36

                transformOrigin: Item.Top

                rotation:
                    root.kneeBend * 0.45

                Rectangle {
                    anchors.fill: parent

                    radius: 7

                    color: "#4fb9ad"
                    border.width: 2
                    border.color: root.bodyDark
                }
            }

            Rectangle {
                x:
                    root.facingLeft
                        ? 27
                        : 31

                y: 77

                width: 25
                height: 15

                radius: 7

                rotation:
                    root.kneeBend * 0.25

                color: "#4fb9ad"
                border.width: 2
                border.color: root.bodyDark
            }
        }

        // --------------------------------------------------------
        // FRONT LEG
        //
        // Dominant visible side silhouette.
        // --------------------------------------------------------

        Item {
            id: frontProfile

            visible: !root.rear
            anchors.fill: parent

            Rectangle {
                id: hip

                x: 16
                y: 1

                width: 27
                height: 24

                radius: 11

                color: root.bodyColor
                border.width: 2
                border.color: root.bodyDark
            }

            Item {
                id: sideThigh

                x: 19
                y: 20

                width: 22
                height: 35

                transformOrigin: Item.Top

                rotation:
                    root.swing * 0.75

                Rectangle {
                    anchors.fill: parent

                    radius: 10

                    color: root.bodyColor
                    border.width: 2
                    border.color: root.bodyDark
                }
            }

            Rectangle {
                id: knee

                x: 14
                y: 47

                width: 29
                height: 26

                radius: 13

                color: root.bodyColor
                border.width: 2
                border.color: root.bodyDark
            }

            Item {
                id: shin

                x: 19
                y: 66

                width: 21
                height: 30

                transformOrigin: Item.Top

                rotation:
                    root.kneeBend

                Rectangle {
                    anchors.fill: parent

                    radius: 9

                    color: root.bodyColor
                    border.width: 2
                    border.color: root.bodyDark
                }
            }

            Rectangle {
                id: foot

                y: 77

                width: 42
                height: 20

                radius: 9

                x:
                    root.facingLeft
                        ? 4
                        : 12

                rotation:
                    root.kneeBend * 0.35

                color: root.bodyColor
                border.width: 2
                border.color: root.bodyDark
            }
        }
    }
}
