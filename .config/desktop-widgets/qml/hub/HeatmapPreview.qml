pragma ComponentBehavior: Bound
import QtQuick
import Eclipse.Ui.Singletons

/**
 * A plain-QML preview of the activity-heatmap desktop widget for the Desktop
 * Widgets settings page. Horizontal shows a full-year GitHub-style contribution
 * graph (month + weekday labels); vertical shows the compact 12-week grid.
 * Fixed sample values -- no live feed. Drawn at its native box with an implicit
 * size; the page scales the whole box to fit.
 */
Item {
    id: root

    property string design: "horizontal"
    property int year: new Date().getFullYear()

    readonly property bool vertical: root.design === "vertical"

    readonly property int pad: 20
    readonly property int cellSize: root.vertical ? 14 : 7
    readonly property int cellGap: 3
    readonly property int cols: 7
    readonly property int leftGutter: root.vertical ? 0 : 18
    readonly property int topGutter: root.vertical ? 0 : 14

    // Full-year geometry (horizontal): Monday-aligned weeks.
    readonly property int offset: (new Date(root.year, 0, 1).getDay() + 6) % 7
    readonly property int daysInYear: Math.round((new Date(root.year + 1, 0, 1) - new Date(root.year, 0, 1)) / 86400000)
    readonly property int weeks: root.vertical ? 12 : Math.ceil((root.offset + root.daysInYear) / 7)

    readonly property int gridCols: root.vertical ? root.cols : root.weeks
    readonly property int gridRows: root.vertical ? root.weeks : root.cols
    readonly property int gridWidth: root.gridCols * (root.cellSize + root.cellGap) - root.cellGap
    readonly property int gridHeight: root.gridRows * (root.cellSize + root.cellGap) - root.cellGap

    readonly property int gridX: root.pad + root.leftGutter
    readonly property int gridY: 64 + root.topGutter

    implicitWidth: root.vertical ? 200 : (root.pad * 2 + root.leftGutter + root.gridWidth)
    implicitHeight: root.vertical ? 400 : (root.gridY + root.gridHeight + root.pad)

    readonly property color ink: Tokens.ink
    readonly property color dim: Tokens.inkDim

    // Deterministic sample activity (0..8) for a given day.
    function sampleCount(d) {
        return (d.getDate() * 7 + (d.getMonth() + 1) * 3 + d.getDay()) % 9
    }

    readonly property var cells: {
        const out = []
        const DAY = 86400000
        const today = new Date()
        today.setHours(0, 0, 0, 0)
        const todayTS = today.getTime()
        function push(d, inYear) {
            const n = inYear ? root.sampleCount(d) : 0
            const future = d.getTime() > todayTS
            const level = n === 0 ? 0 : Math.min(4, Math.ceil((n / 8) * 4))
            out.push({ t: d.getTime(), n: n, future: future, inYear: inYear, level: level })
        }
        if (root.vertical) {
            const since = new Date(today)
            since.setDate(since.getDate() - root.weeks * 7)
            for (let i = 0; i < root.weeks * 7; i++)
                push(new Date(since.getTime() + i * DAY), true)
        } else {
            const first = new Date(root.year, 0, 1 - root.offset)
            const count = root.weeks * 7
            for (let i = 0; i < count; i++) {
                const d = new Date(first.getTime() + i * DAY)
                push(d, d.getFullYear() === root.year)
            }
        }
        return out
    }

    readonly property int total: {
        let s = 0
        const c = root.cells
        for (let i = 0; i < c.length; i++) {
            if (c[i].inYear && !c[i].future) s += c[i].n
        }
        return s
    }

    // Week column (0-based) where each month starts -- for the month labels.
    readonly property var monthCols: {
        const cols = []
        if (root.vertical) return cols
        const jan1 = new Date(root.year, 0, 1).getTime()
        for (let m = 0; m < 12; m++) {
            const first = new Date(root.year, m, 1).getTime()
            const dayIdx = Math.round((first - jan1) / 86400000)
            cols.push(Math.floor((root.offset + dayIdx) / 7))
        }
        return cols
    }

    readonly property var heatStops: [
        Qt.rgba(0.78, 0.86, 0.78, 1),
        Qt.rgba(0.61, 0.83, 0.57, 1),
        Qt.rgba(0.41, 0.73, 0.36, 1),
        Qt.rgba(0.24, 0.57, 0.20, 1),
        Qt.rgba(0.11, 0.41, 0.09, 1)
    ]

    Text {
        x: root.pad; y: 16
        text: "Contributions"
        color: root.ink
        font.family: "Inter"
        font.pixelSize: 18
        font.weight: Font.Medium
    }

    Text {
        x: root.pad; y: 40
        text: root.vertical
            ? (root.total + " contributions in the last 12 weeks")
            : (root.year + " · sample activity")
        color: root.dim
        font.family: "Inter"
        font.pixelSize: 13
        font.weight: Font.Normal
    }

    // Month labels (horizontal only)
    Repeater {
        model: root.vertical ? [] : root.monthCols
        delegate: Text {
            required property int index
            required property var modelData
            x: root.gridX + modelData * (root.cellSize + root.cellGap)
            y: 64
            text: ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"][index]
            color: root.dim
            font.family: "Inter"
            font.pixelSize: 10
        }
    }

    // Weekday labels (horizontal only): Mon / Wed / Fri
    Repeater {
        model: root.vertical ? [] : [0, 2, 4]
        delegate: Text {
            required property int index
            required property var modelData
            x: root.pad
            y: root.gridY + modelData * (root.cellSize + root.cellGap) + root.cellSize / 2 - 5
            text: ["Mon", "Wed", "Fri"][index]
            color: root.dim
            font.family: "Inter"
            font.pixelSize: 10
        }
    }

    Item {
        id: grid
        x: root.gridX
        y: root.gridY
        width: root.gridWidth
        height: root.gridHeight

        Repeater {
            model: root.cells
            delegate: Rectangle {
                required property int index
                required property var modelData
                property var c: modelData
                property int dayIdx: index % root.cols
                property int weekIdx: Math.floor(index / root.cols)
                width: root.cellSize
                height: width
                x: (root.vertical ? dayIdx : weekIdx) * (width + root.cellGap)
                y: (root.vertical ? weekIdx : dayIdx) * (width + root.cellGap)
                radius: Math.max(1, Math.round(width * 0.15))
                color: (!c.inYear || c.future) ? Qt.rgba(0, 0, 0, 0)
                    : (root.heatStops[c.level] || root.heatStops[0])
            }
        }
    }
}
