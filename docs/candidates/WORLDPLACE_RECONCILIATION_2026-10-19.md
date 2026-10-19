# WorldPlace reconciliation candidate — 2026-10-19

Source origins:
- ULTMO final package supplied by Magno and installed/tested in Studio.
- TreeJump v2.1 bugfix package supplied afterwards and confirmed working by Magno.

Status: TESTING / CANDIDATE.
This branch is not a canonical promotion and must not be merged to main until focused QA + explicit co-owner approval.

Manual package snippets are merged by the reconciliation script into:
- ReplicatedStorage/ProjectileConfigs
- ReplicatedStorage/Shared/StatusEffects/StatusEffectDefinitions
- StarterPlayerScripts/PlayerNameplateController

Runtime scripts superseded by the installed reworks are removed from this candidate source branch where their source-only representation cannot preserve Roblox Studio Disabled metadata. Git history/rollback branches preserve the previous implementations.

Important limitation: this reconciliation is package-derived from the files installed during the chat. It is not a fresh RBXM export of the Studio tree, so Roblox instance metadata/attributes that are not represented by source files are not asserted byte-for-byte here.
