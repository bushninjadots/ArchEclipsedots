pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Keep-awake switch shared by the bar's caffeine button and the command
// center: while on, a systemd-inhibit holds off idle lock and suspend.
Singleton {
    id: root

    property bool awake: false
    function toggle() {
        root.awake = !root.awake;
    }

    Process {
        running: root.awake
        command: ["systemd-inhibit", "--what=idle:sleep", "--who=ArchEclipse", "--why=Caffeine", "--mode=block", "sleep", "infinity"]
    }
}
