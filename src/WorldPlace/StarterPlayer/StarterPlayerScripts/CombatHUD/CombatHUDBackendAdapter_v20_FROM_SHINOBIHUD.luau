--!strict
-- StarterPlayer > StarterPlayerScripts > CombatHUD > CombatHUDBackendAdapter_v20_FROM_SHINOBIHUD
--
-- WAYLESS Combat HUD v20 live adapter
--
-- Resource sources preserved from the old working ShinobiHUDController:
--   Health  -> Humanoid.Health / Humanoid.MaxHealth
--   Chakra  -> Character.Chakra / Character.MaxChakra
--   Stamina -> Character.Stamina / Character.MaxStamina
--   Armor   -> ArmorDurability / ArmorMaxDurability / ArmorBroken
--   Chakra aura -> Character.ChakraCharging
--
-- Technique slot sources preserved from the old working TechniqueHotbarController:
--   Player.TechniqueLoadoutSlot_1 ... TechniqueLoadoutSlot_10
--   Player.TechniqueLoadoutReady
--   Character.CoreCooldown_<TechniqueId>_StartsAt
--   Character.CoreCooldown_<TechniqueId>_EndsAt
--
-- Technique metadata comes from the same existing ShinobiMenuSystem RemoteFunction:
--   Request:InvokeServer("GetTechniques", {})
--
-- Frame selection follows Astra v20 exactly:
--   ability -> explicit frameType -> element -> jutsuType -> default
--
-- We author frameType from the authoritative sanitized technique metadata:
--   NatureId -> fire / water / wind / lightning / earth
--   Category -> genjutsu / healing / taijutsu / shuriken / kenjutsu
--
-- IMPORTANT:
-- This adapter replaces the visual responsibility of TechniqueHotbarController.
-- JutsuController / JutsuServer / TechniqueLoadoutService remain authoritative.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local Adapter = {}

local SLOT_COUNT = 10

local HUD_KEY_BY_SLOT: {[number]: string} = {
	[1] = "1",
	[2] = "2",
	[3] = "3",
	[4] = "4",
	[5] = "5",
	[6] = "6",
	[7] = "7",
	[8] = "8",
	[9] = "9",
	[10] = "0",
}

type TechniqueMeta = {
	Id: string,
	DisplayName: string?,
	Category: string?,
	NatureId: string?,
	Icon: string?,
}

local characterConnections: {RBXScriptConnection} = {}
local globalConnections: {RBXScriptConnection} = {}
local heartbeatConnection: RBXScriptConnection? = nil

local techniqueMetaById: {[string]: TechniqueMeta} = {}
local cooldownSignatureBySlot: {[number]: string} = {}
local catalogRefreshBusy = false
local destroyed = false

---------------------------------------------------------------------
-- CONNECTION HELPERS
---------------------------------------------------------------------

local function disconnectList(list: {RBXScriptConnection})
	for _, connection in ipairs(list) do
		connection:Disconnect()
	end
	table.clear(list)
end

local function addCharacterConnection(connection: RBXScriptConnection)
	table.insert(characterConnections, connection)
	return connection
end

local function addGlobalConnection(connection: RBXScriptConnection)
	table.insert(globalConnections, connection)
	return connection
end

---------------------------------------------------------------------
-- RESOURCE HELPERS
---------------------------------------------------------------------

local function numericAttribute(character: Model, name: string, fallback: number): number
	local value = character:GetAttribute(name)
	if typeof(value) == "number" then
		return value
	end
	return fallback
end

local function positiveAttribute(character: Model, name: string, fallback: number): number
	local value = character:GetAttribute(name)
	if typeof(value) == "number" and value > 0 then
		return value
	end
	return fallback
end

local function bindHealth(hud, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	local function refresh()
		hud:SetResource("health", humanoid.Health, humanoid.MaxHealth)
	end

	addCharacterConnection(humanoid.HealthChanged:Connect(refresh))
	addCharacterConnection(humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refresh))
	refresh()
end

local function bindChakra(hud, character: Model)
	local function refresh()
		local maximum = positiveAttribute(character, "MaxChakra", 100)
		local current = math.clamp(numericAttribute(character, "Chakra", maximum), 0, maximum)
		hud:SetResource("chakra", current, maximum)
	end

	local function refreshAura()
		hud:SetAura("chakra", character:GetAttribute("ChakraCharging") == true)
	end

	addCharacterConnection(character:GetAttributeChangedSignal("Chakra"):Connect(refresh))
	addCharacterConnection(character:GetAttributeChangedSignal("MaxChakra"):Connect(refresh))
	addCharacterConnection(character:GetAttributeChangedSignal("ChakraCharging"):Connect(refreshAura))

	refresh()
	refreshAura()
