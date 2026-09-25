# WAYLESS Source

Initial source-control import prepared from the **2026-09-24 installed Roblox Studio baseline**.

## Baseline rule

This initial import intentionally preserves the scripts exactly as they were installed in Roblox Studio at snapshot time. Known fixes are **not** folded into this baseline. They remain separate Trello backlog work and must go through candidate -> QA -> approval.

## Places

- `src/FrontendPlace`
- `src/WorldPlace`
- `src/AfterlifePlace`

Source is grouped first by Place, then by Roblox service. Script filenames use source-control suffixes only:

- `.server.luau` = Roblox `Script`
- `.client.luau` = Roblox `LocalScript`
- `.luau` = Roblox `ModuleScript`

The original Roblox instance name/path/class/Disabled state and source SHA-256 are preserved in `metadata/SOURCE_SNAPSHOT_MANIFEST.json`.

## Important

The authoritative raw Studio snapshots remain in Google Drive under each Place's `LIVE_INSTALLED_SNAPSHOT_2026-09-24` folder. This repository import is a text-source representation for diff/history/collaboration.

Do not use this tree as a destructive Rojo sync target until a separate mapping/QA pass explicitly approves that workflow.
