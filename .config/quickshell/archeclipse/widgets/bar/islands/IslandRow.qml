import QtQuick
import qs.theme

// List row for island lists (Wi-Fi networks, Bluetooth devices…): glyph,
// title + detail, trailing text/action and a hover/press feel.
Rectangle {
    id: root

    property string icon: ""
    property string title: ""
    property string detail: ""
    property string trailing: ""
    // Accent the row (connected / current).
    property bool current: false
    // Show a spinner dot (connecting…).
    property bool busy: false
    property color iconColor: root.current ? Theme.accent : Theme.fg
    default property alias extra: extraRow.data

    signal clicked
    signal rightClicked

    width: parent ? parent.width : 0
    height: 40
    radius: 10
    color: root.current ? Theme.rgba(Theme.accent, mouse.containsMouse ? 0.22 : 0.14)
        : mouse.containsMouse ? Theme.rgba(Theme.foreground, 0.07) : "transparent"
    border.width: root.current ? 1 : 0
    border.color: Theme.rgba(Theme.accent, 0.35)
    scale: mouse.pressed ? 0.98 : 1
    Behavior on scale {
        NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2 }
    }
    Behavior on color {
        ColorAnimation { duration: 140 }
    }

    Text {
        id: glyph
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 20
        horizontalAlignment: Text.AlignHCenter
        text: root.icon
        color: root.iconColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize + 3
        SequentialAnimation on opacity {
            running: root.busy
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { to: 0.3; duration: 500 }
            NumberAnimation { to: 1; duration: 500 }
        }
    }
    Column {
        anchors.left: glyph.right
        anchors.leftMargin: 10
        anchors.right: trail.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
        Text {
            width: parent.width
            text: root.title
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: root.current
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            visible: root.detail !== ""
            text: root.detail
            color: root.current ? Theme.accent : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeCaption
            elide: Text.ElideRight
        }
    }
    Row {
        id: trail
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.trailing !== ""
            text: root.trailing
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
        Row {
            id: extraRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: m => m.button === Qt.RightButton ? root.rightClicked() : root.clicked()
    }
}
