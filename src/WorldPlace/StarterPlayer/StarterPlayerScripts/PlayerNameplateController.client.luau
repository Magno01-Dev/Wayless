--!strict
-- StarterPlayer > StarterPlayerScripts > PlayerNameplateController.client.lua
--
-- WAYLESS Player Nameplate v2.1 - Aspect + LOS Fix
--
-- Asset visual:
--   rbxassetid://81157076050471
--
-- Fuente:
--   El archivo que enviaste es "Kungfoo Fighter DEMO".
--   Roblox no puede cargar un .otf desde tu PC durante el juego.
--   Debes importar/subir esa fuente a Roblox y colocar SU ASSET ID
--   en CUSTOM_FONT_ASSET_ID, abajo.
--
-- PvP:
--   - El jugador local NUNCA ve su propio nameplate.
--   - Solo se muestra a corta distancia.
--   - El Billboard usa AlwaysOnTop = true para que el propio cuerpo/cabeza
--     no lo oculte segun el angulo.
--   - Un raycast local de linea de vision evita verlo a traves de paredes.
--
-- Datos usados:
--   CharacterLevel
--   NinjaRankDisplayName / NinjaRank
--   AffiliationVillageId
--   IsRogue
--   ClanDisplayName / ClanId
--   CharacterFirstName (si algun sistema lo publica)
--   Fallback de nombre: Player.DisplayName
--
-- ================================================================
-- AJUSTES RAPIDOS
-- ================================================================
--
-- Para mover algo:
--   X mas grande  = mover a la DERECHA
--   X mas pequeno = mover a la IZQUIERDA
--   Y mas grande  = mover ABAJO
--   Y mas pequeno = mover ARRIBA
--
-- Estos son los valores que normalmente vas a tocar manualmente.
--
-- BASE RECOMENDADA CON EL ASSET 81157076050471:
--   BILLBOARD_WIDTH  = 390
--   BILLBOARD_HEIGHT = 150
--   NAME_Y           = 0.395
--   INFO_Y           = 0.690
--
-- NO cambies ScaleType a Stretch: el asset se deforma.
-- ================================================================

local MAX_VISIBLE_DISTANCE = 18

-- true = no mostrar nameplates si hay una pared/objeto opaco entre ambos.
-- Recomendado para PvP.
local REQUIRE_LINE_OF_SIGHT = true

-- Tamano completo del BillboardGui.
local BILLBOARD_WIDTH = 390
local BILLBOARD_HEIGHT = 150

-- Altura sobre la cabeza.
local BILLBOARD_OFFSET_X = 0
local BILLBOARD_OFFSET_Y = 3.15
local BILLBOARD_OFFSET_Z = 0

-- ------------------------------------------------
-- POSICION DEL NOMBRE
-- ------------------------------------------------
local NAME_X = 0.530
local NAME_Y = 0.480

local NAME_WIDTH = 0.60
local NAME_HEIGHT = 0.22

local NAME_MIN_TEXT_SIZE = 25
local NAME_MAX_TEXT_SIZE = 50

-- ------------------------------------------------
-- POSICION DE ALDEA / RANGO / NIVEL
-- ------------------------------------------------
local INFO_X = 0.510
local INFO_Y = 0.650

local INFO_WIDTH = 0.56
local INFO_HEIGHT = 0.105

local INFO_MIN_TEXT_SIZE = 14
local INFO_MAX_TEXT_SIZE = 22

-- ------------------------------------------------
-- IMAGEN
-- ------------------------------------------------
local NAMEPLATE_IMAGE_ASSET_ID = 81157076050471

-- ------------------------------------------------
-- FUENTE CUSTOM
-- ------------------------------------------------
--
-- IMPORTANTE:
-- El .otf que me pasaste es:
--   Kungfoo Fighter DEMO
--
-- Cuando lo importes/subas a Roblox, pon aqui el ID del FONT ASSET.
-- Ejemplo:
-- local CUSTOM_FONT_ASSET_ID = 12345678901234
--
-- Mientras sea 0, usa Fondamento como fallback para que el script
-- funcione sin romperse.
--
local CUSTOM_FONT_ASSET_ID = 0

-- false = la fuente custom solo se usa para el nombre.
-- true  = tambien se usa en "Leaf Village • Genin • Lv. 12".
local USE_CUSTOM_FONT_FOR_INFO = false

