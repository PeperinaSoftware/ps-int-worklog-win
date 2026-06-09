# Arquitectura

Port en Windows del plasmoide KDE `worklog-plasmoid/`. Misma división
de responsabilidades pero idiomas distintos: QML+JS pasa a XAML+C#, y
la inyección de dependencias por propiedades (`store: _jira`) pasa a
constructor args + propiedades en code-behind.

## Pirámide

```
                ┌──────────────────┐
                │   MainWindow     │  ← header, footer, week nav
                └──────────────────┘
                          │
              ┌───────────┴───────────┐
              │                       │
   ┌──────────────────────┐  ┌─────────────────────┐
   │ WeekCalendarControl  │  │ ContentDialogs:     │
   │ (grid + drag-create) │  │  Settings           │
   └──────────────────────┘  │  JiraEdit           │
              │              │  ClockifyEdit       │
              │              │  Diagnostics        │
              ▼              └─────────────────────┘
   ┌──────────────────────┐
   │ JiraWorklogStore     │ ──┐
   │ ClockifyStore        │ ──┤  (HttpClient + JSON)
   └──────────────────────┘   │
              │               │
              ▼               ▼
        AppSettings ──►  settings.json
```

## Stores: dueños del estado

Los dos stores (`JiraWorklogStore`, `ClockifyStore`) implementan
`INotifyPropertyChanged` y guardan listas inmutables (`IReadOnlyList`)
que se reasignan completas en cada fetch. La UI escucha
`PropertyChanged` y rebuildea su parte.

Ningún view alcanza directamente a la red ni al archivo de settings —
sólo lee/escribe a través de los stores y de `AppSettings`.

### Mutaciones

- `JiraWorklogStore.CreateWorklogAsync(...)` → `POST /worklog`
- `JiraWorklogStore.UpdateWorklogAsync(...)` → `PUT /worklog/<id>`
- `JiraWorklogStore.DeleteWorklogAsync(...)` → `DELETE /worklog/<id>`
- `ClockifyStore.CreateEntryAsync(...)`     → `POST /time-entries`
- `ClockifyStore.UpdateEntryAsync(...)`     → `PUT /time-entries/<id>`
- `ClockifyStore.DeleteEntryAsync(...)`     → `DELETE /time-entries/<id>`

Tras un mutate exitoso, el diálogo cierra y la window dispara
`RefreshAsync()` que es el equivalente a `syncNow()` del plasmoide.

## Renderizado de la semana

`WeekCalendarControl.xaml.cs` construye la grilla **programáticamente**
en `Refresh()`. Razones:

1. El número de filas depende de `viewMode` (18 vs 48 slots).
2. La fila de totales por día cambia color según `dailyTargetHours`.
3. Los bloques se posicionan absolutamente sobre un `Canvas` por día,
   con `Canvas.SetTop` calculado desde el `started` unix-ms y
   `RowHeight = 22 px`.

Cada bloque guarda en su `Tag` la metadata (`isJira`, `startedMs`,
`durationSec`, ref a la entry) para que el layout pueda recolocarlo
ante cambios de tamaño del Canvas.

## Drag-to-create

`PointerPressed` en el `Canvas` del día captura el cursor y arranca un
estado de drag con la `pressY` (y, en modo combinado, `pressLeft`).
`PointerMoved` actualiza el overlay rectangular. `PointerReleased`
calcula `startMs / endMs` snapeados a 30 min y dispara
`CreateJiraRequested` o `CreateClockifyRequested`, que la MainWindow
abre como un `ContentDialog`.

Si el `OriginalSource` del press es un `Border` (un bloque ya
renderado) el drag NO arranca — eso permite clickear un bloque para
editar sin disparar drag.

## Async / threading

- `HttpClient` se reusa por store (singleton). Timeouts de 30 s.
- Todos los handlers de UI son `async void` (eventos) o
  `async Task` (métodos privados). Las llamadas a `HttpClient` ya están
  fuera del UI thread; los `PropertyChanged` los disparamos desde el
  thread llamante porque las assignments `Worklogs = list` ocurren tras
  el `await`, ya sobre el `SynchronizationContext` del dispatcher.

## Errores y diagnóstico

Cada store mantiene:

- `LastError` — string con el último error visible al usuario.
- `_log` (StringBuilder, máx 80k chars) — backbuffer para el diálogo
  Diagnóstico. Toda request hace `Log(...)` aunque el toggle
  `JiraDebug`/`ClockifyDebug` esté off.

El botón ⓘ del header abre `DiagnosticsDialog` que concatena ambos
logs.

## Comparación con la versión QML

| Característica | Plasmoide (QML) | WinUI 3 (C#) |
|---|---|---|
| Reactividad | `property var foo` + binding `foo.length` | `INotifyPropertyChanged` + handlers code-behind |
| HTTP | `XMLHttpRequest` | `HttpClient` |
| JSON | `JSON.parse` | `System.Text.Json.JsonDocument` |
| Persistencia | `Plasmoid.configuration` (KConfig) | `AppSettings` (JSON) |
| Modal | `Item { visible: ... }` overlay | `ContentDialog` |
| Drag overlay | `Rectangle` con `Qt.rgba` semitransparente | `Rectangle` (Shape) con `SolidColorBrush(alpha)` |
| Threading | callbacks JS sync | `async`/`await` |
| Build | `kpackagetool5 install` | `dotnet publish` + `install.ps1` |

## Para extender

- Agregar otra fuente (Toggl, Harvest, etc.) — crear `XxxStore.cs` con
  la misma firma de `JiraWorklogStore` (fetch / create / update /
  delete + `PropertyChanged`), agregar opción al `SourceChooser`, y
  hook al `WeekCalendarControl` (otro array de entries con su color).
- Cachear localmente con SQLite — agregar `Microsoft.Data.Sqlite`
  como NuGet ref y un `Database.cs` que el constructor de los stores
  use como write-through cache antes de devolver. El plasmoide usa
  `QtQuick.LocalStorage`; la lógica de migrations sería igual de
  trivial.
- Notificaciones de toast diarias — `Microsoft.Toolkit.Uwp.
  Notifications` (no se incluye en el port inicial).
