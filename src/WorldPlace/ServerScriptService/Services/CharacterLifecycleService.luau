--!strict
-- ServerScriptService > Services > CharacterLifecycleService
--
-- WAYLESS Character Lifecycle v2 - CharacterId/LifeId canonical state machine.
--
-- This service no longer rerolls genetics.
--
-- Canonical transitions:
--   Alive
--     -> DeadAwaitingDecision
--     -> Alive (Revive)
--     -> Empty (Finalize Wipe metadata)
--
-- A NEW life is created only through Character Creation after the slot is
-- empty. AccountProfileService assigns a fresh CharacterId + LifeId.
--
-- Child stores are life-scoped, so old life data remains archived under its
-- previous LifeId and cannot be inherited by the new incarnation.

local ServerScriptService =
	game:GetService("ServerScriptService")

local Services =
	ServerScriptService:WaitForChild("Services")

local AccountProfileService =
	require(Services:WaitForChild("AccountProfileService"))

local CharacterSlotContextService =
	require(Services:WaitForChild("CharacterSlotContextService"))

local CharacterLifeContextService =
	require(Services:WaitForChild("CharacterLifeContextService"))

local CharacterLifecycleService = {}

local transitionLocks: {[Player]: boolean} = {}
local transitionSerials: {[Player]: number} = {}

local lifecycleChanged = Instance.new("BindableEvent")
CharacterLifecycleService.LifecycleChanged =
	lifecycleChanged.Event

CharacterLifecycleService.PolicyVersion = 2

CharacterLifecycleService.CurrentPolicy =
	table.freeze({
		Mode = "CharacterLifeCanonical",
		GeneticsScope = "Slot",
		LifeDataScope = "LifeId",
		AutomaticGeneticReroll = false,
		FinalDeathState = "DeadAwaitingDecision",
		RevivalPreservesLifeId = true,
		WipeDetachesCurrentLife = true,
		NewLifeRequiresCharacterCreation = true,
		AfterlifePlaceImplemented = false,
	})

local function withTransitionLock(
	player: Player,
	callback: () -> (boolean, string)
): (boolean, string)
	if transitionLocks[player] then
		return false, "LifecycleBusy"
	end

	transitionLocks[player] = true

	local ok, success, reason =
		pcall(callback)

	transitionLocks[player] = nil

	if not ok then
		warn(
			"[CharacterLifecycleService] TRANSITION ERROR",
			player.Name,
			success
		)

		return false,
			"LifecycleInternalError"
	end

	return success, reason
end

local function publishReady(player: Player)
	local identity =
		CharacterLifeContextService.GetIdentity(
			player
		)

	player:SetAttribute(
		"CharacterLifecycleReady",
		true
	)

	player:SetAttribute(
		"CharacterLifecyclePolicyVersion",
		CharacterLifecycleService.PolicyVersion
	)

	player:SetAttribute(
		"CharacterLifecycleActiveSlotId",
		identity.SlotId
	)

	player:SetAttribute(
		"CharacterLifecycleLifeId",
		identity.LifeId
	)

	player:SetAttribute(
		"CharacterLifecycleCharacterId",
		identity.CharacterId
	)

	player:SetAttribute(
		"CharacterLifecycleLifeNumber",
		identity.LifeNumber
	)

	player:SetAttribute(
		"CharacterLifecycleState",
		identity.State
	)

	player:SetAttribute(
		"CharacterLifecycleTransitionSerial",
		transitionSerials[player] or 0
	)

	player:SetAttribute(
		"CharacterLifecycleLastAction",
		player:GetAttribute(
			"CharacterLifecycleLastAction"
		)
			or "None"
	)
end

local function recordTransition(
	player: Player,
	action: string,
	reason: string?,
	state: string?
)
	local serial =
		(transitionSerials[player] or 0)
		+ 1

	transitionSerials[player] = serial

	player:SetAttribute(
		"CharacterLifecycleTransitionSerial",
		serial
	)

	player:SetAttribute(
		"CharacterLifecycleLastAction",
		action
	)

	player:SetAttribute(
		"CharacterLifecycleLastReason",
		reason or "Unspecified"
	)

	if state then
		player:SetAttribute(
			"CharacterLifecycleState",
			state
		)
	end

	lifecycleChanged:Fire(
		player,
		{
			Action = action,
			Reason = reason or "Unspecified",
			State = state,
			Serial = serial,
			SlotId =
				player:GetAttribute(
					"CharacterLifecycleActiveSlotId"
				),
			LifeId =
				player:GetAttribute(
					"CharacterLifecycleLifeId"
				),
			CharacterId =
				player:GetAttribute(
					"CharacterLifecycleCharacterId"
				),
		}
	)
