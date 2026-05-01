/*
 * CompactRepresentation.qml - panel / system-tray view.
 *
 * Two operating modes:
 *   - "todo": one colored swatch + count per category.
 *   - "jira": one colored swatch + count per Jira status category
 *             (To Do / In Progress / [Done]).
 *
 * Inside each mode, the layout follows panelCounterStyle ("right" or
 * "inside") and panelCounterColors (white | black per swatch) just as
 * before. For Jira the per-swatch color falls back to white.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: compact
    property var store
    property var jira

    readonly property string mode: plasmoid.configuration.mode || "todo"
    readonly property int _vTodo: store ? store.version : 0
    readonly property int _vJira: jira ? jira.version : 0

    CategoryHelper { id: cats }

    readonly property int _smallSwatch: Math.max(10, PlasmaCore.Units.iconSizes.small - 2)
    readonly property int _bigSwatch:   Math.max(18, PlasmaCore.Units.iconSizes.medium - 2)

    function _todoTextColor(idx) {
        var arr = plasmoid.configuration.panelCounterColors || [];
        var v = arr[idx];
        return (v === "black") ? "black" : "white";
    }

    // Static color triplet for Jira status categories.
    readonly property var _jiraSlots: [
        { key: "new",           label: i18n("Por hacer"),  color: "#42526e" },
        { key: "indeterminate", label: i18n("En curso"),    color: "#f5a623" },
        { key: "done",          label: i18n("Hechas"),      color: "#2ecc71" }
    ]

    Layout.minimumWidth: row.implicitWidth + PlasmaCore.Units.smallSpacing * 2
    Layout.preferredWidth: Layout.minimumWidth
    Layout.minimumHeight: PlasmaCore.Units.iconSizes.small
    Layout.preferredHeight: PlasmaCore.Units.iconSizes.medium

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        hoverEnabled: true
        onClicked: plasmoid.expanded = !plasmoid.expanded
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: PlasmaCore.Units.smallSpacing * 2

        // -------- TODO mode --------
        Repeater {
            model: compact.mode === "todo" ? cats.count() : 0
            delegate: SwatchBadge {
                catIndex: index
                color: cats.color(index)
                count: (compact._vTodo, store ? store.pendingCountForCategory(index) : 0)
                showZero: plasmoid.configuration.panelShowZero
                label: cats.name(index)
                showLabel: plasmoid.configuration.panelShowLabels
                textColor: compact._todoTextColor(index)
                insideMode: plasmoid.configuration.panelCounterStyle === "inside"
                smallSwatch: compact._smallSwatch
                bigSwatch: compact._bigSwatch
            }
        }

        // -------- JIRA mode --------
        Repeater {
            model: compact.mode === "jira" ? compact._jiraSlots.length : 0
            delegate: SwatchBadge {
                // Hide "done" unless the user enabled it.
                readonly property var slot: compact._jiraSlots[index]
                visible: slot.key !== "done" || plasmoid.configuration.jiraShowDone
                catIndex: index
                color: slot.color
                count: (compact._vJira, jira ? jira.countByStatusCategory(slot.key) : 0)
                showZero: plasmoid.configuration.panelShowZero
                label: slot.label
                showLabel: plasmoid.configuration.panelShowLabels
                textColor: "white"
                insideMode: plasmoid.configuration.panelCounterStyle === "inside"
                smallSwatch: compact._smallSwatch
                bigSwatch: compact._bigSwatch
            }
        }
    }
}
