# Worklog Calendar — Windows 11 (WinUI 3 / C# / XAML)

Aplicación **de escritorio** para Windows 11 que muestra una **vista
semanal** (Domingo a Sábado, o Lunes a Domingo) con los **worklogs** del
usuario, con tres fuentes intercambiables:

- **Jira** — worklogs vía la REST API v3 de Jira Cloud (auth Basic con
  email + API token).
- **Clockify** — time entries vía la API v1 con `X-Api-Key`.
- **Jira / Clockify** (combinado) — cada día se parte en dos columnas
  verticales: Jira a la izquierda (lila), Clockify a la derecha (verde).
  Sirve para detectar qué falta cargar y para mirror Jira → Clockify con
  un click.

Es el port **1-a-1** del plasmoide KDE Plasma 5 que vive en
`worklog-plasmoid/`, reescrito en **WinUI 3 + C# 12** sobre **.NET 8** y
el **Windows App SDK 1.6**. La app se ejecuta como un `.exe`
desempaquetado (sin MSIX, sin Microsoft Store): basta con copiar la
carpeta publicada o usar el script `install.ps1`.

## Capturas de pantalla rápidas (descripción)

- Header con título dinámico, navegación de semana (◀ Hoy ▶), toggle
  9h↔24h, refrescar, diagnóstico, configuración.
- Grilla semanal: 7 columnas con header + fila de totales (color verde
  si llegaste al objetivo diario, amarillo si no) + 18 filas de 30 min
  en modo 9h (36 en modo 24h).
- Footer con totales de la semana y, en modo combinado, picker del
  proyecto Clockify destino + botón **Jira → Clockify**.
- Bloques de worklog con dos líneas (rango horario + issue key/proyecto)
  cuando ocupan más de 30 min, una sola línea cuando son cortos.
- Drag-to-create: arrastrá verticalmente sobre cualquier día y se
  abre el modal correspondiente con la hora pre-cargada.

---

## Requisitos

| | Mínimo |
|---|---|
| OS | Windows 10 1809 (build 17763) o posterior — recomendado Windows 11 |
| .NET | SDK 8.0+ (sólo para compilar) |
| Arquitectura | x64, x86 o ARM64 |
| Runtime | El binario publicado es **self-contained**: no requiere instalar nada en la máquina destino |

Para compilar desde código fuente:

