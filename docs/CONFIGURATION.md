# Configuración

Toda la configuración vive en
`%LOCALAPPDATA%\WorklogCalendar\settings.json`. La app la lee al
arrancar y la reescribe cada vez que se guarda el diálogo
**⚙ Configurar…** o cuando los stores autodetectan información (por
ejemplo el `workspaceId` de Clockify).

## settings.json — esquema completo

```jsonc
{
  // ---- Jira ----
  "jiraSite":   "https://your-company.atlassian.net",
  "jiraEmail":  "you@your-company.com",
  "jiraToken":  "ATATT3xFfGF0...",
  "jiraIssueJql": "assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC",
  "jiraIssueMax": 50,
  "showJiraSummary": false,
  "jiraDebug": true,

  // ---- Clockify ----
  "clockifyApiKey":  "YzY...",
  "clockifyWorkspaceId": "60f3...",     // auto-resuelto
  "clockifyUserId":      "60f3...",     // auto-resuelto
  "clockifyDefaultProjectId": "",
  "clockifyBillableDefault": true,
  "clockifyDebug": true,

  // ---- Vista / comportamiento ----
  "viewMode": "9h",                     // "9h" o "24h"
  "source":   "jira",                   // "jira" | "clockify" | "jira-clockify"
  "dailyTargetHours": 8,
  "windowWidth":  1280,
  "windowHeight": 760,
  "alwaysOnTop":  false,
  "firstDayOfWeek": 0                   // 0 = Domingo, 1 = Lunes
}
```

## Editor in-app

`⚙ Configurar…` abre un `ContentDialog` con un `Pivot` de 3 pestañas:

### General

- **Modo de vista** — Radio buttons `9h` vs `24h`. Define el rango
  vertical de la grilla. `9h` muestra 18 filas de 30 min (09:00 a
  18:00). `24h` muestra 48 filas.
- **Fuente por defecto** — al abrir la app se posiciona en esta
  fuente. Se puede cambiar en runtime desde el `DropDownButton` del
  header.
- **Primer día de la semana** — `Domingo` (default, mantiene la
  semántica del plasmoide) o `Lunes` (más natural en LATAM/Europa). La
  navegación `◀ Hoy ▶` respeta este valor.
- **Objetivo diario (horas)** — usado por la fila de totales. Si el
  total del día llega al target, la celda se pinta verde; si no,
  amarillo. Default 8h.
- **Ancho/alto ventana** — geometría inicial al arrancar la app.
- **Mantener sobre otras ventanas** — toggle `AppWindow.Presenter.
  IsAlwaysOnTop`, el equivalente al pin del plasmoide.

### Jira

- **Site URL** — `https://your-company.atlassian.net`. Se trimea el `/`
  final automáticamente.
- **Email** — el de tu cuenta Atlassian.
- **API token** — generalo en
  <https://id.atlassian.com/manage-profile/security/api-tokens>. El
  campo es un `PasswordBox` con peek.
- **JQL del picker** — query usada para llenar el modal "Nuevo
  worklog". Cambia esto si querés mostrar issues que no son tuyos, o
  filtrar por proyecto. Default:
  ```jql
  assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC
  ```
- **Máx. issues picker** — clamp 10..200.
- **Mostrar el título del issue además de la key** — afecta sólo el
  texto del bloque en la grilla. La fila de detalle del modal siempre
  muestra los dos.
- **Logs** — toggle de `Debug.WriteLine("[JiraWorklog] ...")`. Visible
  con DebugView, Visual Studio, o el diálogo ⓘ.

### Clockify

- **API key** — Profile → Settings → API en Clockify.
- **Workspace ID (opcional)** — dejá vacío. La app va a `GET /user` y
  guarda el `defaultWorkspace` automáticamente. Si pegás el *nombre*
  por error la app lo descarta (un workspaceId válido es 24 hex chars).
- **Proyecto por defecto (ID)** — usado por el modal "Nueva entrada
  Clockify" y por el sync Jira→Clockify. Vacío = sin proyecto.
- **Billable por defecto** — afecta sólo la creación de entradas
  nuevas. El modal de edición respeta el `billable` original de la
  entry.
- **Logs** — idem Jira.

## Reset

Para volver a factory defaults: cerrá la app y borrá
`%LOCALAPPDATA%\WorklogCalendar\settings.json`.

## Editar a mano

El archivo es JSON con comentarios desactivados (camelCase). Tras
editar, **reiniciá la app** para que tome los cambios — al guardar
desde el diálogo de Configuración la app reescribe el archivo y se
perderían los cambios manuales.

## Notas de seguridad

- Los tokens se guardan **en texto plano** en `settings.json`. Si
  necesitás storage seguro, el paquete `Windows.Security.Credentials`
  (PasswordVault) está disponible para una mejora futura.
- La app sólo hace requests a `*.atlassian.net` (configurable) y
  `api.clockify.me`. No hay telemetría.
