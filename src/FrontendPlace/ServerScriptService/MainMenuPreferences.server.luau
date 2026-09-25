--!strict
-- ServerScriptService > MainMenuPreferencesBootstrap
-- WAYLESS Main Menu Preferences v1
--
-- Isolated persistence for frontend-only preferences. The first preference is
-- LastSlotId, used by Main Menu Quickplay. It does NOT authorize a slot or a
-- teleport: FrontendService/PlaySlot remains the authoritative validator.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local STORE_NAME = "WAYLESS_FrontendPreferences_v1"
local store = DataStoreService:GetDataStore(STORE_NAME)

type PreferenceState = {
	Ready: boolean,
	LastSlotId: string?,
}

local states: {[Player]: PreferenceState} = {}

local function normalizeSlotId(value: any): string?
	if value == nil then
		return nil
	end

	local numeric = tonumber(value)
	if not numeric
		or numeric < 1
		or numeric ~= math.floor(numeric) then
		return nil
	end

	return tostring(math.floor(numeric))
end

local function keyForUserId(userId: number): string
	return "u_" .. tostring(userId)
end

local function setAttribute(player: Player, slotId: string?)
	player:SetAttribute("FrontendLastUsedSlotId", slotId)
end

local function saveUserId(userId: number, slotId: string?): boolean
	local ok, err = pcall(function()
		store:UpdateAsync(keyForUserId(userId), function(old)
			local value = typeof(old) == "table" and old or {}
			value.LastSlotId = slotId
			value.UpdatedAt = os.time()
			return value
		end)
	end)

	if not ok then
		warn("[MainMenuPreferences] Save failed", userId, err)
	end

	return ok
end

local function loadPlayer(player: Player)
	local state: PreferenceState = {
		Ready = false,
		LastSlotId = nil,
	}
	states[player] = state

	local ok, result = pcall(function()
		return store:GetAsync(keyForUserId(player.UserId))
	end)

	if ok then
		if typeof(result) == "table" then
			state.LastSlotId = normalizeSlotId(result.LastSlotId)
		else
			state.LastSlotId = normalizeSlotId(result)
		end
	else
		-- Studio without API Services or a temporary DataStore failure should not
		-- block the frontend. The preference simply behaves as memory-only.
		warn("[MainMenuPreferences] Load failed; using memory fallback", player.Name, result)
	end

	state.Ready = true
	setAttribute(player, state.LastSlotId)
end

local function ensureRemote(): RemoteFunction
	local system = ReplicatedStorage:FindFirstChild("FrontendSystem")
	if not system then
		system = Instance.new("Folder")
		system.Name = "FrontendSystem"
		system.Parent = ReplicatedStorage
	end

	local remotes = system:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = system
	end

	local existing = remotes:FindFirstChild("MainMenuPreferencesRequest")
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = "MainMenuPreferencesRequest"
	remote.Parent = remotes
	return remote
end

local remote = ensureRemote()

remote.OnServerInvoke = function(player: Player, action: any, payload: any)
	local state = states[player]
	if not state then
		loadPlayer(player)
		state = states[player]
	end

	if action == "GetLastSlot" then
		return {
			Ok = true,
			Ready = state.Ready,
			LastSlotId = state.LastSlotId,
		}
	end

	if action == "SetLastSlot" then
		local slotId = normalizeSlotId(
			typeof(payload) == "table" and payload.SlotId or nil
		)

		if not slotId then
			return {
				Ok = false,
				Ready = state.Ready,
				Reason = "InvalidSlotId",
				LastSlotId = state.LastSlotId,
			}
		end

		state.LastSlotId = slotId
		state.Ready = true
		setAttribute(player, slotId)

		local userId = player.UserId
		task.spawn(function()
			saveUserId(userId, slotId)
		end)

		return {
			Ok = true,
			Ready = true,
			Reason = "LastSlotUpdated",
			LastSlotId = slotId,
		}
	end

	return {
		Ok = false,
		Ready = state.Ready,
		Reason = "UnknownAction",
		LastSlotId = state.LastSlotId,
	}
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(loadPlayer, player)
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(loadPlayer, player)
end)

Players.PlayerRemoving:Connect(function(player)
	local state = states[player]
	if state and state.LastSlotId then
		saveUserId(player.UserId, state.LastSlotId)
	end
	states[player] = nil
end)

game:BindToClose(function()
	for player, state in pairs(states) do
		if state.LastSlotId then
			saveUserId(player.UserId, state.LastSlotId)
		end
	end
end)

print("[MainMenuPreferences] READY v1 | LastSlotPersistence=ON | Store=" .. STORE_NAME)
