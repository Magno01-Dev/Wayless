local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

--------------------------------------------------
-- CONFIG
--------------------------------------------------

local HEIGHT_OFFSET = 0.5
local EDGE_INSET = 0.5

local GRASS_COLOR = BrickColor.new("Parsley green").Color
local GRASS_MATERIAL = Enum.Material.Grass

--------------------------------------------------
-- TOOLBAR
--------------------------------------------------

local toolbar = plugin:CreateToolbar("WAYLESS Map Tools")

local button = toolbar:CreateButton(
	"Create Grass Layer",
	"Creates a grass layer over selected MeshParts",
	"rbxassetid://0"
)

button.ClickableWhenViewportHidden = true

--------------------------------------------------
-- CREATE GRASS
--------------------------------------------------

local function createGrassLayer()
	local selected = Selection:Get()
	local created = {}

	ChangeHistoryService:SetWaypoint("Before Create Grass Layer")

	for _, original in ipairs(selected) do
		if original:IsA("MeshPart") then

			-- Prevent accidentally processing an existing grass layer
			if original:GetAttribute("GrassLayer") then
				continue
			end

			local newX = original.Size.X - (EDGE_INSET * 2)
			local newZ = original.Size.Z - (EDGE_INSET * 2)

			-- Ignore meshes that would become invalid
			if newX <= 0 or newZ <= 0 then
				warn(
					"[Grass Tool] Skipped:",
					original:GetFullName(),
					"- too small for current inset."
				)

				continue
			end

			local grass = original:Clone()

			grass.Name = original.Name .. "_Grass"

			grass.Size = Vector3.new(
				newX,
				original.Size.Y,
				newZ
			)

			-- Move upward relative to the mesh itself
			grass.CFrame =
				original.CFrame
				* CFrame.new(0, HEIGHT_OFFSET, 0)

			grass.Material = GRASS_MATERIAL
			grass.Color = GRASS_COLOR

			grass.CanCollide = false
			grass.CanTouch = false
			grass.CanQuery = false

			grass:SetAttribute("GrassLayer", true)

			grass.Parent = original.Parent

			table.insert(created, grass)
		end
	end

	if #created > 0 then
		Selection:Set(created)
	end

	ChangeHistoryService:SetWaypoint("Create Grass Layer")

	print(
		string.format(
			"[WAYLESS Grass Tool] Created %d grass layers.",
			#created
		)
	)
end

--------------------------------------------------
-- BUTTON
--------------------------------------------------

button.Click:Connect(createGrassLayer)