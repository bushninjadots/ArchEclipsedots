import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.theme
import qs.services
import qs.widgets.visualizer

// Music-reactive spectrum that rises from the bar's inner edge while a track
// plays. Inserted into Bar.qml's pill surface *before* the state stack, so it
// sits behind the content and the border appears to feed the visualiser.
//
// It never owns an analyser: it claims the shared AudioBars cava feed (the
// owner-refcounted singleton) only while it is actually drawing, so there is
// no extra process and no duplicate analysis.
Item {
    id: root

    // Live only in the pill bar style, when a visualiser style is chosen, and
    // when a real track is playing.
    // Not while an island is open: its card would sit on top of the bars.
    readonly property bool wanted: Settings.barStyle === "pill"
        && Settings.visualizerStyle !== "off"
        && root.playing
        && !BarEditState.active
        && (BarState.state === "default" || BarState.state === "recording")

    // ---- player selection (same ghost filtering as MprisWidget) ----
    // playerctld proxies freeze as "Playing" after their player quits and
    // dead entries report Stopped with no metadata — neither lights the bar.
    function isProxy(p) {
        var n = (p.dbusName || "") + " " + (p.identity || "");
        return /playerctld/i.test(n);
    }
    function isReal(p) {
        if (!p)
            return false;
        if (isProxy(p))
            return false;
        if (p.playbackState === MprisPlaybackState.Stopped)
            return false;
        var hasMeta = (p.trackTitle && p.trackTitle.length > 0);
        return hasMeta || p.playbackState === MprisPlaybackState.Playing;
    }
    readonly property var player: {
        var vals = Mpris.players.values;
        for (var i = 0; i < vals.length; i++) {
            var p = vals[i];
            if (!isReal(p))
                continue;
            if (p.playbackState === MprisPlaybackState.Playing)
                return p;
        }
        return null;
    }
    // Only genuine playback drives the spectrum — paused settles to rest.
    readonly property bool playing: player !== null

    // Ease the whole layer in/out so the spectrum doesn't pop on track change.
    visible: opacity > 0.001
    opacity: wanted ? 1 : 0
    Behavior on opacity {
        enabled: Settings.animationsEnabled
        NumberAnimation {
            duration: 420
            easing.type: Easing.OutCubic
        }
    }

    onWantedChanged: AudioBars.setActive(root, wanted)
    Component.onDestruction: AudioBars.setActive(root, false)

    // The bars hug the inner edge: the bottom of a top bar, the top of a
    // bottom bar. CavaBars grows its bars upward off the feed, so a bottom
    // bar flips them to grow downward from the top edge instead.
    Item {
        id: visual
        anchors.fill: parent
        opacity: 0.5
        transform: Scale {
            origin.y: 0
            yScale: Settings.barOrientation ? 1 : -1
        }

        Loader {
            anchors.fill: parent
            sourceComponent: Settings.visualizerStyle === "wave" ? wave : bars
        }
        Component {
            id: bars
            CavaBars {
                points: AudioBars.levels
                tint: Theme.accent
            }
        }
        Component {
            id: wave
            CavaWave {
                points: AudioBars.levels
                tint: Theme.accent
            }
        }
    }
}
