/*
 * CompactRepresentation.qml - panel / system-tray view.
 *
 * Two layouts supported via plasmoid.configuration.panelCounterStyle:
 *   - "right":  [swatch] N    (swatch + count to the right; original layout)
 *   - "inside": [ N ]         (a bigger swatch with the count drawn inside)
 *
 * The text color of the counter is configurable per category via
 * plasmoid.configuration.panelCounterColors ("white" | "black").
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

    // Tunables used for sizing.
    readonly property int _smallSwatch: Math.max(10, PlasmaCore.Units.iconSizes.small - 2)
    readonly property int _bigSwatch:   Math.max(18, PlasmaCore.Units.iconSizes.medium - 2)

    function _textColor(idx) {
        var arr = plasmoid.configuration.panelCounterColors || [];
        var v = arr[idx];
        return (v === "black") ? "black" : "white";
    }

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

            // Each entry is a Loader-like Item that renders the right layout
            // based on the configured counter style.
            Item {
                id: badge
                readonly property int catIndex: index
                readonly property int pending: (compact._v, store.pendingCountForCategory(catIndex))
                readonly property bool show: plasmoid.configuration.panelShowZero || pending > 0
                readonly property bool insideMode: plasmoid.configuration.panelCounterStyle === "inside"

                visible: show
                implicitWidth: insideMode ? insideRow.implicitWidth : rightRow.implicitWidth
                implicitHeight: insideMode ? insideRow.implicitHeight : rightRow.implicitHeight
                Layout.preferredWidth: implicitWidth
                Layout.preferredHeight: implicitHeight

                // -------- "right" style: square + counter to its right --------
                RowLayout {
                    id: rightRow
                    visible: !badge.insideMode
                    spacing: PlasmaCore.Units.smallSpacing

                    Rectangle {
                        Layout.preferredWidth: compact._smallSwatch
                        Layout.preferredHeight: compact._smallSwatch
                        radius: 2
                        color: cats.color(badge.catIndex)
                        border.width: 1
                        border.color: Qt.darker(color, 1.4)
                    }

                    PlasmaComponents3.Label {
                        text: badge.pending
                        color: compact._textColor(badge.catIndex)
                        font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize + 2
                        font.bold: true
                    }

                    PlasmaComponents3.Label {
                        visible: plasmoid.configuration.panelShowLabels
                        text: cats.name(badge.catIndex)
                        font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                        opacity: 0.75
                    }
                }

                // -------- "inside" style: bigger square with number inside --------
                RowLayout {
                    id: insideRow
                    visible: badge.insideMode
                    spacing: PlasmaCore.Units.smallSpacing

                    Rectangle {
                        id: bigSwatch
                        // Slightly wider for two-digit counts so it doesn't clip.
                        property bool wide: badge.pending >= 10
                        Layout.preferredWidth: wide ? compact._bigSwatch + 8 : compact._bigSwatch
                        Layout.preferredHeight: compact._bigSwatch
                        radius: 3
                        color: cats.color(badge.catIndex)
                        border.width: 1
                        border.color: Qt.darker(color, 1.4)

                        PlasmaComponents3.Label {
                            anchors.centerIn: parent
                            text: badge.pending
                            color: compact._textColor(badge.catIndex)
                            font.bold: true
                            font.pixelSize: Math.max(
                                PlasmaCore.Theme.smallestFont.pixelSize,
                                Math.round(compact._bigSwatch * 0.6))
                        }
                    }

                    PlasmaComponents3.Label {
                        visible: plasmoid.configuration.panelShowLabels
                        text: cats.name(badge.catIndex)
                        font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                        opacity: 0.75
                    }
                }
            }
        }
    }
}
