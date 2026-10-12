import QtQuick
import QtQuick.Shapes
import qs.theme
import qs.services
import qs.widgets.shared

// Shared system-resources content — single source of truth used by both
// the bar's SystemMonitorIsland and the right panel's SystemResourcesWidget.
// One tile per resource (CPU, RAM, each GPU): a ring gauge with the load in
// its centre, two detail lines (temperature chip coloured by heat) and a
// sparkline of the last ~80 s. Width-driven grid: all tiles in one row when
// there's room, else two columns, else one.
Column {
    id: root
    spacing: 10

    readonly property var stats: SysInfo.systemResources
    readonly property var gpus: stats?.gpus ?? []
    readonly property real cpuFrac: (stats?.cpuLoad ?? null) !== null ? Math.max(0, Math.min(1, stats.cpuLoad / 100)) : 0
    readonly property real ramFrac: (stats?.ramUsedGB && stats?.ramTotalGB) ? Math.max(0, Math.min(1, stats.ramUsedGB / stats.ramTotalGB)) : 0
    readonly property int totalCards: 2 + root.gpus.length
    readonly property int columns: width >= root.totalCards * 128 ? root.totalCards : (width >= 260 ? 2 : 1)

    function fmt(v, digits, suffix) {
        if (v === null || v === undefined || (typeof v === "number" && isNaN(v)))
            return "—";
        return Number(v).toFixed(digits) + (suffix ?? "");
    }
    // Calm accent below 60%, warm toward 85%, hot above.
    function loadColor(f) {
        return f >= 0.85 ? "#ef5350" : f >= 0.6 ? "#ffb74d" : Theme.accent;
    }
    function tempColor(t) {
        if (t === null || t === undefined)
            return Theme.muted;
        return t >= 85 ? "#ef5350" : t >= 70 ? "#ffb74d" : "#81c784";
    }

    // ---- header ----
    Item {
        width: parent.width
        height: 22
        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{F0EE0}  System"
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeLarge
            font.bold: true
        }
        Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 18
            width: upd.implicitWidth + 14
            radius: 9
            color: Theme.rgba(Theme.foreground, 0.06)
            Row {
                id: upd
                anchors.centerIn: parent
                spacing: 5
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 5
                    height: 5
                    radius: 3
                    color: root.stats ? "#81c784" : Theme.muted
                    SequentialAnimation on opacity {
                        running: !!root.stats
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 900 }
                        NumberAnimation { to: 1; duration: 900 }
                    }
                }
                Text {
                    text: root.stats ? "live · " + (root.stats.updatedAt || "--") : "collecting…"
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeCaption
                }
            }
        }
    }

    Grid {
        id: grid
        visible: !!root.stats
        width: parent.width
        columns: root.columns
        spacing: 8
        readonly property real tileW: (width - spacing * (columns - 1)) / columns

        Tile {
            icon: "\u{F0EE0}"
            label: root.stats?.cpuLabel || "CPU"
            frac: root.cpuFrac
            history: SysInfo.history.cpu
            line1: root.fmt(root.stats?.clockGHz, 2, " GHz")
            line2: "load " + root.fmt(root.stats?.cpuLoad, 0, "%")
            temp: root.stats?.cpuTempC ?? null
        }
        Tile {
            icon: "\u{F035B}"
            label: "Memory"
            frac: root.ramFrac
            history: SysInfo.history.ram
            line1: root.fmt(root.stats?.ramUsedGB, 1, "") + " / " + root.fmt(root.stats?.ramTotalGB, 0, " GB")
            line2: root.fmt(root.stats?.ramFreeGB, 1, " GB free")
        }
        Repeater {
            model: root.gpus
            delegate: Tile {
                required property var modelData
                required property int index
                icon: "\u{F08AE}"
                label: modelData.label || "GPU"
                frac: (modelData.load ?? null) !== null ? Math.max(0, Math.min(1, modelData.load / 100)) : 0
                history: index === 0 ? SysInfo.history.gpu : []
                line1: modelData.memoryUsedGB !== null && modelData.memoryUsedGB !== undefined
                    ? root.fmt(modelData.memoryUsedGB, 2, "") + (modelData.memoryTotalGB ? " / " + root.fmt(modelData.memoryTotalGB, 1, " GB") : " GB") : "—"
                line2: "load " + root.fmt(modelData.load, 0, "%")
                temp: modelData.tempC ?? null
            }
        }
    }

    // ---- one resource tile ----
    component Tile: Rectangle {
        id: tile
        property string icon: ""
        property string label: ""
        property real frac: 0
        property var history: []
        property string line1: ""
        property string line2: ""
        property var temp: null
        readonly property color tone: root.loadColor(tile.frac)

        width: grid.tileW
        height: col.implicitHeight + 20
        radius: 12
        color: Theme.rgba(Theme.foreground, 0.04)
        border.width: 1
        border.color: Theme.rgba(tile.tone, 0.25)
        Behavior on border.color {
            ColorAnimation { duration: 300 }
        }

        Column {
            id: col
            anchors.top: parent.top
            anchors.topMargin: 10
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 8

            Text {
                width: parent.width
                text: tile.icon + "  " + tile.label
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                elide: Text.ElideRight
            }

            // Ring gauge.
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 76
                height: 76
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: Theme.rgba(Theme.foreground, 0.10)
                        strokeWidth: 7
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: 38
                            centerY: 38
                            radiusX: 33
                            radiusY: 33
                            startAngle: 135
                            sweepAngle: 270
                        }
                    }
                    ShapePath {
                        strokeColor: tile.tone
                        strokeWidth: 7
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: 38
                            centerY: 38
                            radiusX: 33
                            radiusY: 33
                            startAngle: 135
                            sweepAngle: Math.max(0.5, 270 * tile.shown)
                        }
                    }
                }
                Column {
                    anchors.centerIn: parent
                    spacing: -2
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Math.round(tile.shown * 100)
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 20
                        font.bold: true
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "%"
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeCaption
                    }
                }
            }

            // Details: value line + temperature chip.
            Item {
                width: parent.width
                height: 18
                Text {
                    anchors.left: parent.left
                    anchors.right: tempChip.visible ? tempChip.left : parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    text: tile.line1
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeCaption
                    elide: Text.ElideRight
                }
                Rectangle {
                    id: tempChip
                    visible: tile.temp !== null
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 16
                    width: tempText.implicitWidth + 10
                    radius: 8
                    color: Theme.rgba(root.tempColor(tile.temp), 0.16)
                    Text {
                        id: tempText
                        anchors.centerIn: parent
                        text: "\u{F050F}" + root.fmt(tile.temp, 0, "°")
                        color: root.tempColor(tile.temp)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeCaption
                    }
                }
            }
            Text {
                // Always takes its line so every tile has the same height.
                width: parent.width
                text: tile.line2 !== "" ? tile.line2 : " "
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeCaption
                elide: Text.ElideRight
            }

            // Sparkline of recent load.
            Canvas {
                id: spark
                width: parent.width
                height: 26
                visible: tile.history.length > 1
                property var pts: tile.history
                property color tone: tile.tone
                onPtsChanged: requestPaint()
                onToneChanged: requestPaint()
                onWidthChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const p = spark.pts, n = p.length;
                    if (n < 2)
                        return;
                    const max = SysInfo.historySize - 1;
                    const x = i => spark.width * (i + (max - (n - 1))) / max;
                    const y = v => spark.height - 2 - v * (spark.height - 4);
                    ctx.beginPath();
                    ctx.moveTo(x(0), spark.height);
                    for (let i = 0; i < n; i++)
                        ctx.lineTo(x(i), y(p[i]));
                    ctx.lineTo(x(n - 1), spark.height);
                    ctx.closePath();
                    const g = ctx.createLinearGradient(0, 0, 0, spark.height);
                    g.addColorStop(0, Qt.rgba(spark.tone.r, spark.tone.g, spark.tone.b, 0.35));
                    g.addColorStop(1, Qt.rgba(spark.tone.r, spark.tone.g, spark.tone.b, 0));
                    ctx.fillStyle = g;
                    ctx.fill();
                    ctx.beginPath();
                    for (let i = 0; i < n; i++) {
                        if (i === 0)
                            ctx.moveTo(x(i), y(p[i]));
                        else
                            ctx.lineTo(x(i), y(p[i]));
                    }
                    ctx.strokeStyle = spark.tone;
                    ctx.lineWidth = 1.5;
                    ctx.stroke();
                }
            }
        }

        // Smoothed value the ring and number show.
        property real shown: 0
        Behavior on shown {
            NumberAnimation { duration: 700; easing.type: Easing.OutCubic }
        }
        onFracChanged: tile.shown = tile.frac
        Component.onCompleted: tile.shown = tile.frac
    }
}
