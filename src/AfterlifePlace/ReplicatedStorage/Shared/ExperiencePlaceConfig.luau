--!strict
-- ReplicatedStorage > Shared > ExperiencePlaceConfig
--
-- WAYLESS multi-place routing v1.
-- Fill these three PlaceIds from Creator Dashboard after the Places exist.

return table.freeze({
	FrontendPlaceId = 93018732836485, -- Main Menu / Character Slots
	WorldPlaceId = 126355335464449, -- Wayless / Gameplay
	AfterlifePlaceId = 131890462877698, -- Death Realm

	Handoff = table.freeze({
		MapName = "WAYLESS_CharacterHandoff_v1",
		TTLSeconds = 120,
	}),

	Afterlife = table.freeze({
		WipeConfirmSeconds = 12,
		CreatePlaceholderScene = true,

		-- QA convenience. Requires DeveloperAccessService.IsDeveloper().
		-- Production players cannot use free developer revival.
		AllowDeveloperFreeRevive = true,

		-- Keep false for production. Direct joins without a valid handoff
		-- should never gain access to somebody's dead character state.
		AllowDeveloperDirectJoin = false,
	}),
})
