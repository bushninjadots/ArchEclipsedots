pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."

QtObject {
    id: client

    // ArchEclipse: no wallpaper daemon. call() is answered locally: the list
    // comes from bin/wallpaper-index (thumbnails + colour buckets), applying
    // hands the file to qs-wallpaperpicker (which draws it and runs matugen),
    // and favourites/state live in ~/.cache/wallpaper-styles. Everything the
    // daemon alone could do (Steam Workshop, Wallpaper Engine, effects,
    // playlists, rotation) answers "not available".
    readonly property bool connected: true
    property bool ready: false

    property bool cacheRunning: false
    property int cacheProgress: 0
    property int cacheTotal: 0

    signal eventReceived(string event, var data)

    signal fileAdded(string name, string path, string type)
    signal fileRemoved(string name, string type)
    signal fileRenamed(string oldName, string newName)
    signal folderRemoved(var names)
    signal weItemAdded(string weId, string weDir)
    signal weItemRemoved(string weId)
    signal scanDone()

    signal cacheReady()
    signal itemCached(var data)

    signal wallpaperApplied(string type, string name, string path, string weId, string key)
    signal wallpaperToggle()
    signal wallpaperShow()
    signal wallpaperHide()

    property bool randomRunning: false
    property int randomInterval: 0
    signal randomStarted(int interval)
    signal randomStopped()

    // Unified auto-rotate: true if random OR a playlist is rotating. The command
    // bar's rotate control reflects and toggles this, so "off" stops everything.
    property bool rotationActive: false
    function rotationStatus(callback) {
        call("wall.rotation_status", {}, function(result, err) {
            if (!err && result) client.rotationActive = !!result.active
            if (callback) callback(result, err)
        })
    }
    function rotationStop(callback) {
        call("wall.rotation_stop", {}, function(result, err) {
            client.randomRunning = false
            client.rotationActive = false
            if (callback) callback(result, err)
        })
    }

    // Palette frame: which second of a video clip drives the matugen palette.
    property real paletteFrame: 1
    function paletteFrameStatus(callback) {
        call("wall.palette_frame", {}, function(result, err) {
            if (!err && result && result.frame !== undefined) client.paletteFrame = result.frame
            if (callback) callback(result, err)
        })
    }
    function setPaletteFrame(sec, callback) {
        client.paletteFrame = sec
        call("wall.palette_frame", { frame: sec }, callback)
    }

    property int audioCapableCount: 0
    property int audioPlayingCount: 0
    property var audioOutputs: ({})
    property var audioGroups: []

    function refreshAudioState() {
        outputs(function(result, err) {
            if (err || !result) return
            var outs = result.outputs || {}
            var capable = 0
            var playing = 0
            for (var k in outs) {
                var entry = outs[k]
                if (!entry) continue
                var t = entry.type || ""
                if (t === "video" || t === "we") {
                    capable++
                    if (entry.mute === false) playing++
                }
            }
            client.audioOutputs = outs
            client.audioCapableCount = capable
            client.audioPlayingCount = playing
            client._rebuildAudioGroups()
        })
    }

    function _rebuildAudioGroups() {
        var byKey = {}
        var outs = client.audioOutputs || {}
        var weIdSet = {}
        for (var k in outs) {
            var entry = outs[k]
            if (!entry) continue
            var t = entry.type || ""
            if (t !== "video" && t !== "we") continue
            var groupKey
            if (t === "we") {
                groupKey = "we:*"
                if (entry.we_id) weIdSet[entry.we_id] = true
            } else {
                groupKey = "vid:" + (entry.path || "")
            }
            if (!byKey[groupKey]) {
                byKey[groupKey] = {
                    key: groupKey,
                    type: t,
                    path: entry.path || "",
                    weId: entry.we_id || "",
                    name: _audioDisplayName(entry),
                    outputs: [],
                    muted: true,
                    primary: "",
                    volume: 80
                }
            }
            byKey[groupKey].outputs.push(k)
            if (entry.mute === false) {
                byKey[groupKey].muted = false
                if (!byKey[groupKey].primary) byKey[groupKey].primary = k
            }
            if (typeof entry.volume === "number") {
                byKey[groupKey].volume = entry.volume
            }
        }
        var weCount = 0
        for (var w in weIdSet) weCount++
        if (byKey["we:*"] && weCount > 1) {
            byKey["we:*"].name = I18n.tr("Wallpaper Engine · %1 wallpapers").arg(weCount)
        }
        var arr = []
        for (var gk in byKey) {
            var g = byKey[gk]
            g.outputs.sort()
            if (!g.primary) g.primary = g.outputs[0]
            arr.push(g)
        }
        arr.sort(function(a, b) { return (a.name || "").localeCompare(b.name || "") })
        client.audioGroups = arr
    }

    function _audioDisplayName(entry) {
        if ((entry.type || "") === "we") {
            var id = entry.we_id || ""
            return id !== "" ? I18n.tr("Wallpaper Engine · %1").arg(id) : I18n.tr("Wallpaper Engine")
        }
        var p = entry.path || ""
        var idx = p.lastIndexOf("/")
        var name = idx >= 0 ? p.substring(idx + 1) : p
        var dot = name.lastIndexOf(".")
        if (dot > 0) name = name.substring(0, dot)
        return name || I18n.tr("Untitled")
    }

    function call(method, params, callback) {
        var p = params || {}
        var done = function(result, error) { if (callback) Qt.callLater(function() { callback(result, error) }) }
        switch (method) {
        case "status":
        case "subscribe":
        case "wall.preheat":
        case "wall.update_metadata":
        case "wall.clear_video_cache":
            return done({ ok: true }, null)
        case "wall.list":
            return done({ wallpapers: client._listRows(!!p.favourites) }, null)
        case "wall.apply":
            return client._apply(p, done)
        case "wall.set_favourite":
            client._setFav(p.key, !!p.favourite)
            return done({ ok: true }, null)
        case "state.get":
            return done({ value: client._state[p.key] }, null)
        case "state.set":
            client._state[p.key] = p.value
            client._saveState()
            return done({ ok: true }, null)
        case "wall.outputs":
            return done({ outputs: {} }, null)
        case "wall.cache_status":
            return done({ running: client.cacheRunning, progress: client.cacheProgress, total: client.cacheTotal }, null)
        case "wall.cache_reset":
        case "wall.cache_rebuild":
        case "wall.recompute_colors":
            client.rescan()
            return done({ ok: true }, null)
        case "wall.delete":
            return client._trash(p, done)
        case "wall.random_status":
        case "wall.rotation_status":
            return done({ running: false, active: false, interval: 0 }, null)
        default:
            return done(null, { code: -1, message: I18n.tr("Not available in ArchEclipse") })
        }
    }

    function subscribe(events) { call("subscribe", {events: events}) }
    function status(callback)  { call("status", {}, callback) }

    function toggle() { call("wall.toggle", {}) }
    function show()   { call("wall.show", {}) }
    function hide()   { call("wall.hide", {}) }

    function applyStatic(path, outputs, neighbors, screens, callback) {
        var params = {type: "static", path: path}
        if (outputs && outputs.length > 0) params.outputs = outputs
        if (neighbors && neighbors.length > 0) params.neighbors = neighbors
        if (screens && screens.length > 0) params.screens = screens
        call("wall.apply", params, callback)
    }
    function applyVideo(path, outputs, neighbors, screens, audioMap, volumeMap, callback) {
        var params = {type: "video", path: path}
        if (outputs && outputs.length > 0) params.outputs = outputs
        if (neighbors && neighbors.length > 0) params.neighbors = neighbors
        if (screens && screens.length > 0) params.screens = screens
        if (audioMap) params.outputs_audio = audioMap
        if (volumeMap) params.outputs_volume = volumeMap
        call("wall.apply", params, callback)
    }
    function applyWE(weId, screens, audioMap, volumeMap, callback) {
        var params = {type: "we", we_id: weId, screens: screens || []}
        if (audioMap) params.outputs_audio = audioMap
        if (volumeMap) params.outputs_volume = volumeMap
        call("wall.apply", params, callback)
    }
    function restore(callback) { call("wall.restore", {}, callback) }
    function outputs(callback) { call("wall.outputs", {}, callback) }
    function setAudio(mute, volume, outputs, callback) {
        if (typeof outputs === "function") { callback = outputs; outputs = null }
        let params = {}
        if (mute !== undefined && mute !== null) params.mute = !!mute
        if (volume !== undefined && volume !== null) params.volume = volume | 0
        if (outputs && outputs.length > 0) params.outputs = outputs
        call("wall.set_audio", params, callback)
    }

    function preheat(path) {
        if (!path) return
        call("wall.preheat", {path: path})
    }
    // Light/dark from the picker goes to ArchEclipse's system theme switch.
    property var _rethemeProc: Process {}
    function retheme(scheme, mode, colorIndex, callback) {
        if (typeof colorIndex === "function" && callback === undefined) {
            callback = colorIndex
            colorIndex = undefined
        }
        var knobs = {}
        if (mode) knobs.mode = mode
        if (scheme) knobs.schemeType = scheme
        if (typeof colorIndex === "number") knobs.sourceColorIndex = colorIndex | 0
        // ArchEclipse: light/dark is the system theme switch, which re-runs
        // matugen for the current wallpaper; scheme/index stay matugen's.
        if (mode) {
            _rethemeProc.running = false
            _rethemeProc.command = [Quickshell.env("HOME") + "/.config/hypr/theme/scripts/system-theme.sh", "switch", mode]
            _rethemeProc.running = true
        }
        if (callback) callback({ ok: true }, null)
    }
    function themePreview(scheme, mode, colorIndex, callback) {
        call("wall.theme_preview", {
            scheme: scheme || "scheme-fidelity",
            mode: mode || "dark",
            color_index: colorIndex | 0,
        }, callback)
    }

    function rebuildCache(callback)    { call("wall.cache_rebuild", {}, callback) }
    function clearData(callback)       { call("wall.clear_data", {}, callback) }
    function cacheStatus(callback)     { call("wall.cache_status", {}, callback) }
    function clearVideoCache(days, callback) { call("wall.clear_video_cache", { days: days | 0 }, callback) }
    // The picker's Refresh: drop every derived cache and scan the folders again.
    function resetCache(callback) { call("wall.cache_reset", {}, callback) }

    function listWallpapers(favouritesOnly, callback) {
        call("wall.list", {favourites: !!favouritesOnly}, callback)
    }
    function setFavourite(key, favourite, callback) {
        call("wall.set_favourite", {key: key, favourite: favourite}, callback)
    }
    function recomputeColors(callback) {
        call("wall.recompute_colors", {}, callback)
    }
    function importFromQml(callback) { call("wall.import", {}, callback) }
    function deleteItem(name, type, weId, callback) {
        var params = {name: name, type: type || "static"}
        if (weId) params.we_id = weId
        call("wall.delete", params, callback)
    }

    function updateMetadata(key, filesize, width, height) {
        call("wall.update_metadata", {key: key, filesize: filesize, width: width, height: height})
    }

    function randomStart(intervalSecs, options, callback) {
        var params = {interval: intervalSecs || 300}
        if (options) {
            if (options.types) params.types = options.types
            if (options.favouritesOnly !== undefined) params.favourites_only = !!options.favouritesOnly
        }
        call("wall.random_start", params, callback)
    }
    function randomStop(callback) {
        call("wall.random_stop", {}, callback)
    }
    function randomStatus(callback) {
        call("wall.random_status", {}, function(result, err) {
            if (!err && result) {
                client.randomRunning = !!result.running
                client.randomInterval = result.interval || 0
            }
            if (callback) callback(result, err)
        })
    }

    // Day/night rotation (#247). The daemon reads the pools/interval from
    // config.json itself, so start takes no arguments beyond the verb; force
    // pins a phase for manual testing.
    function dayNightStart(callback) {
        call("wall.daynight_start", {}, callback)
    }
    function dayNightStop(callback) {
        call("wall.daynight_stop", {}, callback)
    }
    function dayNightStatus(callback) {
        call("wall.daynight_status", {}, callback)
    }
    function dayNightForce(phase, callback) {
        call("wall.daynight_force", {phase: phase || ""}, callback)
    }

    function stateGet(key, callback) {
        call("state.get", {key: key}, callback)
    }
    function stateSet(key, value) {
        call("state.set", {key: key, value: value})
    }

    // ── local backend ────────────────────────────────────────────────────
    readonly property string _home: Quickshell.env("HOME")
    readonly property string _cache: (Quickshell.env("XDG_CACHE_HOME") || (_home + "/.cache")) + "/wallpaper-styles"
    readonly property string _bin: _home + "/.config/wallpaper-styles/bin"
    readonly property string _picker: _home + "/.config/qs-wallpaperpicker/bin/qs-wallpaperpicker"
    property var _index: ({})          // name -> {type, path, thumb, mtime, hue, sat, richness, w, h}
    property var _favs: ({})
    property var _state: ({})

    function _listRows(favOnly) {
        var rows = []
        var applied = client._state.applyCounts || {}
        for (var name in client._index) {
            var it = client._index[name]
            var fav = client._favs[name] ? 1 : 0
            if (favOnly && !fav) continue
            rows.push({
                key: name, name: name, type: it.type, thumb: it.thumb,
                video_file: it.type === "video" ? it.path : "", video_prev: "",
                mtime: it.mtime || 0, hue: it.hue, sat: it.sat || 0,
                richness: it.richness || 0, apply_count: applied[name] || 0,
                favourite: fav, filesize: it.size || 0, width: it.w || 0, height: it.h || 0
            })
        }
        return rows
    }
    function _nameOf(path) {
        for (var n in client._index) if (client._index[n].path === path) return n
        var i = path.lastIndexOf("/")
        return i >= 0 ? path.substring(i + 1) : path
    }
    function _apply(p, done) {
        if (p.type === "we")
            return done(null, { code: -1, message: I18n.tr("Wallpaper Engine scenes are not available in ArchEclipse") })
        var path = p.path || ""
        if (!path)
            return done(null, { code: -1, message: I18n.tr("No wallpaper to apply") })
        _applyProc.command = [client._picker, "set", path]
        _applyProc.running = true
        var name = client._nameOf(path)
        var counts = client._state.applyCounts || {}
        counts[name] = (counts[name] || 0) + 1
        client._state.applyCounts = counts
        client._saveState()
        client.wallpaperApplied(p.type || "static", name, path, "", name)
        done({ ok: true }, null)
    }
    property var _applyProc: Process {}
    function _trash(p, done) {
        var it = client._index[p.name]
        if (!it) return done(null, { code: -1, message: I18n.tr("Not found") })
        // gio trash: recoverable from the file manager's Trash.
        _trashProc.command = ["gio", "trash", it.path]
        _trashProc.running = true
        var idx = client._index
        delete idx[p.name]
        client._index = idx
        client.fileRemoved(p.name, it.type)
        done({ ok: true }, null)
    }
    property var _trashProc: Process {}
    function _setFav(key, on) {
        var f = client._favs
        if (on) f[key] = true; else delete f[key]
        client._favs = f
        _favFile.setText(JSON.stringify(f))
    }
    function _saveState() { _stateFile.setText(JSON.stringify(client._state)) }

    property var _favFile: FileView {
        path: client._cache + "/favourites.json"
        printErrors: false
        onLoaded: { try { client._favs = JSON.parse(text()) || {} } catch (e) { client._favs = {} } }
    }
    property var _stateFile: FileView {
        path: client._cache + "/state.json"
        printErrors: false
        onLoaded: { try { client._state = JSON.parse(text()) || {} } catch (e) { client._state = {} } }
    }
    property var _indexFile: FileView {
        path: client._cache + "/index.json"
        printErrors: false
        onLoaded: {
            try { client._index = (JSON.parse(text()) || {}).items || {} } catch (e) {}
            client.ready = true
        }
        onLoadFailed: client.ready = true
    }

    // The wallpaper folder is qs-wallpaperpicker's (its settings.json), so both
    // pickers show the same collection.
    property string wallpaperFolder: _home + "/Pictures/wallpapers"
    property var _pickerSettings: FileView {
        path: client._home + "/.config/qs-wallpaperpicker/settings.json"
        printErrors: false
        onLoaded: {
            try {
                var d = JSON.parse(text())
                if (d.wallpaperDir) client.wallpaperFolder = d.wallpaperDir.replace(/^~/, client._home)
            } catch (e) {}
        }
    }

    // Re-index (new or changed files only) in the background at idle priority.
    function rescan() {
        if (_indexer.running) return
        client.cacheRunning = true
        _indexer.command = ["nice", "-n", "19", "python3", "-I", client._bin + "/wallpaper-index", client.wallpaperFolder]
        _indexer.running = true
    }
    property var _indexer: Process {
        stdout: SplitParser {
            onRead: line => {
                try {
                    var m = JSON.parse(line)
                    client.cacheProgress = m.progress || 0
                    client.cacheTotal = m.total || 0
                } catch (e) {}
            }
        }
        onExited: {
            client.cacheRunning = false
            client._indexFile.reload()
            Qt.callLater(function() { client.scanDone(); client.cacheReady() })
        }
    }

    Component.onCompleted: Qt.callLater(client.rescan)
}
