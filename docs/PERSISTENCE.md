# Persistencia de datos

Este documento explica **dónde** se guardan las tareas y la configuración del
plasmoide *Categorized ToDo*, **cómo** se persisten y **cómo depurar** si
algo no se guarda. Está pensado para Kubuntu 24.04 con KDE Plasma 5.27 y
Qt 5.15, pero aplica a cualquier instalación equivalente.

---

## TL;DR

- **Todo** (configuración + tareas activas + tareas archivadas) se guarda
  en el mismo archivo:
  ```
  ~/.config/plasma-org.kde.plasma.desktop-appletsrc
  ```
- Bajo la sección del applet (cada instancia es una sub-sección distinta),
  dentro del grupo `[Configuration][General]`.
- El plasmoide ahora hace un *flush* sincrónico (`writeConfig()`) después
  de cada cambio en las tareas, así nada se pierde aunque Plasma se cierre
  abruptamente.

---

## El bug original

Antes del fix, las **categorías y colores** se guardaban pero las
**tareas no**. Esto era contraintuitivo, ya que los dos viajan por el
mismo `Plasmoid.configuration`. La causa real:

1. Plasma expone `Plasmoid.configuration` en QML como un
   [`KConfigPropertyMap`](https://api.kde.org/frameworks/kdeclarative/html/classKDeclarative_1_1ConfigPropertyMap.html).
2. Cuando se escribe un valor (`plasmoid.configuration.X = ...`),
   `KConfigPropertyMap` programa una escritura **debounced**: se acumulan
   los cambios y un timer escribe en disco un rato más tarde.
3. Las **categorías y colores** se editan desde el diálogo *Configurar*,
   que al pulsar **Aceptar/Aplicar** llama explícitamente a
   `writeConfig()` antes de cerrarse → quedan en disco enseguida.
4. Las **tareas** se editan desde el popup, sin pasar por el diálogo de
   configuración. El timer interno *eventualmente* las habría escrito,
   pero un reinicio frío, un `kquitapp5 plasmashell`, o cualquier muerte
   abrupta del proceso ocurría antes de que se ejecutara, y los cambios
   se perdían.

---

## El fix

`package/contents/ui/TaskStore.qml` ahora invoca `writeConfig()` después
de cada mutación:

```qml
function save() {
    if (!plasmoid || !_loaded) return;
    plasmoid.configuration.tasksJson = JSON.stringify(tasks);
    plasmoid.configuration.archivedJson = JSON.stringify(archived);
    plasmoid.configuration.nextId = _nextId;
    _flushConfig();    // <-- forzamos la escritura
}

function _flushConfig() {
    if (plasmoid && plasmoid.configuration
            && typeof plasmoid.configuration.writeConfig === "function") {
        plasmoid.configuration.writeConfig();
    }
}
```

`writeConfig()` está expuesto como método invocable (`Q_INVOKABLE`) por
`KConfigPropertyMap`, así que se puede llamar directamente desde QML.
La operación es sincrónica y muy rápida (es un INI plano).

Además, **se consolidaron todas las entradas KCfg en el grupo `General`**
de `package/contents/config/main.xml`. Algunas combinaciones de Plasma
con grupos secundarios no exponen los entries de manera correcta; usar
un solo grupo evita ese terreno gris.

---

## Dónde viven los datos exactamente

Cada applet de Plasma se identifica por su posición en la jerarquía de
*Containments*. Para nuestro plasmoide la ruta del archivo es siempre la
misma:

```
~/.config/plasma-org.kde.plasma.desktop-appletsrc
```

Y dentro hay un fragmento parecido a esto (los números de containment y
applet cambian según donde lo coloques):

```ini
[Containments][2][Applets][12]
immutability=1
plugin=org.kde.plasma.categorizedtodo

[Containments][2][Applets][12][Configuration][General]
categoryCount=4
categoryNames=Personal,Trabajo,Estudio,Otros
categoryColors=#2ecc71,#f1c40f,#3498db,#e74c3c
showPriorityIcons=true
confirmDelete=true
panelShowLabels=false
panelShowZero=true
panelCounterStyle=right
panelCounterColors=white,black,white,white
popupWidth=420
popupHeight=500
tasksJson=[{"id":1,"title":"Comprar pan","category":0,...}]
archivedJson=[]
nextId=2
```

Notas:

- El backend es **KConfig** (formato INI con escapes propios). Las
  cadenas con `=`, comillas, `\`, saltos de línea, etc., son escapadas
  automáticamente. No hay límite efectivo de tamaño, las tareas con
  varios miles de caracteres conviven sin problemas.
- `tasksJson` y `archivedJson` son strings JSON; `categoryNames`,
  `categoryColors` y `panelCounterColors` son `StringList` (separados
  por coma).
- El archivo se sincroniza en disco con `fsync()` por KConfig, así que
  un crash justo después de un `writeConfig()` no debería corromperlo.

---

## Cómo verificarlo manualmente

Con el plasmoide instalado y al menos una tarea creada:

```bash
# Ubicar el archivo y filtrar por nuestro plugin:
grep -n 'org.kde.plasma.categorizedtodo' \
    ~/.config/plasma-org.kde.plasma.desktop-appletsrc

# Ver el bloque de Configuration completo del applet (cambia 12 por tu
# número de applet):
awk '/^\[Containments\]\[.*\]\[Applets\]\[12\]/{p=1} p; /^\[/{if (p && !/Applets.12./) p=0}' \
    ~/.config/plasma-org.kde.plasma.desktop-appletsrc
```

Inmediatamente después de tildar/destildar una tarea o crear una nueva,
el archivo debería reflejar el cambio. Si no, ver la sección de debug
abajo.

### Tip: en vivo

```bash
# Mostrar cambios en el archivo en tiempo real:
inotifywait -m -e modify ~/.config/plasma-org.kde.plasma.desktop-appletsrc
```

---

## Cómo respaldar / migrar

Como todo está en un único archivo INI, basta con copiarlo:

```bash
# Backup
cp ~/.config/plasma-org.kde.plasma.desktop-appletsrc ~/plasma-applets.bak

# Restore (cerrá Plasma antes para evitar pisar tu copia)
kquitapp5 plasmashell
cp ~/plasma-applets.bak ~/.config/plasma-org.kde.plasma.desktop-appletsrc
kstart5 plasmashell
```

Para migrar tareas entre máquinas o entre instancias del plasmoide
**sin tocar este archivo**, usá la función **Exportar / Importar JSON**
que tiene cada categoría desde la cabecera de la pestaña.

---

## Debug: si las tareas siguen sin persistir

1. **Verificá que el plasmoide esté usando esta versión** (con el fix en
   `TaskStore.qml`). Si lo instalaste con `./install.sh --dev` (symlink),
   los cambios al `.qml` se aplican al recargar el plasmoide o a
   plasmashell.

2. **Confirmá que `writeConfig()` exista**. En la consola QML:
   ```bash
   plasmashell --replace 2>&1 | grep -i 'writeConfig'
   ```
   Si aparece `TaskStore: writeConfig() failed`, tu plasma-framework no
   expone el método. En tal caso, instalá una versión más reciente (KDE
   Plasma 5.27+ y kdeclarative 5.103+ lo tienen).

3. **Mirá si el INI cambia** al modificar una tarea (ver la sección
   *Cómo verificarlo manualmente* arriba). Si no cambia, el problema es
   que el flush no llegó a disco. Si cambia pero al reabrir las tareas
   aparecen vacías, el problema está en la deserialización (`load()`).

4. **Permisos**:
   ```bash
   ls -l ~/.config/plasma-org.kde.plasma.desktop-appletsrc
   ```
   Tiene que ser tuyo y tener permiso de escritura (`-rw-`). Algún
   `sudo` viejo puede haberlo dejado como `root`.

5. **Logs QML**:
   ```bash
   journalctl --user -f -u plasma-plasmashell.service | grep -i todo
   ```
   El `TaskStore` registra `console.warn(...)` cuando JSON.parse falla.

6. **Reset duro** (último recurso): borrar el bloque
   `[Containments][...][Applets][...][Configuration][General]`
   correspondiente al plasmoide. Volverá a sus defaults.

---

## ¿Por qué no usamos un archivo propio?

Tres razones:

1. Plasma ya provee el mecanismo y se integra con el ciclo de vida del
   widget (creación, configuración, eliminación). Si el plasmoide se
   borra, también se borra su config — no quedan archivos huérfanos.
2. Sin librerías externas, el QML puro **no puede escribir archivos**:
   `XMLHttpRequest` solo lee, y no hay API estándar de write. La
   alternativa sería `Qt.labs.settings`, pero también delega en
   `QSettings` y termina siendo equivalente.
3. El JSON exportado (botón **Exportar** de cada categoría) cubre el
   caso de respaldo/migración granular sin necesidad de tocar el INI.
