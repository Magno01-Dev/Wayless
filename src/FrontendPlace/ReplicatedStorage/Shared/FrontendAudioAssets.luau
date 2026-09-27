--!strict
-- ReplicatedStorage > Shared > FrontendAudioAssets
-- WAYLESS Frontend audio candidate set for PRE-ALPHA SHOWCASE 01.
--
-- TESTING ONLY until focused in-game audio QA + explicit approval.
-- MenuMusic is intentionally reserved at ID 0 until the final track is supplied.

local FrontendAudioAssets = {}

FrontendAudioAssets.Version = "SHOWCASE01_CANDIDATE_01"

FrontendAudioAssets.Sounds = {
	Hover = {
		Id = 138502294083434,
		Volume = 0.18,
	},
	Click = {
		Id = 121930705809280,
		Volume = 0.28,
	},
	Transition = {
		Id = 72190111895719,
		Volume = 0.30,
	},
	Notification = {
		Id = 103953537067717,
		Volume = 0.34,
	},
	Warning = {
		Id = 120844772439898,
		Volume = 0.34,
	},
	CosmeticSelect = {
		Id = 131983841354349,
		Volume = 0.16,
	},
	MenuMusic = {
		Id = 0,
		Volume = 0.12,
		Looped = true,
	},
}

-- Deliberately excluded from the current set by owner decision:
-- Error/Denied, separate Confirm/Success, separate Back/Cancel.

return FrontendAudioAssets
