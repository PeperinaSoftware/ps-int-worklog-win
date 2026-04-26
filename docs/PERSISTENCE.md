# Persistencia de datos

Este documento explica **dónde** se guardan las tareas y la configuración del
plasmoide *Categorized ToDo*, **cómo** se persisten y **cómo depurar** si
algo no se guarda. Está pensado para Kubuntu 24.04 con KDE Plasma 5.27 y
Qt 5.15, pero aplica a cualquier instalación equivalente.

---

## TL;DR

- Las **tareas** (activas + archivadas) se guardan como **archivos JSON**
  bajo:
  ```
  ~/.local/share/categorizedtodo/
  ```
- La **configuración** del widget (cantidad de categorías, nombres,
  colores, opciones del panel/popup) sigue en `Plasmoid.configuration` →
  `~/.config/plasma-org.kde.plasma.desktop-appletsrc`.
- Las escrituras de las tareas son **atómicas** (escribir a `*.tmp` y
  hacer `mv`), así que un crash o reinicio nunca deja archivos a medio
  escribir.
- Backup = copiar la carpeta. Restore = volver a copiarla.

---

## Por qué se cambió desde `Plasmoid.configuration`

Plasma 5 expone `Plasmoid.configuration` como un `KConfigPropertyMap`
con escritura **debounced**: los cambios se acumulan y se vuelcan al
disco un rato después. Las categorías y colores se persistían porque el
diálogo *Configurar* llama `writeConfig()` al pulsar Aceptar. Pero las
tareas se editan desde el popup, sin pasar por ese diálogo, y a pesar
de que agregamos un `writeConfig()` explícito en `TaskStore.save()` el
flush no era confiable en algunos setups (race con el shutdown de
plasmashell, posibles bugs en versiones específicas de
`KConfigPropertyMap`).

Para cortar el problema de raíz se migró el storage de tareas a
**archivos JSON propios** que el plasmoide controla por completo. La
configuración del widget (que sí persiste bien) queda donde está.

---

## Layout en disco

```
~/.local/share/categorizedtodo/
├── manifest.json           # metadatos del store
├── 0-personal.json         # tareas activas de la categoría 0
├── 1-trabajo.json          # tareas activas de la categoría 1
├── 2-estudio.json          # tareas activas de la categoría 2
├── 3-otros.json            # tareas activas de la categoría 3
└── archived.json           # tareas archivadas (de cualquier categoría)
```

El nombre de cada archivo de tareas combina el **índice** de la
categoría (estable) y un **slug** del nombre de la categoría
(legible). Si renombrás una categoría, el archivo se renombra
automáticamente en el siguiente save.

### Ejemplo: `manifest.json`

```json
{
  "schema": "categorizedtodo.v1",
  "nextId": 7,
  "slugs": ["personal", "trabajo", "estudio", "otros"],
  "updatedAt": 1736290800000
}
```

`nextId` es el contador para asignar IDs únicos a tareas y subtareas;
`slugs` permite detectar renombres de categorías entre sesiones.

### Ejemplo: `0-personal.json`

```json
{
  "schema": "categorizedtodo.v1",
  "categoryIndex": 0,
  "categoryName": "Personal",
  "tasks": [
    {
      "id": 1,
      "title": "Comprar pan",
      "description": "Panadería de la esquina",
      "category": 0,
      "priority": "M",
      "done": false,
      "createdAt": 1736290000000,
      "archivedAt": 0,
      "subtasks": [
        { "id": 2, "title": "Pedir integral", "priority": "S", "done": false }
      ]
    }
  ]
}
```

### Ejemplo: `archived.json`

```json
{
  "schema": "categorizedtodo.v1",
  "tasks": [
    {
      "id": 5,
      "title": "Pagar luz",
      "category": 1,
      "priority": "L",
      "done": true,
      "createdAt": 1735000000000,
      "archivedAt": 1736000000000,
      "subtasks": []
    }
  ]
}
```

---

## Cómo se escriben los archivos (sin librerías externas)

QML por sí solo no tiene API para escribir archivos. La solución usada
combina dos piezas que ya vienen con Plasma 5.27 + Qt 5.15:

1. **Lectura**: `XMLHttpRequest` síncrona contra URLs `file://`.
2. **Escritura**: `org.kde.plasma.core 2.0` `DataSource { engine:
   "executable" }` que ejecuta un comando shell.

El comando es un `sh -c` con argumentos posicionales para que el JSON
nunca se interpole en el script:

```sh
sh -c 'mkdir -p "$1" && \
       printf "%s" "$3" | base64 -d > "$1/$2.tmp" && \
       mv -f "$1/$2.tmp" "$1/$2"' \
   sh "$DIR" "$FILENAME" "$BASE64_JSON"
```

