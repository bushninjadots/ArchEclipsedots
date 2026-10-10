pragma ComponentBehavior: Bound
import QtQuick

// Full-year GitHub-style contribution graph.
//
// In:  contributions (var: [{date:"YYYY-MM-DD", count:n}]), year (int),
//      baseCol (color), stops (var: 5 colors), ink (color), dim (color),
//      cellSize (int), cellGap (int), pinnedDate (string).
// Out: cells (var), gridWidth/gridHeight (int), stats (var), monthCols (var).
// Signal: dayClicked(var cell)
Item {
    id: root

    property var contributions: []
    property int year: new Date().getFullYear()
    property color baseCol: "#3d8f24"
    property var stops: ["#c8d8c8", "#9adb7d", "#6fbf4a", "#3d8f24", "#1a6b0f"]
    property color ink: "#e8e8e8"
    property color dim: "#9a9a9a"
    // Tooltip plate (supplied by the host so it follows the theme).
    property color plateCol: "#1c1c1c"
    property color lineCol: "#33ffffff"
    property color textCol: "#f2f2f2"
    property int cellSize: 11
    property int cellGap: 2
    property string pinnedDate: ""

    signal dayClicked(var cell)

    readonly property int leftGutter: 22
    readonly property int topGutter: 14

    readonly property var _weekdayNames: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    readonly property var _monthNames: ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    readonly property int _offset: (new Date(year, 0, 1).getDay() + 6) % 7
    readonly property int _daysInYear: Math.round((new Date(year + 1, 0, 1) - new Date(year, 0, 1)) / 86400000)
    readonly property int _weeks: Math.ceil((_offset + _daysInYear) / 7)
    readonly property int _cellCount: _weeks * 7

    readonly property int plotWidth: _weeks * (cellSize + cellGap) - cellGap
    readonly property int plotHeight: 7 * (cellSize + cellGap) - cellGap

    // Overall (content) size, including the label gutters.
    readonly property int gridWidth: leftGutter + plotWidth
    readonly property int gridHeight: topGutter + plotHeight

    readonly property var cells: _build()

    function _iso(d) {
        var m = d.getMonth() + 1
        var day = d.getDate()
        return d.getFullYear() + "-" + (m < 10 ? "0" : "") + m + "-" + (day < 10 ? "0" : "") + day
    }

    function _build() {
        var byDate = {}
        var contribs = root.contributions || []
        for (var j = 0; j < contribs.length; j++) {
            var e = contribs[j]
            if (e && e.date)
                byDate[e.date] = e.count || 0
        }
        var peak = 1
        for (var key in byDate) {
            if (byDate[key] > peak)
                peak = byDate[key]
        }
        var today = new Date()
        today.setHours(0, 0, 0, 0)
        var list = []
        for (var i = 0; i < root._cellCount; i++) {
            var d = new Date(root.year, 0, 1 + i - root._offset)
            var iso = root._iso(d)
            var inYear = d.getFullYear() === root.year
            var cnt = inYear ? (byDate[iso] || 0) : 0
            var future = d.getTime() > today.getTime()
            var level = cnt === 0 ? 0 : Math.min(4, Math.ceil((cnt / peak) * 4))
            list.push({
                t: d.getTime(), date: iso, n: cnt, future: future, level: level, inYear: inYear,
                weekIdx: Math.floor(i / 7), dayIdx: i % 7
            })
        }
        return list
    }

    readonly property var monthCols: _monthCols()

    function _monthCols() {
        var cols = []
        for (var m = 0; m < 12; m++)
            cols.push(-1)
        var c = root.cells
        for (var i = 0; i < c.length; i++) {
            if (!c[i].inYear)
                continue
            var mo = new Date(c[i].t).getMonth()
            if (cols[mo] === -1)
                cols[mo] = c[i].weekIdx
        }
        return cols
    }

    readonly property var stats: _stats()

    function _stats() {
        var c = root.cells
        var total = 0
        var busyDate = ""
        var busyN = 0
        var run = 0
        var best = 0
        for (var i = 0; i < c.length; i++) {
            var cell = c[i]
            if (!cell.inYear)
                continue
            total += cell.n
            if (cell.n > busyN) {
                busyN = cell.n
                busyDate = cell.date
            }
            if (cell.n > 0) {
                run += 1
                if (run > best)
                    best = run
            } else {
                run = 0
            }
        }
        return { total: total, longestStreak: best, busiestDay: { date: busyDate, count: busyN } }
    }

    function label(iso) {
        if (!iso)
            return ""
        var p = iso.split("-")
        var d = new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10))
        return root._weekdayNames[d.getDay()] + ", " + root._monthNames[d.getMonth()] + " "
                + d.getDate() + ", " + d.getFullYear()
    }

    property var hovered: null

    // Drop the tooltip reference when the underlying data or year changes so it
    // can't linger showing a previous year's date.
    onYearChanged: root.hovered = null
    onContributionsChanged: root.hovered = null

    implicitWidth: gridWidth
    implicitHeight: gridHeight

    // Month labels (top)
    Repeater {
        model: 12
        delegate: Text {
            required property int index
            visible: root.monthCols[index] >= 0
            x: root.leftGutter + root.monthCols[index] * (root.cellSize + root.cellGap)
            y: 0
            text: root._monthNames[index]
            color: root.dim
            font.pixelSize: 9
        }
    }

    // Weekday labels (left): Mon/Wed/Fri on rows 0/2/4
    Repeater {
        model: ["Mon", "", "Wed", "", "Fri", "", ""]
        delegate: Text {
            required property int index
            required property var modelData
            visible: modelData !== ""
            x: 0
            y: root.topGutter + index * (root.cellSize + root.cellGap)
            text: modelData
            color: root.dim
            font.pixelSize: 9
        }
    }

    // The grid
    Item {
        id: grid
        x: root.leftGutter
        y: root.topGutter
        width: root.plotWidth
        height: root.plotHeight

        Repeater {
            model: root.cells
            delegate: Rectangle {
                required property int index
                required property var modelData
                property var c: modelData
                width: root.cellSize
                height: root.cellSize
                radius: 2
                x: c.weekIdx * (root.cellSize + root.cellGap)
                y: c.dayIdx * (root.cellSize + root.cellGap)
                color: (!c.inYear || c.future) ? "transparent" : (root.stops[c.level] !== undefined ? root.stops[c.level] : root.stops[0])
                opacity: 0
                Behavior on opacity { NumberAnimation { duration: 220 } }
                Component.onCompleted: opacity = 1
                border.width: (root.pinnedDate !== "" && c.date === root.pinnedDate) ? 1 : 0
                border.color: root.baseCol

                MouseArea {
                    anchors.fill: parent
                    enabled: c.inYear
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.hovered = parent.c
                    onExited: if (root.hovered === parent.c) root.hovered = null
                    onClicked: root.dayClicked(parent.c)
                }
            }
        }
    }

    // Hover tooltip: an opaque themed plate so it reads over any wallpaper.
    // It sits above the hovered cell and flips below when it would overflow the
    // top edge, clamped horizontally inside the widget.
    readonly property int _tipCellX: root.hovered === null ? 0
        : root.leftGutter + root.hovered.weekIdx * (root.cellSize + root.cellGap)
    readonly property int _tipCellY: root.hovered === null ? 0
        : root.topGutter + root.hovered.dayIdx * (root.cellSize + root.cellGap)

    Rectangle {
        // Soft shadow behind the plate.
        visible: tip.visible
        z: 19
        x: tip.x + 1
        y: tip.y + 2
        width: tip.width
        height: tip.height
        radius: tip.radius
        color: Qt.rgba(0, 0, 0, 0.38)
    }

    Rectangle {
        id: tip
        visible: root.hovered !== null
        z: 20
        radius: 7
        color: root.plateCol
        border.width: 1
        border.color: root.lineCol
        width: tipText.implicitWidth + 18
        height: tipText.implicitHeight + 12
        x: Math.max(0, Math.min(root._tipCellX - 28, root.gridWidth - width))
        y: (root._tipCellY - height - 5 >= 0)
           ? (root._tipCellY - height - 5)
           : Math.min(root._tipCellY + root.cellSize + 5, root.gridHeight - height)
        Text {
            id: tipText
            anchors.centerIn: parent
            color: root.textCol
            font.pixelSize: 11
            text: root.hovered === null ? ""
                  : root.label(root.hovered.date) + "  ·  " + root.hovered.n
                    + (root.hovered.n === 1 ? " contribution" : " contributions")
        }
    }
}
