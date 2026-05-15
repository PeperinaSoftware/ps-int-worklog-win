/*
 * GlobalView.qml - "Global" tab in the ToDo popup. Lists every task across
 * every category, with a colored bar on the left showing which category it
 * belongs to. Read-only-ish: clicks open the same edit dialogs as the
 * per-category view; quick-add is intentionally absent here (the user picks
 * a real category to create tasks).
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: view
    property var store

    signal editTaskRequested(var task)
    signal editSubtaskRequested(var task, var subtask)

    CategoryHelper { id: cats }

    readonly property int _v: store ? store.version : 0
    readonly property var allTasks: (_v, view._collect())

    function _collect() {
        if (!store || !store.tasks) return [];
        var n = cats.count();
        var out = [];
        for (var i = 0; i < store.tasks.length; i++) {
            var t = store.tasks[i];
            if ((t.category | 0) < 0 || (t.category | 0) >= n) continue;
            out.push(t);
        }
        // Sort: pending first, then by priority high → low, then by createdAt desc.
        var prioRank = { "XL": 4, "L": 3, "M": 2, "S": 1, "XS": 0 };
        out.sort(function(a, b) {
            if (a.done !== b.done) return a.done ? 1 : -1;
            var pa = prioRank[a.priority] === undefined ? 2 : prioRank[a.priority];
            var pb = prioRank[b.priority] === undefined ? 2 : prioRank[b.priority];
            if (pa !== pb) return pb - pa;
            return (b.createdAt || 0) - (a.createdAt || 0);
        });
        return out;
    }

    function _pendingCount() {
        var c = 0;
        for (var i = 0; i < view.allTasks.length; i++) if (!view.allTasks[i].done) c++;
        return c;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: PlasmaCore.Units.smallSpacing

        // Header.
        RowLayout {
            Layout.fillWidth: true

            PlasmaCore.IconItem {
                source: "view-list-tree"
                Layout.preferredWidth: 14
                Layout.preferredHeight: 14
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: i18n("Global — %1 pending of %2",
                           view._pendingCount(), view.allTasks.length)
                font.bold: true
                elide: Text.ElideRight
            }
            // Small legend swatches so the user can read the color → category mapping.
            Repeater {
                model: cats.count()
                Rectangle {
                    Layout.preferredWidth: 10
                    Layout.preferredHeight: 10
                    radius: 2
                    color: cats.color(index)
                    border.width: 1
                    border.color: Qt.darker(color, 1.4)
                    PlasmaComponents3.ToolTip.visible: _legendHover.hovered
                    PlasmaComponents3.ToolTip.text: cats.name(index)
                    PlasmaComponents3.ToolTip.delay: 300
                    HoverHandler { id: _legendHover }
                }
            }
        }

        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                id: list
                spacing: 4
                model: view.allTasks
                delegate: TaskItem {
                    width: list.width
                    task: modelData
                    store: view.store
                    catColor: cats.color(modelData ? (modelData.category | 0) : 0)
                    onEditRequested: view.editTaskRequested(task)
                    onSubtaskEditRequested: view.editSubtaskRequested(task, subtask)
                }

                PlasmaComponents3.Label {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: i18n("No tasks yet. Crea una en una categoría específica.")
                    opacity: 0.55
                }
            }
        }
    }
}
