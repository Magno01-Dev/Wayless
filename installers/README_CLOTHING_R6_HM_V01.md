# WAYLESS — R6 Clothing Catalog v0.1 (TESTING / CANDIDATE)
Date: 2026-10-22. Parent baseline: owner-tested Hair System v0.2 branch `feature/hair-clan-color-size-2026-10-22`. **The hair system is not modified.**

## Installed from one model
`installers/WAYLESS_CLOTHING_R6_HM_V01_CANDIDATE.rbxmx`

### FrontendPlace
- REPLACE `ReplicatedStorage/Shared/AppearanceCatalog` with full module included.
- REPLACE `StarterPlayer/StarterPlayerScripts/FrontendController` with full LocalScript included.

### WorldPlace
- REPLACE `ReplicatedStorage/Shared/AppearanceCatalog` with full module included (maintains its existing FaceHDIntegration reference).

The automatic installer makes exact instance clones into `ServerStorage/WAYLESS_CLOTHING_INSTALLER_BACKUPS` before any replacement, preserves the previous backup pointer and installs **only** scripts for the detected Place. It does not modify CharacterCreationService, CharacterIdentityService, any hair scripts, or the HUD assets.

## Installation
1. Save a manual Studio snapshot first; open FrontendPlace in Edit Mode (not Play/Run).
2. Workspace > Insert from File… > choose the RBXMX.
3. Command Bar:
```lua
require(workspace:FindFirstChild("WAYLESS_CLOTHING_INSTALLER_V01", true):WaitForChild("InstallerCore")).Install()
```
4. Check Output + backup in ServerStorage.
5. Open WorldPlace in Edit Mode and repeat 2–4 **using the same RBXMX**.
6. Do not install in AfterlifePlace.

### Rollback
On each Place where the kit was installed:
```lua
require(workspace:FindFirstChild("WAYLESS_CLOTHING_INSTALLER_V01", true):WaitForChild("InstallerCore")).Rollback()
```
Backups restore the exact replaced scripts, including the v0.2 hair-enabled FrontendController. The approved catalog is not overwritten in GitHub main.

## Creator behavior
- Tops: H01–H15 + M01–M15 = 30 selectable image IDs.
- Bottoms: H01–H15 + M01–M15 = 30 selectable image IDs.
- Top and Bottom are selectable **independently**, preserving the existing UI's mix-and-match behavior; the H/M prefix is merely the art group's naming.
- The obsolete Clothing Color selector stays in place, shows **RESERVED**, has no active click handler and does not affect appearance.
- `ClothingColors` now contains one compatibility group `Wardrobe` with all 30 tops/bottoms.
- Defaults are `H01_TOP` and `H01_BOTTOM`.
- Old template entries remain stored in StarterTops/StarterBottoms with `Enabled=false` so **existing saved characters** with old `TopId`/`BottomId` continue rendering; new creations cannot choose them.

## Reserved gameplay-only outfits (not available in creator)
- U01: top 103885314189934, bottom 94585484625397.
- U01B: top 87002815907882, bottom 128595239715208.
- ANBU01: top 89415554251469, pants 106925469772959.
- ANBU02: top 105306988371172, pants 106925469772959.
- ANBU03: top 139783018810103, pants 106925469772959.

All five are registered under `AppearanceCatalog.GameplayOutfits` and as inactive `StarterTops` / `StarterBottoms` entries, so future equipment services can resolve them through `GetGameplayOutfit()`, `GetStarterTop()`, `GetStarterBottom()`. No gameplay unlock logic is wired in this candidate.

## Duplicate resolution explicitly supplied by owner
- H05 camisa: **104019442142191** (do not use 71389748478598).
- M01 camisa: **135751576245135** (do not use 136473406517053).
- All three ANBU upper variants share ANBU01 pants ID **106925469772959**.

## QA plan
1. Confirm Frontend app loads: no AppearanceCatalog require errors, no FaceHD changes, Hair v0.2 still works.
2. 30/30 options for Top and Bottom, including H05 and M01 corrections; try mixing Top H07 + Bottom M09.
3. Click old Color left/right: no outfit changes and value stays RESERVED.
4. Confirm U01, U01B, ANBU01–03 never appear as creator options.
5. Save new character; verify slot portrait and WorldPlace appearance match chosen TopId/BottomId, with Hair IDs and clan tint intact.
6. Check saved old character retains original outfit using legacy keys; World catalog `GetStarterTop` and `GetStarterBottom` still resolve old entries.
7. Respawn and rejoin in WorldPlace; check FaceHD, gloves, shoes and wearable layers unchanged.
8. Check image moderation/availability of all 65 distinct image IDs in Roblox Studio; these IDs were supplied by owner, but loading cannot be confirmed from this connector.

## Approval
This candidate was **statically source-verified, not tested in Roblox Studio**. Wait for owner QA before promoting to CANONICAL; preserve previous rollback and project status. Design of the retired Color row is deliberately unchanged pending a new UI asset decision.
