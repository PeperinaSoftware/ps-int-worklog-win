/*
 * WorklogEntry.qml - one logged block on the calendar grid.
 *
 * Shows the time range, the issue key, the duration, and the comment
 * (elided/wrapped to whatever vertical space we have). Click → edit.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents3

Rectangle {
    id: block
    property var entry

    signal clicked()

    radius: 3
    color: Qt.rgba(155/255, 145/255, 230/255, 0.55)   // muted purple, like the screenshot
    border.color: Qt.rgba(120/255, 110/255, 200/255, 0.95)
    border.width: 1

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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 3
        spacing: 0

        // Top row: time range + open button.
        RowLayout {
            Layout.fillWidth: true
            spacing: 2

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: block.entry
                      ? (block._fmtTime(block.entry.started) + " - " +
                         block._fmtTime(block.entry.started + block.entry.durationSec * 1000) +
                         "  (" + block._fmtDuration(block.entry.durationSec) + ")")
                      : ""
                color: "white"
                font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
                elide: Text.ElideRight
            }
        }

        // Body: issue key + comment.
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: block.entry
                  ? (block.entry.issueKey + ": " +
                     (block.entry.comment && block.entry.comment.length > 0
                          ? block.entry.comment
                          : i18n("(no comment provided)")))
                  : ""
            color: "white"
            font.pixelSize: PlasmaCore.Theme.smallestFont.pixelSize
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            verticalAlignment: Text.AlignTop
        }
    }

    MouseArea {
        anchors.fill: parent
        // We accept clicks but let the calendar's drag-area not steal them.
        onClicked: block.clicked()
        cursorShape: Qt.PointingHandCursor
    }
}
