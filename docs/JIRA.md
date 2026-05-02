# Integración con Jira

El plasmoide *Categorized ToDo* tiene dos modos:

- **ToDo** (por defecto): la lista de tareas local con categorías,
  prioridades, subtareas y archivado.
- **Jira**: vista de **solo lectura** de las incidencias que tenés
  asignadas en un **Jira Cloud** vía la REST API v3.

Este documento explica cómo configurar el modo Jira, qué hace cada
opción y consideraciones de seguridad.

---

## Qué se muestra

En modo Jira, el popup tiene tres pestañas (la tercera es opcional):

- **Por hacer** — incidencias con `statusCategory = "new"` (todo lo
  que aún no se empezó).
- **En curso** — `statusCategory = "indeterminate"` (en progreso).
- **Hechas** — `statusCategory = "done"`. Oculta por defecto;
  habilítala desde *Configurar → Jira → "Mostrar pestaña Hechas"*.

Cada incidencia muestra:

- Insignia de **issuetype** (S = Story, T = Task, B = Bug, E = Epic,
  ↳ = Subtask, …).
- **Clave** (ej. `PROJ-123`) en monospace.
- **Resumen** (con elipsis si no entra).
- **Prioridad** (chip).
- **Estado** (chip con el color que devuelve la API de Jira).
- Si es subtask, debajo aparece la línea `↳ Parent: PARENT-12 — resumen del padre`.

Hacer clic en cualquier incidencia abre `https://<sitio>/browse/<KEY>`
en tu navegador por defecto.

---

## Cómo configurar

1. Abrí *Configurar widget* y andá a la pestaña **Jira**.
2. Completá los tres campos:
   - **Sitio Jira**: la URL raíz de tu Jira Cloud.
     Ejemplo: `https://your-company.atlassian.net`. Sin barra final.
   - **Email**: el email registrado en tu cuenta Atlassian (NO un
     usuario "humano", es el email).
   - **API token**: generá uno en
     <https://id.atlassian.com/manage-profile/security/api-tokens>.
     **No es tu password de Atlassian** — es un token específico que
     podés revocar individualmente.
3. (Opcional) Ajustá el **JQL** si querés ver más o menos incidencias.
   Default:
   ```
   assignee = currentUser() AND statusCategory != Done ORDER BY priority DESC, updated DESC
   ```
4. Pulsá **Probar** dentro de la pestaña Jira para validar las
   credenciales contra `/rest/api/3/myself`. Si funciona vas a ver tu
   `displayName`.
5. En la pestaña **General**, cambiá el **Modo** a *Jira*.
6. Aceptar / Aplicar.

El plasmoide hace una primera carga al entrar a modo Jira. Después
refresca cada `Auto-refresh (min)` minutos (default 5; poné 0 para
manual). Podés forzar un refresco con el botón ↻ del popup.

---

## JQL: ejemplos útiles

- Sólo Stories y Subtasks asignadas a vos, abiertas:
  ```
  assignee = currentUser() AND issuetype in ("Story", "Sub-task") AND statusCategory != Done ORDER BY updated DESC
  ```
- Lo que vence esta semana:
  ```
  assignee = currentUser() AND duedate <= endOfWeek() AND statusCategory != Done
  ```
- Bugs reportados por vos sin asignar:
  ```
  reporter = currentUser() AND issuetype = Bug AND assignee is EMPTY
  ```
- Sprint actual:
  ```
  assignee = currentUser() AND sprint in openSprints() AND statusCategory != Done
  ```

Tip: probá tus JQL primero en la UI de Jira (filtro avanzado), copiala
y pegala en el plasmoide.

---

## Cache local

La última respuesta exitosa se guarda en la **base SQLite**
(tabla `jira_cache`). Ver `docs/PERSISTENCE.md` para la ubicación
exacta del archivo `.sqlite`.

De esta forma, al abrir el popup mostramos las incidencias del último
fetch al instante mientras corre la siguiente actualización en
background.

Para limpiar el cache:

