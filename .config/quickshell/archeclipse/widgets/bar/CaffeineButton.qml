import QtQuick
import qs.theme
import qs.services

// Keep-awake toggle (shared Caffeine service, also in the command center).
BarIconButton {
    id: root

    icon: ""
    lit: Caffeine.awake
    tooltip: Caffeine.awake ? "Staying awake · click to allow sleep" : "Keep awake (block idle lock / suspend)"
    onClicked: Caffeine.toggle()
}
