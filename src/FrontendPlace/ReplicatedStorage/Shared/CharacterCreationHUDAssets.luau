--!strict
-- ReplicatedStorage > Shared > CharacterCreationHUDAssets
-- WAYLESS Character Creation HUD asset map v2 - static Astra labels
--
-- Upload the PNG files listed in WAYLESS_CHARACTER_CREATION_HUD_ASSET_MANIFEST.json
-- to Roblox, then paste the resulting image asset IDs below.
-- Keep this as the only place where HUD image IDs live.

local AssetIds: {[string]: number} = {
	panel = 106996171392023,
	title = 121490893977893,
	primary = 116588625311652,
	secondary = 75094987615999,
	title_underline = 120175754887984,
	heading_wash = 90718948031719,
	heading_identity = 91455657776264,
	heading_skin = 109471443630614,
	heading_hair = 112536609527373,
	heading_face = 114807931478423,
	heading_clothing = 101382623706462,
	heading_accessories = 78896759342249,
	selector = 90810942971013,
	hair_input = 85196113481440,
	hair_input_focus = 94420602387820,
	separator = 131075834427915,
	scene_controls = 99319339243212,
	icon_identity = 86672144084842,
	icon_skin = 104055403096544,
	icon_hair = 107675662324623,
	icon_face = 79929670977107,
	icon_clothing = 132218189055076,
	icon_accessories = 133048756670320,
	arrow_left = 80709082519922,
	arrow_right = 96266142607332,
	village_leaf = 130205738487661,
	village_sand = 117460391295418,
	village_mist = 72698742788797,
	village_stone = 94511934672233,
	village_cloud = 78702295377565,
	element_fire = 95264734244125,
	element_water = 132649472721314,
	element_earth = 82031485538771,
	element_lightning = 91387361197908,
	element_wind = 126840780524186,
	label_village = 90586348823023,
	label_nature = 134093588663673,
	label_hair_1 = 115954142664010,
	label_hair_2 = 85415284397274,
	label_hair_3 = 130759153009313,
	label_hair_4 = 131375145221793,
	label_eyes = 106893693315122,
	label_brows = 71158830253509,
	label_nose = 127832932976918,
	label_mouth = 125188291282067,
	label_color = 115905603429558,
	label_top = 112209203585325,
	label_bottom = 75400670212185,
	label_shoes = 93914190001054,
	label_gloves = 124955294310860,
}

local CharacterCreationHUDAssets = {}

function CharacterCreationHUDAssets.Get(key: string): string
	local id = AssetIds[key]
	if not id or id <= 0 then
		return ""
	end

	return "rbxassetid://" .. tostring(id)
end

function CharacterCreationHUDAssets.Has(key: string): boolean
	local id = AssetIds[key]
	return id ~= nil and id > 0
end

CharacterCreationHUDAssets.Ids = AssetIds

return CharacterCreationHUDAssets
