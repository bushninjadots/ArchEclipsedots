import QtQuick
import qs.theme
import qs.widgets.shared

// Shared bar action button: a glyph (+ optional label) with one consistent
// feel — hover tint, a springy press dip, a soft accent "lit" state for
// toggles that are on, an optional badge and a tooltip. Every new bar widget
// is built on it so clicking anything on the bar answers the same way.
Item {
    id: root

    property string icon: ""
    property string label: ""
    property string tooltip: ""
    // Toggle/state highlight (accent glyph + tinted backing).
    property bool lit: false
    // Alert tint (recording, muted mic…): overrides lit.
    property bool alert: false
    property color alertColor: "#ef5350"
    // Small count/dot in the corner ("" = none, "•" = dot).
    property string badge: ""
    property int iconSize: Theme.fontSize + 1
    property int pad: 8

    signal clicked
    signal rightClicked
    signal middleClicked
    signal wheel(int delta)

    readonly property bool hovered: mouse.containsMouse
    readonly property bool pressed: mouse.pressed

    implicitWidth: row.implicitWidth + root.pad * 2
    implicitHeight: Theme.barContentHeight
    width: implicitWidth
    height: implicitHeight

    readonly property color tone: root.alert ? root.alertColor : (root.lit ? Theme.accent : Theme.fg)

    // Backing: invisible at rest, a tint on hover, accent-tinted when lit.
    Rectangle {
        id: backing
        anchors.fill: parent
        radius: Math.min(Theme.radius, height / 2)
        color: root.alert ? Qt.rgba(root.alertColor.r, root.alertColor.g, root.alertColor.b, root.hovered ? 0.28 : 0.18)
            : root.lit ? Theme.rgba(Theme.accent, root.hovered ? 0.26 : 0.16)
            : root.hovered ? Theme.surfaceHover : "transparent"
        Behavior on color {
            CAnim {}
        }
    }

    // Press ripple: a quick accent bloom from the centre.
    Rectangle {
        id: ripple
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        radius: backing.radius
        color: Theme.accent
        opacity: 0
        scale: 0.6
        ParallelAnimation {
            id: rippleAnim
            NumberAnimation { target: ripple; property: "opacity"; from: 0.35; to: 0; duration: 380; easing.type: Easing.OutCubic }
            NumberAnimation { target: ripple; property: "scale"; from: 0.6; to: 1.08; duration: 380; easing.type: Easing.OutCubic }
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5
        // Springy press dip.
        scale: root.pressed ? 0.88 : 1
        Behavior on scale {
            NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon !== ""
            text: root.icon
            color: root.tone
            font.family: Theme.fontFamily
            font.pixelSize: root.iconSize
            Behavior on color {
                CAnim {}
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.label !== ""
            text: root.label
            color: root.alert ? root.alertColor : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }
    }

    // Badge.
    Rectangle {
        visible: root.badge !== ""
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 2
        anchors.topMargin: 2
        height: root.badge === "•" ? 6 : 12
        width: root.badge === "•" ? 6 : Math.max(12, badgeText.implicitWidth + 6)
        radius: height / 2
        color: Theme.accent
        Text {
            id: badgeText
            anchors.centerIn: parent
            visible: root.badge !== "•"
            text: root.badge
            color: Theme.background
            font.pixelSize: 8
            font.bold: true
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: rippleAnim.restart()
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                root.rightClicked();
            else if (mouse.button === Qt.MiddleButton)
                root.middleClicked();
            else
                root.clicked();
        }
        onWheel: wheel => root.wheel(wheel.angleDelta.y)
    }

    AppTooltip {
        text: root.tooltip
        visible: root.tooltip !== "" && root.hovered && !root.pressed
    }
}