end

local function bindStamina(hud, character: Model)
	local function refresh()
		local maximum = positiveAttribute(character, "MaxStamina", 100)
		local current = math.clamp(numericAttribute(character, "Stamina", maximum), 0, maximum)
		hud:SetResource("stamina", current, maximum)
	end

	addCharacterConnection(character:GetAttributeChangedSignal("Stamina"):Connect(refresh))
	addCharacterConnection(character:GetAttributeChangedSignal("MaxStamina"):Connect(refresh))
	refresh()
end

local function bindArmor(hud, character: Model)
	local function refresh()
		local durability = character:GetAttribute("ArmorDurability")
		local maximum = character:GetAttribute("ArmorMaxDurability")
		local broken = character:GetAttribute("ArmorBroken") == true

		if typeof(maximum) ~= "number" or maximum <= 0 then
			hud:SetResource("armor", 0, 0)
			return
		end

		local current = if typeof(durability) == "number" then durability else 0
		current = math.clamp(current, 0, maximum)

		if broken then
			current = 0
		end

		hud:SetResource("armor", current, maximum)
	end

	addCharacterConnection(character:GetAttributeChangedSignal("ArmorDurability"):Connect(refresh))
	addCharacterConnection(character:GetAttributeChangedSignal("ArmorMaxDurability"):Connect(refresh))
	addCharacterConnection(character:GetAttributeChangedSignal("ArmorBroken"):Connect(refresh))
	addCharacterConnection(character:GetAttributeChangedSignal("EquippedArmorId"):Connect(refresh))
	refresh()
end

---------------------------------------------------------------------
-- TECHNIQUE LOADOUT HELPERS
---------------------------------------------------------------------

local function slotAttributeName(slotIndex: number): string
	return "TechniqueLoadoutSlot_" .. tostring(slotIndex)
end

local function getTechniqueId(slotIndex: number): string?
	local value = player:GetAttribute(slotAttributeName(slotIndex))
	if typeof(value) ~= "string" or value == "" then
		return nil
	end
	return value
end

local function getMenuRequest(): RemoteFunction?
	local system = ReplicatedStorage:FindFirstChild("ShinobiMenuSystem")
	if not system then
		return nil
	end

	local remotes = system:FindFirstChild("Remotes")
	if not remotes then
		return nil
	end

	local request = remotes:FindFirstChild("Request")
	if request and request:IsA("RemoteFunction") then
		return request
	end

	return nil
end

local ELEMENT_FRAME_BY_NATURE: {[string]: string} = {
	fire = "fire",
	water = "water",
	wind = "wind",
	lightning = "lightning",
	earth = "earth",
}

local function normalizeToken(value: any): string
	if typeof(value) ~= "string" then
		return ""
	end

	local token = string.lower(value)
	token = string.gsub(token, "[%s_%-]", "")
	return token
end

local function categoryFrame(category: any): string?
	local token = normalizeToken(category)
	if token == "" then
		return nil
	end

	if string.find(token, "genjutsu", 1, true) then
		return "genjutsu"
	end

	if string.find(token, "healing", 1, true)
		or string.find(token, "medical", 1, true)
		or string.find(token, "medic", 1, true) then
		return "healing"
	end

	if string.find(token, "taijutsu", 1, true) then
		return "taijutsu"
	end

	if string.find(token, "shuriken", 1, true)
		or string.find(token, "throwing", 1, true)
		or string.find(token, "throwable", 1, true)
		or string.find(token, "bukijutsu", 1, true) then
		return "shuriken"
	end

	if string.find(token, "kenjutsu", 1, true)
		or string.find(token, "sword", 1, true) then
		return "kenjutsu"
	end

	return nil
end

local function resolveFrameType(meta: TechniqueMeta?): string
	if not meta then
		return "default"
	end

	local natureToken = normalizeToken(meta.NatureId)
	local elementFrame = ELEMENT_FRAME_BY_NATURE[natureToken]
	if elementFrame then
		return elementFrame
	end

	return categoryFrame(meta.Category) or "default"
end

local function extractIcon(technique: any): string
	-- Current ShinobiMenuService does not expose a technique icon.
	-- These aliases are future-safe if the sanitized payload gains one later.
	local candidates = {
		technique.Icon,
		technique.IconUri,
		technique.Image,
		technique.ImageUri,
	}

	for _, value in ipairs(candidates) do
		if typeof(value) == "string" and value ~= "" then
			return value
		end
	end

	local numericCandidates = {
		technique.IconId,
		technique.ImageId,
	}

	for _, value in ipairs(numericCandidates) do
		if typeof(value) == "number" and value > 0 then
			return "rbxassetid://" .. tostring(math.floor(value))
		elseif typeof(value) == "string" and value ~= "" then
			if string.find(value, "rbxassetid://", 1, true) == 1 then
				return value
			end
			if tonumber(value) then
				return "rbxassetid://" .. value
			end
		end
	end

	return ""
