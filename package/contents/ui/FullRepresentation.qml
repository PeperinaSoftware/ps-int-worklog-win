/*
 * FullRepresentation.qml - popup with tabs for each category + Archive tab.
 *
 * Hosts all dialogs at the root level so they overlay the whole popup rather
 * than being nested inside a ListView delegate.
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

    CategoryHelper { id: cats }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: PlasmaCore.Units.smallSpacing
        spacing: PlasmaCore.Units.smallSpacing

        // -------- Tab bar --------
        QQC2.TabBar {
            id: tabs
            Layout.fillWidth: true

            Repeater {
                model: cats.count()
                QQC2.TabButton {
                    property int pending: (store.version, store.pendingCountForCategory(index))
                    contentItem: RowLayout {
                        spacing: 4
                        Rectangle {
                            width: 10
                            height: 10
                            radius: 5
                            color: cats.color(index)
                            Layout.alignment: Qt.AlignVCenter
                        }
                        PlasmaComponents3.Label {
                            text: cats.name(index)
                            elide: Text.ElideRight
                            Layout.alignment: Qt.AlignVCenter
                        }
                        Rectangle {
                            visible: pending > 0
                            color: cats.color(index)
                            radius: 8
                            implicitHeight: 16
                            implicitWidth: Math.max(16, countLabel.implicitWidth + 8)
                            PlasmaComponents3.Label {
                                id: countLabel
                                anchors.centerIn: parent
                                text: pending
                                color: "white"
                                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                                font.bold: true
                            }
                        }
                    }
                }
            }

            QQC2.TabButton {
                contentItem: RowLayout {
                    spacing: 4
                    PlasmaCore.IconItem {
                        source: "archive-insert"
                        Layout.preferredWidth: 14
                        Layout.preferredHeight: 14
                    }
                    PlasmaComponents3.Label {
                        text: i18n("Archive")
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        visible: (store.version, store.archived.length > 0)
                        color: PlasmaCore.Theme.disabledTextColor
                        radius: 8
                        implicitHeight: 16
                        implicitWidth: Math.max(16, aCountLabel.implicitWidth + 8)
                        PlasmaComponents3.Label {
                            id: aCountLabel
                            anchors.centerIn: parent
                            text: (store.version, store.archived.length)
                            color: "white"
                            font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                            font.bold: true
                        }
                    }
                }
            }
        }

        // -------- Stacked views --------
        StackLayout {
            id: stack
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex

            Repeater {
                model: cats.count()
                CategoryView {
                    store: full.store
                    catIndex: index
                    onNewTaskRequested: taskDialog.openNew(catIndex)
                    onEditTaskRequested: taskDialog.openEdit(task)
                    onEditSubtaskRequested: subDialog.openFor(task, subtask)
                }
            }

            ArchiveView {
                store: full.store
                onConfirmDelete: { confirmDeleteDlg.pendingId = id; confirmDeleteDlg.open(); }
                onConfirmEmpty: confirmEmptyDlg.open()
            }
        }

        // -------- Footer --------
        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: (store.version, i18np("%1 pending task in total",
                                             "%1 pending tasks in total",
                                             store.totalPending()))
                opacity: 0.6
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            }
            PlasmaComponents3.ToolButton {
                icon.name: "configure"
                text: i18n("Configure…")
                onClicked: plasmoid.action("configure").trigger()
            }
        }
    }

    // -------- Shared dialogs (rendered on top of the popup) --------
    TaskEditDialog {
        id: taskDialog
        store: full.store
    }

    SubtaskEditDialog {
        id: subDialog
        store: full.store
    }

    QQC2.Dialog {
        id: confirmDeleteDlg
        property int pendingId: 0
        title: i18n("Delete task?")
        modal: true
        standardButtons: QQC2.Dialog.Yes | QQC2.Dialog.No
        anchors.centerIn: parent
        onAccepted: if (pendingId) store.deleteArchived(pendingId)
        contentItem: PlasmaComponents3.Label {
            text: i18n("This will permanently remove the task from the archive.")
            wrapMode: Text.WordWrap
        }
    }

    QQC2.Dialog {
        id: confirmEmptyDlg
        title: i18n("Empty archive?")
        modal: true
        standardButtons: QQC2.Dialog.Yes | QQC2.Dialog.No
        anchors.centerIn: parent
        onAccepted: store.clearArchive()
        contentItem: PlasmaComponents3.Label {
            text: i18n("This will permanently delete all archived tasks.")
            wrapMode: Text.WordWrap
        }
    }
}
