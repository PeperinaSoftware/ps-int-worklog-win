# Jira Worklog Calendar — KDE Plasma 5 plasmoid

Plasmoide independiente que muestra **una vista semanal** (Domingo a Sábado)
con los **worklogs** del usuario actual en Jira Cloud. Permite **arrastrar
sobre el grid** para crear un worklog y abre un modal que pide la
issue/subtarea a la cual cargarle las horas.

Compatible con Kubuntu 24.04 / Plasma 5.27 / Qt 5.15. QML puro, sin librerías
nativas. Comparte las credenciales de Jira con el plasmoide **Categorized
ToDo** (mismo archivo KConfig `categorizedtodorc`), así que si ya lo tenés
configurado no hay que volver a meter sitio + email + token.

---

## Qué hace

- **Vista compacta (panel)**: un solo ícono de calendario.
- **Vista grande (popup)**:
  - Barra superior con **← / Hoy / →** para navegar semanas, label de rango,
    toggle **9h ↔ 24h**, botón de sync manual (↻) y diagnóstico (ⓘ).
  - Grid de 7 columnas (Dom → Sáb). **Cada línea = 30 minutos.**
  - **Drag** sobre un día → modal con time pre-llenado + picker de issue.
  - **Click** en un block existente → modal de edición / eliminación.
  - Fila "total" debajo del header con horas cargadas vs. objetivo diario
    (configurable, default 8h).

---

## Cómo se conecta a Jira

Usa el endpoint nuevo (`/rest/api/3/search/jql`) y los endpoints de
worklog:

| Acción                       | Endpoint                                                              |
| ---------------------------- | --------------------------------------------------------------------- |
| Detectar usuario actual      | `GET /rest/api/3/myself`                                              |
| Issues con worklog semanal   | `POST /rest/api/3/search/jql` con `worklogAuthor = currentUser()...`  |
| Listar issues del picker     | `POST /rest/api/3/search/jql` con el JQL configurable (default mío)   |
| Crear worklog                | `POST /rest/api/3/issue/<key>/worklog`                                |
| Modificar worklog            | `PUT /rest/api/3/issue/<key>/worklog/<id>`                            |
| Borrar worklog               | `DELETE /rest/api/3/issue/<key>/worklog/<id>`                         |

Auth: HTTP Basic con email + API token. El token se guarda en el mismo
archivo que usa el plasmoide *Categorized ToDo* (`~/.config/categorizedtodorc`).

---

## Instalación

Asume que ya tenés Plasma 5.27 + Qt 5.15 + el módulo `QtQuick.Controls 2`
(que el plasmoide ToDo ya valida; si no, instalá
`qml-module-qtquick-controls2`).

```bash
cd worklog-plasmoid
./install.sh             # instala (o upgradea)
./install.sh --dev       # symlink para desarrollo
./install.sh --uninstall # remover

# Recargar Plasma:
kquitapp5 plasmashell && kstart5 plasmashell
```

Una vez instalado, click derecho en el panel → *Add Widgets* → buscá
**"Jira Worklog Calendar"** y arrastralo.

---

## Configuración

Pestaña **General**:
- Modo de vista (9h o 24h).
- Ancho y alto del popup.
- Horas objetivo por día (para el diff en la fila de totales).
- **JQL del picker** (con default `assignee = currentUser() AND
  statusCategory != Done ORDER BY updated DESC`).
- Máximo de issues a traer en el picker.
- Toggle de logs.

Pestaña **Jira**:
- Sitio, email, API token.
- Botón **Probar** que ejecuta `/rest/api/3/myself`.
- Las credenciales **son las mismas** que las del plasmoide *Categorized
  ToDo*. Cualquier cambio acá impacta allá y viceversa.

---

## Flujo típico

1. Abrir el popup.
2. **Drag** vertical sobre el día → modal "Nuevo worklog".
3. En el modal:
   - El rango de tiempo viene pre-llenado (se puede ajustar en pasos de
     30 min con los `+ / -`).
   - Elegir la issue del picker (filtrable por texto).
   - Agregar comentario opcional.
   - Guardar.
4. El modal se cierra y dispara un re-sync; el block aparece en el grid.
5. Para **editar**, click en un block; sale el mismo modal con la issue
   bloqueada (la API de Jira no permite mover un worklog de issue) y un
   botón **Eliminar**.

---

## Limitaciones conocidas

- Solo lectura de los worklogs propios. No se muestran worklogs de otros
  usuarios.
- El comentario se envía/recibe como ADF *plain text* (1 párrafo). Sin
  formatting, sin menciones.
- El picker trae como mucho `worklogIssueMax` issues. Para conjuntos más
  grandes, ajustá el JQL.
- Drag solo dentro de un único día. Para spans multi-día creá dos worklogs.
- Sync es **solo manual** por ahora (botón ↻).

---

## Debugging

Activá *Logs* en la pestaña General y mirá:

```bash
journalctl --user -f _COMM=plasmashell | grep '\[JiraWorklog\]'
```

O abrí el botón **ⓘ** del popup: el log de la última request se acumula
ahí incluso si el toggle de consola está apagado.

---

## Licencia

MIT.
