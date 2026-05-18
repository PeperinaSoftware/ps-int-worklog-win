/*
 * main.qml - root for the Jira Worklog Calendar plasmoid.
 *
 * Hosts the JiraWorklogStore and dispatches compact / full representations.
 * Reads credentials from the same KConfig file as the Categorized ToDo
 * plasmoid (see config/main.xml's <kcfgfile>) so they're effectively shared.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore

Item {
    id: root

    Plasmoid.switchWidth: PlasmaCore.Units.gridUnit * 14
    Plasmoid.switchHeight: PlasmaCore.Units.gridUnit * 10

    Plasmoid.fullRepresentation: FullRepresentation {
        store: _store
        Layout.minimumWidth: plasmoid.configuration.worklogPopupWidth
        Layout.minimumHeight: plasmoid.configuration.worklogPopupHeight
        Layout.preferredWidth: plasmoid.configuration.worklogPopupWidth
        Layout.preferredHeight: plasmoid.configuration.worklogPopupHeight
    }

    Plasmoid.compactRepresentation: CompactRepresentation {
        store: _store
    }

    Plasmoid.toolTipMainText: i18n("Jira Worklog Calendar")
    Plasmoid.toolTipSubText: {
        if (!_store) return "";
        if (_store.loading) return i18n("Cargando…");
        if (_store.lastError) return _store.lastError;
        if (_store.lastFetchedAt > 0)
            return i18np("%1 worklog en la semana",
                         "%1 worklogs en la semana",
                         _store.totalCount());
        return i18n("Sin datos. Abrí el popup y sincronizá.");
    }

    JiraWorklogStore {
        id: _store
        plasmoidApi: plasmoid
    }

    Component.onCompleted: {
        _store.plasmoidApi = plasmoid;
        _store.init();
    }
}
