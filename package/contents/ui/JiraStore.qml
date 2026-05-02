/*
 * JiraStore.qml
 *
 * Connects to a Jira Cloud REST API (v3), fetches the issues matching
 * the configured JQL, normalizes them and exposes them grouped by
 * status category. Caches the last successful response in SQLite so the
 * popup is populated immediately on next launch.
 *
 * Auth: HTTP Basic with email + API token. The credentials are mirrored
 * to SQLite (settings table) every time they change in
 * Plasmoid.configuration. On startup we restore any missing field from
 * SQLite, so a Plasma config loss doesn't wipe out the Jira setup.
 *
 * No external libraries: XMLHttpRequest, Qt.btoa, JSON, LocalStorage.
 */

import QtQuick 2.15

QtObject {
    id: store

    // Configuration injected from main.qml.
    property var plasmoid: null
    property var database: null

    property var issues: []
    property bool loading: false
    property string lastError: ""
    property real lastFetchedAt: 0
    property int version: 0

    signal changed()
    signal fetchFinished(bool ok)

    property var _refreshTimer: Timer {
        repeat: true
        running: false
        onTriggered: store.fetch()
    }

    // ------------------------------------------------------------------
    // Lifecycle
    // ------------------------------------------------------------------

    function init() {
        restoreCredentialsFromCache();
        loadCache();
        applyRefreshSchedule();
    }

    function applyRefreshSchedule() {
        if (!plasmoid) return;
        var minutes = plasmoid.configuration.jiraRefreshMinutes | 0;
        if (minutes > 0) {
            _refreshTimer.interval = minutes * 60 * 1000;
            _refreshTimer.running = true;
        } else {
            _refreshTimer.running = false;
        }
    }

    // ------------------------------------------------------------------
    // Credentials mirror — defends against Plasmoid.configuration losses
    // ------------------------------------------------------------------

    // If any of the cfg_jira* fields is empty, try to restore it from
    // the SQLite settings table. Called once on init.
    function restoreCredentialsFromCache() {
        if (!database || !database.ready || !plasmoid) return;
        var pc = plasmoid.configuration;
        if (!pc.jiraSite)  pc.jiraSite  = database.getSetting("jira.site",  "");
        if (!pc.jiraEmail) pc.jiraEmail = database.getSetting("jira.email", "");
        if (!pc.jiraToken) pc.jiraToken = database.getSetting("jira.token", "");
        if (!pc.jiraJql)   pc.jiraJql   = database.getSetting("jira.jql",   "");
    }

    // Mirror the current cfg_jira* values to the SQLite settings table.
    // Called from main.qml every time the user changes one of them.
    function persistCredentials() {
        if (!database || !database.ready || !plasmoid) return;
        var pc = plasmoid.configuration;
        database.setSetting("jira.site",  pc.jiraSite  || "");
        database.setSetting("jira.email", pc.jiraEmail || "");
        database.setSetting("jira.token", pc.jiraToken || "");
        database.setSetting("jira.jql",   pc.jiraJql   || "");
    }

    // ------------------------------------------------------------------
    // Cache (issue list)
    // ------------------------------------------------------------------

    function loadCache() {
        if (!database || !database.ready) return;
        var d = database.loadJiraIssues();
        if (d.issues && d.issues.length > 0) {
            issues = d.issues;
            lastFetchedAt = d.fetchedAt;
            _bump();
        }
    }

    function saveCache() {
        if (!database || !database.ready) return;
        database.saveJiraIssues(issues, lastFetchedAt);
    }

    // ------------------------------------------------------------------
    // Fetch
    // ------------------------------------------------------------------

    function fetch() {
        if (loading) return;
        if (!plasmoid) return;

        var site  = (plasmoid.configuration.jiraSite || "").trim().replace(/\/+$/, "");
        var email = (plasmoid.configuration.jiraEmail || "").trim();
        var token = (plasmoid.configuration.jiraToken || "").trim();
        var jql   = (plasmoid.configuration.jiraJql || "").trim();
        var max   = Math.max(10, Math.min(200, plasmoid.configuration.jiraMaxResults | 0 || 50));

        if (!site || !email || !token) {
            lastError = qsTr("Configurá la URL del sitio, el email y el API token de Jira.");
            _bump();
            fetchFinished(false);
            return;
        }
        if (!jql) {
            lastError = qsTr("La consulta JQL está vacía.");
            _bump();
            fetchFinished(false);
            return;
        }

        loading = true;
        lastError = "";
        _bump();

        var fields = "summary,status,priority,issuetype,parent,updated";
        var url = site + "/rest/api/3/search?jql=" + encodeURIComponent(jql)
                + "&maxResults=" + max + "&fields=" + fields;

        var xhr = new XMLHttpRequest();
        xhr.open("GET", url, true);
        xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(email + ":" + token));
        xhr.setRequestHeader("Accept", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            store.loading = false;
            if (xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText);
                    var raw = data.issues || [];
                    var out = [];
                    for (var i = 0; i < raw.length; i++) {
                        out.push(_normalize(raw[i], site));
                    }
                    store.issues = out;
                    store.lastFetchedAt = Date.now();
                    store.lastError = "";
                    store.saveCache();
                    store._bump();
                    store.fetchFinished(true);
                } catch (e) {
                    store.lastError = qsTr("Error al parsear la respuesta: ") + e;
                    store._bump();
                    store.fetchFinished(false);
                }
            } else if (xhr.status === 401 || xhr.status === 403) {
                store.lastError = qsTr("Credenciales inválidas (HTTP %1). Revisá email + API token.").arg(xhr.status);
                store._bump();
                store.fetchFinished(false);
            } else if (xhr.status === 0) {
                store.lastError = qsTr("No se pudo contactar el servidor. ¿La URL es correcta y hay conexión?");
                store._bump();
                store.fetchFinished(false);
            } else {
                store.lastError = qsTr("HTTP %1: %2").arg(xhr.status).arg(_extractErrorMessage(xhr.responseText));
                store._bump();
                store.fetchFinished(false);
            }
        };
        try {
            xhr.send();
        } catch (sendErr) {
            store.loading = false;
            store.lastError = qsTr("Error de red: ") + sendErr;
            store._bump();
            store.fetchFinished(false);
        }
    }

    function testConnection(site, email, token, callback) {
        site = (site || "").trim().replace(/\/+$/, "");
        email = (email || "").trim();
        token = (token || "").trim();
        if (!site || !email || !token) {
            callback(false, qsTr("Completá los tres campos antes de probar."));
            return;
        }
        var xhr = new XMLHttpRequest();
        xhr.open("GET", site + "/rest/api/3/myself", true);
        xhr.setRequestHeader("Authorization", "Basic " + Qt.btoa(email + ":" + token));
        xhr.setRequestHeader("Accept", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText);
                    callback(true, qsTr("OK — autenticado como %1").arg(data.displayName || email));
                } catch (e) {
                    callback(true, qsTr("OK (respuesta inesperada pero el servidor aceptó las credenciales)."));
                }
            } else if (xhr.status === 401 || xhr.status === 403) {
                callback(false, qsTr("Credenciales rechazadas (HTTP %1).").arg(xhr.status));
            } else if (xhr.status === 0) {
                callback(false, qsTr("No se pudo contactar el servidor."));
            } else {
                callback(false, qsTr("HTTP %1: %2").arg(xhr.status).arg(_extractErrorMessage(xhr.responseText)));
            }
        };
        try {
            xhr.send();
        } catch (e) {
            callback(false, qsTr("Error de red: ") + e);
        }
    }

    // ------------------------------------------------------------------
    // Queries
    // ------------------------------------------------------------------

    function issuesByStatusCategory(cat) {
        var out = [];
        for (var i = 0; i < issues.length; i++) {
            if (issues[i].statusCat === cat) out.push(issues[i]);
        }
        return out;
    }

    function countByStatusCategory(cat) {
        var c = 0;
        for (var i = 0; i < issues.length; i++) {
            if (issues[i].statusCat === cat) c++;
        }
        return c;
    }

    function totalCount() {
        return issues.length;
    }

    function pendingCount() {
        var c = 0;
        for (var i = 0; i < issues.length; i++) {
            if (issues[i].statusCat !== "done") c++;
        }
        return c;
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    function _bump() {
        version = version + 1;
        changed();
    }

    function _normalize(raw, site) {
        var f = raw.fields || {};
        var status = f.status || {};
        var sc = status.statusCategory || {};
        var prio = f.priority || {};
        var it = f.issuetype || {};
        var parent = f.parent || null;
        var parentSummary = "";
        if (parent && parent.fields && parent.fields.summary) {
            parentSummary = parent.fields.summary;
        }
        return {
            key: raw.key || "",
            summary: f.summary || "",
            statusName: status.name || "",
            statusCat: sc.key || "undefined",
            statusColor: sc.colorName || "",
            priority: prio.name || "",
            priorityIconUrl: prio.iconUrl || "",
            issuetype: it.name || "",
            isSubtask: !!it.subtask,
            parentKey: parent ? (parent.key || "") : "",
            parentSummary: parentSummary,
            updated: f.updated || "",
            url: site + "/browse/" + (raw.key || "")
        };
    }

    function _extractErrorMessage(body) {
        if (!body) return "";
        try {
            var d = JSON.parse(body);
            if (d.errorMessages && d.errorMessages.length) return d.errorMessages.join("; ");
            if (d.message) return d.message;
        } catch (e) { /* not json */ }
        return String(body).substring(0, 200);
    }
}
