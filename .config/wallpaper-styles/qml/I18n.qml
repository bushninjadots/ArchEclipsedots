pragma Singleton
import QtQuick
import Quickshell

// Text helper kept from the original UI so its strings stay wrapped: English
// only, so tr() returns the text unchanged.
Singleton {
    readonly property bool rtl: false
    readonly property int dir: Qt.LeftToRight
    function tr(s) { return s; }
}
