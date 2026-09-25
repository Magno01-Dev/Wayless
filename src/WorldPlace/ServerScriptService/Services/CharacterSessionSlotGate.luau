--!strict
-- ServerScriptService > Services > CharacterSessionSlotGate
--
-- WAYLESS Character Session Slot Gate v2
--
-- Resolves the immutable session slot for character-scoped services.
-- Teardown-safe: PlayerRemoving/BindToClose must NEVER lose the already
-- published slot just because CharacterSlotContextService cleared its
-- internal per-player cache first.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")

local CharacterSlotContextService =
	require(Services:WaitForChild("CharacterSlotContextService"))

local CharacterSessionSlotGate = {}

local DEFAULT_TIMEOUT = 30

local function normalize(slotId: any): string?
	if slotId == nil then
		return nil
	end

	local text = tostring(slotId)
	local n = tonumber(text)

	if not n or n < 1 or n ~= math.floor(n) then
		return nil
	end

	return tostring(math.floor(n))
end

local function getPublishedSlot(player: Player): string?
	return normalize(
		player:GetAttribute("CharacterSlotId")
			or player:GetAttribute("CharacterActiveSlotId")
	)
end

function CharacterSessionSlotGate.WaitForSlot(
	player: Player,
	timeoutSeconds: number?
): string
	-- Fast path: once CharacterSlotContextService publishes the immutable
	-- session slot, that replicated attribute remains usable during teardown
	-- even if the service's internal cache has already been cleared.
	local published = getPublishedSlot(player)

	if published
		and (
			player:GetAttribute("CharacterSlotContextReady") == true
				or player.Parent ~= Players
		) then

		return published
	end

	local timeout =
		typeof(timeoutSeconds) == "number"
		and math.max(0, timeoutSeconds)
		or DEFAULT_TIMEOUT

	local ready, slotId =
		CharacterSlotContextService.WaitUntilReady(
			player,
			timeout
		)

	if ready then
		local normalized = normalize(slotId)
		if normalized then
			return normalized
		end
	end

	-- One final teardown-safe read. This specifically protects
	-- PlayerRemoving/BindToClose races.
	published = getPublishedSlot(player)
	if published then
		return published
	end

	error(
		("[CharacterSessionSlotGate] Slot context unavailable for %s")
			:format(player.Name)
	)
end

function CharacterSessionSlotGate.AssertLoadedSlot(
	player: Player,
	loadedSlotId: any,
	serviceName: string
)
	local actual = normalize(loadedSlotId)

	if not actual then
		error(
			("[%s] Invalid loaded slot | Player=%s Actual=%s")
				:format(
					serviceName,
					player.Name,
					tostring(loadedSlotId)
				)
		)
	end

	local expected = getPublishedSlot(player)

	-- While the player is still live, resolve normally if attributes have
	-- not been published yet.
	if not expected and player.Parent == Players then
		expected =
			CharacterSessionSlotGate.WaitForSlot(
				player
			)
	end

	-- During teardown, if Player is already detached and the published
	-- attributes are unexpectedly unavailable, trust the immutable slot
	-- captured by the service session rather than aborting the final save.
	if not expected and player.Parent ~= Players then
		return
	end

	if expected ~= actual then
		error(
			("[%s] REFUSED wrong slot load/save | Player=%s Expected=%s Actual=%s")
				:format(
					serviceName,
					player.Name,
					tostring(expected),
					actual
				)
		)
	end
end

return CharacterSessionSlotGate
