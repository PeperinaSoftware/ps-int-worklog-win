# Instalación y compilación

## Tres caminos

### 1. Instalar desde código fuente (recomendado para usuarios finales)

```powershell
git clone <repo>
cd kde-todo-1/worklog-winui
.\install.ps1
```

El script:

1. Restaura paquetes NuGet del proyecto.
2. Compila Release `win-x64` self-contained (incluye runtime .NET 8 y
   Windows App SDK, así corre en una Win11 limpia sin instalar nada
   más).
3. Copia los artefactos a `%LOCALAPPDATA%\Programs\WorklogCalendar\`.
4. Crea un acceso directo en *Menú Inicio → Worklog Calendar*.

Parámetros:

| Parámetro | Default | Descripción |
|---|---|---|
| `-Arch` | `x64` | `x86`, `x64` o `arm64` |
| `-NoBuild` | false | Reusa `bin\...\publish\` ya existente |
| `-Uninstall` | false | Borra `%LOCALAPPDATA%\Programs\WorklogCalendar` y el acceso directo |

### 2. Compilar sin instalar (desarrollo)

```powershell
.\build.ps1                       # x64 Release framework-dependent
.\build.ps1 -Config Debug         # Debug build
.\build.ps1 -SelfContained        # Self-contained: no requiere .NET runtime instalado
.\build.ps1 -Arch arm64 -SelfContained
```

El ejecutable queda en:

```
src\WorklogCalendar\bin\<Arch>\<Config>\net8.0-windows10.0.19041.0\win-<Arch>\publish\WorklogCalendar.exe
```

### 3. Visual Studio

1. Abrir `worklog-winui\WorklogCalendar.sln`.
2. Elegir plataforma (`x64`, `x86`, o `ARM64`) en la barra superior.
3. F5 (Debug) o Ctrl+F5 (sin debugger).

Si VS pide instalar workloads, los necesarios son:

- *.NET Multi-platform App UI development* (o *Desktop development with
  .NET*).
- Componente individual *Windows App SDK C# Templates*.

## Requisitos en runtime

El **self-contained build** (lo que produce `install.ps1`) incluye:

- .NET 8 runtime para Windows
- Windows App SDK 1.6 runtime
- Microsoft.UI.Xaml.* DLLs

Por eso pesa ~150 MB pero corre en cualquier Windows 10 1809+ /
Windows 11.

El **framework-dependent build** (default de `build.ps1`) pesa <10 MB
pero requiere que el usuario tenga el [.NET 8 Desktop
Runtime](https://dotnet.microsoft.com/download/dotnet/8.0) y el
[Windows App SDK 1.6
runtime](https://learn.microsoft.com/windows/apps/windows-app-sdk/downloads).

## Estructura post-instalación

```
%LOCALAPPDATA%\Programs\WorklogCalendar\
├── WorklogCalendar.exe
├── WorklogCalendar.dll
├── Microsoft.WindowsAppRuntime.Bootstrap.dll
├── Microsoft.ui.xaml.dll
├── ...
└── resources.pri
```

Configuración de usuario:

```
%LOCALAPPDATA%\WorklogCalendar\settings.json
```

(JSON plano, podés editarlo a mano).

## Actualizar a una versión nueva

`.\install.ps1` borra y vuelve a copiar la carpeta de destino. La
configuración (`%LOCALAPPDATA%\WorklogCalendar\settings.json`) no se
toca, por lo que las credenciales se mantienen.

## Desinstalar

```powershell
.\install.ps1 -Uninstall
```

O manualmente:

```powershell
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Programs\WorklogCalendar"
Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Worklog Calendar.lnk"
# La config NO se borra automáticamente:
# Remove-Item -Recurse -Force "$env:LOCALAPPDATA\WorklogCalendar"
```
