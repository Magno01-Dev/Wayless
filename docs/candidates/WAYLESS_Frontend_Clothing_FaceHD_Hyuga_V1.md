# WAYLESS — Frontend Clothing v0.1.1 + FaceHD/Hyuga (TESTING CANDIDATE)
Date: 2026-10-22. FrontendPlace only. This branch is NOT canonical.

## Conflict identified
The user-supplied `WAYLESS_CLOTHING_HOTFIX_V011_FRONTEND_ONLY.rbxmx` packages a complete FrontendController. Its source matches the prior clothing-candidate branch blob `02298f7b35ee8c4769c613ef8dfdc58fa26d84ad` exactly. That source omits later FaceHD creator patches: HD-only face selection and Hyuga-white eyes. Separately, the clothing candidate's AppearanceCatalog omitted `WaylessFaceHD.RegisterCatalog(AppearanceCatalog)`, so HD options could disappear when its catalog is replaced.

## Candidate changes
- `src/FrontendPlace/StarterPlayer/StarterPlayerScripts/FrontendController.client.luau`: exact clothing v0.1.1 source, with only the HD-only selector and Hyuga slot eye overlay (creator + saved slot portrait) merged; hair v0.2 and reserved clothing-color controls preserved. New Git blob: `ac9da1d6dcbd68d9c16797fa04fb71343ece537d`.
- `src/FrontendPlace/ReplicatedStorage/Shared/AppearanceCatalog.luau`: retain all R6 H/M wardrobe entries and register FaceHD before Defaults. New Git blob: `d9f254bc24ea1a869cd1a6637564c1eba99513ee`.

## Runtime dependencies
This source candidate depends on the FaceHD modules already installed in the real FrontendPlace: ReplicatedStorage/Shared/{FaceHDAssets, FaceHDIntegration, FaceHDSurface}, and StarterPlayerScripts/FaceHDFrontendController. They are not replaced by this branch. The Studio model installer guards these dependencies, validates 20 neutral Byakugan assets, and can restore the original Frontend overlay client if missing.

## Studio installation
Use the single accompanying `WAYLESS_FRONTEND_ROPA_FACEHD_HYUGA_UNIFICADO_V1_CANDIDATE.rbxmx`, not sequential installers. It patches the installed source in place while preserving unrelated concurrent changes, creates explicit rollback snapshots, accepts wardrobe v0.1 or v0.1.1 controller sources, and refuses unknown code/catalogue variants. Clothing H/M AppearanceCatalog must already be present.

Do not merge to main without user QA. Do not mistake this PR/branch for proof of working Roblox Studio runtime or replace WorldPlace FaceHD v2.2.
