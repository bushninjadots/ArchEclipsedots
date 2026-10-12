import QtQuick
import qs.theme
import qs.services
import qs.widgets.shared
import qs.widgets.bar.islands

// Weather island: a sky-tinted hero (icon, temperature, conditions, today's
// high/low), the next 12 hours as a temperature curve with icons and rain
// bars, condition tiles (humidity, wind with a direction needle, rain,
// daylight progress) and tomorrow at a glance. The pencil swaps the place
// line for a city search (empty = locate automatically).
IslandPanel {
    id: root
    stateName: "weather"
    islandWidth: 440
    spacing: 8

    readonly property var wx: Weather.data
    readonly property bool hasData: !!root.wx
    readonly property var cur: root.wx?.current ?? ({})
    readonly property var day: root.wx?.daily ?? ({})
    readonly property var hour: root.wx?.hourly ?? ({})
    readonly property string tUnit: "°"
    readonly property string windUnit: root.wx?.current_units?.wind_speed_10m ?? "km/h"
    readonly property color sky: root.hasData ? Weather.background(root.cur.weather_code) : Theme.surfaceActive

    function at(arr, i) {
        return Array.isArray(arr) && i < arr.length ? arr[i] : null;
    }
    function parse(iso) {
        return iso ? new Date(String(iso).replace("T", " ").replace(/-/g, "/")) : null;
    }
    // Next 12 hourly slots starting with the current hour.
    readonly property var hours: {
        const t = root.hour.time;
        if (!Array.isArray(t))
            return [];
        const now = new Date();
        now.setMinutes(0, 0, 0);
        let start = 0;
        for (let i = 0; i < t.length; i++) {
            const d = root.parse(t[i]);
            if (d && d.getTime() >= now.getTime()) {
                start = i;
                break;
            }
        }
        const out = [];
        for (let i = start; i < Math.min(t.length, start + 12); i++) {
            const d = root.parse(t[i]);
            out.push({
                label: i === start ? "Now" : Qt.formatTime(d, "HH"),
                temp: root.hour.temperature_2m?.[i] ?? 0,
                code: root.hour.weather_code?.[i],
                rain: root.hour.precipitation?.[i] ?? 0
            });
        }
        return out;
    }
    // Fraction of today's daylight already gone (0 before sunrise, 1 after).
    readonly property real daylight: {
        const a = root.parse(root.at(root.day.sunrise, 0)), b = root.parse(root.at(root.day.sunset, 0));
        if (!a || !b)
            return 0;
        return Math.max(0, Math.min(1, (Date.now() - a.getTime()) / (b.getTime() - a.getTime())));
    }

    property bool searching: false

    Text {
        visible: !root.hasData
        text: "Weather is loading…"
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    // ---- hero ----
    Rectangle {
        visible: root.hasData
        width: parent.width
        height: 112
        radius: 16
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(root.sky, 1.25) }
            GradientStop { position: 1; color: Qt.darker(root.sky, 1.35) }
        }
        border.width: 1
        border.color: Theme.rgba("#ffffff", 0.10)

        // Big glyph, slightly breathing.
        Text {
            id: bigIcon
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: Weather.icon(root.cur.weather_code)
            color: "white"
            font.family: Theme.fontFamily
            font.pixelSize: 52
            SequentialAnimation on scale {
                loops: Animation.Infinite
                NumberAnimation { to: 1.06; duration: 2200; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 2200; easing.type: Easing.InOutSine }
            }
        }
        Column {
            anchors.left: bigIcon.right
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Text {
                text: Weather.fmt(root.cur.temperature_2m, root.tUnit)
                color: "white"
                font.family: Theme.fontFamily
                font.pixelSize: 34
                font.bold: true
            }
            Text {
                text: Weather.description(root.cur.weather_code)
                color: Theme.rgba("#ffffff", 0.85)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }
        Column {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Row {
                anchors.right: parent.right
                spacing: 6
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{F034E} " + (root.wx?.city ?? "")
                    color: "white"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }
                Rectangle {
                    width: 22
                    height: 22
                    radius: 11
                    color: penMouse.containsMouse ? Theme.rgba("#ffffff", 0.25) : Theme.rgba("#ffffff", 0.12)
                    Text {
                        anchors.centerIn: parent
                        text: root.searching ? "\u{F0156}" : "\u{F03EB}"
                        color: "white"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: penMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.searching = !root.searching
                    }
                }
            }
            Text {
                anchors.right: parent.right
                text: "Feels " + Weather.fmt(root.cur.apparent_temperature, root.tUnit)
                color: Theme.rgba("#ffffff", 0.8)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }
            Text {
                anchors.right: parent.right
                text: "\u{F005D} " + Weather.fmt(root.at(root.day.temperature_2m_max, 0), root.tUnit)
                    + "   \u{F0045} " + Weather.fmt(root.at(root.day.temperature_2m_min, 0), root.tUnit)
                color: Theme.rgba("#ffffff", 0.8)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    // ---- city search (pencil) ----
    Row {
        visible: root.searching
        width: parent.width
        spacing: 6
        AppTextField {
            id: cityField
            width: parent.width - goBtn.width - autoBtn.width - 12
            height: 32
            placeholderText: "City name…"
            onVisibleChanged: if (visible) forceActiveFocus()
            onAccepted: goBtn.clicked()
        }
        AppButton {
            id: goBtn
            width: 54
            height: 32
            cornerRadius: 10
            idleBg: Theme.surfaceActive
            text: "Set"
            onClicked: {
                if (cityField.text.trim() === "")
                    return;
                Weather.setCity(cityField.text);
                cityField.text = "";
                root.searching = false;
            }
        }
        AppButton {
            id: autoBtn
            width: 54
            height: 32
            cornerRadius: 10
            text: "Auto"
            tooltipText: "Locate automatically"
            onClicked: {
                Weather.setCity("");
                root.searching = false;
            }
        }
    }

    // ---- next 12 hours ----
    Rectangle {
        visible: root.hasData && root.hours.length > 1
        width: parent.width
        height: 118
        radius: 14
        color: Theme.rgba(Theme.foreground, 0.04)
        border.width: 1
        border.color: Theme.border

        readonly property real colW: (width - 16) / Math.max(1, root.hours.length)
        readonly property real tMin: Math.min.apply(null, root.hours.map(h => h.temp))
        readonly property real tMax: Math.max.apply(null, root.hours.map(h => h.temp))
        // y of a temperature on the curve band (top 28..64).
        function ty(t) {
            const span = Math.max(1, tMax - tMin);
            return 62 - (t - tMin) / span * 30;
        }

        Canvas {
            id: curve
            anchors.fill: parent
            property var pts: root.hours
            property color tone: Theme.accent
            onPtsChanged: requestPaint()
            onWidthChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const h = curve.pts, n = h.length, box = curve.parent;
                if (n < 2)
                    return;
                const px = i => 8 + box.colW * (i + 0.5);
                ctx.beginPath();
                ctx.moveTo(px(0), box.ty(h[0].temp));
                for (let i = 1; i < n; i++) {
                    const x0 = px(i - 1), x1 = px(i), y0 = box.ty(h[i - 1].temp), y1 = box.ty(h[i].temp);
                    const mx = (x0 + x1) / 2;
                    ctx.bezierCurveTo(mx, y0, mx, y1, x1, y1);
                }
                ctx.strokeStyle = curve.tone;
                ctx.lineWidth = 2;
                ctx.stroke();
                // Soft fill under the curve.
                ctx.lineTo(px(n - 1), 70);
                ctx.lineTo(px(0), 70);
                ctx.closePath();
                const g = ctx.createLinearGradient(0, 30, 0, 70);
                g.addColorStop(0, Qt.rgba(curve.tone.r, curve.tone.g, curve.tone.b, 0.22));
                g.addColorStop(1, Qt.rgba(curve.tone.r, curve.tone.g, curve.tone.b, 0));
                ctx.fillStyle = g;
                ctx.fill();
            }
        }

        Repeater {
            model: root.hours
            delegate: Item {
                required property var modelData
                required property int index
                x: 8 + parent.colW * index
                width: parent.colW
                height: parent.height
                // Temperature above its point on the curve.
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.parent.ty(modelData.temp) - 20
                    text: Math.round(modelData.temp) + "°"
                    color: index === 0 ? Theme.accent : Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeCaption
                    font.bold: index === 0
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.parent.ty(modelData.temp) - 3
                    width: 6
                    height: 6
                    radius: 3
                    color: index === 0 ? Theme.accent : Theme.background
                    border.width: 1.5
                    border.color: Theme.accent
                }
                // Rain bar (mm).
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 74 - height
                    width: 4
                    radius: 2
                    height: Math.min(10, modelData.rain * 5)
                    visible: modelData.rain > 0
                    color: "#64b5f6"
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 76
                    text: Weather.icon(modelData.code)
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 2
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 98
                    text: modelData.label
                    color: index === 0 ? Theme.accent : Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeCaption
                }
            }
        }
    }

    // ---- condition tiles ----
    Row {
        id: tiles
        visible: root.hasData
        width: parent.width
        spacing: 6
        readonly property real tileW: (width - spacing * 3) / 4

        Tile {
            icon: "\u{F058E}"
            label: "Humidity"
            value: Weather.fmt(root.cur.relative_humidity_2m, "%")
            bar: (root.cur.relative_humidity_2m ?? 0) / 100
        }
        Tile {
            label: "Wind"
            value: Weather.fmt(root.cur.wind_speed_10m, "") + " " + root.windUnit
            sub: Weather.windDirection(root.cur.wind_direction_10m)
            // Direction needle instead of a glyph: points where it blows to.
            needle: root.cur.wind_direction_10m ?? -1
        }
        Tile {
            icon: "\u{F054A}"
            label: "Rain today"
            value: Weather.fmt(root.at(root.day.precipitation_sum, 0), " mm")
            sub: (root.at(root.day.precipitation_hours, 0) ?? 0) + " h"
        }
        Tile {
            icon: "\u{F059C}"
            label: "Daylight"
            value: Weather.formatTime(root.at(root.day.sunrise, 0)) + "–" + Weather.formatTime(root.at(root.day.sunset, 0))
            bar: root.daylight
        }
    }

    // ---- tomorrow ----
    Rectangle {
        visible: root.hasData && root.at(root.day.weather_code, 1) !== null
        width: parent.width
        height: 38
        radius: 12
        color: Theme.rgba(Theme.foreground, 0.04)
        border.width: 1
        border.color: Theme.border
        Text {
            id: tmIcon
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: Weather.icon(root.at(root.day.weather_code, 1))
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 4
        }
        Text {
            anchors.left: tmIcon.right
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "Tomorrow · " + Weather.description(root.at(root.day.weather_code, 1))
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: Weather.fmt(root.at(root.day.temperature_2m_max, 1), "°") + " / " + Weather.fmt(root.at(root.day.temperature_2m_min, 1), "°")
                + (root.at(root.day.precipitation_sum, 1) > 0 ? "   \u{F054A} " + Weather.fmt(root.at(root.day.precipitation_sum, 1), " mm") : "")
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    component Tile: Rectangle {
        id: tile
        property string icon: ""
        property string label: ""
        property string value: ""
        property string sub: ""
        // 0..1 progress bar under the value (-1 = none).
        property real bar: -1
        // Wind direction in degrees (-1 = none): draws a needle.
        property real needle: -1
        width: tiles.tileW
        height: 70
        radius: 12
        color: Theme.rgba(Theme.foreground, 0.04)
        border.width: 1
        border.color: Theme.border
        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 9
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Row {
                spacing: 5
                Item {
                    width: 14
                    height: 14
                    Text {
                        visible: tile.needle < 0
                        anchors.centerIn: parent
                        text: tile.icon
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }
                    Text {
                        visible: tile.needle >= 0
                        anchors.centerIn: parent
                        // Meteorological degrees say where wind comes FROM.
                        rotation: tile.needle + 180
                        text: "\u{F0390}"
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        Behavior on rotation {
                            NumberAnimation { duration: 600; easing.type: Easing.OutBack }
                        }
                    }
                }
                Text {
                    text: tile.label
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeCaption
                }
            }
            Text {
                width: parent.width
                text: tile.value
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                visible: tile.sub !== ""
                text: tile.sub
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeCaption
            }
            Rectangle {
                visible: tile.bar >= 0
                width: parent.width
                height: 4
                radius: 2
                color: Theme.rgba(Theme.foreground, 0.10)
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, tile.bar))
                    height: parent.height
                    radius: 2
                    color: Theme.accent
                }
            }
        }
    }
}
