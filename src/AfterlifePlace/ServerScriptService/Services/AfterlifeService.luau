--!strict
-- ServerScriptService > Services > AfterlifeService
--
-- WAYLESS Afterlife / Death Realm v1.
--
-- Valid entry requires a one-time MemoryStore handoff and an AccountProfile
-- life in DeadAwaitingDecision. The client never decides SlotId/LifeId.
--
-- Choices:
--   ReviveWithToken -> consumes account RevivalToken, same LifeId -> World
--   ReviveDeveloper -> QA only, same LifeId -> World
--   Wipe -> archives old life, slot Empty -> Frontend
--   Leave -> no state change -> Frontend

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ExperiencePlaceConfig =
	require(Shared:WaitForChild("ExperiencePlaceConfig"))

local Services = ServerScriptService:WaitForChild("Services")

local AccountProfileService =
	require(Services:WaitForChild("AccountProfileService"))

local CharacterHandoffService =
	require(Services:WaitForChild("CharacterHandoffService"))

local AfterlifeService = {}

local started = false

type Session = {
	Ready: boolean,
	SlotId: string,
	LifeId: string,
	CharacterId: string,
	WipeArmLifeId: string?,
	WipeArmExpiresAt: number?,
}

local sessions: {[Player]: Session} = {}

local developerService: any? = nil
do
	local module = Services:FindFirstChild("DeveloperAccessService")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			developerService = result
			pcall(function()
				developerService.Start()
			end)
		end
	end
end

local function isDeveloper(player: Player): boolean
	if not developerService then
		return false
	end

	local ok, result =
		pcall(function()
			return developerService.IsDeveloper(player)
		end)

	return ok and result == true
end

local function waitForAccount(
	player: Player,
	timeoutSeconds: number
): boolean
	AccountProfileService.Start()

	local deadline = time() + timeoutSeconds
	while player.Parent
		and time() < deadline do

		if AccountProfileService.IsReady(player) then
			return true
		end

		task.wait(0.05)
	end

	return AccountProfileService.IsReady(player)
end

local function getTeleportToken(
	player: Player
): string?
	local ok, joinData =
		pcall(function()
			return player:GetJoinData()
		end)

	if not ok or typeof(joinData) ~= "table" then
		return nil
	end

	local teleportData = joinData.TeleportData
	if typeof(teleportData) ~= "table" then
		return nil
	end

	local token = teleportData.HandoffToken
	return typeof(token) == "string"
		and token ~= ""
		and token
		or nil
end

local function findSingleDeveloperDeadLife(
	player: Player
): (string?, string?, string?)
	if not ExperiencePlaceConfig.Afterlife.AllowDeveloperDirectJoin then
		return nil, nil, nil
	end

	if not isDeveloper(player) then
		return nil, nil, nil
	end

	local snapshot =
		AccountProfileService.GetSnapshot(player)

	if not snapshot
		or typeof(snapshot.Slots) ~= "table" then

		return nil, nil, nil
	end

	local foundSlot: string? = nil
	local foundLife: string? = nil
	local foundCharacter: string? = nil

	for slotId, slot in pairs(snapshot.Slots) do
		if typeof(slot) == "table"
			and slot.State == "DeadAwaitingDecision"
			and typeof(slot.CurrentLife) == "table" then

			if foundSlot then
				return nil, nil, nil
			end

			foundSlot = tostring(slotId)
			foundLife = tostring(slot.CurrentLife.LifeId or "")
			foundCharacter = tostring(slot.CurrentLife.CharacterId or "")
		end
	end

	return foundSlot, foundLife, foundCharacter
end

local function validateDeadLife(
	player: Player,
	slotId: string,
	lifeId: string
): (boolean, string, string?)
	local slot =
		AccountProfileService.GetSlot(
			player,
			slotId
		)

	if not slot then
		return false, "SlotNotUnlocked", nil
	end

	if slot.State ~= "DeadAwaitingDecision" then
		return false, "LifeNotAwaitingDecision", nil
	end

	local life = slot.CurrentLife
	if typeof(life) ~= "table" then
		return false, "NoCurrentLife", nil
	end

	if tostring(life.LifeId or "") ~= lifeId then
		return false, "LifeIdentityMismatch", nil
	end

	local characterId =
		tostring(life.CharacterId or lifeId)

	return true, "Validated", characterId
