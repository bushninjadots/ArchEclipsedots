pragma ComponentBehavior: Bound
import QtQuick

// Hover-revealed control strip for the heatmap widget.
// Row 1: username (click to edit) · year stepper · refresh
// Row 2: status / stats text
Item {
    id: root

    property string displayName: ""
    property int year: new Date().getFullYear()
    property var years: []
    property int total: 0
    property bool loading: false
    property var stats: null
    property bool pinned: false
    property string pinnedDate: ""
    property int pinnedCount: 0
    property color ink: "#e8e8e8"
    property color dim: "#9a9a9a"

    signal userEdited(string name)
    signal yearStep(int delta)
    signal syncRequested()

    property bool editing: false

    implicitWidth: col.implicitWidth
    implicitHeight: col.implicitHeight

    Column {
        id: col
        spacing: 2

        Row {
            spacing: 10

            // ---- username (click to edit) ----
            Item {
                id: nameBox
                width: nameText.width
                height: nameText.height
                visible: !root.editing
                Text {
                    id: nameText
                    text: root.displayName === "" ? "set username" : root.displayName
                    color: root.displayName === "" ? root.dim : root.ink
                    font.pixelSize: 12
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        input.text = root.displayName
                        root.editing = true
                        input.forceActiveFocus()
                    }
                }
            }
            TextInput {
                id: input
                visible: root.editing
                width: 150
                color: root.ink
                font.pixelSize: 12
                activeFocusOnPress: true
                clip: true
                onEditingFinished: root.editing = false
                Keys.onReturnPressed: {
                    root.userEdited(text.trim())
                    root.editing = false
                }
                Keys.onEnterPressed: {
                    root.userEdited(text.trim())
                    root.editing = false
                }
                Keys.onEscapePressed: root.editing = false
            }

            Text { text: "·"; color: root.dim; font.pixelSize: 12 }

            // ---- year stepper ----
            Row {
                spacing: 4
                Text {
                    text: "‹"
                    color: root.ink
                    font.pixelSize: 13
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -3
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.yearStep(-1)
                    }
                }
                Text {
                    text: root.year
                    color: root.ink
                    font.pixelSize: 12
                }
                Text {
                    text: "›"
                    color: root.ink
                    font.pixelSize: 13
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -3
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.yearStep(1)
                    }
                }
            }

            Text { text: "·"; color: root.dim; font.pixelSize: 12 }

            // ---- refresh ----
            Text {
                text: "↻"
                color: root.ink
                opacity: root.loading ? 0.4 : 1.0
                font.pixelSize: 13
                Behavior on opacity { NumberAnimation { duration: 150 } }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -3
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.syncRequested()
                }
            }
        }

        Text {
            id: status
            color: root.dim
            font.pixelSize: 10
            text: {
                if (root.pinned && root.pinnedDate !== "")
                    return root.pinnedDate + " · " + root.pinnedCount
                        + (root.pinnedCount === 1 ? " contribution" : " contributions")
                if (root.stats && root.stats.total > 0 && root.stats.busiestDay)
                    return root.stats.longestStreak + "d streak · busiest "
                        + root.stats.busiestDay.date + " (" + root.stats.busiestDay.count + ")"
                if (root.displayName === "")
                    return "set your GitHub username"
                if (root.loading)
                    return "loading…"
                return root.total > 0 ? root.total + " this year" : "no contributions"
            }
        }
    }
}
