/*
 * SwatchBadge.qml - one entry of the compact (panel) representation.
 *
 * Renders either:
 *   - a small colored swatch with the count to the right, or
 *   - a bigger colored swatch with the count drawn inside,
 * depending on `insideMode`. Optionally appends a label after the count.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Item {
    id: badge

    property int catIndex: 0
    property color color: "#7f8c8d"
    property int count: 0
    property bool showZero: true
    property string label: ""
    property bool showLabel: false
    property color textColor: "white"
    property bool insideMode: false
    property int smallSwatch: 12
    property int bigSwatch: 22

    // Optional hover tooltip. When non-empty a tooltip is shown after a short
    // delay; the HoverHandler doesn't consume click/wheel so the parent's
    // MouseArea still cycles modes and opens the popup.
    property string tooltipTitle: ""
    property string tooltipBody: ""

    visible: showZero || count > 0
    implicitWidth:  insideMode ? insideRow.implicitWidth : rightRow.implicitWidth
    implicitHeight: insideMode ? insideRow.implicitHeight : rightRow.implicitHeight
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight

    // -------- "right" style --------
    RowLayout {
        id: rightRow
        visible: !badge.insideMode
        spacing: PlasmaCore.Units.smallSpacing

        Rectangle {
            Layout.preferredWidth: badge.smallSwatch
            Layout.preferredHeight: badge.smallSwatch
            radius: 2
            color: badge.color
            border.width: 1
            border.color: Qt.darker(color, 1.4)
        }

        PlasmaComponents3.Label {
            text: badge.count
            color: badge.textColor
            font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize + 2
            font.bold: true
        }

        PlasmaComponents3.Label {
            visible: badge.showLabel
            text: badge.label
            font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            opacity: 0.75
        }
    }

    // -------- "inside" style --------
    RowLayout {
        id: insideRow
        visible: badge.insideMode
        spacing: PlasmaCore.Units.smallSpacing

        Rectangle {
            id: bigSwatchRect
            property bool wide: badge.count >= 10
            Layout.preferredWidth: wide ? badge.bigSwatch + 8 : badge.bigSwatch
            Layout.preferredHeight: badge.bigSwatch
            radius: 3
            color: badge.color
            border.width: 1
            border.color: Qt.darker(color, 1.4)

            PlasmaComponents3.Label {
                anchors.centerIn: parent
                text: badge.count
                color: badge.textColor
                font.bold: true
                font.pixelSize: Math.max(
                    PlasmaCore.Theme.smallestFont.pixelSize,
                    Math.round(badge.bigSwatch * 0.6))
            }
        }

        PlasmaComponents3.Label {
            visible: badge.showLabel
            text: badge.label
            font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            opacity: 0.75
        }
    }

    // -------- Hover tooltip --------
    HoverHandler {
        id: _hover
        // Hover detection only; does not consume click/wheel events.
    }
    QQC2.ToolTip {
        parent: badge
        visible: _hover.hovered && (badge.tooltipTitle.length > 0 || badge.tooltipBody.length > 0)
        delay: 400
        timeout: 8000
        contentItem: ColumnLayout {
            spacing: 2
            PlasmaComponents3.Label {
                visible: badge.tooltipTitle.length > 0
                text: badge.tooltipTitle
                font.bold: true
                color: PlasmaCore.Theme.textColor
            }
            PlasmaComponents3.Label {
                visible: badge.tooltipBody.length > 0
                text: badge.tooltipBody
                color: PlasmaCore.Theme.textColor
                wrapMode: Text.WordWrap
                Layout.maximumWidth: 320
            }
        }
        background: Rectangle {
            color: PlasmaCore.Theme.backgroundColor
            border.color: PlasmaCore.Theme.textColor
            border.width: 1
            radius: 3
            opacity: 0.97
        }
    }
}