-- Si el juego ya desactiva el nombre default de Roblox globalmente,
-- puedes poner esto en false.
local HIDE_DEFAULT_ROBLOX_NAMEPLATE = true

-- ================================================================
-- FIN DE AJUSTES RAPIDOS
-- ================================================================

local Players =
	game:GetService(
		"Players"
	)

local RunService =
	game:GetService(
		"RunService"
	)

local ReplicatedStorage =
	game:GetService(
		"ReplicatedStorage"
	)

local Workspace =
	game:GetService(
		"Workspace"
	)

local LOCAL_PLAYER =
	Players.LocalPlayer

local NAMEPLATE_IMAGE =
	"rbxassetid://"
	.. tostring(
		NAMEPLATE_IMAGE_ASSET_ID
	)

local NAMEPLATE_SIZE =
	UDim2.fromOffset(
		BILLBOARD_WIDTH,
		BILLBOARD_HEIGHT
	)

local STUDS_OFFSET =
	Vector3.new(
		BILLBOARD_OFFSET_X,
		BILLBOARD_OFFSET_Y,
		BILLBOARD_OFFSET_Z
	)

---------------------------------------------------------------------
-- OPTIONAL VILLAGE DEFINITIONS
---------------------------------------------------------------------

local VillageDefinitions: any =
	nil

do
	local originSystem =
		ReplicatedStorage:
		FindFirstChild(
			"CharacterOriginSystem"
		)

	if originSystem then
		local shared =
			originSystem:
			FindFirstChild(
				"Shared"
			)

		if shared then
			local module =
				shared:
				FindFirstChild(
					"VillageDefinitions"
				)

			if module
				and module:IsA(
					"ModuleScript"
				) then

				local ok,
					result =
					pcall(
						require,
						module
					)

				if ok then
					VillageDefinitions =
						result
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- TYPES / STATE
---------------------------------------------------------------------

type NameplateRecord = {
	Player: Player,
	Character: Model?,
	Gui: BillboardGui?,
	NameLabel: TextLabel?,
	InfoLabel: TextLabel?,
	Connections: {RBXScriptConnection},
}

local records: {[Player]: NameplateRecord} =
	{}

---------------------------------------------------------------------
-- FONT
---------------------------------------------------------------------

local function applyCustomFont(
	label: TextLabel,
	fallback: Enum.Font
)
	if CUSTOM_FONT_ASSET_ID > 0 then
		local ok =
			pcall(
				function()
					label.FontFace =
					Font.new(
						"rbxassetid://"
						.. tostring(
							CUSTOM_FONT_ASSET_ID
						)
					)
				end
			)

		if ok then
			return
		end

		warn(
			"[WAYLESS Nameplate] No se pudo cargar CUSTOM_FONT_ASSET_ID:",
			CUSTOM_FONT_ASSET_ID
		)
	end

	label.Font =
		fallback
end

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------

local function disconnectAll(
	record: NameplateRecord
)
	for _, connection in ipairs(
		record.Connections
		) do
		connection:
			Disconnect()
	end

	table.clear(
		record.Connections
	)
end

local function getRoot(
	character: Model?
): BasePart?
	if not character then
		return nil
	end

	local root =
		character:
		FindFirstChild(
			"HumanoidRootPart"
		)

	if root
		and root:IsA(
			"BasePart"
		) then

		return root
	end

	return nil
end

local function getHead(
	character: Model?
): BasePart?
	if not character then
		return nil
	end

	local head =
		character:
		FindFirstChild(
			"Head"
		)

	if head
		and head:IsA(
			"BasePart"
		) then

		return head
	end

	return nil
end

local function hideDefaultRobloxNameplate(
	character: Model
)
	if not HIDE_DEFAULT_ROBLOX_NAMEPLATE then
		return
	end

	local humanoid =
		character:
		FindFirstChildOfClass(
			"Humanoid"
		)

	if humanoid then
		humanoid.DisplayDistanceType =
			Enum.HumanoidDisplayDistanceType.None
	end
end

local function getCharacterName(
	player: Player
): string
	-- Si posteriormente el sistema de slots/nombres publica
	-- CharacterFirstName, este nameplate ya lo usara automaticamente.
	local customName =
		player:GetAttribute(
			"CharacterFirstName"
		)

	if typeof(customName) ==
		"string"
		and customName ~= "" then

		return customName
	end

	if player.DisplayName ~= "" then
		return player.DisplayName
	end

	return player.Name
end

