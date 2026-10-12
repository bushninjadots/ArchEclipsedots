import QtQuick
import qs.theme

// Compact on/off switch for island headers.
Item {
    id: root

    property bool checked: false
    property bool busy: false
    signal toggled(bool on)

    implicitWidth: 40
    implicitHeight: 22
    width: implicitWidth
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? Theme.rgba(Theme.accent, 0.85) : Theme.rgba(Theme.foreground, 0.12)
        border.width: 1
        border.color: root.checked ? Theme.accent : Theme.border
        Behavior on color {
            ColorAnimation { duration: 160 }
        }
        Rectangle {
            width: parent.height - 6
            height: width
            radius: width / 2
            y: 3
            x: root.checked ? parent.width - width - 3 : 3
            color: root.checked ? Theme.background : Theme.fg
            opacity: root.busy ? 0.5 : 1
            Behavior on x {
                NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
