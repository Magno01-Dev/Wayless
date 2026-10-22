# WAYLESS Hair v0.2 — NO SIZE LIMIT (TESTING / CANDIDATE)

This is an update to the earlier **v0.1** candidate. It fixes normal Hair IDs being rejected as HairTooLarge.

## Download
Use the complete Roblox model:
`installers/WAYLESS_HAIR_INSTALLER_V02_NO_SIZE_LIMIT.rbxmx`

## Install on top of v0.1
1. Make and keep your ordinary Roblox Studio Place backup.
2. In **FrontendPlace**, stop Play/Run. In Workspace select **Insert from File...** and insert the v0.2 RBXMX.
3. In Command Bar in Edit Mode run:

```lua
require(workspace:FindFirstChild("WAYLESS_HAIR_INSTALLER_V02", true):WaitForChild("InstallerCore")).Install()
```

4. Confirm Output says FrontendPlace and backup was saved in `ServerStorage/WAYLESS_HAIR_INSTALLER_BACKUPS`.
5. Repeat steps 2-4 in **WorldPlace** using the SAME .rbxmx.
6. Do **not** run in AfterlifePlace. Do not merge into main yet.

## What changed
- Removed dimension / length limits entirely in Frontend preview, Frontend server character-creation validation, World character equip.
- No body size changes; no hair scaling.
- Unchanged existing max of four Hair IDs, HairAccessory-type validation, clan palette 01/02/03, tint workflow, current HUD layout, AccountProfileService.
- The old v0.1 installer remains in the repository for historical reproduction.
- This v0.2 installer backs up scripts it replaces before writing. When updating from v0.1 it stores a new backup containing v0.1 and remembers previous backup pointer, so reverting v0.2 returns to v0.1 and preserves original backups.

## Roll back v0.2
In the corresponding Place, run:

```lua
require(workspace:FindFirstChild("WAYLESS_HAIR_INSTALLER_V02", true):WaitForChild("InstallerCore")).Rollback()
```

This reverts the **v0.2** install only, restoring scripts that were present at installation (typically v0.1). To restore the pre-v0.1 baseline, use the v0.1 rollback after v0.2 rollback.

## QA
No in-game Studio QA has been performed for v0.2 in this conversation. Validate one Hair ID, multiple Hair IDs, three clan colors, slot portrait, World respawn and any hair texture alpha issues. Record screenshot if another error persists.

Status: **TESTING / CANDIDATE**. No canonical promotion.
