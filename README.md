# Categorized ToDo — KDE Plasma 5 plasmoid

Un plasmoide (gadget de escritorio y de panel) para **Kubuntu 24.04**
(**KDE Plasma 5.27** + **Qt 5.15**) que implementa una lista de tareas con
categorías, prioridades, subtareas y archivo.

Todo el código es QML puro. **No se usan librerías externas**: sólo los módulos
que vienen con Plasma 5 y Qt 5.15 (`org.kde.plasma.*`, `org.kde.kirigami`,
`QtQuick`, `QtQuick.Controls 2`, `QtQuick.Dialogs`).

---

## Características

### Vista completa (popup)

- **Pestañas por categoría** (hasta 4, configurable de 1 a 4). Cada pestaña
  tiene el color de la categoría, su nombre y un contador de tareas pendientes.
- **Alta rápida** de tareas por categoría (título + prioridad).
- **Botón “Nueva…”** para el diálogo completo con descripción, categoría
  y prioridad.
- Cada tarea muestra:
  - Casilla para marcarla como hecha.
  - Título (con tachado si está hecha).
  - Franja de color de la categoría a la izquierda.
  - Chip de prioridad **XS / S / M / L / XL** (coloreado según nivel).
  - Botón para **expandir** (ver descripción y subtareas).
  - Botón **Editar** (título, descripción, categoría, prioridad).
  - Botón **Archivar** (la manda al módulo de archivado; sólo ahí se
    puede borrar).
- **Subtareas** dentro de cada tarea: cada una con su propia casilla,
  prioridad, botón para editar y botón para eliminar. También una fila inline
  de “Agregar subtarea”.
- **Exportar / Importar JSON por categoría**:
  - Botón **Exportar** (icono de exportación) en la cabecera de cada
    pestaña: abre un diálogo con todo el JSON de esa categoría
    (incluyendo subtareas) listo para copiar al portapapeles.
  - Botón **Importar** (icono de importación) en la cabecera de cada
    pestaña: abre un diálogo donde se pega un JSON y se agregan las
    tareas a esa categoría. Soporta tanto el formato exportado
    (`{ schema, tasks: [...] }`) como un array plano de tareas.
- Pestaña **Archivo**:
  - Muestra las tareas archivadas con fecha y la categoría original.
  - Botón para **restaurar** a la lista activa.
  - Botón para **borrar permanentemente** (con confirmación opcional).
  - Botón para **vaciar archivo**.

### Vista compacta (panel / systray)

Diseñada para ir en una barra de tareas. Muestra, **en horizontal**, una
casilla con el color de cada categoría seguida del número de tareas
pendientes de esa categoría. Por ejemplo:

```
[verde] 1   [amarillo] 3   [azul] 5   [rojo] 0
```

Opciones (pestaña *Apariencia* de la configuración):
- **Disposición del contador**: a la derecha del cuadrado (predeterminado)
  o **dentro** del cuadrado (en ese caso el cuadrado es más grande y el
  número se centra dentro).
- **Color del número por categoría**: blanco o negro, elegido
  individualmente para que contraste con cada color de categoría.
- Mostrar u ocultar el nombre al lado del contador.
- Ocultar las categorías con 0 pendientes.

Clic abre el popup.

### Configuración (todo configurable)

Pestaña **General**:
- Cantidad de categorías activas (1 – 4).
- Mostrar / ocultar las insignias de prioridad.
- Confirmar antes de borrar permanentemente.
- Tamaño del popup (alto y ancho).

Pestaña **Categorías**:
- Nombre y color de las 4 ranuras de categoría (las que excedan la cantidad
  activa simplemente no se muestran; los datos no se pierden).
- Selector de color nativo Qt (`QtQuick.Dialogs.ColorDialog`).

Pestaña **Apariencia** (controla la vista compacta):
- Disposición del contador: a la derecha o dentro del cuadrado.
- Color del número (blanco / negro) por categoría con vista previa.
- Mostrar nombre al lado de cada contador.
- Mostrar categorías con cero pendientes.

---

## Instalación

Requisitos: Kubuntu 24.04 con Plasma 5.27 y Qt 5.15 (vienen por defecto).

```bash
# Desde el clon del repo
./install.sh            # instala para el usuario actual
./install.sh --dev      # en su lugar, hace un symlink (modo desarrollo)
./install.sh --uninstall
```

El script usa `kpackagetool5` (o `plasmapkg2` si está presente). Ambos ya
vienen con la sesión Plasma.

Una vez instalado, agrega el widget con:

1. Clic derecho en el escritorio o en el panel → **Agregar widgets…**.
2. Buscá **“ToDo”** o **“Categorized ToDo”**.
3. Arrastralo al escritorio (vista completa) o al panel (vista compacta).

