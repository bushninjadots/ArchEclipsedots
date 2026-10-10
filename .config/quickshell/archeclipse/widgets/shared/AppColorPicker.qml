import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.theme

// A settings row that picks a colour without numbers: the row shows a swatch;
// tap it to open a palette of ready swatches (the wallpaper theme's own colours
// first), a square to drag for how light/vivid it is, and a rainbow bar for
// the colour itself. Every move applies live through `picked`. The hex stays
// visible (and typeable) for anyone who has one.
Column {
    id: root

    property string label: ""
    property string value: "#ffffff"
    signal picked(string hex)

    property bool open: false
    spacing: 6

    // Working HSV, seeded from `value` when the picker opens; a grey keeps the
    // last hue so dragging saturation back up does not snap to red.
    property real hue: 0
    property real sat: 1
    property real val: 1
    function seed() {
        const c = Qt.color(root.value);
        if (c.hsvHue >= 0) root.hue = c.hsvHue;
        root.sat = c.hsvSaturation;
        root.val = c.hsvValue;
    }
    function hexOf(c) {
        const h = x => Math.round(Math.max(0, Math.min(1, x)) * 255).toString(16).padStart(2, "0");
        return "#" + h(c.r) + h(c.g) + h(c.b);
    }
    function commit() { root.picked(root.hexOf(Qt.hsva(root.hue, root.sat, root.val, 1))); }
    function choose(c) {
        const q = Qt.color(c);
        if (q.hsvHue >= 0) root.hue = q.hsvHue;
        root.sat = q.hsvSaturation;
        root.val = q.hsvValue;
        root.picked(root.hexOf(q));
    }
    onOpenChanged: if (open) seed()
    Component.onCompleted: if (open) seed()

    RowLayout {
        width: parent.width
        spacing: 8
        Label {
            font.pixelSize: Theme.fontSize
            text: root.label
            color: Theme.fg
            Layout.fillWidth: true
        }
        Rectangle {
            Layout.preferredWidth: 160
            Layout.preferredHeight: 26
            radius: 6
            color: swatchHover.hovered ? Theme.surfaceHover : "transparent"
            border.color: root.open ? Theme.accent : Theme.border
            border.width: 1
            Row {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 8
                Rectangle {
                    width: 34
                    height: parent.height
                    radius: 4
                    color: root.value
                    border.color: Theme.border
                    border.width: 1
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.value.toUpperCase()
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: root.open ? "▴" : "▾"
                color: Theme.fgDim
                font.pixelSize: 10
            }
            HoverHandler { id: swatchHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.open = !root.open }
        }
    }

    Rectangle {
        width: parent.width
        visible: root.open
        height: visible ? pickerCol.implicitHeight + 16 : 0
        radius: Theme.radius
        color: Theme.rgba(Theme.background, 0.5)
        border.color: Theme.border
        border.width: 1

        Column {
            id: pickerCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 8

            // Ready swatches: the wallpaper theme's colours, then a spread of
            // everyday colours.
            Flow {
                width: parent.width
                spacing: 5
                Repeater {
                    model: [Theme.accent, Theme.color1, Theme.color2, Theme.color3, Theme.color4,
                            Theme.color6, Theme.color7, Theme.foreground,
                            "#ff5c5c", "#ff9f43", "#ffd84d", "#7bd88f", "#3ddbd9", "#4da3ff",
                            "#7c5cff", "#c77dff", "#ff6fb5", "#ffffff", "#9aa0a6", "#1e1e24"]
                    Rectangle {
                        required property var modelData
                        width: 20
                        height: 20
                        radius: 10
                        color: modelData
                        border.width: root.value.toLowerCase() === String(modelData).toLowerCase() ? 2 : 1
                        border.color: root.value.toLowerCase() === String(modelData).toLowerCase() ? Theme.fg : Theme.border
                        scale: dotHover.hovered ? 1.15 : 1
                        Behavior on scale { NumberAnimation { duration: 100 } }
                        HoverHandler { id: dotHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.choose(modelData) }
                    }
                }
            }

            // Shade square: left→right more vivid, top→bottom darker.
            Item {
                width: parent.width
                height: 110
                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "white" }
                        GradientStop { position: 1; color: Qt.hsva(root.hue, 1, 1, 1) }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    gradient: Gradient {
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 1; color: "black" }
                    }
                }
                Rectangle {
                    x: root.sat * parent.width - width / 2
                    y: (1 - root.val) * parent.height - height / 2
                    width: 14
                    height: 14
                    radius: 7
                    color: Qt.hsva(root.hue, root.sat, root.val, 1)
                    border.color: "white"
                    border.width: 2
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.CrossCursor
                    preventStealing: true
                    function pick(m) {
                        root.sat = Math.max(0, Math.min(1, m.x / width));
                        root.val = 1 - Math.max(0, Math.min(1, m.y / height));
                        root.commit();
                    }
                    onPressed: m => pick(m)
                    onPositionChanged: m => { if (pressed) pick(m) }
                }
            }

            // Colour bar: the rainbow.
            Item {
                width: parent.width
                height: 16
                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.000; color: "#ff0000" }
                        GradientStop { position: 0.167; color: "#ffff00" }
                        GradientStop { position: 0.333; color: "#00ff00" }
                        GradientStop { position: 0.500; color: "#00ffff" }
                        GradientStop { position: 0.667; color: "#0000ff" }
                        GradientStop { position: 0.833; color: "#ff00ff" }
                        GradientStop { position: 1.000; color: "#ff0000" }
                    }
                }
                Rectangle {
                    x: root.hue * parent.width - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 18
                    radius: 9
                    color: Qt.hsva(root.hue, 1, 1, 1)
                    border.color: "white"
                    border.width: 2
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    preventStealing: true
                    function pick(m) {
                        root.hue = Math.max(0, Math.min(0.9999, (m.x - 4) / (width - 8)));
                        if (root.sat < 0.05) root.sat = 0.8;   // picking a colour off grey means "give me that colour"
                        if (root.val < 0.05) root.val = 0.9;
                        root.commit();
                    }
                    onPressed: m => pick(m)
                    onPositionChanged: m => { if (pressed) pick(m) }
                }
            }
        }
    }
}