end

local function buildHUDItem(techniqueId: string): {[string]: any}
	local meta = techniqueMetaById[techniqueId]
	local frameType = resolveFrameType(meta)

	return {
		kind = "ability",
		id = techniqueId,
		name = meta and meta.DisplayName or techniqueId,
		displayName = meta and meta.DisplayName or techniqueId,
		frameType = frameType,
		element = meta and meta.NatureId and string.lower(meta.NatureId) or nil,
		jutsuType = meta and meta.Category and string.lower(meta.Category) or nil,
		icon = meta and meta.Icon or "",
	}
end

local function refreshTechniqueCatalog(hud): boolean
	if catalogRefreshBusy or destroyed then
		return false
	end

	catalogRefreshBusy = true

	local request = getMenuRequest()
	if not request then
		catalogRefreshBusy = false
		return false
	end

	local ok, response = pcall(function()
		return request:InvokeServer("GetTechniques", {})
	end)

	if not ok or typeof(response) ~= "table" or typeof(response.Techniques) ~= "table" then
		catalogRefreshBusy = false
		return false
	end

	local fresh: {[string]: TechniqueMeta} = {}

	for _, technique in ipairs(response.Techniques) do
		if typeof(technique) == "table" and typeof(technique.Id) == "string" then
			fresh[technique.Id] = {
				Id = technique.Id,
				DisplayName = if typeof(technique.DisplayName) == "string" then technique.DisplayName else technique.Id,
				Category = if typeof(technique.Category) == "string" then technique.Category else nil,
				NatureId = if typeof(technique.NatureId) == "string" then technique.NatureId else nil,
				Icon = extractIcon(technique),
			}
		end
	end

	techniqueMetaById = fresh
	catalogRefreshBusy = false

	-- Re-render because slots may have first appeared before metadata arrived.
	for slotIndex = 1, SLOT_COUNT do
		local techniqueId = getTechniqueId(slotIndex)
		local hudKey = HUD_KEY_BY_SLOT[slotIndex]

		if techniqueId then
			hud:SetSlot(hudKey, buildHUDItem(techniqueId))
		else
			hud:SetSlot(hudKey, nil)
		end
	end

	print(
		"[CombatHUDBackendAdapter] TECHNIQUE CATALOG"
			.. " | Count=" .. tostring(#response.Techniques)
	)

	return true
end

local function refreshSlot(hud, slotIndex: number)
	local hudKey = HUD_KEY_BY_SLOT[slotIndex]
	local techniqueId = getTechniqueId(slotIndex)

	if not techniqueId then
		hud:SetSlot(hudKey, nil)
		cooldownSignatureBySlot[slotIndex] = ""
		return
	end

	hud:SetSlot(hudKey, buildHUDItem(techniqueId))
	cooldownSignatureBySlot[slotIndex] = ""
end

local function refreshAllSlots(hud)
	for slotIndex = 1, SLOT_COUNT do
		refreshSlot(hud, slotIndex)
	end

	-- Slot G is a Ninja Bag / item slot, not part of TechniqueLoadoutSlot_1..10.
	-- Leave it empty until we connect the Ninja Bag source separately.
	hud:SetSlot("G", nil)
end

---------------------------------------------------------------------
-- COOLDOWNS
---------------------------------------------------------------------

local function getCooldown(character: Model?, techniqueId: string): (number?, number?)
	if not character then
		return nil, nil
	end

	local startsAt = character:GetAttribute(
		"CoreCooldown_" .. techniqueId .. "_StartsAt"
	)

	local endsAt = character:GetAttribute(
		"CoreCooldown_" .. techniqueId .. "_EndsAt"
	)

	if typeof(endsAt) ~= "number" then
		return nil, nil
	end

	local now = workspace:GetServerTimeNow()
	if endsAt <= now then
		return nil, nil
	end

	local duration: number

	if typeof(startsAt) == "number" and endsAt > startsAt then
		duration = endsAt - startsAt
	else
		-- Compatibility fallback. The old controller only needed EndsAt,
		-- but Astra's cooldown shade needs a duration ratio.
		duration = math.max(endsAt - now, 0.05)
	end

	return endsAt, duration
end

local function refreshSlotCooldown(hud, slotIndex: number, character: Model?)
	local hudKey = HUD_KEY_BY_SLOT[slotIndex]
	local techniqueId = getTechniqueId(slotIndex)

	if not techniqueId then
		if cooldownSignatureBySlot[slotIndex] ~= "empty" then
			cooldownSignatureBySlot[slotIndex] = "empty"
			hud:SetCooldown(hudKey, nil, nil)
		end
		return
	end

	local endsAt, duration = getCooldown(character, techniqueId)

	if not endsAt or not duration then
		local signature = techniqueId .. ":ready"
		if cooldownSignatureBySlot[slotIndex] ~= signature then
			cooldownSignatureBySlot[slotIndex] = signature
			hud:SetCooldown(hudKey, nil, nil)
		end
		return
	end

	local signature = techniqueId
		.. ":"
		.. string.format("%.4f", endsAt)
		.. ":"
		.. string.format("%.4f", duration)

	if cooldownSignatureBySlot[slotIndex] ~= signature then
		cooldownSignatureBySlot[slotIndex] = signature
		hud:SetCooldown(hudKey, endsAt, duration)
	end
end

---------------------------------------------------------------------
-- CHARACTER BINDING
---------------------------------------------------------------------

local function bindCharacter(hud, character: Model)
	disconnectList(characterConnections)
	table.clear(cooldownSignatureBySlot)

	bindHealth(hud, character)
	bindChakra(hud, character)
	bindStamina(hud, character)
	bindArmor(hud, character)

	-- Existing working HUD has no authoritative Life Force source yet.
	-- Preserve current behavior rather than inventing one.
	hud:SetLifeForce(100)

	-- Re-apply cooldowns immediately after respawn.
	for slotIndex = 1, SLOT_COUNT do
		refreshSlotCooldown(hud, slotIndex, character)
	end
end

---------------------------------------------------------------------
-- PUBLIC BIND
---------------------------------------------------------------------

function Adapter.Bind(hud)
	destroyed = false

	refreshAllSlots(hud)

	if player.Character then
		task.spawn(bindCharacter, hud, player.Character)
	end

	addGlobalConnection(player.CharacterAdded:Connect(function(character)
		bindCharacter(hud, character)
	end))

	addGlobalConnection(player:GetAttributeChangedSignal("TechniqueLoadoutReady"):Connect(function()
		if player:GetAttribute("TechniqueLoadoutReady") == true then
			task.spawn(function()
				if refreshTechniqueCatalog(hud) then
					refreshAllSlots(hud)
				end
			end)
		end
	end))

	for slotIndex = 1, SLOT_COUNT do
		local index = slotIndex
		addGlobalConnection(player:GetAttributeChangedSignal(slotAttributeName(index)):Connect(function()
			refreshSlot(hud, index)
			refreshSlotCooldown(hud, index, player.Character)
		end))
	end

	-- Same startup strategy as the working old hotbar:
	-- wait/retry for loadout + menu remote to become ready.
	task.spawn(function()
		for _ = 1, 40 do
			if destroyed then
				return
			end

			if player:GetAttribute("TechniqueLoadoutReady") == true then
				if refreshTechniqueCatalog(hud) then
					refreshAllSlots(hud)
					break
				end
			end

			task.wait(0.25)
		end
	end)

	-- Astra's cooldown visuals keep their own RenderStepped countdown.
	-- This heartbeat only notices authoritative cooldown attribute changes.
	local accumulator = 0
	heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 0.05 then
			return
		end
		accumulator = 0

		local character = player.Character

		for slotIndex = 1, SLOT_COUNT do
			refreshSlotCooldown(hud, slotIndex, character)
		end
	end)

	print(
		"[CombatHUDBackendAdapter] CONNECTED"
			.. " | Health=Humanoid"
			.. " | Chakra=CharacterAttributes"
			.. " | Stamina=CharacterAttributes"
			.. " | Armor=DurabilityAttributes"
			.. " | ChakraAura=ChakraCharging"
			.. " | TechniqueSlots=TechniqueLoadoutSlot_1..10"
			.. " | TechniqueFrames=NatureId/Category"
			.. " | Cooldowns=CoreCooldown_StartsAt/EndsAt"
			.. " | LifeForce=TEMP_FULL"
			.. " | GSlot=PENDING_NINJA_BAG"
			.. " | States=PENDING"
	)
end

function Adapter.Destroy()
	destroyed = true

	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end

	disconnectList(characterConnections)
	disconnectList(globalConnections)

	table.clear(techniqueMetaById)
	table.clear(cooldownSignatureBySlot)
end

return Adapter