end

local function publishSession(
	player: Player,
	session: Session
)
	player:SetAttribute("AfterlifeReady", session.Ready)
	player:SetAttribute("AfterlifeSlotId", session.SlotId)
	player:SetAttribute("AfterlifeLifeId", session.LifeId)
	player:SetAttribute("AfterlifeCharacterId", session.CharacterId)
	player:SetAttribute(
		"AfterlifeWipeArmed",
		session.WipeArmExpiresAt ~= nil
	)
end

local function buildState(
	player: Player,
	ok: boolean,
	reason: string
): {[string]: any}
	local session = sessions[player]
	local snapshot =
		AccountProfileService.GetSnapshot(player)

	local tokens = 0
	if snapshot
		and typeof(snapshot.Currencies) == "table" then
		tokens =
			tonumber(
				snapshot.Currencies.RevivalTokens
			) or 0
	end

	local wipeSeconds = 0
	if session
		and session.WipeArmExpiresAt then

		wipeSeconds =
			math.max(
				0,
				math.ceil(
					session.WipeArmExpiresAt
					- os.clock()
				)
			)

		if wipeSeconds <= 0 then
			session.WipeArmExpiresAt = nil
			session.WipeArmLifeId = nil
		end
	end

	local slot =
		session
		and AccountProfileService.GetSlot(
			player,
			session.SlotId
		)
		or nil

	return {
		Ok = ok,
		Reason = reason,
		Ready =
			session ~= nil
			and session.Ready == true,
		SlotId =
			session and session.SlotId or nil,
		LifeId =
			session and session.LifeId or nil,
		CharacterId =
			session and session.CharacterId or nil,
		SlotState =
			slot and slot.State or nil,
		RevivalTokens = tokens,
		WipeArmed = wipeSeconds > 0,
		WipeSecondsRemaining = wipeSeconds,
		CanDeveloperRevive =
			ExperiencePlaceConfig.Afterlife.AllowDeveloperFreeRevive
			and isDeveloper(player),
		FrontendConfigured =
			(tonumber(ExperiencePlaceConfig.FrontendPlaceId) or 0) > 0,
		WorldConfigured =
			(tonumber(ExperiencePlaceConfig.WorldPlaceId) or 0) > 0,
	}
end

local function teleportTo(
	player: Player,
	targetKind: string,
	placeId: number,
	slotId: string,
	lifeId: string?,
	reason: string
): (boolean, string)
	if placeId <= 0 then
		return false,
			targetKind .. "PlaceIdNotConfigured"
	end

	local handoffOk,
		handoffReason,
		token =
		CharacterHandoffService.Create(
			player,
			targetKind,
			slotId,
			lifeId,
			{
				Reason = reason,
				FromAfterlife = true,
			}
		)

	if not handoffOk or not token then
		return false, handoffReason
	end

	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({
		Flow = "AfterlifeTo" .. targetKind,
		HandoffToken = token,
		CharacterSlotId = slotId,
	})

	local ok, err =
		pcall(function()
			TeleportService:TeleportAsync(
				placeId,
				{ player },
				options
			)
		end)

	if not ok then
		CharacterHandoffService.Revoke(token)

		warn(
			"[AfterlifeService] TELEPORT FAILED",
			player.Name,
			targetKind,
			err
		)

		return false,
			targetKind .. "TeleportFailed"
	end

	player:SetAttribute(
		"AfterlifeTeleporting",
		true
	)

	return true,
		targetKind .. "TeleportStarted"
end

local function teleportWorld(
	player: Player,
	session: Session,
	reason: string
): (boolean, string)
	return teleportTo(
		player,
		"World",
		tonumber(ExperiencePlaceConfig.WorldPlaceId) or 0,
		session.SlotId,
		session.LifeId,
		reason
	)
end

local function teleportFrontend(
	player: Player,
	session: Session,
	lifeId: string?,
	reason: string
): (boolean, string)
	return teleportTo(
		player,
		"Frontend",
		tonumber(ExperiencePlaceConfig.FrontendPlaceId) or 0,
		session.SlotId,
		lifeId,
		reason
	)
end

