# WAYLESS — Instalador Hairs v0.1 (CANDIDATE)

Archivo: `WAYLESS_HAIR_INSTALLER_V01_CANDIDATE.rbxmx`.

## ¿Qué es?
Un **único modelo Roblox XML (.rbxmx)** con los cinco scripts completos del candidato del PR #7, un ModuleScript `InstallerCore` y comandos incluidos para instalar o hacer rollback. No depende de HTTP ni descarga scripts desde la web: los lleva dentro.

## Antes
1. **Guardar copia del Place**, y ejecutar la instalación exclusivamente en **Studio Edit Mode**, sin Play/Run.
2. Abrir **FrontendPlace**.
3. Explorer > clic derecho sobre **Workspace** > **Insert from File…** > seleccionar `WAYLESS_HAIR_INSTALLER_V01_CANDIDATE.rbxmx`.
4. En **View > Command Bar** ejecutar esta línea EXACTA:

```lua
require(workspace:FindFirstChild("WAYLESS_HAIR_INSTALLER_V01", true):WaitForChild("InstallerCore")).Install()
```

5. Revisar Output. El respaldo debe existir bajo `ServerStorage/WAYLESS_HAIR_INSTALLER_BACKUPS`.
6. Abrir **WorldPlace** y repetir pasos 3-5 con **el mismo .rbxmx**. Se instalarán sólo los scripts del WorldPlace.

**Nunca instalar en AfterlifePlace**. El módulo detecta por la presencia de `CharacterCreationService` (Frontend) o `CharacterIdentityService` (World); si encuentra ambos o ninguno, cancela.

## ¿Qué modifica?
- **FrontendPlace**: `ReplicatedStorage/Shared/HairAppearance` (nuevo); `ServerScriptService/Services/CharacterCreationService` (reemplaza); `StarterPlayer/StarterPlayerScripts/FrontendController` (reemplaza).
- **WorldPlace**: `ReplicatedStorage/Shared/HairAppearance` (nuevo); `ServerScriptService/Services/CharacterIdentityService` (reemplaza).

No altera otros scripts, `AccountProfileService`, HUD assets ni el cuerpo R6. La instalación no se activa al insertar el modelo; hay que ejecutar el comando para que haga el respaldo y coloque los scripts.

## Rollback
Con el mismo kit todavía insertado en el Place, ejecutar en Command Bar:

```lua
require(workspace:FindFirstChild("WAYLESS_HAIR_INSTALLER_V01", true):WaitForChild("InstallerCore")).Rollback()
```

**Repetir en cada Place** en el que se haya instalado. El rollback sólo restaura scripts marcados por esta versión; si han sido cambiados manualmente, se detiene para evitar sobrescribirlos por accidente.

## Estado y pruebas
**TESTING / CANDIDATE**. El RBXMX se generó a partir de fuentes completas recuperadas del branch `feature/hair-clan-color-size-2026-10-22` y se verificó textualmente, pero **no se ha importado ni ejecutado aún dentro de Roblox Studio**. Es necesario QA de recolor, Hair IDs con alpha, límites de geometría, retratos, persistencia y respawn.

La rama `main` conserva la versión anterior aprobada para rollback de GitHub.
