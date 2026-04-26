/*
 * FileStore.qml
 *
 * Minimal file I/O for the Categorized ToDo plasmoid. Pure QML using
 * facilities that ship with Qt 5.15 + Plasma 5.27 (no native plugins,
 * no third-party libraries).
 *
 *   - Reads:   synchronous XMLHttpRequest GET on file:// URLs.
 *   - Writes:  PlasmaCore.DataSource with engine "executable", running
 *              a small shell pipeline that writes atomically (temp file
 *              + mv). The JSON payload is base64-encoded in QML so the
 *              shell never has to deal with quote/newline escaping.
 *
 * All filenames are validated against a strict slug regex before being
 * passed to the shell. The full destination path is computed in QML and
 * passed through positional arguments ($1, $2, $3) — the script never
 * interpolates user-controlled strings.
 */

import QtQuick 2.15
import Qt.labs.platform 1.1 as Platform
import org.kde.plasma.core 2.0 as PlasmaCore

QtObject {
    id: store

    // Absolute filesystem path (no scheme). Empty until init() runs.
    property string dataDir: ""

    // Set to true once the data directory has been created.
    property bool ready: false

    // Emitted after each write attempt; ok=false on failure.
    signal writeFinished(string filename, bool ok)

    // Single shared executable data source. Each shell invocation is
    // tagged with a unique source name so we can correlate the result
    // back to the originating call.
    property var _executable: PlasmaCore.DataSource {
        engine: "executable"
        connectedSources: []
        onNewData: {
            // sourceName is the full command we ran. We tagged it via
            // _pendingTags below to know what file it corresponds to.
            var tag = store._pendingTags[sourceName];
            disconnectSource(sourceName);
            delete store._pendingTags[sourceName];
            if (tag) {
                var ok = (data["exit code"] === 0);
                if (!ok) {
                    console.warn("FileStore: command failed for", tag.filename,
                                 "exit=", data["exit code"],
                                 "stderr=", (data["stderr"] || "").trim());
                }
                if (tag.kind === "write" || tag.kind === "rename" || tag.kind === "remove") {
                    store.writeFinished(tag.filename, ok);
                }
            }
        }
    }
    property var _pendingTags: ({})

    // ------------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------------

    function init() {
        // GenericDataLocation == ~/.local/share on Linux. The returned
        // value is a "file://..." URL string; strip the scheme so we can
        // feed it to shell commands.
        var url = Platform.StandardPaths.writableLocation(
                    Platform.StandardPaths.GenericDataLocation);
        dataDir = _urlToPath(url) + "/categorizedtodo";
        _exec("mkdir -p \"$1\"", [dataDir],
              { kind: "mkdir", filename: dataDir });
        ready = true;
        return dataDir;
    }

    // Returns the parsed JSON value, or `fallback` if the file does not
    // exist or cannot be parsed.
    function readJson(filename, fallback) {
        if (!_validName(filename)) {
            console.warn("FileStore.readJson: invalid filename", filename);
            return fallback;
        }
        var text = _readText(filename);
        if (text === null) return fallback;
        try {
            return JSON.parse(text);
        } catch (e) {
            console.warn("FileStore.readJson: parse failed for", filename, e);
            return fallback;
        }
    }

    // Writes `value` (any JSON-serializable thing) atomically to filename.
    function writeJson(filename, value) {
        if (!_validName(filename)) {
            console.warn("FileStore.writeJson: invalid filename", filename);
            writeFinished(filename, false);
            return;
        }
        var text;
        try {
            text = JSON.stringify(value, null, 2);
        } catch (e) {
            console.warn("FileStore.writeJson: stringify failed", e);
            writeFinished(filename, false);
            return;
        }
        var b64 = Qt.btoa(text);
        // Atomic write: write to .tmp then mv. mv on the same filesystem
        // is atomic per POSIX, so readers never see a partial file.
        var script = 'mkdir -p "$1" && '
                   + 'printf "%s" "$3" | base64 -d > "$1/$2.tmp" && '
                   + 'mv -f "$1/$2.tmp" "$1/$2"';
        _exec(script, [dataDir, filename, b64],
              { kind: "write", filename: filename });
    }

    function renameFile(oldName, newName) {
        if (!_validName(oldName) || !_validName(newName)) {
            console.warn("FileStore.renameFile: invalid filename(s)", oldName, newName);
            writeFinished(newName, false);
            return;
        }
        // Use mv -f; if the source doesn't exist we silently succeed so
        // the caller doesn't have to pre-check.
        var script = 'if [ -e "$1/$2" ]; then mv -f "$1/$2" "$1/$3"; fi';
        _exec(script, [dataDir, oldName, newName],
              { kind: "rename", filename: newName });
    }

    function removeFile(filename) {
        if (!_validName(filename)) {
            console.warn("FileStore.removeFile: invalid filename", filename);
            writeFinished(filename, false);
            return;
        }
        _exec('rm -f "$1/$2"', [dataDir, filename],
              { kind: "remove", filename: filename });
    }

    // Synchronous existence check via XHR. Cheap (HEAD-style: GET 1 byte
    // wouldn't work here so we just look at the readyState/status).
    function existsSync(filename) {
        if (!_validName(filename)) return false;
        return _readText(filename) !== null;
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    function _validName(name) {
        return typeof name === "string" && /^[a-zA-Z0-9._-]+$/.test(name);
    }

    function _urlToPath(url) {
        // StandardPaths returns "file:///home/user/.local/share". Strip
        // the scheme so we can pass it to shell commands.
        if (typeof url !== "string") return "";
        if (url.indexOf("file://") === 0) return url.substring(7);
        return url;
    }

    function _readText(filename) {
        if (!dataDir) return null;
        var url = "file://" + dataDir + "/" + filename;
        var xhr = new XMLHttpRequest();
        try {
            xhr.open("GET", url, false);  // synchronous
            xhr.send(null);
        } catch (e) {
            return null;
        }
        // For file:// URLs, status is 0 on success in Qt's XHR.
        // readyState 4 == DONE.
        if (xhr.readyState !== 4) return null;
        if (xhr.status !== 0 && xhr.status !== 200) return null;
        if (typeof xhr.responseText !== "string") return null;
        if (xhr.responseText.length === 0) {
            // An empty response can also mean "file does not exist" on
            // some Qt builds. Treat empty as "no data" so callers fall
            // back to defaults.
            return null;
        }
        return xhr.responseText;
    }

    // Build a `sh -c 'script' sh arg1 arg2 ...` command and connect it.
    // Using positional arguments means the user-controlled values never
    // touch the script body, so there's no shell injection surface.
    function _exec(script, args, tag) {
        // Single-quote the script for sh -c. The script we write here is
        // a constant literal in QML, so escaping single-quotes in it is
        // irrelevant — but we still defend by replacing ' with '\''.
        var safeScript = script.replace(/'/g, "'\\''");
        var cmd = "sh -c '" + safeScript + "' sh";
        for (var i = 0; i < args.length; i++) {
            cmd += " " + _shellQuote(args[i]);
        }
        _pendingTags[cmd] = tag;
        _executable.connectSource(cmd);
    }

    // Quote an argument for sh by wrapping in single quotes and escaping
    // any embedded single quote.
    function _shellQuote(s) {
        var str = String(s);
        return "'" + str.replace(/'/g, "'\\''") + "'";
    }
}
