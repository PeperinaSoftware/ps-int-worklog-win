/*
 * main.qml - Categorized ToDo plasmoid root.
 *
 * Declares the compact (panel) and full (popup) representations and owns the
 * shared TaskStore so every view sees the same data.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore

Item {
    id: root

    Plasmoid.switchWidth: PlasmaCore.Units.gridUnit * 10
    Plasmoid.switchHeight: PlasmaCore.Units.gridUnit * 8

    Plasmoid.fullRepresentation: FullRepresentation {
        store: _store
        Layout.minimumWidth: plasmoid.configuration.popupWidth
        Layout.minimumHeight: plasmoid.configuration.popupHeight
        Layout.preferredWidth: plasmoid.configuration.popupWidth
        Layout.preferredHeight: plasmoid.configuration.popupHeight
    }

    Plasmoid.compactRepresentation: CompactRepresentation {
        store: _store
    }

    Plasmoid.toolTipMainText: i18n("Categorized ToDo")
    Plasmoid.toolTipSubText: _store
            ? i18np("%1 pending task", "%1 pending tasks", _store.totalPending())
            : ""

    TaskStore {
        id: _store
        plasmoid: plasmoid
    }

    Component.onCompleted: _store.load()

    // If the user reduces the number of categories, clamp orphan tasks.
    Connections {
        target: plasmoid.configuration
        function onCategoryCountChanged() {
            var n = Math.min(4, Math.max(1, plasmoid.configuration.categoryCount || 4));
            _store.reassignOutOfRangeCategories(n);
        }
    }
}