end

function CharacterLifecycleService.InitializePlayer(
	player: Player
)
	AccountProfileService.Start()
	CharacterSlotContextService.Start()
	CharacterLifeContextService.Start()

	publishReady(player)
end

function CharacterLifecycleService.GetState(
	player: Player
): {[string]: any}
	publishReady(player)

	return {
		ActiveSlotId =
			player:GetAttribute(
				"CharacterLifecycleActiveSlotId"
			),

		LifeId =
			player:GetAttribute(
				"CharacterLifecycleLifeId"
			),

		CharacterId =
			player:GetAttribute(
				"CharacterLifecycleCharacterId"
			),

		LifeNumber =
			player:GetAttribute(
				"CharacterLifecycleLifeNumber"
			),

		State =
			player:GetAttribute(
				"CharacterLifecycleState"
			),

		SlotMode =
			CharacterSlotContextService.GetMode(),

		PolicyVersion =
			CharacterLifecycleService.PolicyVersion,

		TransitionSerial =
			transitionSerials[player] or 0,

		LifeForceImplemented = false,
		AfterlifePlaceImplemented = false,
		ChildDataLifeScoped = true,
	}
end

-- Old v1 API retained only so legacy dev UI cannot mutate genetics.
function CharacterLifecycleService.BeginNewLife(
	_player: Player,
	_reason: string?
): (boolean, string)
	return false,
		"DirectNewLifeDeprecatedUseCharacterCreation"
end

function CharacterLifecycleService.MarkFinalDeath(
	player: Player,
	reason: string?
): (boolean, string)
	return withTransitionLock(
		player,
		function()
			local identity =
				CharacterLifeContextService.GetIdentity(
					player
				)

			local ok, result =
				AccountProfileService.MarkFinalDeath(
					player,
					identity.SlotId
				)

			if not ok then
				return false, result
			end

			recordTransition(
				player,
				"FinalDeath",
				reason,
				"DeadAwaitingDecision"
			)

			return true,
			"DeadAwaitingDecision"
		end
	)
end

function CharacterLifecycleService.ReviveCurrentLife(
	player: Player,
	reason: string?
): (boolean, string)
	return withTransitionLock(
		player,
		function()
			local slotId =
				CharacterSlotContextService.GetActiveSlotId(
					player
				)

			local ok, result =
				AccountProfileService.ReviveCurrentLife(
					player,
					slotId
				)

			if not ok then
				return false, result
			end

			recordTransition(
				player,
				"Revive",
				reason,
				"Alive"
			)

			return true,
			"LifeRevived"
		end
	)
end

function CharacterLifecycleService.RequestFinalWipe(
	player: Player,
	reason: string?
): (boolean, string)
	return withTransitionLock(
		player,
		function()
			local slotId =
				tostring(
					player:GetAttribute(
						"CharacterLifecycleActiveSlotId"
					)
					or CharacterSlotContextService.GetActiveSlotId(
						player
					)
				)

			local ok, result =
				AccountProfileService.FinalizeWipeMetadata(
					player,
					slotId
				)

			if not ok then
				return false, result
			end

			recordTransition(
				player,
				"FinalizeWipe",
				reason,
				"Empty"
			)

			-- Do not mutate/replace runtime child-service identities in this
			-- server. The player must leave this life session after a wipe.
			player:SetAttribute(
				"CharacterLifecycleMustExitSession",
				true
			)

			return true,
			"SlotReadyForNewLife"
		end
	)
end

function CharacterLifecycleService.ForgetPlayer(
	player: Player
)
	transitionLocks[player] = nil
	transitionSerials[player] = nil
end

print(
	"[CharacterLifecycleService] READY v2"
		.. " | CharacterId+LifeId=ON"
		.. " | GeneticsScope=SLOT"
		.. " | LifeDataScope=LIFE"
		.. " | AutoKGReroll=OFF"
		.. " | DeadAwaitingDecision=ON"
		.. " | WipeMetadata=ON"
		.. " | AfterlifePlace=PENDING"
)

return CharacterLifecycleService
