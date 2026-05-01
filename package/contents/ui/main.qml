/*
 * main.qml - Categorized ToDo plasmoid root.
 *
 * Hosts both representations and owns the shared stores. The plasmoid
 * has two operating modes (configurable):
 *   - "todo": local task list (TaskStore + JSON files).
 *   - "jira": read-only view of Jira issues assigned to the user.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore

Item {
    id: root

    Plasmoid.switchWidth: PlasmaCore.Units.gridUnit * 10
    Plasmoid.switchHeight: PlasmaCore.Units.gridUnit * 8

    readonly property string mode: plasmoid.configuration.mode || "todo"

    Plasmoid.fullRepresentation: FullRepresentation {
        store: _store
        jira: _jira
        Layout.minimumWidth: plasmoid.configuration.popupWidth
        Layout.minimumHeight: plasmoid.configuration.popupHeight
        Layout.preferredWidth: plasmoid.configuration.popupWidth
        Layout.preferredHeight: plasmoid.configuration.popupHeight
    }

    Plasmoid.compactRepresentation: CompactRepresentation {
        store: _store
        jira: _jira
    }

    Plasmoid.toolTipMainText: root.mode === "jira"
            ? i18n("Jira — assigned issues")
            : i18n("Categorized ToDo")

    Plasmoid.toolTipSubText: {
        if (root.mode === "jira") {
            if (!_jira) return "";
            if (_jira.lastError) return _jira.lastError;
            return i18np("%1 issue", "%1 issues", _jira.totalCount());
        }
        return _store ? i18np("%1 pending task", "%1 pending tasks", _store.totalPending()) : "";
    }

    FileStore {
        id: _fileStore
    }

    TaskStore {
        id: _store
        plasmoid: plasmoid
        fileStore: _fileStore
    }

    JiraStore {
        id: _jira
        plasmoid: plasmoid
        fileStore: _fileStore
    }

    Component.onCompleted: {
        _fileStore.init();
        _store.load();
        _jira.init();
        // If the user starts the plasmoid already in jira mode and has
        // never fetched, kick off an initial fetch.
        if (root.mode === "jira" && _jira.lastFetchedAt === 0) {
            _jira.fetch();
        }
    }

    Component.onDestruction: {
        _store.flushNow();
    }

    // React to category changes (todo mode).
    Connections {
        target: plasmoid.configuration
        function onCategoryCountChanged() {
            var n = Math.min(4, Math.max(1, plasmoid.configuration.categoryCount || 4));
            _store.reassignOutOfRangeCategories(n);
        }
        function onCategoryNamesChanged() {
            _store.notifyCategoryNamesChanged();
        }
        // Jira-side reactions.
        function onJiraRefreshMinutesChanged() {
            _jira.applyRefreshSchedule();
        }
        function onJiraJqlChanged()        { /* applied on next fetch */ }
        function onJiraSiteChanged()       { /* same */ }
        function onJiraEmailChanged()      { /* same */ }
        function onJiraTokenChanged()      { /* same */ }
        function onModeChanged() {
            // Auto-fetch the first time the user enters jira mode.
            if (root.mode === "jira" && _jira.lastFetchedAt === 0 && !_jira.loading) {
                _jira.fetch();
            }
        }
    }
}
