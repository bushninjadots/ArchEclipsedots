pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import shell.services
import Eclipse.Ui.Singletons as Ui
import "../Singletons"

// GitHub-style activity heatmap widget for the desktop.
// Horizontal = full-year GitHub graph (hover reveals the toolbar).
// Vertical   = compact 12-week grid. Click the username to edit it.

Item {
    id: root

    property real underL: 0
    property string inkColorA: ""
    property real s: 1
    property bool active: true

    // State
    property string displayName: ""
    property bool editing: false
    property string editText: ""
    property bool vertical: false
    property string pinnedDate: ""

    implicitWidth: box.width * root.s
    implicitHeight: box.height * root.s

    // Accept a username, @handle, or a full GitHub profile URL and return the
    // bare login (the fetcher does the same server-side).
    function cleanUser(u) {
        let s = (u || "").trim()
        if (!s) return ""
        s = s.split("?")[0].split("#")[0].replace(/\/+$/, "")
        const m = s.toLowerCase().indexOf("github.com/")
        if (m >= 0) s = s.substring(m + "github.com/".length)
        return s.split("/")[0].replace(/^@/, "").trim()
    }

    // Username: the editor's "GitHub username" setting wins, else whatever the
    // GithubContrib service has stored (user.txt) or resolved.
    function syncName() {
        root.displayName = root.cleanUser(Config.heatmapUsername) || GithubContrib.user || ""
    }

    function applyUser(raw) {
        const u = root.cleanUser(raw)
        // Rewrite a pasted URL/handle in the setting to the clean login.
        if (raw && u && u !== raw)
            Config.set("heatmapUsername", u)
        if (u && GithubContrib.user !== u)
            GithubContrib.setUser(u)
        if (!root.editing)
            root.syncName()
    }

    // Step the selected calendar year within the years the account has data for.
    function stepYear(delta) {
        const ys = GithubContrib.years || []
        let y = GithubContrib.year || Config.heatmapYear || new Date().getFullYear()
        if (ys.length > 0) {
            const idx = ys.indexOf(y)
            y = idx >= 0 ? ys[Math.max(0, Math.min(ys.length - 1, idx + delta))] : ys[ys.length - 1]
        } else {
            y = y + delta
        }
        Config.set("heatmapYear", y)
        GithubContrib.setYear(y)
    }

    Component.onCompleted: {
        vertical = Config.heatmapDesign === "vertical"
        if (!GithubContrib.year)
            GithubContrib.setYear(Config.heatmapYear || new Date().getFullYear())
        root.applyUser(Config.heatmapUsername)
        root.syncName()
    }

    Connections {
        target: GithubContrib
        function onUserChanged() { if (!root.editing) root.syncName() }
    }

    // The editor (Hub) writes the username and layout to Config; follow them
    // live so a saved setting applies without restarting the widgets.
    Connections {
        target: Config
        function onHeatmapDesignChanged() {
            root.vertical = Config.heatmapDesign === "vertical"
        }
        function onHeatmapUsernameChanged() { root.applyUser(Config.heatmapUsername) }
        function onHeatmapYearChanged() { GithubContrib.setYear(Config.heatmapYear) }
    }

    // ---- compact (vertical) geometry ----
    readonly property int weeks: 12
    readonly property int cols: 7
    readonly property int cellSize: root.vertical ? 10 : 14
    readonly property int cellGap: 2
    readonly property int step: root.cellSize + root.cellGap
    // Horizontal (GitHub-style): 12 weeks across x 7 days down.
    // Vertical: 7 days across x 12 weeks down.
    readonly property int gridCols: root.vertical ? root.cols : root.weeks
    readonly property int gridRows: root.vertical ? root.weeks : root.cols
    readonly property int gridW: root.gridCols * root.step - root.cellGap
    readonly property int gridH: root.gridRows * root.step - root.cellGap

    // Live data from the shared GithubContrib service (shell.services).
    readonly property var contributions: GithubContrib.data
    readonly property int total: GithubContrib.total
    readonly property bool loading: GithubContrib.loading
    readonly property string feedError: GithubContrib.error

    readonly property int pinnedCount: {
        if (root.pinnedDate === "") return 0
        const arr = GithubContrib.data || []
        for (let i = 0; i < arr.length; i++)
            if (arr[i].date === root.pinnedDate) return arr[i].count
        return 0
    }

    // Compact cells: the last 12 weeks.
    readonly property var cells: {
        const out = []
        const today = new Date()
        today.setHours(0,0,0,0)
        const since = new Date(today)
        since.setDate(since.getDate() - root.weeks * 7)
        const DAY = 86400000
        const byDate = {}
        for (let i = 0; i < root.contributions.length; i++) {
            byDate[root.contributions[i].date] = root.contributions[i].count
        }
        let max = 0
        for (const k in byDate) { if (byDate[k] > max) max = byDate[k] }
        const peak = max || 1
        for (let i = 0; i < root.weeks * 7; i++) {
            const t = since.getTime() + i * DAY
            const d = new Date(t)
            const iso = d.getFullYear() + "-" +
                ("0" + (d.getMonth()+1)).slice(-2) + "-" +
                ("0" + d.getDate()).slice(-2)
            const n = byDate[iso] || 0
            const future = t > today.getTime()
            const level = n === 0 ? 0 : Math.min(4, Math.ceil((n/peak)*4))
            out.push({t, n, future, level})
        }
        return out
    }

    // Colors — dynamic: seeded from the pinned widget colour, else the live
    // wallpaper accent. Levels 1-4 are an alpha ramp of the seed; empty cells
    // are a faint neutral ink wash so real contributions stand out.
    readonly property color seedCol: (root.inkColorA && root.inkColorA.length > 0)
                                     ? root.inkColorA : Theme.accent
    readonly property color inkCol: Theme.inkOn2(root.underL, root.inkColorA)
    readonly property color baseCol: root.seedCol
    readonly property var stops: {
        const c = root.seedCol
        const k = root.inkCol
        return [
            Qt.rgba(k.r, k.g, k.b, 0.10),
            Qt.rgba(c.r, c.g, c.b, 0.32),
            Qt.rgba(c.r, c.g, c.b, 0.55),
            Qt.rgba(c.r, c.g, c.b, 0.78),
            Qt.rgba(c.r, c.g, c.b, 1.00)
        ]
    }

    Item {
        id: box
        readonly property int pad: 8
        // Reserved top strip: shows the title at rest and the toolbar on hover —
        // never both at once, so they can't overlap.
        readonly property int hStrip: 46
        width: root.vertical ? 160 : (graph.gridWidth + box.pad * 2)
        height: root.vertical ? (root.gridH + 64) : (box.hStrip + graph.gridHeight + box.pad)

        readonly property color ink: Theme.inkOn2(root.underL, root.inkColorA)
        readonly property color dim: Theme.inkDimOn2(root.underL, root.inkColorA)

        // Tracks the cursor anywhere over the widget so the toolbar can reveal.
        HoverHandler { id: rootHover }

        // ================= VERTICAL (compact 12-week) =================
        Item {
            anchors.fill: parent
            visible: root.vertical

            // Header: username + toggle
            Row {
                x: 8; y: 6
                spacing: 6

                Text {
                    text: root.displayName
                    color: box.ink
                    font.family: "Inter"
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.editText = root.displayName
                            root.editing = true
                        }
                    }
                }

                TextInput {
                    visible: root.editing
                    x: 8
                    y: 6
                    width: 90
                    height: 20
                    text: root.editText
                    color: box.ink
                    font.family: "Inter"
                    font.pixelSize: 11
                    selectByMouse: true
                    activeFocusOnPress: true
                    focus: root.editing
                    Keys.onEnterPressed: {
                        const u = root.cleanUser(text)
                        if (u) {
                            root.editText = u
                            root.displayName = u
                            root.editing = false
                            Config.set("heatmapUsername", u)
                            GithubContrib.setUser(u)
                        }
                    }
                    Keys.onEscapePressed: root.editing = false
                }

                Item { width: 4; height: 1 }

                Text {
                    text: "⊞"
                    color: box.ink
                    font.pixelSize: 12
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.vertical = false
                            Config.set("heatmapDesign", "horizontal")
                        }
                    }
                }
            }

            // Title
            Text {
                x: 8; y: 26
                text: "Contributions"
                color: box.ink
                font.family: "Inter"
                font.pixelSize: 12
                font.weight: Font.Medium
            }

            Text {
                x: 8; y: 40
                text: root.displayName === "" ? "set your GitHub username"
                    : (root.loading ? "loading…"
                    : (root.feedError ? "contributions unavailable"
                    : root.total + " this year"))
                color: box.dim
                font.family: "Inter"
                font.pixelSize: 10
            }

            // Grid
            Item {
                id: grid
                x: 8
                y: 54
                width: root.gridW
                height: root.gridH
                property real cw: root.cellSize
                property real ch: root.cellSize
                property real gap: root.cellGap

                Repeater {
                    model: root.cells
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        property var c: modelData
                        // Each week is 7 consecutive days. Horizontal lays weeks
                        // left-to-right (days stacked down); vertical stacks weeks
                        // top-to-bottom (days run across).
                        property int dayIdx: index % root.cols
                        property int weekIdx: Math.floor(index / root.cols)
                        width: grid.cw
                        height: grid.ch
                        x: (root.vertical ? dayIdx : weekIdx) * (grid.cw + grid.gap)
                        y: (root.vertical ? weekIdx : dayIdx) * (grid.cw + grid.gap)
                        radius: Math.max(1, Math.round(grid.cw * 0.2))
                        color: c.future ? "transparent" : (root.stops[c.level] || root.stops[0])
                    }
                }
            }
        }

        // ================= HORIZONTAL (full year) =================
        Item {
            anchors.fill: parent
            visible: !root.vertical

            Text {
                id: hTitle
                x: box.pad
                y: Math.round((box.hStrip - implicitHeight) / 2)
                text: "Contributions"
                color: box.ink
                font.family: "Inter"
                font.pixelSize: 12
                font.weight: Font.Medium
                // Fades out while the toolbar plate takes over the strip.
                opacity: rootHover.hovered ? 0.0 : 1.0
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }

            Text {
                anchors.right: parent.right
                anchors.rightMargin: box.pad
                y: Math.round((box.hStrip - implicitHeight) / 2)
                text: "T"
                color: box.ink
                font.pixelSize: 12
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -3
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.vertical = true
                        Config.set("heatmapDesign", "vertical")
                    }
                }
            }

            HeatmapGraph {
                id: graph
                x: box.pad
                y: box.hStrip
                contributions: root.contributions
                year: GithubContrib.year || Config.heatmapYear || new Date().getFullYear()
                baseCol: root.baseCol
                stops: root.stops
                ink: box.ink
                dim: box.dim
                plateCol: Qt.rgba(Theme.cardTop.r, Theme.cardTop.g, Theme.cardTop.b, 0.97)
                lineCol: Theme.line
                textCol: Theme.ink
                pinnedDate: root.pinnedDate
                onDayClicked: function(c) {
                    root.pinnedDate = (root.pinnedDate === c.date) ? "" : c.date
                }
            }

            // Hover-revealed controls on an opaque plate inside the reserved
            // strip, so no title or cell shows through them.
            Rectangle {
                z: 4
                x: toolbarPlate.x + 1
                y: toolbarPlate.y + 2
                width: toolbarPlate.width
                height: toolbarPlate.height
                radius: toolbarPlate.radius
                color: Qt.rgba(0, 0, 0, 0.38)
                opacity: toolbarPlate.opacity
            }

            Rectangle {
                id: toolbarPlate
                x: box.pad
                y: Math.round((box.hStrip - height) / 2)
                z: 5
                width: toolbar.implicitWidth + 18
                height: toolbar.implicitHeight + 10
                radius: Theme.radiusTile
                color: Qt.rgba(Theme.cardTop.r, Theme.cardTop.g, Theme.cardTop.b, 0.97)
                border.width: 1
                border.color: Theme.line
                opacity: rootHover.hovered ? 1.0 : 0.0
                // Inert until revealed: opacity 0 alone still accepts clicks.
                enabled: rootHover.hovered
                Behavior on opacity { NumberAnimation { duration: 150 } }

                HeatmapToolbar {
                    id: toolbar
                    anchors.centerIn: parent
                    displayName: root.displayName
                    year: GithubContrib.year || Config.heatmapYear || new Date().getFullYear()
                    years: GithubContrib.years
                    total: root.total
                    loading: root.loading
                    stats: graph.stats
                    pinned: root.pinnedDate !== ""
                    pinnedDate: root.pinnedDate
                    pinnedCount: root.pinnedCount
                    ink: box.ink
                    dim: box.dim
                    onUserEdited: function(name) { root.applyUser(name) }
                    onYearStep: function(d) { root.stepYear(d) }
                    onSyncRequested: GithubContrib.forceRefresh()
                }
            }
        }
    }
}
