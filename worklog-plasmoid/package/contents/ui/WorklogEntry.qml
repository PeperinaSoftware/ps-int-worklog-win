/*
 * WorklogEntry.qml - one logged block on the calendar grid.
 *
 * Layout rules (driven by block height in slots):
 *   - 1 slot (≤30 min): single line, smaller font:
 *       09:00  CP-2796
 *     The issue key is always shown; the summary is omitted because
 *     there's no room.
 *   - 2+ slots (>30 min): two lines, default font:
 *       09:00 - 11:30 (2h 30m)
 *       CP-2796               ← always
 *     or, if worklogShowIssueSummary is on:
 *       09:00 - 11:30 (2h 30m)
 *       CP-2796: <summary>    ← elided right
 *
 * Comments are never rendered on the block itself — clicking opens the
 * edit dialog where the full comment + summary are visible.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Rectangle {
    id: block
    property var entry

    signal clicked()

    radius: 3
    color: Qt.rgba(155/255, 145/255, 230/255, 0.55)
    border.color: Qt.rgba(120/255, 110/255, 200/255, 0.95)
    border.width: 1

    readonly property bool _isCompact: entry && entry.durationSec <= 30 * 60
    readonly property bool _showSummary: plasmoid.configuration.worklogShowIssueSummary === true
    readonly property int _baseSize:    PlasmaCore.Theme.smallestFont.pixelSize
    readonly property int _compactSize: Math.max(7, _baseSize - 1)

    function _fmtTime(ms) {
        var d = new Date(ms);
        var h = d.getHours();
        var m = d.getMinutes();
        return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
    }
    function _fmtDuration(sec) {
        var h = Math.floor(sec / 3600);
        var m = Math.floor((sec % 3600) / 60);
        if (h > 0 && m > 0) return h + "h " + m + "m";
        if (h > 0)          return h + "h";
        return m + "m";
    }

    // -------- Compact: single line for 30-min blocks --------
    Item {
        anchors.fill: parent
        anchors.margins: 2
        visible: block._isCompact

        PlasmaComponents3.Label {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 2
            anchors.rightMargin: 2
            text: block.entry
                  ? (block._fmtTime(block.entry.started) + "  " + block.entry.issueKey)
                  : ""
            color: "white"
            font.pixelSize: block._compactSize
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
    }

    // -------- Normal: two lines for >30-min blocks --------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 3
        spacing: 0
        visible: !block._isCompact

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: block.entry
                  ? (block._fmtTime(block.entry.started) + " - " +
                     block._fmtTime(block.entry.started + block.entry.durationSec * 1000) +
                     "  (" + block._fmtDuration(block.entry.durationSec) + ")")
                  : ""
            color: "white"
            font.pixelSize: block._baseSize
            elide: Text.ElideRight
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: {
                if (!block.entry) return "";
                if (block._showSummary && block.entry.issueSummary &&
                    block.entry.issueSummary.length > 0) {
                    return block.entry.issueKey + ": " + block.entry.issueSummary;
                }
                return block.entry.issueKey;
            }
            color: "white"
            font.pixelSize: block._baseSize
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }

        Item { Layout.fillHeight: true }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: block.clicked()
        cursorShape: Qt.PointingHandCursor
    }
}
