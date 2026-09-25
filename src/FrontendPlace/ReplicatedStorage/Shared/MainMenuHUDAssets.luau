--!strict
-- ReplicatedStorage > Shared > MainMenuHUDAssets
-- WAYLESS Main Menu HUD asset registry v1.
--
-- Filled with approved main-menu IDs plus the layered animated background IDs.
-- Note: brush_red was not present in the provided asset list, so it remains 0.

local MainMenuHUDAssets = {}

MainMenuHUDAssets.AssetIds = table.freeze({
	-- Full-screen / brand
	background = 88528444518773,
	menu_shade = 91770020367685,
	logo = 102323032644806,
	brush_red = 116588625311652,
	section_rule = 128201328723214,

	-- Layered animated background (WAYLESS_Fondo_Animado.zip)
	valley_clean = 113645924790729,
	cloud = 85013645212395,
	mist = 120102072535706,
	water_0 = 90043199626976,
	water_1 = 116261123192650,
	water_2 = 86481530390836,
	birds = 77017327260721,

	-- Complete button state images (preferred runtime assets)
	play_normal = 107155158118466,
	play_hover = 132544373629073,
	play_pressed = 93406546588050,
	play_disabled = 136508974329236,

	quickplay_normal = 100520036163468,
	quickplay_hover = 92108137917859,
	quickplay_pressed = 124929310084200,
	quickplay_disabled = 77769624750293,

	credits_normal = 95710126615703,
	credits_hover = 70444363947901,
	credits_pressed = 80836565664822,
	credits_disabled = 129169176587512,

	settings_normal = 121969192085374,
	settings_hover = 74887008608951,
	settings_pressed = 120204335813057,
	settings_disabled = 77007130733691,

	-- Blank button bases kept available for later localization / reusable rows.
	button_normal = 91418955976126,
	button_hover = 137536382802184,
	button_pressed = 109006061369120,
	button_disabled = 126327546300218,

	-- Optional separate baked labels from the source pack.
	label_play = 131937417671414,
	label_quickplay = 108913195214705,
	label_credits = 87654213716100,
	label_settings = 70986036076179,

	-- Optional separate icons from the source pack.
	icon_play = 120029544864748,
	icon_quickplay = 109515562524175,
	icon_credits = 107431012693367,
	icon_settings = 82311802662130,

	-- Patch notes
	patch_panel = 71475669282654,
	patch_heading = 98833633517989,
	scroll_track = 122092759849876,
	scroll_thumb = 129068131847077,
})

local function toImage(assetId: number?): string
	if typeof(assetId) ~= "number" or assetId <= 0 then
		return ""
	end
	return "rbxassetid://" .. tostring(math.floor(assetId))
end

function MainMenuHUDAssets.Get(key: string): string
	return toImage((MainMenuHUDAssets.AssetIds :: any)[key])
end

function MainMenuHUDAssets.Has(key: string): boolean
	local id = (MainMenuHUDAssets.AssetIds :: any)[key]
	return typeof(id) == "number" and id > 0
end

return MainMenuHUDAssets
