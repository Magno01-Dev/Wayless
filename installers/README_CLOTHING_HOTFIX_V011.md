# WAYLESS R6 Clothing — Hotfix v0.1.1 (FrontendPlace only)
Date: 2026-10-22. Status: TESTING / CANDIDATE.

## Observed error
User Studio client Output:
`AutoButtonColor is not a valid member of TextLabel 'Players.Magno0o1.PlayerGui.WAYLESSFrontend.Creation.Canvas1920x1080.ColorValue'`
`FrontendController` line 4335.

## Root cause
The v0.1 clothing installation disabled the old Color selector by setting `creationUI.colorValue.AutoButtonColor = false` on a **TextLabel**, which has no AutoButtonColor. It crashes the whole FrontendController before binding the menu Play flow. This is not an asset-ID error and not a server startup error.

## Correction
Complete `FrontendController.client.luau` with ONLY these obsolete operations removed:
`creationUI.colorValue.Active = false` (unnecessary) and
`creationUI.colorValue.AutoButtonColor = false` (invalid property).
Color left and right buttons remain disabled; label says RESERVED. Creator continues displaying the 30 H/M tops and 30 pants from the previous v0.1 catalog. Hair v0.2 and all WorldPlace services stay unchanged.

## Install
1. Stop Play/Run and make an ordinary copy of FrontendPlace.
2. Workspace > Insert from File... > `WAYLESS_CLOTHING_HOTFIX_V011_FRONTEND_ONLY.rbxmx`.
3. Studio Command Bar:
```lua
require(workspace:FindFirstChild("WAYLESS_CLOTHING_HOTFIX_V011", true):WaitForChild("InstallerCore")).Install()
```
4. Existing `StarterPlayer/StarterPlayerScripts/FrontendController` is copied into `ServerStorage/WAYLESS_CLOTHING_INSTALLER_BACKUPS` before replacement. Existing v0.1 backup remains intact.
5. Test Play button and Creator H/M selections. **Do not run this installer on WorldPlace.**

## Undo just v0.1.1
```lua
require(workspace:FindFirstChild("WAYLESS_CLOTHING_HOTFIX_V011", true):WaitForChild("InstallerCore")).Rollback()
```
This returns the previous v0.1 FrontendController (including its bug) while preserving earlier backups for full v0.1 rollback. Use only for diagnosis.

## QA pending
Only static source/installer checks passed. Need in-game Studio test: Frontend Play action, creation UI, new clothing preview, old color selector inert, hair tint, portrait and subsequent WorldPlace appearance. Do not mark CANONICAL until tested.
