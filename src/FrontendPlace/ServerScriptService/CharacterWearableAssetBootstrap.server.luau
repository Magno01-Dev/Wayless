--!strict
-- ServerScriptService > CharacterWearableAssetBootstrap
-- WAYLESS Character Wearable Asset Bootstrap v1

local ServerScriptService =
	game:GetService(
		"ServerScriptService"
	)

local services =
	ServerScriptService:
	WaitForChild(
		"Services"
	)

local service =
	require(
		services:
		WaitForChild(
			"CharacterWearableAssetService"
		)
	)

local ok, result =
	pcall(
		service.Initialize
	)

if not ok then
	warn(
		"[CharacterWearableAssetBootstrap] FAILED",
		result
	)
else
	print(
		"[CharacterWearableAssetBootstrap] READY v1",
		result
	)
end
