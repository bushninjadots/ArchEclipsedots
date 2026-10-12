import QtQuick
import qs.theme

// Island title row: glyph in a tinted disc, title + subtitle, and an
// optional trailing control (children go to the right edge).
Item {
    id: root

    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property color tint: Theme.accent
    // Dim the disc when the thing it stands for is off.
    property bool active: true
    default property alias trailing: trail.data

    width: parent ? parent.width : 0
    implicitHeight: 40
    height: implicitHeight

    Rectangle {
        id: disc
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 36
        height: 36
        radius: 18
        color: Theme.rgba(root.tint, root.active ? 0.20 : 0.08)
        border.width: 1
        border.color: Theme.rgba(root.tint, root.active ? 0.45 : 0.15)
        Behavior on color {
            ColorAnimation { duration: 200 }
        }
        Text {
            anchors.centerIn: parent
            text: root.icon
            color: root.active ? root.tint : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: 18
        }
    }
    Column {
        anchors.left: disc.right
        anchors.leftMargin: 12
        anchors.right: trail.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        Text {
            width: parent.width
            text: root.title
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 1
            font.bold: true
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            visible: root.subtitle !== ""
            text: root.subtitle
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideRight
        }
    }
    Row {
        id: trail
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
    }
}