local function getClanSurname(
	player: Player
): string?
	local clan =
		player:GetAttribute(
			"ClanDisplayName"
		)

	if typeof(clan) ==
		"string"
		and clan ~= "" then

		return clan
	end

	local clanId =
		player:GetAttribute(
			"ClanId"
		)

	if typeof(clanId) ==
		"string"
		and clanId ~= "" then

		return clanId
	end

	return nil
end

local function getFullName(
	player: Player
): string
	local firstName =
		getCharacterName(
			player
		)

	local clan =
		getClanSurname(
			player
		)

	if clan then
		-- Evita duplicar el clan si el DisplayName ya termina
		-- exactamente con ese apellido.
		local lowerFirst =
			string.lower(
				firstName
			)

		local lowerClan =
			string.lower(
				clan
			)

		local suffix =
			" "
			.. lowerClan

		if string.sub(
			lowerFirst,
			-math.min(
				#lowerFirst,
				#suffix
			)
			) ~= suffix then

			return firstName
				.. " "
				.. clan
		end
	end

	return firstName
end

local function getVillageDisplayName(
	player: Player
): string
	if player:GetAttribute(
		"IsRogue"
		) == true then

		return "Rogue"
	end

	local villageId =
		player:GetAttribute(
			"AffiliationVillageId"
		)

	if typeof(villageId) ~=
		"string"
		or villageId == "" then

		return "No Village"
	end

	if VillageDefinitions then
		local ok,
			definition =
			pcall(
				function()
					if VillageDefinitions.Get then
						return VillageDefinitions.Get(
							villageId
						)
					end

					return VillageDefinitions[
					villageId
					]
				end
			)

		if ok
			and typeof(definition) ==
			"table" then

			local display =
				definition.DisplayName
				or definition.Name

			if typeof(display) ==
				"string"
				and display ~= "" then

				return display
			end
		end
	end

	return villageId
end

local function getRank(
	player: Player
): string
	local displayRank =
		player:GetAttribute(
			"NinjaRankDisplayName"
		)

	if typeof(displayRank) ==
		"string"
		and displayRank ~= "" then

		return displayRank
	end

	local rank =
		player:GetAttribute(
			"NinjaRank"
		)

	if typeof(rank) ==
		"string"
		and rank ~= "" then

		return rank
	end

	return "Shinobi"
end

local function getLevel(
	player: Player
): number
	local level =
		player:GetAttribute(
			"CharacterLevel"
		)

	if typeof(level) ==
		"number" then

		return math.max(
			1,
			math.floor(
				level
			)
		)
	end

	return 1
end

---------------------------------------------------------------------
-- UI
---------------------------------------------------------------------

local function makeNameLabel(
	parent: Instance
): TextLabel
	local label =
		Instance.new(
			"TextLabel"
		)

	label.Name =
		"CharacterName"

	label.BackgroundTransparency =
		1

	label.AnchorPoint =
		Vector2.new(
			0.5,
			0.5
		)

	label.Position =
		UDim2.fromScale(
			NAME_X,
			NAME_Y
		)

	label.Size =
		UDim2.fromScale(
			NAME_WIDTH,
			NAME_HEIGHT
		)

	label.Text =
		""

	label.TextColor3 =
		Color3.fromRGB(
			27,
			24,
			20
		)

	label.TextScaled =
		true

	label.TextWrapped =
		false

	label.TextXAlignment =
		Enum.TextXAlignment.Center

	label.TextYAlignment =
		Enum.TextYAlignment.Center

	applyCustomFont(
		label,
		Enum.Font.Fondamento
	)

	label.Parent =
		parent

	local constraint =
		Instance.new(
			"UITextSizeConstraint"
		)

	constraint.MinTextSize =
		NAME_MIN_TEXT_SIZE

	constraint.MaxTextSize =
		NAME_MAX_TEXT_SIZE

	constraint.Parent =
		label

	return label
end

