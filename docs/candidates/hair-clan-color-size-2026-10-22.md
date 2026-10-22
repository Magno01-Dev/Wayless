# WAYLESS — Clan Hair Tint + Size Guard v0.1
Status: **TESTING / CANDIDATE** (no in-game QA performed). 2026-10-22.

## Scope
Extends existing four Roblox Hair IDs without making hair assets manually or modifying the R6 body, clan generation, permadeath, wearables, AppearanceCatalog, HUD assets, or account profile schema.

## Files (complete files on this branch)
- FrontendPlace: `ReplicatedStorage/Shared/HairAppearance.luau` **NEW**
- WorldPlace: `ReplicatedStorage/Shared/HairAppearance.luau` **NEW** (identical)
- FrontendPlace: `ServerScriptService/Services/CharacterCreationService.luau` **CHANGED**
- FrontendPlace: `StarterPlayer/StarterPlayerScripts/FrontendController.client.luau` **CHANGED**
- WorldPlace: `ServerScriptService/Services/CharacterIdentityService.luau` **CHANGED**

## Behavior
- The current four Hair ID fields remain unchanged.
- Three small hair-color choices are added below the ID inputs (without editing Astra's approved HUD module).
- Each existing approved clan has three **provisional** hair colors.
- New metadata: `Appearance.HairColorId = "01" | "02" | "03"`, validated by the server using the slot's **PermanentOrigin.ClanId**.
- Legacy appearance without the field defaults to "01" in its own clan.
- The texture color on loaded hair is removed (MeshPart.TextureID, SpecialMesh.TextureId, SurfaceAppearance/Decal/Texture), then the selected Color3 is applied to all parts. SmoothPlastic preserves mesh lighting but does NOT reconstruct texture-painted details or alpha cutouts.
- CharacterCreationService checks actual loaded R6 accessories, excluding extreme bounds before saving any character metadata.
- WorldPlace rechecks hair size before attaching it; no scaling of body or hair is used.
- The Frontend creator preview and saved slot portrait use the same dye rules.

## Installation
Do not overwrite the approved version directly. In an isolated Studio copy of **FrontendPlace**, import both changed complete scripts at their exact paths and create the HairAppearance ModuleScript under ReplicatedStorage/Shared. In an isolated copy of **WorldPlace**, import changed CharacterIdentityService and the identical HairAppearance module. Do not place these in AfterlifePlace without checking whether it renders live character cosmetics.

## QA gates
1. Open an EMPTY test slot from each clan; use the existing Hair ID fields. Without adding hair, color options must still be usable.
2. Load at least one normal black hair, white hair, textured hair and multilayer hair from the Roblox catalog. No hand-classification is needed **for the player**; testers should keep IDs and screenshots of unexpected results.
3. In creator preview, cycle 01/02/03: color should change, without moving the camera or removing face/wearables.
4. Save and verify slot portrait; join WorldPlace; reset/respawn; verify color and same Hair IDs. CharacterId and PermanentOrigin must not change.
5. Try a very oversized legitimate HairAccessory ID: client should refuse preview and server should refuse commit before persistence, with reason HairTooLarge.
6. Test four legal Hair IDs combined. Check bounds, ability to reject extremes, loading performance and possible accessory flicker.
7. Test at least one classic SpecialMesh hair, a modern MeshPart, and a hair relying on a transparency/alpha texture. **Known risk:** stripping the alpha map may turn hair cards into visible flat planes. Such hair is not guaranteed to recolor attractively; revise policy before approval.
8. Check Studio Output for HairAssetUnavailable, HairTooLarge, HairTooComplex, HairAssetLoadFailed. No silent successful commit when validation fails.
9. Regression: character creation, slot portraits, chosen face, wearable gloves/shoes, world R6 shape, death/revive/wipe and subsequent creation.
10. Confirm final RGB palette with project owner. This is only provisional.

## Calibration
`HairAppearance.Bounds` X=1.85, top=1.85, bottom=-2.60, Z=1.95 head-local studs and 36 max parts are **initial conservative tuning**, not approved Deepwoken values. They should be calibrated against actual R6 assets; legacy SpecialMesh vertex extent is not exactly knowable from BasePart size alone. There is no universal, documented guarantee of pixel-perfect recolor for arbitrary third-party hair.

## Rollback
Revert only this draft branch/PR to the unchanged main branch; do not overwrite approved baseline or update CURRENT_STATUS/FILE_MANIFEST to CANONICAL until hands-on QA and explicit approval.
