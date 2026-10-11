import QtQuick

Item {
    id: root

    width: 44
    height: 112

    property color bodyColor: "#63d8c7"
    property color bodyDark: "#42b8aa"

    property real swing: 0
    property real elbowBend: 0

    property bool sideProfile: false
    property bool facingLeft: true
    property bool rear: false

    // ============================================================
    // FRONT / BACK ARM
    // ============================================================

    Item {
        id: normalArm

        visible: !root.sideProfile
        anchors.fill: parent

        Item {
            id: upper

            x: 10
            y: 0

            width: 24
            height: 56

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
                x: 5
                y: 8

                width: 5
                height: 36

                radius: 2.5

                color: "#9aeade"
                opacity: 0.2
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom

                width: 23
                height: 23

                radius: 11.5

                color: root.bodyColor
                border.width: 2
                border.color: root.bodyDark
            }

            Item {
                x: 1
                y: 48

                width: 22
                height: 58

                rotation: root.elbowBend
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

                    width: 27
                    height: 22

                    radius: 10

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
        id: sideArm

        visible: root.sideProfile
        anchors.fill: parent

        z: root.rear ? 1 : 5

        // ========================================================
        // REAR PROFILE ARM
        // ========================================================

        Item {
            id: rearProfile

            visible: root.rear
            anchors.fill: parent

            Item {
                id: rearUpper

                x: 25
                y: 8

                width: 16
                height: 39

                transformOrigin: Item.Top

                rotation: root.swing * 0.45

                Rectangle {
                    anchors.fill: parent

                    radius: 8

                    color: "#4fb9ad"
                    border.width: 2
                    border.color: root.bodyDark
                }
            }

            Rectangle {
                x: 23
                y: 39

                width: 20
                height: 20

                radius: 10

                color: "#4fb9ad"
                border.width: 2
                border.color: root.bodyDark
            }

            Item {
                id: rearForearm

                x: 27
                y: 51

                width: 15
                height: 39

                transformOrigin: Item.Top

                rotation: root.elbowBend * 0.45

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
                        ? 25
                        : 29

                y: 84

                width: 17
                height: 13

                radius: 6.5

                rotation: root.elbowBend * 0.25

                color: "#4fb9ad"
                border.width: 2
                border.color: root.bodyDark
            }
        }

        // ========================================================
        // FRONT PROFILE ARM
        // ========================================================

        Item {
            id: frontProfile

            visible: !root.rear
            anchors.fill: parent

            Rectangle {
                id: shoulder

                x: 13
                y: 5

                width: 25
                height: 25

                radius: 12.5

                color: root.bodyColor
                border.width: 2
                border.color: root.bodyDark
            }

            Item {
                id: upperSide

                x: 17
                y: 22

                width: 20
                height: 38

                transformOrigin: Item.Top

                rotation: root.swing * 0.65

                Rectangle {
                    anchors.fill: parent

                    radius: 9

                    color: root.bodyColor
                    border.width: 2
                    border.color: root.bodyDark
                }
            }

            Rectangle {
                id: elbowSide

                x: 13
                y: 51

                width: 25
                height: 25

                radius: 12.5

                color: root.bodyColor
                border.width: 2
                border.color: root.bodyDark
            }

            Item {
                id: forearmSide

                x: 17
                y: 68

                width: 20
                height: 39

                transformOrigin: Item.Top

                rotation: root.elbowBend

                Rectangle {
                    anchors.fill: parent

                    radius: 8

                    color: root.bodyColor
                    border.width: 2
                    border.color: root.bodyDark
                }
            }

            Rectangle {
                id: handSide

                y: 88

                width: 31
                height: 19

                radius: 9.5

                x:
                    root.facingLeft
                        ? 5
                        : 14

                rotation:
                    root.elbowBend * 0.4

                color: root.bodyColor
                border.width: 2
                border.color: root.bodyDark
            }
        }
    }
}