local function makeInfoLabel(
	parent: Instance
): TextLabel
	local label =
		Instance.new(
			"TextLabel"
		)

	label.Name =
		"CharacterInfo"

	label.BackgroundTransparency =
		1

	label.AnchorPoint =
		Vector2.new(
			0.5,
			0.5
		)

	label.Position =
		UDim2.fromScale(
			INFO_X,
			INFO_Y
		)

	label.Size =
		UDim2.fromScale(
			INFO_WIDTH,
			INFO_HEIGHT
		)

	label.Text =
		""

	label.TextColor3 =
		Color3.fromRGB(
			239,
			225,
			198
		)

	label.TextScaled =
		true

	label.TextWrapped =
		false

	label.TextXAlignment =
		Enum.TextXAlignment.Center

	label.TextYAlignment =
		Enum.TextYAlignment.Center

	if USE_CUSTOM_FONT_FOR_INFO then
		applyCustomFont(
			label,
			Enum.Font.Garamond
		)
	else
		label.Font =
			Enum.Font.Garamond
	end

	label.Parent =
		parent

	local constraint =
		Instance.new(
			"UITextSizeConstraint"
		)

	constraint.MinTextSize =
		INFO_MIN_TEXT_SIZE

	constraint.MaxTextSize =
		INFO_MAX_TEXT_SIZE

	constraint.Parent =
		label

	return label
end

local function createGui(
	player: Player,
	character: Model
): (
	BillboardGui?,
	TextLabel?,
	TextLabel?
	)
	if player ==
		LOCAL_PLAYER then

		return nil,
			nil,
			nil
	end

	local head =
		getHead(
			character
		)

	if not head then
		return nil,
			nil,
			nil
	end

	local old =
		head:
		FindFirstChild(
			"WAYLESSPlayerNameplate"
		)

	if old then
		old:
			Destroy()
	end

	local gui =
		Instance.new(
			"BillboardGui"
		)

	gui.Name =
		"WAYLESSPlayerNameplate"

	gui.Adornee =
		head

	-- Debe ser true.
	-- Con false, la cabeza/cuerpo del propio personaje puede tapar el
	-- Billboard dependiendo del angulo de la camara (el error que vio KMZ).
	-- Las paredes se controlan aparte con raycast.
	gui.AlwaysOnTop =
		true

	gui.LightInfluence =
		0

	gui.Size =
		NAMEPLATE_SIZE

	gui.StudsOffsetWorldSpace =
		STUDS_OFFSET

	gui.MaxDistance =
		MAX_VISIBLE_DISTANCE

	gui.Enabled =
		false

	gui.Parent =
		head

	local background =
		Instance.new(
			"ImageLabel"
		)

	background.Name =
		"Background"

	background.BackgroundTransparency =
		1

	background.AnchorPoint =
		Vector2.new(
			0.5,
			0.5
		)

	background.Position =
		UDim2.fromScale(
			0.5,
			0.5
		)

	background.Size =
		UDim2.fromScale(
			1,
			1
		)

	background.Image =
		NAMEPLATE_IMAGE

	-- NO usar Stretch: deforma horizontalmente el arte.
	-- Fit conserva la proporcion original del asset.
	background.ScaleType =
		Enum.ScaleType.Fit

	background.Parent =
		gui

	local nameLabel =
		makeNameLabel(
			background
		)

	local infoLabel =
		makeInfoLabel(
			background
		)

	return gui,
		nameLabel,
		infoLabel
end

---------------------------------------------------------------------
-- REFRESH
---------------------------------------------------------------------

local function refreshText(
	record: NameplateRecord
)
	local player =
		record.Player

	if record.NameLabel then
		record.NameLabel.Text =
			getFullName(
				player
			)
	end

	if record.InfoLabel then
		local village =
			getVillageDisplayName(
				player
			)

		local rank =
			getRank(
				player
			)

		local level =
			getLevel(
				player
			)

		record.InfoLabel.Text =
			string.format(
				"%s  •  %s  •  Lv. %d",
				village,
				rank,
				level
			)
	end
end

local WATCHED_ATTRIBUTES = {
	"CharacterFirstName",

	"ClanId",
	"ClanDisplayName",

	"CharacterLevel",

	"NinjaRank",
	"NinjaRankDisplayName",

	"OriginVillageId",
	"AffiliationVillageId",
	"IsRogue",
}

local function bindCharacter(
	record: NameplateRecord,
	character: Model
)
	record.Character =
		character

	if record.Gui then
		record.Gui:
			Destroy()
	end

	record.Gui =
		nil

	record.NameLabel =
		nil

	record.InfoLabel =
		nil

	local head =
		character:
		WaitForChild(
			"Head",
			10
		)

	if not head then
		return
	end

	hideDefaultRobloxNameplate(
		character
	)

	local gui,
		nameLabel,
		infoLabel =
		createGui(
			record.Player,
			character
		)

	record.Gui =
		gui

	record.NameLabel =
		nameLabel

	record.InfoLabel =
		infoLabel

	refreshText(
		record
	)