Si el widget no aparece en el buscador, reiniciá Plasma:
```bash
kquitapp5 plasmashell && kstart5 plasmashell
```

---

## Estructura del paquete

```
package/
├── metadata.desktop              # metadatos del plasmoide (id, autor, …)
├── contents/
│   ├── config/
│   │   ├── main.xml              # esquema KCfg: opciones + datos serializados
│   │   └── config.qml            # define las pestañas del diálogo de config
│   └── ui/
│       ├── main.qml              # root: expone Compact y Full
│       ├── CompactRepresentation.qml   # vista para el panel
│       ├── FullRepresentation.qml      # popup con pestañas
│       ├── CategoryView.qml      # lista de tareas de una categoría
│       ├── ArchiveView.qml       # lista de archivadas
│       ├── TaskItem.qml          # delegate de una tarea (con subtareas)
│       ├── PriorityBadge.qml     # chip XS/S/M/L/XL
│       ├── PrioritySelector.qml  # combo XS/S/M/L/XL
│       ├── TabCountBadge.qml     # contador circular dentro de las pestañas
│       ├── TaskEditDialog.qml    # diálogo nuevo/editar tarea
│       ├── SubtaskEditDialog.qml # diálogo editar subtarea
│       ├── ExportDialog.qml      # diálogo de exportación JSON por categoría
│       ├── ImportDialog.qml      # diálogo de importación JSON por categoría
│       ├── CategoryHelper.qml    # helper: lee nombres/colores desde config
│       ├── FileStore.qml         # I/O atómico de archivos JSON propios
│       ├── TaskStore.qml         # modelo en memoria + persistencia
│       ├── configGeneral.qml     # pestaña General de la config
│       ├── configCategories.qml  # pestaña Categorías de la config
│       └── configAppearance.qml  # pestaña Apariencia de la config
├── install.sh
└── README.md
```

---

## Modelo de datos

Las tareas se guardan como **archivos JSON** bajo
`~/.local/share/categorizedtodo/`, uno por categoría más uno único de
archivado. La configuración del widget (categorías, colores, opciones
del panel) sigue en `Plasmoid.configuration`. Las escrituras son
atómicas (temp file + `mv`) y no usan ninguna librería externa: la
escritura va por `PlasmaCore.DataSource(engine: "executable")` que ya
viene con Plasma 5.27, y la lectura por `XMLHttpRequest` síncrono. Los
detalles —dónde vive cada archivo, cómo se escribe y cómo depurar—
están en [`docs/PERSISTENCE.md`](docs/PERSISTENCE.md).

Forma de cada tarea:

```json
{
    "id": 12,
    "title": "Comprar pan",
    "description": "Panadería de la esquina",
    "category": 0,
    "priority": "M",
    "done": false,
    "createdAt": 1730000000000,
    "archivedAt": 0,
    "subtasks": [
        { "id": 13, "title": "Pedir integral", "priority": "S", "done": false }
    ]
}
```

Dos arrays independientes: `tasksJson` (activas) y `archivedJson`
(archivadas). Cuando se **archiva** una tarea se mueve de uno a otro; cuando
se **restaura** se hace el movimiento inverso; cuando se **borra permanentemente**
se remueve del archivo. De esta forma, **una tarea sólo puede eliminarse
desde el archivo**, que es lo que pedimos.

---

## Flujo de uso

1. Crear una tarea: escribí el título en el campo superior de una pestaña y
   Enter, o clic en **“Nueva…”** para abrir el diálogo con descripción.
2. Expandí la tarea (botón ▼) para agregar subtareas y verlas.
3. Marcá la tarea (o subtarea) como completada con la casilla.
4. Cuando termines la tarea, clic en el botón de **archivar** (icono de caja).
   La tarea deja de aparecer en la pestaña de su categoría y pasa a
   **Archivo**.
5. Desde la pestaña **Archivo** podés:
   - Restaurarla a la lista activa.
   - Eliminarla permanentemente.
6. La vista compacta del panel refleja en tiempo real cuántas tareas
   pendientes hay por categoría.

---

## Desarrollo

Para iterar sin desinstalar/reinstalar cada vez:

```bash
./install.sh --dev            # hace un symlink al paquete
kquitapp5 plasmashell && kstart5 plasmashell
```

A partir de ahí cualquier cambio en `package/contents/ui/*.qml` se aplica
al recargar el plasmoide (o reiniciar plasmashell).

Logs de errores QML:
```bash
journalctl --user -f -u plasma-plasmashell.service
# o bien:
plasmashell --replace 2>&1 | grep -i -E 'qml|warning|error'
```

---

## Licencia

MIT. Ver cabecera en `metadata.desktop`.
