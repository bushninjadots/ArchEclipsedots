import QtQuick
import qs.theme
import qs.widgets.bar.islands

// Shared shell for card-style islands (network, bluetooth, battery,
// weather, system): fixed width, unfold-on-open body, hover pin and Esc to
// close. Children go into a Column, so an island is just its content.
Item {
    id: root

    property string stateName: ""
    property int islandWidth: 380
    property int islandMargins: 8
    property alias spacing: body.spacing
    default property alias content: body.data

    // Expand driver: 0 -> 1 on creation unfolds the body; the Bar exit
    // driver plays 1 -> 0 on close before swapping content.
    property real expand: 0
    Component.onCompleted: expand = 1

    implicitWidth: root.islandWidth + root.islandMargins * 2
    implicitHeight: clip.height + root.islandMargins * 2
    width: implicitWidth
    height: implicitHeight

    IslandExpandClip {
        id: clip
        expand: root.expand
        contentHeight: body.implicitHeight
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.islandMargins

        Column {
            id: body
            anchors.top: parent.top
            width: parent.width
            spacing: 10
        }
    }

    IslandHoverPin {
        stateName: root.stateName
    }
    IslandEscClose {
        states: [root.stateName]
    }
}
