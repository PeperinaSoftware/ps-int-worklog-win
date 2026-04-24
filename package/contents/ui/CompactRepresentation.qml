/*
 * CompactRepresentation.qml - panel / system-tray view.
 *
 * Lays out one badge per active category, horizontally:
 *     [GREEN] 1   [YELLOW] 3   [BLUE] 5   [RED] 0
 *
 * Each badge is a colored square followed by the pending-task count
 * for that category. Clicking the widget toggles the popup.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: compact
    property var store

    // Depend on store.version so counts refresh whenever tasks change.
    readonly property int _v: store ? store.version : 0

    CategoryHelper { id: cats }

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

        Repeater {
            model: cats.count()

            RowLayout {
                spacing: PlasmaCore.Units.smallSpacing
                visible: plasmoid.configuration.panelShowZero
                         || (compact._v, store.pendingCountForCategory(index) > 0)

                Rectangle {
                    Layout.preferredWidth: Math.max(10, PlasmaCore.Units.iconSizes.small - 2)
                    Layout.preferredHeight: Layout.preferredWidth
                    radius: 2
                    color: cats.color(index)
                    border.width: 1
                    border.color: Qt.darker(color, 1.4)
                }

                PlasmaComponents3.Label {
                    text: (compact._v, store.pendingCountForCategory(index))
                    font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize + 2
                    font.bold: true
                }

                PlasmaComponents3.Label {
                    visible: plasmoid.configuration.panelShowLabels
                    text: cats.name(index)
                    font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                    opacity: 0.75
                }
            }
        }
    }
}
