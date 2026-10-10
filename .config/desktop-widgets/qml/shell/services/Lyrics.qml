pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../utils/menupoll.js" as MenuPoll

// The playing track's lyrics, asked from lrclib.net through bin/lyrics and
// cached on disk. Ported from impasto's LyricsService
// (github.com/andreumassanet/impasto) onto this config's Media/Music services:
// Media picks the player, Music carries the shared playback clock, so the
// current line is derived from Music.elapsed instead of running its own
// position poll.
//
// `hold(owner, on)` is owner-refcounted like Music: the lookup and the line
// tracker run only while a visible surface claims them, so a hidden lyrics
// widget costs nothing (and never tells lrclib.net what is playing).
Singleton {
    id: root

    readonly property string fetcher: Quickshell.env("HOME") + "/.config/desktop-widgets/bin/lyrics"

    // The track, as lrclib matches on it. Length is part of the key because
    // lrclib uses it to disambiguate.
    readonly property string track: Media.present
        ? [Music.artist, Music.title, Music.album, Math.round(Music.length)].join("\n")
        : ""

    // ── the frame the widget reads ────────────────────────────────────────
    property var lines: []
    property bool synced: false
    property bool instrumental: false
    property string readFor: ""
    // what a surface says when there is no line to show
    readonly property string status: !Media.present ? "idle"
        : root.loading ? "loading"
        : root.instrumental ? "instrumental"
        : !root.available ? "missing"
        : !root.synced ? "plain"
        : ""
    readonly property bool loading: Media.present
        && root.readFor !== root.track
    // Kept once read: a track that scrolled past is still answered from the
    // cache the next time it plays, and the sheet does not blank mid-song.
    readonly property bool available: root.readFor === root.track
        && (root.lines.length > 0 || root.instrumental)

    // ── the line being sung ───────────────────────────────────────────────
    // Derived from Music's shared playback clock (index recomputes off
    // elapsed), with impasto's quarter-second lead so a line lights as it
    // starts being sung rather than when its stamp reads as late.
    readonly property int index: {
        if (!root.available || !root.synced)
            return -1;
        const t = Music.elapsed + 0.25;
        let found = -1;
        for (let i = 0; i < root.lines.length; i++) {
            if (root.lines[i].t > t)
                break;
            found = i;
        }
        return found;
    }
    readonly property string currentText: root.available && root.synced && root.index >= 0
        ? root.lines[root.index].text : ""
    readonly property string nextText: root.available && root.synced
        && root.index + 1 < root.lines.length ? root.lines[root.index + 1].text : ""
    // unsynced sheets show the plain lines
    readonly property var plain: root.available && !root.synced
        ? root.lines.map(l => l.text) : []

    // ── refcounting ───────────────────────────────────────────────────────
    property var owners: []
    readonly property bool held: root.owners.length > 0
    function hold(owner, on) {
        root.owners = MenuPoll.setOwnership(root.owners, owner, on);
    }

    onHeldChanged: if (root.held) root.fetch()

    onTrackChanged: {
        root.patience = 0;
        root.retry.stop();
        root.fetch();
    }

    // A new track while one is being asked waits for that answer to come
    // back; a refusal waits for its retry, sooner first then less often, for
    // as long as the same track is wanted.
    property bool again: false
    property string asked: ""
    property int patience: 0

    function fetch(): void {
        if (!root.held || !Media.present || root.track === "")
            return;
        if (root.readFor === root.track || (root.retry.running && !root.again))
            return;
        if (query.running) {
            root.again = true;
            return;
        }
        root.asked = root.track;
        query.command = [root.fetcher, Music.artist, Music.title, Music.album,
                         String(Math.round(Music.length))];
        query.running = true;
    }

    Process {
        id: query
        stdout: StdioCollector {
            onStreamFinished: root.take(text)
        }
        onExited: {
            if (root.again) {
                root.again = false;
                Qt.callLater(root.fetch);
            }
        }
    }

    readonly property Timer retry: Timer {
        interval: Math.min(120000, 10000 * Math.pow(2, root.patience))
        onTriggered: {
            root.patience += 1;
            root.fetch();
        }
    }

    function take(text: string): void {
        let report = null;
        try {
            report = JSON.parse(text);
        } catch (error) {
            console.warn("lyrics: cannot parse the report:", error);
            return;
        }
        if (report.reason === "network") {
            if (root.asked === root.track && root.held)
                root.retry.restart();
            return;
        }
        root.lines = report.available === true ? (report.lines ?? []) : [];
        root.synced = report.synced === true;
        root.instrumental = report.instrumental === true;
        root.readFor = root.asked;
    }
}