- El JSON se **codifica en base64** desde QML (`Qt.btoa`) y se
  decodifica en la shell (`base64 -d`). Así no hay que escapar
  comillas, saltos de línea, ni caracteres raros.
- La escritura es **atómica** (`mv` en el mismo filesystem es atómico
  por POSIX).
- Los nombres de archivo se validan con un regex estricto
  (`^[a-zA-Z0-9._-]+$`) antes de pasarlos a la shell, así que no hay
  superficie de inyección.

El código vive en `package/contents/ui/FileStore.qml`.

---

## Verificarlo manualmente

```bash
# Listar el contenido del store
ls -la ~/.local/share/categorizedtodo/

# Ver el manifest (legible si tenés jq)
cat ~/.local/share/categorizedtodo/manifest.json | jq .

# Ver las tareas de una categoría
cat ~/.local/share/categorizedtodo/0-personal.json | jq .

# Ver las archivadas
cat ~/.local/share/categorizedtodo/archived.json | jq .
```

### En vivo

```bash
inotifywait -m ~/.local/share/categorizedtodo/
```

Cada vez que agregues, edites o archives una tarea deberías ver
eventos `CREATE` / `MOVED_TO` / `CLOSE_WRITE,CLOSE`.

---

## Backup / migración

```bash
# Backup
cp -a ~/.local/share/categorizedtodo ~/categorizedtodo-bak

# Restore
cp -a ~/categorizedtodo-bak/. ~/.local/share/categorizedtodo/
```

Para mover tareas entre máquinas o entre instancias del plasmoide
**sin tocar la carpeta**, usá el botón **Exportar / Importar JSON** que
tiene cada categoría desde la cabecera de la pestaña.

---

## Configuración del widget (sigue en KConfig)

Las opciones de Configurar (cantidad de categorías, sus nombres y
colores, estilo del contador en el panel, tamaño del popup, etc.)
viven en:

```
~/.config/plasma-org.kde.plasma.desktop-appletsrc
```

dentro de la sección `[Containments][N][Applets][M][Configuration][General]`
del applet. Se persisten mediante el flujo estándar del diálogo
*Configurar* (Apply / OK), que sí dispara un `writeConfig()` confiable.

---

## Debug: si las tareas no persisten

1. **Carpeta y permisos**:
   ```bash
   ls -la ~/.local/share/categorizedtodo/
   ```
   Debe existir (la crea el plasmoide al cargar) y ser tuya con
   permiso de escritura.

2. **El plasmoide está cargando esta versión**: si lo instalaste en
   modo dev (`./install.sh --dev`), refrescá plasmashell:
   ```bash
   kquitapp5 plasmashell && kstart5 plasmashell
   ```

3. **Logs QML**:
   ```bash
   journalctl --user -f -u plasma-plasmashell.service | grep -iE 'fileStore|TaskStore'
   ```
   El `FileStore` registra `console.warn(...)` cuando un comando shell
   sale con código distinto de 0 (incluyendo `stderr`).

4. **El comando shell no se está ejecutando**: usá `inotifywait` (ver
   arriba) mientras agregás una tarea. Si no llega ningún evento, el
   `DataSource` no está disparando — verificá que `org.kde.plasma.core
   2.0` esté disponible y revisá las trazas de plasmashell.

5. **JSON corrupto**: el lector tiene `try/catch` y loggea el error.
   Si un archivo está corrupto borralo:
   ```bash
   rm ~/.local/share/categorizedtodo/<nombre>.json
   ```
   El plasmoide arrancará con esa categoría vacía pero el resto se
   conserva.

6. **Reset completo**:
   ```bash
   rm -rf ~/.local/share/categorizedtodo
   ```
   Arranca de cero (la configuración del widget no se toca).

---

## Por qué no usamos otra librería

- **Qt.labs.settings**: termina escribiendo a `QSettings` (INI) — el
  mismo modelo "diferido" que ya nos falló con `Plasmoid.configuration`.
- **`Qt.labs.platform` `FileDialog`**: requiere intervención del
  usuario; no sirve para guardar automáticamente.
- **`XMLHttpRequest` PUT a `file://`**: en Qt 5.15 la implementación
  para escritura local no es confiable y depende del build.
- **Plugin C++ propio**: agrega complejidad y dependencias de
  compilación; el objetivo era mantenerse en QML puro.

`PlasmaCore.DataSource` con `engine: "executable"` ya viene con todas
las instalaciones estándar de Plasma 5.27 — no es una "librería
externa" sino parte del framework del entorno de ejecución del
plasmoide.
