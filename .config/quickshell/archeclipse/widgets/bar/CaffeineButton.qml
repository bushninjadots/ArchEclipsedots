import QtQuick
import Quickshell.Io
import qs.theme

// Caffeine: keeps the session awake (blocks idle → lock/suspend) through
// systemd-inhibit while lit. The inhibitor process lives exactly as long as
// the toggle is on, so quitting the shell releases it too.
BarIconButton {
    id: root

    property bool awake: false

    icon: root.awake ? "\uF0F4" : "\uF0F4"
    lit: root.awake
    tooltip: root.awake ? "Staying awake · click to allow sleep" : "Keep awake (block idle lock / suspend)"
    onClicked: root.awake = !root.awake

    Process {
        running: root.awake
        command: ["systemd-inhibit", "--what=idle:sleep", "--who=ArchEclipse", "--why=Caffeine (bar)", "--mode=block", "sleep", "infinity"]
    }
}
