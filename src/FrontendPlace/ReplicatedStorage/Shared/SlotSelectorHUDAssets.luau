--!strict
-- ReplicatedStorage > Shared > SlotSelectorHUDAssets
-- WAYLESS Character Slots / Bingo Book asset registry v2.
-- Filled with the Roblox asset IDs supplied for the slot selector HUD.
-- Village icon IDs remain 0 because they were not included in the supplied screenshots.

local SlotSelectorHUDAssets = {}

SlotSelectorHUDAssets.AssetIds = table.freeze({
	-- Full-screen art / brand
	desk = 107887524849400,
	card_paper = 118856777892689,
	brush_red = 116588625311652,
	title = 119159417695517,
	buy_slot = 74511161171682,

	-- Card / portrait
	card_base = 82224437387965,
	card_hover = 119297788373941,
	card_selected = 126757752009388,
	portrait_backdrop = 99312332629222,
	portrait_frame = 89861883009142,
	empty_portrait = 132551757524810,
	afterlife_cross = 107362513499882,
	afterlife_stamp = 108866323687026,
	separator = 117766173269271,

	-- Reusable action states
	action_normal = 100930668913623,
	action_hover = 137587651765060,
	action_pressed = 78608118905873,
	action_disabled = 131262988714762,

	-- Delete / modal
	delete_action = 106583489574308,
	delete_input_normal = 123859771711103,
	delete_input_focus = 114339227075996,
	delete_input_error = 121446122959307,
	modal_panel = 91589161026880,
	modal_scrim = 85869732855061,

	-- Scrollbar
	scroll_track = 135983223706167,
	scroll_thumb = 122268409638647,

	-- Icons
	add = 109732588253481,
	trash = 114762963529028,

	-- Pending: village icon IDs were not present in this upload batch.
	village_leaf = 130205738487661,
	village_sand = 117460391295418,
	village_mist = 72698742788797,
	village_stone = 94511934672233,
	village_cloud = 78702295377565,
})

local function toImage(assetId: number?): string
	if typeof(assetId) ~= "number" or assetId <= 0 then
		return ""
	end
	return "rbxassetid://" .. tostring(math.floor(assetId))
end

function SlotSelectorHUDAssets.Get(key: string): string
	return toImage((SlotSelectorHUDAssets.AssetIds :: any)[key])
end

function SlotSelectorHUDAssets.Has(key: string): boolean
	local id = (SlotSelectorHUDAssets.AssetIds :: any)[key]
	return typeof(id) == "number" and id > 0
end

return SlotSelectorHUDAssets
