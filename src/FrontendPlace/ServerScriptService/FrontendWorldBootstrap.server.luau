--!strict
-- ServerScriptService > FrontendWorldBootstrap
--
-- WAYLESS Frontend scene bootstrap v3.
-- Streaming-safe creation scene architecture.
--
-- IMPORTANT:
-- Workspace > FrontendScene        = environment / art
-- Workspace > FrontendSceneMarkers = persistent camera/spawn markers
--
-- Keep FrontendSceneMarkers as a Model. Its parts may be moved freely when
-- building the final character-creation environment.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- ============================================================
-- ENVIRONMENT
-- ============================================================

local environment =
	Workspace:FindFirstChild("FrontendScene")

local createdEnvironment = false

if not environment then
	local folder = Instance.new("Folder")
	folder.Name = "FrontendScene"
	folder.Parent = Workspace

	environment = folder
	createdEnvironment = true
end

-- Only create the old placeholder environment if no environment existed.
if createdEnvironment then
	Lighting.ClockTime = 18.5
	Lighting.Brightness = 1.2
	Lighting.Ambient = Color3.fromRGB(42, 45, 54)
	Lighting.OutdoorAmbient = Color3.fromRGB(27, 30, 38)

	local floor = Instance.new("Part")
	floor.Name = "Ground"
	floor.Anchored = true
	floor.Size = Vector3.new(180, 1, 180)
	floor.Position = Vector3.new(0, -1, 0)
	floor.Material = Enum.Material.Slate
	floor.Color = Color3.fromRGB(19, 22, 28)
	floor.Parent = environment
end

-- ============================================================
-- PERSISTENT MARKERS
-- ============================================================

local markerContainer =
	Workspace:FindFirstChild("FrontendSceneMarkers")

if markerContainer
	and not markerContainer:IsA("Model") then

	warn(
		"[FrontendWorldBootstrap] FrontendSceneMarkers existed but was not a Model. "
			.. "Renaming the old object."
	)

	markerContainer.Name =
		"FrontendSceneMarkers_Legacy_"
		.. tostring(os.time())

	markerContainer = nil
end

if not markerContainer then
	local model = Instance.new("Model")
	model.Name = "FrontendSceneMarkers"
	model.Parent = Workspace
	markerContainer = model
end

local markerModel = markerContainer :: Model

-- These markers must never stream out. The actual environment may still use
-- normal instance streaming.
markerModel.ModelStreamingMode =
	Enum.ModelStreamingMode.Persistent

local function findLegacyMarker(
	name: string
): BasePart?
	local legacy =
		environment:
		FindFirstChild(name)

	if legacy
		and legacy:IsA("BasePart") then

		return legacy
	end

	return nil
end

local function ensureMarker(
	name: string,
	defaultCFrame: CFrame
): BasePart
	local existing =
		markerModel:
		FindFirstChild(name)

	if existing
		and existing:IsA("BasePart") then

		return existing
	end

	if existing then
		existing:Destroy()
	end

	-- Preserve any marker positions already created by v1/v2.
	local legacy =
		findLegacyMarker(name)

	if legacy then
		legacy.Parent = markerModel
		return legacy
	end

	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = defaultCFrame
	part.Parent = markerModel

	return part
end

-- Main menu.
local cameraAnchor =
	ensureMarker(
		"CameraAnchor",
		CFrame.new(0, 18, 34)
		* CFrame.Angles(
			math.rad(-10),
			math.rad(180),
			0
		)
	)

ensureMarker(
	"CameraFocus",
	CFrame.new(0, 6, 0)
)

-- Character Creation.
-- v4 centers the mannequin between the two parchment panels. Existing artist-edited
-- markers are preserved; only the old v3 default positions are migrated.
local OLD_CREATION_SPAWN_POSITION = Vector3.new(3.3, 0, 0)
local OLD_CREATION_FOCUS_POSITION = Vector3.new(-0.6, 3.7, 0)
local CENTERED_CREATION_SPAWN_CFRAME =
	CFrame.new(0, 0, 0)
	* CFrame.Angles(0, math.rad(180), 0)
local CENTERED_CREATION_FOCUS_CFRAME = CFrame.new(0, 3.7, 0)

local creationSpawn =
	ensureMarker(
		"CharacterCreationSpawn",
		CENTERED_CREATION_SPAWN_CFRAME
	)

local creationCamera =
	ensureMarker(
		"CharacterCreationCamera",
		CFrame.new(0, 4.6, 15)
	)

local creationFocus =
	ensureMarker(
		"CharacterCreationFocus",
		CENTERED_CREATION_FOCUS_CFRAME
	)

if (creationSpawn.Position - OLD_CREATION_SPAWN_POSITION).Magnitude <= 0.05 then
	creationSpawn.CFrame = CENTERED_CREATION_SPAWN_CFRAME
end

if (creationFocus.Position - OLD_CREATION_FOCUS_POSITION).Magnitude <= 0.05 then
	creationFocus.CFrame = CENTERED_CREATION_FOCUS_CFRAME
end

-- Streaming focus is separate so the artist can move the visible camera/spawn
-- markers without accidentally breaking the streaming configuration.
local streamingFocus =
	ensureMarker(
		"StreamingFocus",
		CFrame.new(
			creationSpawn.Position.X,
			math.max(creationSpawn.Position.Y, 2),
			creationSpawn.Position.Z
		)
	)

-- ============================================================
-- STREAMING
-- ============================================================

local function configurePlayerStreaming(
	player: Player
)
	if not Workspace.StreamingEnabled then
		return
	end

	-- Keep the Frontend scene streamed even when the Roblox character itself is
	-- somewhere else. This is required because streaming follows replication
	-- foci, not the Scriptable camera.
	local addOk, addError =
		pcall(function()
			player:AddReplicationFocus(
				streamingFocus
			)
		end)

	if not addOk then
		warn(
			"[FrontendWorldBootstrap] AddReplicationFocus failed:",
			player.Name,
			addError
		)
	end

	-- Proactively request the initial region as well.
	task.spawn(function()
		local streamOk, streamError =
			pcall(function()
				player:
				RequestStreamAroundAsync(
					streamingFocus.Position
				)
			end)

		if not streamOk then
			warn(
				"[FrontendWorldBootstrap] RequestStreamAroundAsync failed:",
				player.Name,
				streamError
			)
		end
	end)
end

Players.PlayerAdded:
	Connect(configurePlayerStreaming)

for _, player in ipairs(
	Players:GetPlayers()
	) do
	task.spawn(
		configurePlayerStreaming,
		player
	)
end

print(
	"[FrontendWorldBootstrap] READY v4 CENTERED_CREATOR"
		.. " | StreamingSafeMarkers=ON"
		.. " | StreamingEnabled="
		.. tostring(
			Workspace.StreamingEnabled
		)
		.. " | MarkerModel="
		.. markerModel:GetFullName()
		.. " | Spawn="
		.. tostring(
			creationSpawn.Position
		)
)
