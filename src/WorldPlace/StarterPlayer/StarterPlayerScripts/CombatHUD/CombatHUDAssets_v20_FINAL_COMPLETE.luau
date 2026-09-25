-- CombatHUDAssets_v20_FROM_USER_IDS
-- Filled from the asset-id lists you provided in chat.
-- NOTE: A few assets were NOT present in the provided list and remain blank on purpose.
-- Missing critical ids are listed at the bottom.

local function uri(id)
	if type(id) == "string" and id ~= "" then
		if string.find(id, "rbxassetid://", 1, true) == 1 then return id end
		return "rbxassetid://" .. id
	end
	return ""
end

return {
	Slots = {
		default = uri("98281964819977"),
		empty = uri("99079602183715"),
		fire = uri("104421968427422"),
		water = uri("76353498183663"),
		earth = uri("133432123011063"),
		wind = uri("124214723676255"),
		lightning = uri("75511586038041"),
		genjutsu = uri("97652716004252"),
		healing = uri("100614493334413"),
		taijutsu = uri("129982919654547"),
		shuriken = uri("135043989959955"),
		kenjutsu = uri("77329865658331"),
	},
	Bars = {
		pair03_health_frame = uri("130415631778513"),
		pair03_health_track = uri("78861893977899"),
		pair03_health_fill = uri("136146931565861"),
		curved_health_fill = uri("140505580484849"),
		curved_health_track = uri("109750420253526"),

		pair03_chakra_frame = uri("90115973070709"),
		pair03_chakra_track = uri("137656598768018"),
		pair03_chakra_fill = uri("127136147714608"),
		curved_chakra_fill = uri("74875025818495"),
		curved_chakra_track = uri("138611590445693"),

		pair03_armor_frame = uri("70545208260699"),
		pair03_armor_track = uri("113442997290760"),
		pair03_armor_fill = uri("103650362147722"),
		curved_armor_fill = uri("87117042892809"),
		curved_armor_track = uri("127042543767628"),

		pair03_stamina_frame = uri("131574018924700"),
		pair03_stamina_track = uri("82286314821519"),
		pair03_stamina_fill = uri("114838870572101"),
		curved_stamina_fill = uri("133881009734479"),
		curved_stamina_track = uri("121384458755413"),

		life_force_frame = uri("76673623959198"),
		life_force_energy = uri("76235997256900"),
	},
	Animation = {
		ring_sheet = uri("118484371958980"),
		orb_volume = uri("133200729539816"),
		chakra_sheet = uri("118111824612938"),
	},
	StateIcons = {
		concept_1 = uri("101877758599933"),
		concept_2 = uri("127307512551197"),
		concept_3 = uri("121941665291579"),
		concept_4 = uri("72353196678090"),
		concept_5 = uri("101008987563965"),
		concept_6 = uri("89994782680536"),
		concept_7 = uri("139359940106645"),
		concept_8 = uri("109179953089384"),
		concept_9 = uri("121191201972646"),
		concept_10 = uri("87825340694211"),
		concept_11 = uri("92387787183443"),
	}
}
