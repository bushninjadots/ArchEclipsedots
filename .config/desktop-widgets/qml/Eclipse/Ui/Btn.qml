import QtQuick
import "Singletons"

Rectangle {
    id: btn
    property alias text: lab.text
    property bool primary: false
    property bool armed: true
    // A toggle's on-state, distinct from `armed` (which only gates whether the
    // button may act): a checked toggle is filled like a primary but stays
    // clickable, so pressing it again turns it back off.
    property bool checked: false
    property bool compact: false
    signal act()

    activeFocusOnTab: armed
    function activate() { if (armed) act() }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            activate();
            event.accepted = true;
        }
    }

    implicitWidth: lab.width + (compact ? 20 : 30)
    implicitHeight: compact ? 24 : 32
    radius: Tokens.radius
    // 0.5, not 0.3: a control that cannot act must still be legible as itself
    // (the reader needs to see what is there and why it is inert), while the
    // dimming keeps it from reading as available.
    opacity: armed ? 1 : 0.5
    color: (primary || checked) && armed ? Tokens.bone : (tap.pressed && armed ? Tokens.tint16 : (bh.hovered && armed ? Tokens.tint10 : "transparent"))
    border.width: Tokens.border
    border.color: activeFocus ? Tokens.bone : ((primary || checked) && armed ? Tokens.bone : (bh.hovered && armed ? Tokens.lineStrong : Tokens.line))
    Behavior on color { ColorAnimation { duration: Tokens.snap } }
    Behavior on opacity { NumberAnimation { duration: Tokens.snap } }
    Behavior on border.color { ColorAnimation { duration: Tokens.snap } }

    Text {
        id: lab
        anchors.centerIn: parent
        color: ((btn.primary || btn.checked) && btn.armed) ? Tokens.inkOnBone : Tokens.ink
        font.family: Tokens.ui
        font.pixelSize: btn.compact ? 10 : 11
        font.weight: Font.Medium
        font.letterSpacing: Tokens.trackLabel
    }
    HoverHandler { id: bh; enabled: btn.armed; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; enabled: btn.armed; onTapped: btn.act() }
}
