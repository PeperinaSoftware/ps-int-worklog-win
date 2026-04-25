/*
 * TaskStore.qml
 *
 * Central data store for the Categorized ToDo plasmoid.
 *
 * Design:
 *   - Source of truth = two plain JavaScript arrays (tasks, archived).
 *   - A `version` integer is bumped on every change so views can depend on it
 *     in bindings to refresh automatically (Repeater / ListView model reset).
 *   - Persistence uses Plasmoid.configuration.tasksJson / archivedJson.
 *
 * Task shape:
 *   {
 *     id: int,
 *     title: string,
 *     description: string,
 *     category: int,           // index into configured categories
 *     priority: "XS"|"S"|"M"|"L"|"XL",
 *     done: bool,
 *     createdAt: number,       // ms since epoch
 *     archivedAt: number,      // 0 if active
 *     subtasks: [ { id, title, priority, done } ]
 *   }
 */

import QtQuick 2.15

QtObject {
    id: store

    // Injected from main.qml to get access to Plasmoid.configuration.
    property var plasmoid: null

    property var tasks: []
    property var archived: []
    property int version: 0

    property int _nextId: 1
    property bool _loaded: false

    signal changed()

    // ---------------- Load & Save ----------------

    function load() {
        if (!plasmoid) return;
        try {
            tasks = (JSON.parse(plasmoid.configuration.tasksJson || "[]") || []).map(_normalize);
        } catch (e) {
            console.warn("TaskStore: tasksJson parse failed:", e);
            tasks = [];
        }
        try {
            archived = (JSON.parse(plasmoid.configuration.archivedJson || "[]") || []).map(_normalize);
        } catch (e2) {
            console.warn("TaskStore: archivedJson parse failed:", e2);
            archived = [];
        }
        _nextId = Math.max(1, plasmoid.configuration.nextId || 1);
        _loaded = true;
        _bump();
    }

    function save() {
        if (!plasmoid || !_loaded) return;
        plasmoid.configuration.tasksJson = JSON.stringify(tasks);
        plasmoid.configuration.archivedJson = JSON.stringify(archived);
        plasmoid.configuration.nextId = _nextId;
    }

    function _bump() {
        version = version + 1;
        changed();
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

    // ---------------- Queries ----------------

    function tasksForCategory(catIndex) {
        // Returns a shallow-copied list so callers can't mutate our state.
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

    // ---------------- Mutations ----------------

    function addTask(title, category, priority, description) {
        var t = _normalize({
            id: _nextId++,
            title: title,
            category: category | 0,
            priority: priority || "M",
            description: description || ""
        });
        tasks.push(t);
        save();
        _bump();
        return t.id;
    }

    function updateTask(id, fields) {
        var i = _indexOf(tasks, id);
        if (i < 0) return;
        var t = tasks[i];
        for (var k in fields) if (fields.hasOwnProperty(k)) t[k] = fields[k];
        tasks[i] = t;
        save();
        _bump();
    }

    function toggleTaskDone(id) {
        var i = _indexOf(tasks, id);
        if (i < 0) return;
        tasks[i].done = !tasks[i].done;
        save();
        _bump();
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
        save();
        _bump();
    }

    function updateSubtask(taskId, subId, fields) {
        var i = _indexOf(tasks, taskId);
        if (i < 0) return;
        var subs = tasks[i].subtasks;
        for (var j = 0; j < subs.length; j++) {
            if (subs[j].id === subId) {
                for (var k in fields) if (fields.hasOwnProperty(k)) subs[j][k] = fields[k];
                save();
                _bump();
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
                save();
                _bump();
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
                save();
                _bump();
                return;
            }
        }
    }

    // Move a task to the archive (it gets done=true; only archived tasks can
    // be permanently deleted).
    function archiveTask(id) {
        var i = _indexOf(tasks, id);
        if (i < 0) return;
        var t = tasks[i];
        t.archivedAt = Date.now();
        t.done = true;
        archived.unshift(t);
        tasks.splice(i, 1);
        save();
        _bump();
    }

    function restoreTask(id) {
        var i = _indexOf(archived, id);
        if (i < 0) return;
        var t = archived[i];
        t.archivedAt = 0;
        t.done = false;
        tasks.push(t);
        archived.splice(i, 1);
        save();
        _bump();
    }

    function deleteArchived(id) {
        var i = _indexOf(archived, id);
        if (i < 0) return;
        archived.splice(i, 1);
        save();
        _bump();
    }

    function clearArchive() {
        archived = [];
        save();
        _bump();
    }

    // ---------------- Export / Import ----------------

    // Returns a pretty-printed JSON string with all active tasks of one
    // category, including their subtasks. IDs are preserved in the export
    // but not relied upon by the importer.
    function exportCategoryJson(catIndex) {
        var out = [];
        for (var i = 0; i < tasks.length; i++) {
            if (tasks[i].category === catIndex) {
                out.push(tasks[i]);
            }
        }
        var payload = {
            schema: "categorizedtodo.v1",
            exportedAt: Date.now(),
            category: catIndex,
            tasks: out
        };
        return JSON.stringify(payload, null, 2);
    }

    // Parses a JSON string and appends the parsed tasks to the given
    // category. Each imported task and subtask is re-stamped with a fresh
    // id to avoid clashes. Returns the number of imported top-level tasks
    // or throws on malformed input.
    function importCategoryJson(catIndex, jsonText) {
        var data = JSON.parse(jsonText);
        var src = null;

        if (Array.isArray(data)) {
            // Plain array of tasks (e.g. from a hand-edited export).
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
            var task = _normalize(raw);
            task.id = _nextId++;
            task.category = catIndex;
            task.archivedAt = 0;
            // Re-stamp subtask ids too.
            for (var j = 0; j < task.subtasks.length; j++) {
                task.subtasks[j].id = _nextId++;
            }
            tasks.push(task);
            imported++;
        }
        save();
        _bump();
        return imported;
    }

    // When the user lowers categoryCount, reassign orphan tasks to the last
    // visible category so they remain reachable.
    function reassignOutOfRangeCategories(newCount) {
        var dirty = false;
        for (var i = 0; i < tasks.length; i++) {
            if (tasks[i].category >= newCount) {
                tasks[i].category = newCount - 1;
                dirty = true;
            }
        }
        for (var j = 0; j < archived.length; j++) {
            if (archived[j].category >= newCount) {
                archived[j].category = newCount - 1;
                dirty = true;
            }
        }
        if (dirty) {
            save();
            _bump();
        }
    }
}
