import QtQuick
import qs.theme
import qs.services

// Compact up/down bandwidth readout used by both bar styles' centre/core
// zones. Extracted from the inline Text rows that used to live in
// DefaultBar.qml and PillBar.qml so the registry can host it anywhere.
//
// `hideWhenMedia` is true for the pill core, where the music widget takes the
// slot while a real track plays.
Row {
    id: root

    property bool hideWhenMedia: false

    spacing: 4
    visible: !root.hideWhenMedia || BarWidgets.firstPlayable === null

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: BarWidgets.fmtSpeed(SysInfo.bandwidth[0] * 1024)
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "\uf062"
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
    }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: BarWidgets.fmtSpeed(SysInfo.bandwidth[1] * 1024)
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "\uf063"
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
    }
}
