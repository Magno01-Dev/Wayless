# WAYLESS — WorldPlace active source baseline — 2026-10-21

Owner approval: Rodolfo explicitly authorized promoting the currently ACTIVE scripts from the WorldPlace 2026-10-21 script export to canonical GitHub/Drive. Disabled/parked scripts are not live.

Source ZIP: Wayless_FullBackup_2026-10-21.zip
ZIP SHA-256: 67aa5209de88328ae67ce1435c31da5b05a0e6138fe32e74397e415df0f20027
Roblox Place ID: 126355335464449

Operational source: 312 files in src/WorldPlace (173 ModuleScripts, 80 active LocalScripts, 59 active Scripts).
Excluded from operational source: 17 disabled scripts in the live tree, 314 scripts/modules in ServerStorage.
Original complete zip including excluded scripts is preserved in Google Drive > 07_RELEASES > 04_ROLLBACKS.
Canonical active-source ZIP stored in Google Drive > 01_GAME_SOURCE > WorldPlace.

TreeJumpController: the exporter named the active duplicate TreeJumpController__2; repo path uses the actual Roblox instance name TreeJumpController. The exported disabled original is not deployed. All other overlapping old controller paths not present/active in the current source snapshot were removed from src/WorldPlace; preserved in earlier Git history.

FrontendPlace and AfterlifePlace trees were left unchanged.

FaceHD 781 Image Asset IDs are included. Current scripts do not yet bind all gameplay-triggered facial expressions; do not misrepresent it as integrated.

Limitations: this is a scripts-only export, not a full RBXL/RBXM. QA relies on owner confirmation for the active state; regression of all systems and cross-place flow still needs testing after source sync. Third-party art licenses (including Inno's Stylized Asset Pack) require their own review.

Previous main / rollback commit: 396a4add08927ec0b801990e555a2306d8a9f75a
Rollback branch: rollback/pre-worldplace-2026-10-21-active-snapshot
Snapshot status: CANONICAL SOURCE BASELINE — owner-approved, bounded to 2026-10-21 WorldPlace code.
