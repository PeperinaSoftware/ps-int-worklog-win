/*
 * JiraView.qml - the popup contents when the plasmoid is in "jira" mode.
 *
 * Layout:
 *   Header: status text (loading / last fetched / error) + Refresh button
 *   Tabs:   To Do | In Progress | (Done)  — one per Jira status category
 *   Body:   ListView of JiraIssueItem (filtered by tab)
 *   Footer: total count + Configure button
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: view
    property var jira

    // Re-evaluate when the store mutates.
    readonly property int _v: jira ? jira.version : 0

    function _formatDate(ms) {
        if (!ms) return "";
        return Qt.formatDateTime(new Date(ms), Qt.DefaultLocaleShortDate);
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: PlasmaCore.Units.smallSpacing
        spacing: PlasmaCore.Units.smallSpacing

        // -------- Header --------
        RowLayout {
            Layout.fillWidth: true
            spacing: PlasmaCore.Units.smallSpacing

            PlasmaCore.IconItem {
                source: "view-task"
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
            }
            PlasmaComponents3.Label {
                text: i18n("Jira")
                font.bold: true
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: {
                    if (!jira) return "";
                    if (jira.loading) return i18n("Cargando…");
                    if (jira.lastError) return jira.lastError;
                    if (jira.lastFetchedAt > 0)
                        return i18n("Actualizado %1", view._formatDate(jira.lastFetchedAt));
                    return i18n("Sin datos. Pulsá ↻ para cargar.");
                }
                elide: Text.ElideRight
                opacity: 0.7
                color: jira && jira.lastError
                       ? PlasmaCore.Theme.negativeTextColor
                       : PlasmaCore.Theme.textColor
            }
            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh"
                enabled: jira && !jira.loading
                onClicked: jira.fetch()
                PlasmaComponents3.ToolTip.text: i18n("Refrescar")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
        }

        // -------- Tabs (only show "Done" if user enabled it) --------
        QQC2.TabBar {
            id: tabs
            Layout.fillWidth: true

            QQC2.TabButton {
                contentItem: RowLayout {
                    spacing: 6
                    Rectangle { Layout.preferredWidth: 8; Layout.preferredHeight: 8; radius: 4; color: "#42526e" }
                    PlasmaComponents3.Label {
                        text: i18n("Por hacer")
                        elide: Text.ElideRight
                    }
                    TabCountBadge {
                        property int catCount: (view._v, jira ? jira.countByStatusCategory("new") : 0)
                        visible: catCount > 0
                        count: catCount
                        badgeColor: "#42526e"
                    }
                }
            }

            QQC2.TabButton {
                contentItem: RowLayout {
                    spacing: 6
                    Rectangle { Layout.preferredWidth: 8; Layout.preferredHeight: 8; radius: 4; color: "#f5a623" }
                    PlasmaComponents3.Label {
                        text: i18n("En curso")
                        elide: Text.ElideRight
                    }
                    TabCountBadge {
                        property int catCount: (view._v, jira ? jira.countByStatusCategory("indeterminate") : 0)
                        visible: catCount > 0
                        count: catCount
                        badgeColor: "#f5a623"
                    }
                }
            }

            QQC2.TabButton {
                visible: plasmoid.configuration.jiraShowDone
                contentItem: RowLayout {
                    spacing: 6
                    Rectangle { Layout.preferredWidth: 8; Layout.preferredHeight: 8; radius: 4; color: "#2ecc71" }
                    PlasmaComponents3.Label {
                        text: i18n("Hechas")
                        elide: Text.ElideRight
                    }
                    TabCountBadge {
                        property int catCount: (view._v, jira ? jira.countByStatusCategory("done") : 0)
                        visible: catCount > 0
                        count: catCount
                        badgeColor: "#2ecc71"
                    }
                }
            }
        }

        // -------- Body: list --------
        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                id: list
                spacing: 4
                model: {
                    if (!jira) return [];
                    view._v;        // dependency
                    var cat = "new";
                    if (tabs.currentIndex === 1) cat = "indeterminate";
                    else if (tabs.currentIndex === 2) cat = "done";
                    return jira.issuesByStatusCategory(cat);
                }
                delegate: JiraIssueItem {
                    width: list.width
                    issue: modelData
                }

                // Empty placeholder.
                PlasmaComponents3.Label {
                    anchors.centerIn: parent
                    visible: list.count === 0 && jira && !jira.loading
                    width: parent.width - 40
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    opacity: 0.55
                    text: {
                        if (!jira) return "";
                        if (jira.lastError) return jira.lastError;
                        if (jira.lastFetchedAt === 0)
                            return i18n("Aún no se cargaron incidencias. Pulsá el botón de refrescar.");
                        return i18n("Sin incidencias en esta vista.");
                    }
                }

                PlasmaComponents3.BusyIndicator {
                    anchors.centerIn: parent
                    running: jira && jira.loading && list.count === 0
                    visible: running
                }
            }
        }

        // -------- Footer --------
        RowLayout {
            Layout.fillWidth: true

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: jira ? i18np("%1 incidencia", "%1 incidencias", (view._v, jira.totalCount())) : ""
                opacity: 0.6
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            }

            PlasmaComponents3.ToolButton {
                icon.name: "configure"
                text: i18n("Configurar…")
                onClicked: plasmoid.action("configure").trigger()
            }
        }
    }
}
