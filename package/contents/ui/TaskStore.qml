/*
 * TaskStore.qml
 *
 * Central data store for the Categorized ToDo plasmoid.
 *
 * Persistence layout (see docs/PERSISTENCE.md):
 *   ~/.local/share/categorizedtodo/
 *     manifest.json        { schema, nextId, slugs:[s0,s1,s2,s3], updatedAt }
 *     0-<slug>.json        active tasks of category 0
 *     1-<slug>.json
 *     ...
 *     archived.json        archived tasks (any category)
 *
 * Each per-category file:
 *   { schema:"categorizedtodo.v1", categoryIndex, categoryName, tasks:[...] }
 *
 * Source of truth in memory = two plain JS arrays (tasks, archived) plus
 * a `version` integer that views depend on for binding refresh.
 *
 * Saves are debounced ~150ms via a Timer to coalesce rapid edits, and
 * flushNow() is exposed for shutdown handlers.
 */

import QtQuick 2.15

QtObject {
    id: store

    // Injected from main.qml.
    property var plasmoid: null
    property var fileStore: null

    property var tasks: []
    property var archived: []
    property int version: 0

    property int _nextId: 1
    property bool _loaded: false

    // Mutation tracking for selective writes.
    property var _dirtyCategories: ({})   // { "0": true, "2": true }
    property bool _archivedDirty: false
    property bool _manifestDirty: false

    // Cached slugs from the last manifest read; used to detect renames.
    property var _persistedSlugs: []

    signal changed()

    // Debounce timer: every mutation (re)starts it; fires once when idle.
    property var _saveTimer: Timer {
        interval: 150
        repeat: false
        onTriggered: store._writePending()
    }

    // ------------------------------------------------------------------
    // Load
    // ------------------------------------------------------------------

    function load() {
        if (!fileStore) {
            console.warn("TaskStore.load: no FileStore");
            _loaded = true;
            _bump();
            return;
        }

        var manifest = fileStore.readJson("manifest.json", null);
        if (manifest) {
            _nextId = Math.max(1, manifest.nextId || 1);
            _persistedSlugs = (manifest.slugs || []).slice();
        } else {
            _nextId = 1;
            _persistedSlugs = [];
        }

        var n = _categoryCount();
        var loadedTasks = [];
        for (var i = 0; i < n; i++) {
            // Try the file under the current slug; if not found, try the
            // slug recorded in the manifest (rename detection); finally
            // fall back to numbered-only.
            var current = _fileNameForCategory(i, _slugForCategory(i));
            var data = fileStore.readJson(current, null);
            if (!data && _persistedSlugs[i]) {
                var legacy = _fileNameForCategory(i, _persistedSlugs[i]);
                data = fileStore.readJson(legacy, null);
            }
            if (data && Array.isArray(data.tasks)) {
                for (var t = 0; t < data.tasks.length; t++) {
                    var norm = _normalize(data.tasks[t]);
                    norm.category = i; // force category index from file location
                    loadedTasks.push(norm);
                    if (norm.id >= _nextId) _nextId = norm.id + 1;
                }
            }
        }
        tasks = loadedTasks;

        var arc = fileStore.readJson("archived.json", null);
        if (arc && Array.isArray(arc.tasks)) {
            archived = arc.tasks.map(_normalize);
            for (var a = 0; a < archived.length; a++) {
                if (archived[a].id >= _nextId) _nextId = archived[a].id + 1;
            }
        } else {
            archived = [];
        }

        _loaded = true;
        _dirtyCategories = ({});
        _archivedDirty = false;
        _manifestDirty = false;
        _bump();
    }

    // ------------------------------------------------------------------
    // Save (debounced)
    // ------------------------------------------------------------------

    function save() {
        if (!_loaded || !fileStore) return;
        _saveTimer.restart();
    }

    // Force any pending writes to disk synchronously schedule. Note that
    // the writes themselves go through the executable data source which
    // is asynchronous; we cannot truly block. We do, however, stop the
    // debounce timer and submit the commands immediately, which is the
    // safest we can do from QML.
    function flushNow() {
        if (_saveTimer.running) {
            _saveTimer.stop();
        }
        _writePending();
    }

    function _writePending() {
        if (!_loaded || !fileStore) return;

        var n = _categoryCount();
        var currentSlugs = [];
        for (var i = 0; i < n; i++) currentSlugs.push(_slugForCategory(i));

        // Detect renames: for any category whose slug changed, delete
        // the old filename and mark the category dirty so the new file
        // is written below. Doing this in two separate shell commands
        // is race-free because they touch different filenames; the new
        // file is always written before the user can see the change.
        for (var ri = 0; ri < n; ri++) {
            var oldSlug = _persistedSlugs[ri];
            var newSlug = currentSlugs[ri];
            if (oldSlug && oldSlug !== newSlug) {
                fileStore.removeFile(_fileNameForCategory(ri, oldSlug));
                _dirtyCategories[ri] = true;
                _manifestDirty = true;
            }
        }

        // Detect categoryCount shrink: orphan files for indices >= n
        // get deleted. We only know about the slugs we persisted; if
        // user manually placed files we leave them alone.
        for (var di = n; di < _persistedSlugs.length; di++) {
            if (_persistedSlugs[di]) {
                fileStore.removeFile(_fileNameForCategory(di, _persistedSlugs[di]));
                _manifestDirty = true;
            }
        }

        // Write each dirty category file.
        for (var key in _dirtyCategories) {
            if (!_dirtyCategories.hasOwnProperty(key)) continue;
            var idx = parseInt(key, 10);
            if (isNaN(idx) || idx < 0 || idx >= n) continue;
            var slug = currentSlugs[idx];
            var filename = _fileNameForCategory(idx, slug);
            var payload = {
                schema: "categorizedtodo.v1",
                categoryIndex: idx,
                categoryName: _categoryName(idx),
                tasks: tasks.filter(function(t) { return t.category === idx; })
            };
            fileStore.writeJson(filename, payload);
            _manifestDirty = true;
        }
        _dirtyCategories = ({});

        if (_archivedDirty) {
            fileStore.writeJson("archived.json", {
                schema: "categorizedtodo.v1",
                tasks: archived
            });
            _archivedDirty = false;
            _manifestDirty = true;
        }

        // Manifest is cheap and useful for next load: always rewrite if
        // anything changed (or if the slugs differ from what we last
        // persisted).
        var slugsChanged = (_persistedSlugs.length !== currentSlugs.length);
        if (!slugsChanged) {
            for (var ci = 0; ci < currentSlugs.length; ci++) {
                if (_persistedSlugs[ci] !== currentSlugs[ci]) {
                    slugsChanged = true;
                    break;
                }
            }
        }
        if (_manifestDirty || slugsChanged) {
            fileStore.writeJson("manifest.json", {
                schema: "categorizedtodo.v1",
                nextId: _nextId,
                slugs: currentSlugs,
                updatedAt: Date.now()
            });
            _persistedSlugs = currentSlugs.slice();
            _manifestDirty = false;
        }
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function _bump() {
        version = version + 1;
        changed();
    }

    function _markCategoryDirty(catIndex) {
        _dirtyCategories[String(catIndex | 0)] = true;
    }

    function _categoryCount() {
        if (!plasmoid) return 4;
        return Math.min(4, Math.max(1, plasmoid.configuration.categoryCount || 4));
    }

    function _categoryName(i) {
        if (!plasmoid) return "category-" + i;
        var arr = plasmoid.configuration.categoryNames || [];
        return arr[i] || ("category-" + i);
    }

    function _slugForCategory(i) {
        return _slugify(_categoryName(i));
    }

    function _slugify(name) {
        var s = String(name || "").toLowerCase();
        // Replace anything that's not [a-z0-9] with a single dash.
        s = s.replace(/[^a-z0-9]+/g, "-");
        // Trim leading/trailing dashes.
        s = s.replace(/^-+|-+$/g, "");
        if (s.length === 0) s = "untitled";
        if (s.length > 32) s = s.substring(0, 32);
        return s;
    }

    function _fileNameForCategory(catIndex, slug) {
        return (catIndex | 0) + "-" + slug + ".json";
    }

    function _normalize(t) {
        return {
            id: t.id || 0,
            title: t.title || "",
            description: t.description || "",
            category: (t.category === undefined) ? 0 : (t.category | 0),
            priority: t.priority || "M",
            done: !!t.done,
            createdAt: t.createdAt || Date.now(),
            archivedAt: t.archivedAt || 0,
            subtasks: (t.subtasks || []).map(function(s) {
                return {
                    id: s.id || 0,
                    title: s.title || "",
                    priority: s.priority || "M",
                    done: !!s.done
                };
            })
        };
    }

    // ------------------------------------------------------------------
    // Queries
    // ------------------------------------------------------------------

    function tasksForCategory(catIndex) {
        var out = [];
        for (var i = 0; i < tasks.length; i++) {
            if (tasks[i].category === catIndex) out.push(tasks[i]);
        }
        return out;
    }

    function pendingCountForCategory(catIndex) {
        var c = 0;
        for (var i = 0; i < tasks.length; i++) {
            if (tasks[i].category === catIndex && !tasks[i].done) c++;
        }
        return c;
    }

    function totalPending() {
        var c = 0;
        for (var i = 0; i < tasks.length; i++) if (!tasks[i].done) c++;
        return c;
    }

    function _indexOf(arr, id) {
        for (var i = 0; i < arr.length; i++) if (arr[i].id === id) return i;
        return -1;
    }

    function getTask(id) {
        var i = _indexOf(tasks, id);
        return (i >= 0) ? tasks[i] : null;
    }

    // ------------------------------------------------------------------
    // Mutations
    // ------------------------------------------------------------------

    function addTask(title, category, priority, description) {
        var t = _normalize({
            id: _nextId++,
            title: title,
            category: category | 0,
            priority: priority || "M",
            description: description || ""
        });
        tasks.push(t);
        _markCategoryDirty(t.category);
        _bump();
        save();
        return t.id;
    }

    function updateTask(id, fields) {
        var i = _indexOf(tasks, id);
        if (i < 0) return;
        var prevCat = tasks[i].category;
        var t = tasks[i];
        for (var k in fields) if (fields.hasOwnProperty(k)) t[k] = fields[k];
        tasks[i] = t;
        _markCategoryDirty(prevCat);
        if (t.category !== prevCat) _markCategoryDirty(t.category);
        _bump();
        save();
    }

    function toggleTaskDone(id) {
        var i = _indexOf(tasks, id);
        if (i < 0) return;
        tasks[i].done = !tasks[i].done;
        _markCategoryDirty(tasks[i].category);
        _bump();
        save();
    }

    function addSubtask(taskId, title, priority) {
        var i = _indexOf(tasks, taskId);
        if (i < 0) return;
        tasks[i].subtasks.push({
            id: _nextId++,
            title: title,
            priority: priority || "M",
            done: false
        });
        _markCategoryDirty(tasks[i].category);
        _bump();
        save();
    }

    function updateSubtask(taskId, subId, fields) {
        var i = _indexOf(tasks, taskId);
        if (i < 0) return;
        var subs = tasks[i].subtasks;
        for (var j = 0; j < subs.length; j++) {
            if (subs[j].id === subId) {
                for (var k in fields) if (fields.hasOwnProperty(k)) subs[j][k] = fields[k];
                _markCategoryDirty(tasks[i].category);
                _bump();
                save();
                return;
            }
        }
    }

    function toggleSubtaskDone(taskId, subId) {
        var i = _indexOf(tasks, taskId);
        if (i < 0) return;
        var subs = tasks[i].subtasks;
        for (var j = 0; j < subs.length; j++) {
            if (subs[j].id === subId) {
                subs[j].done = !subs[j].done;
                _markCategoryDirty(tasks[i].category);
                _bump();
                save();
                return;
            }
        }
    }

    function removeSubtask(taskId, subId) {
        var i = _indexOf(tasks, taskId);
        if (i < 0) return;
        var subs = tasks[i].subtasks;
        for (var j = 0; j < subs.length; j++) {
            if (subs[j].id === subId) {
                subs.splice(j, 1);
                _markCategoryDirty(tasks[i].category);
                _bump();
                save();
                return;
            }
        }
    }

    function archiveTask(id) {
        var i = _indexOf(tasks, id);
        if (i < 0) return;
        var t = tasks[i];
        t.archivedAt = Date.now();
        t.done = true;
        archived.unshift(t);
        tasks.splice(i, 1);
        _markCategoryDirty(t.category);
        _archivedDirty = true;
        _bump();
        save();
    }

    function restoreTask(id) {
        var i = _indexOf(archived, id);
        if (i < 0) return;
        var t = archived[i];
        t.archivedAt = 0;
        t.done = false;
        tasks.push(t);
        archived.splice(i, 1);
        _markCategoryDirty(t.category);
        _archivedDirty = true;
        _bump();
        save();
    }

    function deleteArchived(id) {
        var i = _indexOf(archived, id);
        if (i < 0) return;
        archived.splice(i, 1);
        _archivedDirty = true;
        _bump();
        save();
    }

    function clearArchive() {
        archived = [];
        _archivedDirty = true;
        _bump();
        save();
    }

    // ------------------------------------------------------------------
    // Export / Import
    // ------------------------------------------------------------------

    function exportCategoryJson(catIndex) {
        var out = [];
        for (var i = 0; i < tasks.length; i++) {
            if (tasks[i].category === catIndex) out.push(tasks[i]);
        }
        return JSON.stringify({
            schema: "categorizedtodo.v1",
            exportedAt: Date.now(),
            category: catIndex,
            categoryName: _categoryName(catIndex),
            tasks: out
        }, null, 2);
    }

    function importCategoryJson(catIndex, jsonText) {
        var data = JSON.parse(jsonText);
        var src = null;
        if (Array.isArray(data)) {
            src = data;
        } else if (data && Array.isArray(data.tasks)) {
            src = data.tasks;
        } else {
            throw new Error("Unrecognized JSON structure");
        }
        var imported = 0;
        for (var i = 0; i < src.length; i++) {
            var raw = src[i];
            if (!raw || typeof raw !== "object") continue;
            var t = _normalize(raw);
            t.id = _nextId++;
            t.category = catIndex;
            t.archivedAt = 0;
            for (var j = 0; j < t.subtasks.length; j++) {
                t.subtasks[j].id = _nextId++;
            }
            tasks.push(t);
            imported++;
        }
        _markCategoryDirty(catIndex);
        _bump();
        save();
        return imported;
    }

    // ------------------------------------------------------------------
    // Category-count adjustments
    // ------------------------------------------------------------------

    function reassignOutOfRangeCategories(newCount) {
        var dirty = false;
        for (var i = 0; i < tasks.length; i++) {
            if (tasks[i].category >= newCount) {
                _markCategoryDirty(tasks[i].category); // old file rewritten / removed
                tasks[i].category = newCount - 1;
                _markCategoryDirty(tasks[i].category);
                dirty = true;
            }
        }
        for (var j = 0; j < archived.length; j++) {
            if (archived[j].category >= newCount) {
                archived[j].category = newCount - 1;
                _archivedDirty = true;
                dirty = true;
            }
        }
        if (dirty) {
            _bump();
            save();
        } else {
            // Even with no task moves, the manifest needs updating so
            // orphan files for categories above newCount get cleaned up.
            _manifestDirty = true;
            save();
        }
    }

    // Called when category names change (without affecting count).
    // We mark every category dirty so file content gets refreshed with
    // the new categoryName, and the rename machinery in _writePending
    // does its work.
    function notifyCategoryNamesChanged() {
        var n = _categoryCount();
        for (var i = 0; i < n; i++) _markCategoryDirty(i);
        _manifestDirty = true;
        save();
    }
}