local function initializePlayer(
	player: Player
)
	player:SetAttribute("AfterlifeReady", false)
	player:SetAttribute("AfterlifeTeleporting", false)

	if not waitForAccount(player, 30) then
		warn(
			"[AfterlifeService] ACCOUNT LOAD FAILED",
			player.Name
		)
		return
	end

	local slotId: string? = nil
	local lifeId: string? = nil
	local characterId: string? = nil

	local token = getTeleportToken(player)

	if token then
		local ok,
			reason,
			handoff =
			CharacterHandoffService.Consume(
				player,
				token,
				"Afterlife"
			)

		if not ok
			or typeof(handoff) ~= "table" then

			warn(
				"[AfterlifeService] HANDOFF REJECTED",
				player.Name,
				reason
			)
			return
		end

		slotId =
			typeof(handoff.SlotId) == "string"
			and handoff.SlotId
			or nil

		lifeId =
			typeof(handoff.LifeId) == "string"
			and handoff.LifeId
			or nil
	else
		slotId,
			lifeId,
			characterId =
			findSingleDeveloperDeadLife(
				player
			)
	end

	if not slotId or not lifeId then
		warn(
			"[AfterlifeService] INVALID ENTRY",
			player.Name,
			"No valid handoff"
		)
		return
	end

	local valid,
		reason,
		validCharacterId =
		validateDeadLife(
			player,
			slotId,
			lifeId
		)

	if not valid then
		warn(
			"[AfterlifeService] DEAD LIFE VALIDATION FAILED",
			player.Name,
			reason
		)
		return
	end

	characterId =
		characterId
		or validCharacterId
		or lifeId

	local session: Session = {
		Ready = true,
		SlotId = slotId,
		LifeId = lifeId,
		CharacterId = characterId,
		WipeArmLifeId = nil,
		WipeArmExpiresAt = nil,
	}

	sessions[player] = session
	publishSession(player, session)

	print(
		"[AfterlifeService] PLAYER READY",
		player.Name,
		"Slot=" .. slotId,
		"Life=" .. lifeId
	)
end

local function ensureRemote(): RemoteFunction
	local system =
		ReplicatedStorage:
		FindFirstChild("AfterlifeSystem")

	if not system then
		system = Instance.new("Folder")
		system.Name = "AfterlifeSystem"
		system.Parent = ReplicatedStorage
	end

	local remotes =
		system:FindFirstChild("Remotes")

	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = system
	end

	local existing =
		remotes:FindFirstChild("AfterlifeRequest")

	if existing and existing:IsA("RemoteFunction") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = "AfterlifeRequest"
	remote.Parent = remotes

	return remote
end

