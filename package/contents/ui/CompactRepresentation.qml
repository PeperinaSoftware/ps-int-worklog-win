/*
 * CompactRepresentation.qml - panel / system-tray view.
 *
 * Three operating modes:
 *   - "todo": one swatch + count per ToDo category.
 *   - "jira": one swatch + count per Jira category (configurable).
 *   - "gh":   one swatch + count per GitHub Projects category.
 *
 * Inside each mode, the layout follows panelCounterStyle ("right" or
 * "inside") and panelCounterColors (white | black per swatch).
 *
 * Mouse wheel over the compact view cycles through the three modes.
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
    property var gh

    readonly property string mode: plasmoid.configuration.mode || "todo"
    readonly property int _vTodo: store ? store.version : 0
    readonly property int _vJira: jira ? jira.version : 0
    readonly property int _vGh:   gh   ? gh.version   : 0

    readonly property var _modeOrder: ["todo", "jira", "gh"]

    CategoryHelper { id: cats }

    readonly property int _smallSwatch: Math.max(10, PlasmaCore.Units.iconSizes.small - 2)
    readonly property int _bigSwatch:   Math.max(18, PlasmaCore.Units.iconSizes.medium - 2)

    function _todoTextColor(idx) {
        var arr = plasmoid.configuration.panelCounterColors || [];
        var v = arr[idx];
        return (v === "black") ? "black" : "white";
    }

    function _jiraTextColor(idx) {
        var arr = plasmoid.configuration.jiraCategoryTextColors || [];
        var v = arr[idx];
        return (v === "black") ? "black" : "white";
    }
    function _jiraName(i) {
        var arr = plasmoid.configuration.jiraCategoryNames || [];
        return arr[i] || qsTr("Cat. %1").arg(i + 1);
    }
    function _jiraColor(i) {
        var arr = plasmoid.configuration.jiraCategoryColors || [];
        return arr[i] || "#7f8c8d";
    }
    function _jiraCount() {
        return Math.min(4, Math.max(1, plasmoid.configuration.jiraCategoryCount | 0 || 3));
    }

    function _ghTextColor(idx) {
        var arr = plasmoid.configuration.ghCategoryTextColors || [];
        var v = arr[idx];
        return (v === "black") ? "black" : "white";
    }
    function _ghName(i) {
        var arr = plasmoid.configuration.ghCategoryNames || [];
        return arr[i] || qsTr("Cat. %1").arg(i + 1);
    }
    function _ghColor(i) {
        var arr = plasmoid.configuration.ghCategoryColors || [];
        return arr[i] || "#7f8c8d";
    }
    function _ghCount() {
        return Math.min(4, Math.max(1, plasmoid.configuration.ghCategoryCount | 0 || 3));
    }

    function _cycleMode(delta) {
        var cur = compact.mode;
        var i = _modeOrder.indexOf(cur);
        if (i < 0) i = 0;
        var n = _modeOrder.length;
        var next = ((i + delta) % n + n) % n;
        plasmoid.configuration.mode = _modeOrder[next];
    }

    Layout.minimumWidth: row.implicitWidth + PlasmaCore.Units.smallSpacing * 2
    Layout.preferredWidth: Layout.minimumWidth
    Layout.minimumHeight: PlasmaCore.Units.iconSizes.small
    Layout.preferredHeight: PlasmaCore.Units.iconSizes.medium

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        hoverEnabled: true
        // Wheel cycles through todo -> jira -> gh -> todo (and reverse).
        // We accept wheel events so they don't bubble up to plasmashell.
        onWheel: {
            if (wheel.angleDelta.y === 0) { wheel.accepted = false; return; }
            compact._cycleMode(wheel.angleDelta.y > 0 ? 1 : -1);
            wheel.accepted = true;
        }
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
            model: compact.mode === "jira" ? compact._jiraCount() : 0
            delegate: SwatchBadge {
                catIndex: index
                color: compact._jiraColor(index)
                count: (compact._vJira, jira ? jira.countByJiraCategory(index) : 0)
                showZero: plasmoid.configuration.panelShowZero
                label: compact._jiraName(index)
                showLabel: plasmoid.configuration.panelShowLabels
                textColor: compact._jiraTextColor(index)
                insideMode: plasmoid.configuration.panelCounterStyle === "inside"
                smallSwatch: compact._smallSwatch
                bigSwatch: compact._bigSwatch
            }
        }

        // -------- GITHUB PROJECTS mode --------
        Repeater {
            model: compact.mode === "gh" ? compact._ghCount() : 0
            delegate: SwatchBadge {
                catIndex: index
                color: compact._ghColor(index)
                count: (compact._vGh, gh ? gh.countByGhCategory(index) : 0)
                showZero: plasmoid.configuration.panelShowZero
                label: compact._ghName(index)
                showLabel: plasmoid.configuration.panelShowLabels
                textColor: compact._ghTextColor(index)
                insideMode: plasmoid.configuration.panelCounterStyle === "inside"
                smallSwatch: compact._smallSwatch
                bigSwatch: compact._bigSwatch
            }
        }
    }
}