end

local function removePlayer(
	player: Player
)
	local record =
		records[
	player
	]

	if not record then
		return
	end

	disconnectAll(
		record
	)

	if record.Gui then
		record.Gui:
			Destroy()
	end

	records[
	player
	] =
		nil
end

local function addPlayer(
	player: Player
)
	if player ==
		LOCAL_PLAYER then

		return
	end

	if records[
		player
		] then

		return
	end

	local record: NameplateRecord = {
		Player = player,
		Character = nil,
		Gui = nil,
		NameLabel = nil,
		InfoLabel = nil,
		Connections = {},
	}

	records[
	player
	] =
		record

	table.insert(
		record.Connections,
		player.CharacterAdded:
			Connect(
				function(
					character
				)
					bindCharacter(
						record,
						character
					)
				end
			)
	)

	for _, attributeName in ipairs(
		WATCHED_ATTRIBUTES
		) do
		table.insert(
			record.Connections,
			player:
				GetAttributeChangedSignal(
					attributeName
				):
				Connect(
					function()
						refreshText(
							record
						)
					end
				)
		)
	end

	if player.Character then
		task.spawn(
			bindCharacter,
			record,
			player.Character
		)
	end
end

---------------------------------------------------------------------
-- VISIBILITY
---------------------------------------------------------------------

local function hasLineOfSight(
	localCharacter: Model,
	targetCharacter: Model,
	targetHead: BasePart
): boolean
	if not REQUIRE_LINE_OF_SIGHT then
		return true
	end

	local camera =
		Workspace.CurrentCamera

	if not camera then
		return false
	end

	local origin =
		camera.CFrame.Position

	-- Apuntamos a la cabeza del jugador, no al Billboard.
	-- El targetCharacter se excluye del raycast para que su propia cabeza,
	-- cabello, accesorios o cuerpo nunca bloqueen su nameplate.
	local targetPosition =
		targetHead.Position

	local direction =
		targetPosition
	- origin

	if direction.Magnitude <= 0.001 then
		return true
	end

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.FilterDescendantsInstances = {
		localCharacter,
		targetCharacter,
	}

	params.IgnoreWater =
		true

	local result =
		Workspace:Raycast(
			origin,
			direction,
			params
		)

	-- Si no golpeamos nada antes del target, hay vision directa.
	return result == nil
end

local function updateVisibility()
	local localCharacter =
		LOCAL_PLAYER.Character

	local localRoot =
		getRoot(
			localCharacter
		)

	if not localRoot then
		for _,
			record in pairs(
				records
			) do

			if record.Gui then
				record.Gui.Enabled =
					false
			end
		end

		return
	end

	for player,
		record in pairs(
			records
		) do

		local gui =
			record.Gui

		if not gui then
			continue
		end

		if player ==
			LOCAL_PLAYER then

			gui.Enabled =
				false

			continue
		end

		local character =
			record.Character

		local root =
			getRoot(
				character
			)

		local humanoid =
			character
			and character:
			FindFirstChildOfClass(
				"Humanoid"
			)

		if not root
			or not humanoid
			or humanoid.Health <= 0 then

			gui.Enabled =
				false

			continue
		end

		local distance =
			(
				root.Position
				- localRoot.Position
			).Magnitude

		if distance >
			MAX_VISIBLE_DISTANCE then

			gui.Enabled =
				false

			continue
		end

		local head =
			getHead(
				character
			)

		if not head then
			gui.Enabled =
				false

			continue
		end

		gui.Enabled =
			hasLineOfSight(
				localCharacter,
				character,
				head
			)
	end
end

---------------------------------------------------------------------
-- START
---------------------------------------------------------------------

for _, player in ipairs(
	Players:GetPlayers()
	) do
	addPlayer(
		player
	)
end

Players.PlayerAdded:
	Connect(
		addPlayer
	)

Players.PlayerRemoving:
	Connect(
		removePlayer
	)

-- 15 actualizaciones por segundo es suficiente para visibilidad
-- y evita gastar trabajo innecesario por frame.
local accumulator =
	0

RunService.Heartbeat:
	Connect(
		function(
			deltaTime
		)
			accumulator +=
			deltaTime

			if accumulator <
				1 / 15 then

				return
			end

			accumulator =
			0

			updateVisibility()
		end
	)