local function handleRequest(
	player: Player,
	action: any
): {[string]: any}
	if typeof(action) ~= "string" then
		return buildState(
			player,
			false,
			"InvalidAction"
		)
	end

	local session = sessions[player]

	if action == "GetState" then
		return buildState(
			player,
			session ~= nil,
			session and "Ready" or "AfterlifeNotReady"
		)
	end

	if not session or not session.Ready then
		return buildState(
			player,
			false,
			"AfterlifeNotReady"
		)
	end

	-- Server checks distance too; UI visibility is not authorization.
	if action ~= "CancelWipe" then
		local room = workspace:FindFirstChild("WAYLESS_Afterlife")
		local anchor = room and room:FindFirstChild("HagoromoAnchor")
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not anchor or not anchor:IsA("BasePart") or not root or not root:IsA("BasePart")
			or not humanoid or humanoid.Health <= 0 or (root.Position-anchor.Position).Magnitude > 16 then
			return buildState(player, false, "ApproachHagoromo")
		end
	end
	local valid,
		validateReason =
		validateDeadLife(
			player,
			session.SlotId,
			session.LifeId
		)

	if action ~= "ReviveDeveloper"
		and action ~= "ReviveWithToken"
		and action ~= "Leave"
		and action ~= "ArmWipe"
		and action ~= "CancelWipe"
		and action ~= "ConfirmWipe" then

		return buildState(
			player,
			false,
			"UnknownAction"
		)
	end

	if action == "ReviveWithToken" then
		if not valid then
			return buildState(
				player,
				false,
				validateReason
			)
		end

		local ok, reason =
			AccountProfileService.ReviveCurrentLifeWithToken(
				player,
				session.SlotId
			)

		if not ok then
			return buildState(
				player,
				false,
				reason
			)
		end

		local teleportOk,
			teleportReason =
			teleportWorld(
				player,
				session,
				"ReviveWithToken"
			)

		return buildState(
			player,
			teleportOk,
			teleportReason
		)
	end

	if action == "ReviveDeveloper" then
		if not ExperiencePlaceConfig.Afterlife.AllowDeveloperFreeRevive
			or not isDeveloper(player) then

			return buildState(
				player,
				false,
				"DeveloperReviveNotAllowed"
			)
		end

		if not valid then
			return buildState(
				player,
				false,
				validateReason
			)
		end

		local ok, reason =
			AccountProfileService.ReviveCurrentLife(
				player,
				session.SlotId
			)

		if not ok then
			return buildState(
				player,
				false,
				reason
			)
		end

		local teleportOk,
			teleportReason =
			teleportWorld(
				player,
				session,
				"DeveloperRevive"
			)

		return buildState(
			player,
			teleportOk,
			teleportReason
		)
	end

	if action == "ArmWipe" then
		if not valid then
			return buildState(
				player,
				false,
				validateReason
			)
		end

		session.WipeArmLifeId =
			session.LifeId

		session.WipeArmExpiresAt =
			os.clock()
			+ math.max(
				5,
				tonumber(
					ExperiencePlaceConfig.Afterlife.WipeConfirmSeconds
				) or 12
			)

		publishSession(player, session)

		return buildState(
			player,
			true,
			"WipeArmed"
		)
	end

	if action == "CancelWipe" then
		session.WipeArmLifeId = nil
		session.WipeArmExpiresAt = nil
		publishSession(player, session)

		return buildState(
			player,
			true,
			"WipeCancelled"
		)
	end

	if action == "ConfirmWipe" then
		if not valid then
			return buildState(
				player,
				false,
				validateReason
			)
		end

		local armed =
			session.WipeArmLifeId == session.LifeId
			and typeof(session.WipeArmExpiresAt) == "number"
			and session.WipeArmExpiresAt > os.clock()

		if not armed then
			session.WipeArmLifeId = nil
			session.WipeArmExpiresAt = nil
			return buildState(
				player,
				false,
				"WipeConfirmationExpired"
			)
		end

		session.WipeArmLifeId = nil
		session.WipeArmExpiresAt = nil

		local ok, reason =
			AccountProfileService.FinalizeWipeMetadata(
				player,
				session.SlotId
			)

		if not ok then
			return buildState(
				player,
				false,
				reason
			)
		end

		local teleportOk,
			teleportReason =
			teleportFrontend(
				player,
				session,
				nil,
				"WipeComplete"
			)

		if not teleportOk
			and teleportReason == "FrontendPlaceIdNotConfigured" then

			return buildState(
				player,
				true,
				"WipeCompleteFrontendNotConfigured"
			)
		end

		return buildState(
			player,
			teleportOk,
			teleportReason
		)
	end

	if action == "Leave" then
		if not valid then
			return buildState(
				player,
				false,
				validateReason
			)
		end

		local teleportOk,
			teleportReason =
			teleportFrontend(
				player,
				session,
				session.LifeId,
				"LeaveAfterlife"
			)

		if not teleportOk
			and teleportReason == "FrontendPlaceIdNotConfigured" then

			return buildState(
				player,
				true,
				"DeadLifePreservedFrontendNotConfigured"
			)
		end

		return buildState(
			player,
			teleportOk,
			teleportReason
		)
	end

	return buildState(
		player,
		false,
		"UnknownAction"
	)
end

function AfterlifeService.Start()
	if started then
		return
	end

	started = true

	AccountProfileService.Start()

	local remote = ensureRemote()
	remote.OnServerInvoke =
		function(
			player: Player,
			action: any
		)
		return handleRequest(
			player,
			action
		)
	end

	for _, player in ipairs(
		Players:GetPlayers()
		) do
		task.spawn(
			initializePlayer,
			player
		)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(
			initializePlayer,
			player
		)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		sessions[player] = nil
	end)

	print(
		"[AfterlifeService] READY v1"
			.. " | SecureHandoff=ON"
			.. " | RevivalToken=ON"
			.. " | Wipe=DOUBLE_CONFIRM"
			.. " | Leave=ON"
	)
end

return AfterlifeService
