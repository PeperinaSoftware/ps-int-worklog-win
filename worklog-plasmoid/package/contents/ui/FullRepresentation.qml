/*
 * FullRepresentation.qml - popup contents.
 *
 * Layout:
 *   - Header: week nav (prev / today / next), week label, view mode toggle
 *             (9h ↔ 24h), sync button, debug info button, configure button.
 *   - Body  : WorklogCalendar grid.
 *   - Hosts the WorklogEditDialog modal that opens from drag-to-create or
 *     clicking an existing entry.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: full
    property var store

    // The week shown — Sunday 00:00 of the visible 7 days.
    property date currentWeekStart: _sundayOf(new Date())
    readonly property int _v: store ? store.version : 0

    function _sundayOf(d) {
        var c = new Date(d);
        c.setHours(0, 0, 0, 0);
        c.setDate(c.getDate() - c.getDay());  // 0 = Sunday
        return c;
    }

    function _formatWeekLabel(start) {
        var end = new Date(start.getTime() + 6 * 24 * 60 * 60 * 1000);
        var months = ["Ene","Feb","Mar","Abr","May","Jun","Jul","Ago","Sep","Oct","Nov","Dic"];
        var s = start.getDate() + " " + months[start.getMonth()];
        var e = end.getDate()   + " " + months[end.getMonth()] + " " + end.getFullYear();
        return s + " — " + e;
    }

    function syncNow() {
        if (!store) return;
        store.fetchWeek(currentWeekStart);
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
                source: "view-calendar-week"
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
            }
            PlasmaComponents3.Label {
                text: i18n("Jira Worklog")
                font.bold: true
            }

            PlasmaComponents3.ToolButton {
                icon.name: "go-previous"
                onClicked: {
                    var d = new Date(full.currentWeekStart.getTime());
                    d.setDate(d.getDate() - 7);
                    full.currentWeekStart = d;
                    full.syncNow();
                }
                PlasmaComponents3.ToolTip.text: i18n("Semana anterior")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
            PlasmaComponents3.Button {
                text: i18n("Hoy")
                onClicked: {
                    full.currentWeekStart = full._sundayOf(new Date());
                    full.syncNow();
                }
            }
            PlasmaComponents3.ToolButton {
                icon.name: "go-next"
                onClicked: {
                    var d = new Date(full.currentWeekStart.getTime());
                    d.setDate(d.getDate() + 7);
                    full.currentWeekStart = d;
                    full.syncNow();
                }
                PlasmaComponents3.ToolTip.text: i18n("Semana siguiente")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: full._formatWeekLabel(full.currentWeekStart)
                font.bold: true
            }

            // View-mode toggle (9h / 24h)
            PlasmaComponents3.Button {
                text: plasmoid.configuration.worklogViewMode === "9h"
                      ? i18n("Modo 9h")
                      : i18n("Modo 24h")
                onClicked: {
                    plasmoid.configuration.worklogViewMode =
                        plasmoid.configuration.worklogViewMode === "9h" ? "24h" : "9h";
                }
                PlasmaComponents3.ToolTip.text: i18n("Cambiar entre vista 09:00–18:00 y 00:00–24:00")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }

            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh"
                enabled: store && !store.loading
                onClicked: full.syncNow()
                PlasmaComponents3.ToolTip.text: i18n("Sincronizar con Jira")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
            PlasmaComponents3.ToolButton {
                icon.name: "dialog-information"
                onClicked: debugOverlay.visible = true
                PlasmaComponents3.ToolTip.text: i18n("Ver diagnóstico de la última consulta")
                PlasmaComponents3.ToolTip.visible: hovered
                PlasmaComponents3.ToolTip.delay: 500
            }
        }

        // Status line
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: store && (store.loading || store.lastError.length > 0)
            text: {
                if (!store) return "";
                if (store.loading) return i18n("Cargando…");
                return store.lastError;
            }
            color: store && store.lastError.length > 0
                   ? PlasmaCore.Theme.negativeTextColor
                   : PlasmaCore.Theme.textColor
            opacity: 0.8
            font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
        }

        // -------- Calendar --------
        WorklogCalendar {
            id: cal
            Layout.fillWidth: true
            Layout.fillHeight: true
            store: full.store
            weekStart: full.currentWeekStart
            onCreateRequested: editDialog.openCreate(dayMs, startMs, endMs)
            onEditRequested: editDialog.openEdit(entry)
        }

        // -------- Footer --------
        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: {
                    if (!store) return "";
                    var total = 0;
                    for (var i = 0; i < store.worklogs.length; i++) {
                        total += store.worklogs[i].durationSec;
                    }
                    var h = Math.floor(total / 3600);
                    var m = Math.floor((total % 3600) / 60);
                    return i18n("Total semana: %1h %2m", h, m);
                }
                opacity: 0.7
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            }
            PlasmaComponents3.ToolButton {
                icon.name: "configure"
                text: i18n("Configurar…")
                onClicked: plasmoid.action("configure").trigger()
            }
        }
    }

    // -------- Create/edit modal --------
    WorklogEditDialog {
        id: editDialog
        store: full.store
        anchors.fill: parent
        onSaved: full.syncNow()
        onDeleted: full.syncNow()
    }

    // -------- Debug overlay --------
    Item {
        id: debugOverlay
        anchors.fill: parent
        visible: false
        z: 900

        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.5
            MouseArea { anchors.fill: parent; onClicked: debugOverlay.visible = false }
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.max(400, parent.width - 16)
            height: Math.max(300, parent.height - 30)
            color: PlasmaCore.Theme.backgroundColor
            border.color: PlasmaCore.Theme.textColor
            border.width: 1
            radius: 4

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: PlasmaCore.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: i18n("Diagnóstico — última consulta")
                        font.bold: true
                    }
                    PlasmaComponents3.ToolButton {
                        icon.name: "edit-copy"
                        text: i18n("Copiar")
                        enabled: store && store.hasDebugLog
                        onClicked: { logArea.selectAll(); logArea.copy(); logArea.deselect(); }
                    }
                    PlasmaComponents3.ToolButton {
                        icon.name: "edit-clear-all"
                        text: i18n("Limpiar")
                        enabled: store && store.hasDebugLog
                        onClicked: store.clearDebugLog()
                    }
                    PlasmaComponents3.ToolButton {
                        icon.name: "window-close"
                        onClicked: debugOverlay.visible = false
                    }
                }

                QQC2.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    QQC2.TextArea {
                        id: logArea
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.WrapAnywhere
                        font.family: "monospace"
                        font.pixelSize: 11
                        text: (store && store.hasDebugLog)
                              ? ((full._v, store.lastDebugLog))
                              : i18n("Sin datos. Pulsá ↻ para sincronizar primero.")
                    }
                }
            }
        }
    }

    Component.onCompleted: {
        // First sync on open if we never fetched.
        if (store && store.lastFetchedAt === 0) syncNow();
    }
}