```bash
DIR=~/.local/share/KDE/plasmashell/QML/OfflineStorage/Databases
DB=$(grep -l 'CategorizedToDo' "$DIR"/*.ini | sed 's/\.ini$/.sqlite/')
sqlite3 "$DB" 'DELETE FROM jira_cache;'
```

---

## Vista compacta (panel)

En modo Jira, la vista compacta sigue el mismo formato que en modo
ToDo: cuadrados de color con un contador, en horizontal. Los slots
son:

- 🔵 *Por hacer* — `#42526e`
- 🟡 *En curso* — `#f5a623`
- 🟢 *Hechas*   — `#2ecc71` (sólo si activaste la pestaña Hechas)

Las opciones de la pestaña *Apariencia* (estilo del contador, mostrar
labels, ocultar ceros) también se aplican en modo Jira.

---

## Seguridad

- El **API token** se almacena en dos lugares (resilientes por
  separado):
  1. `~/.config/plasma-org.kde.plasma.desktop-appletsrc` (KConfig
     estándar de Plasma; lo escribe el diálogo *Configurar*).
  2. La base SQLite del plasmoide, en la tabla `settings` con clave
     `jira.token` (ver `docs/PERSISTENCE.md`).
  Ambos archivos tienen permisos `0600` por defecto (sólo tu usuario
  los lee), pero cualquier proceso corriendo con tu UID puede acceder.
- Limitá el alcance del token: si Atlassian Cloud te ofrece scopes,
  elegí solo los que necesites (lectura de issues alcanza).
- **Revocá** el token en
  <https://id.atlassian.com/manage-profile/security/api-tokens>
  cuando dejes de usar el plasmoide o si alguna vez creés otro.
- Las llamadas HTTP usan **HTTPS** (asumiendo que `jiraSite` empieza
  con `https://`). El plasmoide no fuerza el esquema; si ponés
  `http://` el tráfico va en claro. **No lo hagas.**
- El plasmoide nunca **escribe** en Jira: sólo `GET` a `/rest/api/3/search`
  y `/rest/api/3/myself`. Aun así, si tu token tiene permisos amplios,
  un atacante con acceso a tu sesión podría usarlo.

### Server (no Cloud)

Si usás Jira Server / Data Center on-prem, la API v3 puede no estar
disponible — algunas instalaciones aún sólo tienen v2. Cambiá la URL
del JQL en el código (todavía no es configurable en la UI; PRs
bienvenidos). El esquema de auth Basic con email + password también
funciona pero es **mucho** menos seguro que API tokens; usá un
`Personal Access Token` si tu instancia los soporta.

---

## Debug

- **Ver el último error** en el popup: si una llamada falla, el
  encabezado de la pestaña Jira muestra el motivo (HTTP code +
  mensaje).
- **Logs QML**:
  ```bash
  journalctl --user -f -u plasma-plasmashell.service | grep -i jira
  ```
  El `JiraStore` no es muy locuaz, pero los `console.warn(...)`
  aparecen ahí.
- **Probar a mano** la misma llamada que hace el plasmoide:
  ```bash
  curl -s -u "you@example.com:YOUR_TOKEN" \
      -H "Accept: application/json" \
      "https://your-site.atlassian.net/rest/api/3/myself" | jq .
  ```
  Si esto falla con 401/403, el problema son las credenciales. Si
  falla con 404, el sitio o el path están mal.
- **JQL inválido**: la API responde 400 con un mensaje claro; el
  plasmoide lo muestra tal cual en el header.

---

## Limitaciones conocidas

- Solo **Jira Cloud** está testeado en serio. Server/DC puede
  funcionar pero los nombres de issuetype y los `statusCategory.key`
  pueden variar.
- No hay paginación: traemos hasta `jiraMaxResults` (default 50, máximo
  200). Si tenés más asignadas filtrá con un JQL más estricto.
- No hay edición ni transición de estados desde el plasmoide. Es
  intencionalmente solo lectura.
- El token se almacena en plano (no usamos KWallet por simplicidad y
  para no requerir un plugin C++). Si tu modelo de amenazas requiere
  más, considerá KWallet o variables de entorno.
