# Clan Back Emblem v1 — TESTING / CANDIDATE (2026-10-22)

Owner-specified logos and clothing contrast rules; visual-only 0.8×0.8×0.001 R6 Torso badge.

**Exact Studio installer and rollback**: [WAYLESS_Clan_Back_Emblems_v1_TESTING_CANDIDATE.zip](https://drive.google.com/file/d/1GkDEHCQShJttuG3X0JsfPtINabeDp3t3/view). The ZIP is the authority for the installer tools and snapshots. SHA-256 `1b51121764941de376475999ced811d2349279d95effb8c2f144760e8a583a68`; RBXMX SHA-256 `120c7b61892bfdc672c2d80a9cc27bd17bcf83810651b6fa3c956d665d63ff21`.

## Source scope (do not merge blindly)
- `src/FrontendPlace/ReplicatedStorage/Shared/ClanBackEmblem.luau`: badge visual module; Git blob `aaea888d67f7872e6aa6a80ac61242ccb18e0d54`.
- `src/WorldPlace/ReplicatedStorage/Shared/ClanBackEmblem.luau`: byte-identical module.
- `src/WorldPlace/ServerScriptService/ClanBackEmblemWorld.server.luau`: replica/binder; Git blob `650aed863343bb9d33eb7f5903217f2caea626f5`.
- `src/FrontendPlace/StarterPlayer/StarterPlayerScripts/FrontendController.client.luau`: patch on exact owner-approved clothing+FaceHD+Hyuga controller Git blob `ac9da1d6dcbd68d9c16797fa04fb71343ece537d`; new blob `31e6adcc19c2940ab3e4c55fd93d8045431392ec`. Three localized `ClanBackEmblem.Apply` calls (rebuild, change clothing, slot portrait), one require; everything else preserved.
- World identity, equipment, inventory, combat, FaceHD v2.2 and clothing catalogs are NOT rewritten.

## User-supplied map
Uchiha 88378610115045, Hyuga 115351605032285, Nara 83964381736190/91477586091255, Akimichi 109703424399060/95724777326699, Aburame 73249868409053/123444311578954, Inuzuka 138312642811209/86696623149878, Hozuki 88489711913384/133128139064238, Uzumaki 83887466494363. Second ID is white-on-dark; absent second ID means always use original.

Dark shirt TopIds: H01/H03/H04/H06/H11/H15 and M01/M05/M06/M07/M08/M09. Other valid H01–H15 or M01–M15 use original emblem. Legacy/unmapped/special clothes intentionally receive no badge until classified.

## QA / limitations
Install the RBXMX independently in each Place in Edit mode using the provided Command Bar scripts. Installer checks **exact** approved FrontendController bytes; it REFUSES to overwrite a different live source. Backups in `ServerStorage.WAYLESS_ClanBackEmblem_Backups` include rollback. WorldPlace code is additive; if World wardrobe source is not yet reconciled to H/M tops, its published TopId will be legacy and **the emblem won't show**, correctly: do not replace the World catalog via this patch without separate QA.

Test 8 clans, white variants, dark/light H/M shirt switching, two players, respawn, Frontend creator and portraits, running/jumping physics, potential vest/cape occlusion, asset permission. OWNER QA NOT RUN; NOT SHIPPED.
