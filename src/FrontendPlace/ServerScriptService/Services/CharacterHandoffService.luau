--!strict
-- ServerScriptService > Services > CharacterHandoffService
--
-- WAYLESS secure cross-place handoff v1.
--
-- TeleportData carries ONLY a nonce/hint. Authoritative Slot/Life identity is
-- stored in MemoryStore and consumed once by the destination server.

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ExperiencePlaceConfig =
	require(Shared:WaitForChild("ExperiencePlaceConfig"))

local CharacterHandoffService = {}

local HANDOFF_CONFIG = ExperiencePlaceConfig.Handoff
local map =
	MemoryStoreService:GetHashMap(
		HANDOFF_CONFIG.MapName
	)

local function validText(value: any): boolean
	return typeof(value) == "string"
		and value ~= ""
end

local function tokenKey(token: string): string
	return "t_" .. token
end

function CharacterHandoffService.Create(
	player: Player,
	targetKind: string,
	slotId: string?,
	lifeId: string?,
	extra: {[string]: any}?
): (boolean, string, string?)
	if not validText(targetKind) then
		return false, "InvalidTargetKind", nil
	end

	if slotId ~= nil and not validText(slotId) then
		return false, "InvalidSlotId", nil
	end

	if lifeId ~= nil and not validText(lifeId) then
		return false, "InvalidLifeId", nil
	end

	local token =
		HttpService:GenerateGUID(false)

	local nowUnix = os.time()
	local ttl =
		math.clamp(
			tonumber(HANDOFF_CONFIG.TTLSeconds) or 120,
			30,
			600
		)

	local payload = {
		Version = 1,
		UserId = player.UserId,
		TargetKind = targetKind,
		SlotId = slotId,
		LifeId = lifeId,
		SourcePlaceId = game.PlaceId,
		SourceJobId = game.JobId,
		IssuedAt = nowUnix,
		ExpiresAt = nowUnix + ttl,
		Extra =
			typeof(extra) == "table"
			and extra
			or {},
	}

	local ok, err =
		pcall(function()
			map:SetAsync(
				tokenKey(token),
				payload,
				ttl
			)
		end)

	if not ok then
		warn(
			"[CharacterHandoffService] CREATE FAILED",
			player.Name,
			targetKind,
			err
		)

		return false,
			"HandoffStoreFailed",
			nil
	end

	return true,
		"HandoffCreated",
		token
end

function CharacterHandoffService.Consume(
	player: Player,
	token: any,
	expectedTargetKind: string
): (boolean, string, {[string]: any}?)
	if not validText(token) then
		return false, "MissingHandoffToken", nil
	end

	if not validText(expectedTargetKind) then
		return false, "InvalidExpectedTarget", nil
	end

	local raw: any = nil

	local ok, err =
		pcall(function()
			raw =
			map:GetAsync(
				tokenKey(token)
			)
		end)

	if not ok then
		warn(
			"[CharacterHandoffService] READ FAILED",
			player.Name,
			err
		)
		return false, "HandoffReadFailed", nil
	end

	if typeof(raw) ~= "table" then
		return false, "HandoffMissingOrExpired", nil
	end

	if raw.UserId ~= player.UserId then
		return false, "HandoffUserMismatch", nil
	end

	if raw.TargetKind ~= expectedTargetKind then
		return false, "HandoffTargetMismatch", nil
	end

	if typeof(raw.ExpiresAt) == "number"
		and raw.ExpiresAt < os.time() then

		pcall(function()
			map:RemoveAsync(
				tokenKey(token)
			)
		end)

		return false, "HandoffExpired", nil
	end

	local removeOk, removeErr =
		pcall(function()
			map:RemoveAsync(
				tokenKey(token)
			)
		end)

	if not removeOk then
		-- Do not accept a nonce we could not consume. This preserves the
		-- one-time property under transient MemoryStore failures.
		warn(
			"[CharacterHandoffService] CONSUME REMOVE FAILED",
			player.Name,
			removeErr
		)
		return false, "HandoffConsumeFailed", nil
	end

	return true,
		"HandoffConsumed",
		raw
end

function CharacterHandoffService.Revoke(
	token: any
)
	if not validText(token) then
		return
	end

	pcall(function()
		map:RemoveAsync(
			tokenKey(token)
		)
	end)
end

print(
	"[CharacterHandoffService] READY v1"
		.. " | MemoryStore="
		.. tostring(HANDOFF_CONFIG.MapName)
		.. " | TTL="
		.. tostring(HANDOFF_CONFIG.TTLSeconds)
)

return CharacterHandoffService
