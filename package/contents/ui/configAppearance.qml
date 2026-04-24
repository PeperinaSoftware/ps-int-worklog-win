/*
 * configAppearance.qml - Appearance tab of the configuration dialog.
 *
 * Controls the compact (panel) representation: show labels next to the
 * counters or not, show categories with zero pending tasks or not.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import org.kde.kirigami 2.5 as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_panelShowLabels: showLabelsCheck.checked
    property alias cfg_panelShowZero:   showZeroCheck.checked

    CheckBox {
        id: showLabelsCheck
        Kirigami.FormData.label: i18n("Panel representation:")
        text: i18n("Show category names next to counters")
    }

    CheckBox {
        id: showZeroCheck
        text: i18n("Show categories with zero pending tasks")
    }

    Label {
        Layout.fillWidth: true
        Layout.preferredWidth: 360
        wrapMode: Text.WordWrap
        text: i18n("The panel representation always shows a colored square per "
                 + "category followed by the number of pending tasks, laid out "
                 + "horizontally. For example: [green] 1  [yellow] 3  [blue] 5  [red] 0")
        opacity: 0.75
    }
}