1. [Visual Studio 2022 17.8+](https://visualstudio.microsoft.com/) con la
   workload *Desarrollo de la plataforma universal de Windows* y el
   componente *Windows App SDK C# Templates*, **o** simplemente el
   [.NET SDK 8.x](https://dotnet.microsoft.com/) + `dotnet workload
   install windowsappsdk` (no es estrictamente necesario porque la
   referencia a Windows App SDK viene por NuGet).
2. PowerShell 7+ para usar `build.ps1` / `install.ps1` (Windows
   PowerShell 5.1 también sirve).

## Instalación rápida

```powershell
# Desde el repo, en una terminal PowerShell:
cd worklog-winui
.\install.ps1               # build x64 + copia a %LOCALAPPDATA%\Programs\WorklogCalendar
                            # + crea acceso directo en el menú Inicio

# Otras opciones:
.\install.ps1 -Arch arm64   # build ARM64
.\install.ps1 -NoBuild      # reusar bin\... existente
.\install.ps1 -Uninstall    # remover instalación
```

También se puede compilar sin instalar:

```powershell
.\build.ps1                 # build x64 Release; el exe queda en
                            # src\WorklogCalendar\bin\x64\Release\...\publish\WorklogCalendar.exe
.\build.ps1 -Arch arm64 -SelfContained
```

O usar Visual Studio: abrir `WorklogCalendar.sln`, elegir la
plataforma (x64 / x86 / ARM64), F5.

## Primera ejecución

1. Abrir la app. Sin credenciales, el calendario muestra el estado
   "Faltan credenciales".
2. Click en **⚙ Configurar…** → pestaña **Jira**:
   - **Site URL**: `https://tu-empresa.atlassian.net`
   - **Email**: el de tu cuenta Atlassian
   - **API token**: generalo en
     <https://id.atlassian.com/manage-profile/security/api-tokens>
3. (opcional) Pestaña **Clockify**:
   - **API key**: Profile → Settings → API en Clockify
   - **Workspace ID**: dejá vacío — se autoresuelve en el primer fetch.
   - **Proyecto por defecto** + **billable**: usados al crear entradas
     nuevas y por el sync Jira→Clockify.
4. Guardar. La app dispara el fetch automáticamente.

## Modos

| Modo | Qué muestra |
|---|---|
| **Jira** | Worklogs de Jira ocupando todo el día. |
| **Jira / Clockify** | Día partido al medio: Jira (lila) izquierda, Clockify (verde) derecha. Aparece el botón **Jira → Clockify** en el footer. |
| **Clockify** | Solo time entries de Clockify, full width, coloreadas con el color del proyecto si lo tiene. |

Se cambia desde el botón desplegable del header.

## Drag-to-create

Arrastrá verticalmente sobre cualquier columna de día para crear una
entrada:

- En **modos puros** se abre directamente el modal correspondiente.
- En **modo combinado**, la mitad **izquierda** abre el modal de Jira,
  la **derecha** el de Clockify. El rectángulo del drag se ajusta a la
  mitad correspondiente.

Cada paso del drag se *snapea* a slots de 30 min.

## Sync Jira → Clockify

En modo combinado el footer muestra un picker de proyecto y un botón
**Jira → Clockify**. Lógica:

1. Por cada worklog de Jira en la semana visible, mira si ya existe una
   entry Clockify con la misma `description` y un `start` ±1 min.
2. Si no existe, crea una nueva:
   - `start`/`end` = los del worklog Jira (en hora local)
   - `description` = `<issueKey>: <issueSummary>` (ej. `CP-1234: Fixear bug`)
   - `billable` = el default configurado
   - `projectId` = el seleccionado en el picker del footer (vacío = sin proyecto)
3. Reporta `created / skipped / failed` en la barra de estado.

Después del sync se refresca automáticamente la semana.

## Persistencia y datos

- **Configuración**: `%LOCALAPPDATA%\WorklogCalendar\settings.json`.
  Es JSON plano, podés editarlo a mano si querés.
- **Sin base local**: la app no cachea worklogs ni entries en disco;
  cada cambio de semana dispara un fetch fresco. El estado vive en
  memoria mientras la ventana esté abierta.
- **Sin telemetría**, sin red salvo a Jira / Clockify.

## Configuración disponible

Pestaña **General**:

| Campo | Default | Notas |
|---|---|---|
| Modo de vista | 9h | `9h` (09:00–18:00) o `24h` (00:00–24:00) |
| Fuente por defecto | Jira | Jira / Jira-Clockify / Clockify |
| Primer día de la semana | Domingo | Domingo / Lunes |
| Objetivo diario (horas) | 8 | Para el diff de la fila de totales |
| Ancho × alto ventana | 1280 × 760 | Pixels al arrancar |
| Mantener sobre otras ventanas | off | always-on-top toggle |

Pestaña **Jira**:

| Campo | Notas |
|---|---|
| Site URL | sin `/` final |
| Email | El de tu cuenta Atlassian |
| API token | Tokens con scopes mínimos: `read:jira-work`, `write:jira-work`, `read:me` |
| JQL del picker | Default: `assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC` |
| Máx. issues picker | 50 (entre 10 y 200) |
| Mostrar título de issue | Si on, los bloques Jira muestran `CP-XXXX: título`; si off, solo `CP-XXXX` |
| Logs | Toggle de `Debug.WriteLine` por request |

Pestaña **Clockify**:

| Campo | Notas |
|---|---|
| API key | Clockify → Profile → Settings → API |
| Workspace ID | Opcional. Si está vacío, se resuelve al default del usuario en la primera sync |
| Proyecto por defecto (ID) | Pre-seleccionado en el modal y usado por Jira→Clockify |
| Billable por defecto | on/off |
| Logs | Idem Jira |

## Endpoints

### Jira

- `GET /rest/api/3/myself` — accountId
- `GET /rest/api/3/search/jql?fields=summary,worklog` — semana
- `POST/PUT/DELETE /rest/api/3/issue/<key>/worklog[/<id>]`

### Clockify (base `https://api.clockify.me/api/v1`)

- `GET /user` — resolver `userId` + workspace default
- `GET /workspaces/{wid}/projects?archived=false`
- `GET /workspaces/{wid}/tags?archived=false`
- `GET /workspaces/{wid}/user/{uid}/time-entries?start=…&end=…`
- `POST /workspaces/{wid}/time-entries`
- `PUT /workspaces/{wid}/time-entries/{id}`
- `DELETE /workspaces/{wid}/time-entries/{id}`

## Estructura del repo (este subdirectorio)

```
worklog-winui/
├── README.md                ← este archivo
├── docs/
│   ├── INSTALL.md           ← guía completa de build/install
│   ├── CONFIGURATION.md     ← detalle de cada opción
│   └── ARCHITECTURE.md      ← diseño / mapeo QML → C#
├── build.ps1                ← compila (Release, configurable arch)
├── install.ps1              ← compila + copia a %LOCALAPPDATA%\Programs
├── WorklogCalendar.sln
└── src/WorklogCalendar/
    ├── WorklogCalendar.csproj
    ├── app.manifest
    ├── App.xaml(.cs)        ← bootstrap, brushes globales
    ├── MainWindow.xaml(.cs) ← header / footer / week dispatcher
    ├── Models/Models.cs     ← DTOs Jira + Clockify
    ├── Services/
    │   ├── AppSettings.cs   ← persiste a settings.json
    │   ├── JiraWorklogStore.cs    ← port de JiraWorklogStore.qml
    │   └── ClockifyStore.cs       ← port de ClockifyStore.qml
    ├── Controls/
    │   └── WeekCalendarControl.xaml(.cs)  ← grilla semanal + drag
    └── Views/
        ├── SettingsDialog.xaml(.cs)
        ├── JiraEditDialog.xaml(.cs)
        ├── ClockifyEditDialog.xaml(.cs)
        └── DiagnosticsDialog.xaml(.cs)
```

## Mapeo plasmoide → WinUI 3

| QML / Plasma | C# / WinUI 3 |
|---|---|
| `main.qml` (dispatcher) | `App.xaml.cs` + `MainWindow.xaml.cs` |
| `FullRepresentation.qml` | `MainWindow.xaml` (header + footer + status) |
| `WorklogCalendar.qml` | `Controls/WeekCalendarControl.xaml.cs` |
| `WorklogEntry.qml` | bloque inline construido en `WeekCalendarControl.BuildBlock` |
| `WorklogEditDialog.qml` | `Views/JiraEditDialog.xaml.cs` |
| `ClockifyEditDialog.qml` | `Views/ClockifyEditDialog.xaml.cs` |
| `configGeneral/Jira/Clockify.qml` | `Views/SettingsDialog.xaml.cs` (un solo Pivot con 3 pestañas) |
| `JiraWorklogStore.qml` | `Services/JiraWorklogStore.cs` |
| `ClockifyStore.qml` | `Services/ClockifyStore.cs` |
| `plasmoid.configuration` (KConfig) | `Services/AppSettings.cs` (JSON) |
| `XMLHttpRequest` | `System.Net.Http.HttpClient` |
| `Qt.btoa` | `Convert.ToBase64String(UTF8.GetBytes(...))` |

## Diferencias intencionales con el plasmoide

- **Sin pin** — al ser una ventana desktop ya no hay foco a perder.
  Reemplazado por un toggle *always-on-top* en Configuración → General.
- **Sin vista compacta** — no hay panel en Windows. La ventana es la
  representación full.
- **Sin SQLite local** — el plasmoide no cacheaba worklogs en disco;
  acá lo replicamos. Si querés persistencia local más adelante se puede
  agregar `Microsoft.Data.Sqlite`.
- **Settings en JSON** en vez de KConfig (con la misma semántica de
  "credenciales compartidas" pero como una sola app, no comparte con
  Categorized ToDo).
- **i18n**: las labels van hard-coded en español, igual que en el
  plasmoide original.

## Troubleshooting

**“No se pudo obtener el usuario actual (HTTP 401)”** — el token está
mal, el email no coincide, o la URL del site tiene un `/` extra. El
botón Diagnóstico (ⓘ) muestra el log completo de la última request.

**“HTTP 403 contra /workspaces/{wid}/…”** — el Workspace ID guardado no
es un Object ID válido (24 hex chars). La app autodetecta y guarda el
default del usuario en el siguiente fetch.

**El bloque clipea bajo otra entrada** — la grilla no resuelve overlap
de worklogs solapados; lo mismo que el plasmoide. Si dos entries
arrancan en el mismo slot se renderean superpuestas.

## Licencia

MIT.
