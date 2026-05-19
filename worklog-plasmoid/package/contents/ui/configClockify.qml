/*
 * configClockify.qml - Clockify tab.
 *
 * Auth via the X-Api-Key header. Generate the key at
 * https://app.clockify.me/user/settings → API. The plasmoid will resolve
 * workspaceId + userId on first sync via GET /user and cache them.
 */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import org.kde.kirigami 2.5 as Kirigami

ColumnLayout {
    id: page
    spacing: Kirigami.Units.largeSpacing

    property alias cfg_clockifyApiKey:           keyField.text
    property alias cfg_clockifyWorkspaceId:      workspaceField.text
    property alias cfg_clockifyDefaultProjectId: defaultProjectField.text
    property alias cfg_clockifyBillableDefault:  billableCheck.checked

    Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.75
        text: i18n("Clockify se autentica con un API key personal. Generalo en "
                 + "Clockify → Perfil → Settings → API y pegalo abajo. El plasmoide "
                 + "resuelve usuario + workspace automáticamente en la primera sincronización.")
    }

    Kirigami.FormLayout {
        Layout.fillWidth: true

        RowLayout {
            Kirigami.FormData.label: i18n("API key:")
            spacing: Kirigami.Units.smallSpacing
            TextField {
                id: keyField
                Layout.fillWidth: true
                echoMode: showKey.checked ? TextInput.Normal : TextInput.Password
                placeholderText: i18n("Pegá tu API key acá")
                inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
            }
            CheckBox {
                id: showKey
                text: i18n("Ver")
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Workspace ID:")
            spacing: Kirigami.Units.smallSpacing
            TextField {
                id: workspaceField
                Layout.fillWidth: true
                placeholderText: i18n("Vacío = usa tu workspace por defecto")
                inputMethodHints: Qt.ImhNoPredictiveText
            }
            Button {
                text: i18n("Limpiar")
                icon.name: "edit-clear"
                enabled: workspaceField.text.length > 0
                onClicked: workspaceField.text = ""
                ToolTip.text: i18n("Vaciar el campo para que el plasmoide use el workspace por defecto")
                ToolTip.visible: hovered
                ToolTip.delay: 500
            }
        }

        Label {
            Kirigami.FormData.label: ""
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            opacity: 0.65
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            text: i18n("Es un Object ID hex de 24 caracteres (ej. 60661036c145ea559a4e8be6), no "
                     + "el nombre del workspace. Si lo dejás vacío, el plasmoide va a resolver "
                     + "tu workspace por defecto en la primera sincronización.")
        }

        TextField {
            id: defaultProjectField
            Kirigami.FormData.label: i18n("Proyecto por defecto (ID):")
            Layout.fillWidth: true
            placeholderText: i18n("Vacío = ninguno. Usado al sincronizar Jira → Clockify.")
            inputMethodHints: Qt.ImhNoPredictiveText
        }

        CheckBox {
            id: billableCheck
            Kirigami.FormData.label: i18n("Billable:")
            text: i18n("Marcar como facturable por defecto en nuevas entradas")
        }
    }

    GroupBox {
        Layout.fillWidth: true
        title: i18n("Probar conexión")

        ColumnLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                Button {
                    text: i18n("Probar")
                    icon.name: "network-connect"
                    onClicked: {
                        statusLabel.text = i18n("Conectando…");
                        statusLabel.color = palette.text;
                        page._test(keyField.text);
                    }
                }
                Item { Layout.fillWidth: true }
            }
            Label {
                id: statusLabel
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: ""
            }
        }
    }

    Item { Layout.fillHeight: true }

    function _test(key) {
        key = (key || "").trim();
        if (!key) {
            statusLabel.text = i18n("Pegá una API key antes de probar.");
            statusLabel.color = "#e74c3c";
            return;
        }
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "https://api.clockify.me/api/v1/user", true);
        xhr.setRequestHeader("X-Api-Key", key);
        xhr.setRequestHeader("Accept", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                try {
                    var d = JSON.parse(xhr.responseText);
                    statusLabel.text = i18n("OK — autenticado como %1 (workspace: %2).",
                                            d.name || d.email || "?",
                                            d.defaultWorkspace || "?");
                    statusLabel.color = "#2ecc71";
                } catch (e) {
                    statusLabel.text = i18n("OK (200) pero respuesta inesperada.");
                    statusLabel.color = "#2ecc71";
                }
            } else if (xhr.status === 401 || xhr.status === 403) {
                statusLabel.text = i18n("Credenciales rechazadas (HTTP %1).", xhr.status);
                statusLabel.color = "#e74c3c";
            } else if (xhr.status === 0) {
                statusLabel.text = i18n("No se pudo contactar el servidor.");
                statusLabel.color = "#e74c3c";
            } else {
                statusLabel.text = i18n("HTTP %1: %2", xhr.status,
                                         (xhr.responseText || "").substring(0, 200));
                statusLabel.color = "#e74c3c";
            }
        };
        try { xhr.send(); }
        catch (e) {
            statusLabel.text = i18n("Error de red: %1", e);
            statusLabel.color = "#e74c3c";
        }
    }
}
