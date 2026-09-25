--!strict
-- ServerScriptService > JutsuSystem > Jutsus > WaterBullet
--
-- WaterBullet Anime v2: corrected shell normals, proportions and opaque body.
-- Self-contained VFX. Original gameplay preserved.
-- Assets: ReplicatedStorage/VFX/Jutsus/Water/WaterBulletAnime

local RunService = game:GetService("RunService")

local Debris = game:GetService("Debris")
-- Self-contained visual layer. Does not touch damage or shared VFX controllers.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local WATER = Color3.fromRGB(40, 127, 161)
local LIGHT_WATER = Color3.fromRGB(152, 214, 221)
local FOAM = Color3.fromRGB(226, 244, 237)
local visualStates: {[BasePart]: any} = {}
local missingWarned: {[string]: boolean} = {}
local WaterBulletVFX = {}

local function assets(): Instance?
	local vfx = ReplicatedStorage:FindFirstChild("VFX")
	local jutsus = vfx and vfx:FindFirstChild("Jutsus")
	local water = jutsus and jutsus:FindFirstChild("Water")
	return water and water:FindFirstChild("WaterBulletAnime")
end

local function normalizeTextureId(value: any): string
	if typeof(value) ~= "string" and typeof(value) ~= "number" then return "" end
	local raw = tostring(value):match("^%s*(.-)%s*$") or ""
	local id = raw:match("^(%d+)$")
		or raw:match("^rbxassetid://(%d+)$")
		or raw:match("^https?://www%.roblox%.com/asset/%?id=(%d+)")
		or raw:match("^https?://www%.roblox%.com/asset%?id=(%d+)")
	if not id or not id:find("[1-9]") then return "" end
	return "rbxassetid://" .. id
end

local function texture(name: string): string
	local bank = assets()
	local id = if bank then normalizeTextureId(bank:GetAttribute(name)) else ""
	-- Accept both attribute-based installation and child StringValue objects.
	if id == "" and bank then
		local child = bank:FindFirstChild(name)
		if child and child:IsA("StringValue") then
			id = normalizeTextureId(child.Value)
		end
	end
	local warningKey = "Texture:" .. name
	if id == "" and not missingWarned[warningKey] then
		missingWarned[warningKey] = true
		warn("[WaterBullet Anime] Missing or invalid " .. name
			.. ". Add an attribute or StringValue at ReplicatedStorage/VFX/Jutsus/Water/WaterBulletAnime"
			.. " with the image ID (digits or rbxassetid://ID).")
	elseif id ~= "" then
		missingWarned[warningKey] = nil
	end
	return id
end

local function orient(position: Vector3, direction: Vector3): CFrame
	local up = if math.abs(direction:Dot(Vector3.yAxis)) > 0.98 then Vector3.xAxis else Vector3.yAxis
	return CFrame.lookAt(position, position + direction, up)
end

local function piece(parent: Instance?, name: string, size: Vector3, color: Color3, alpha: number, meshName: string?): BasePart
	local bank = assets()
	local candidate = bank and meshName and bank:FindFirstChild(meshName)
	local template: MeshPart? = nil
	if candidate and candidate:IsA("MeshPart") then
		template = candidate
	elseif candidate then
		template = candidate:FindFirstChildWhichIsA("MeshPart", true) :: MeshPart?
	end
	local p: BasePart
	if template then
		local clone = template:Clone()
		clone:ClearAllChildren()
		clone.TextureID = ""
		clone:SetAttribute("AuthoredMeshSize", template.MeshSize)
		p = clone
	else
		local fallback = Instance.new("Part")
		fallback.Shape = Enum.PartType.Ball
		p = fallback
		if meshName and not missingWarned[meshName] then
			missingWarned[meshName] = true
			warn("[WaterBullet Anime] Import missing MeshPart: WaterBulletAnime/" .. meshName)
		end
	end
	p.Name, p.Size, p.Color, p.Transparency = name, size, color, alpha
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Plastic
	p.Reflectance = 0
	p.PivotOffset = CFrame.identity
	p:SetAttribute("ProjectileIgnore", true)
	p.Parent = parent
	return p
end

local function attach(parent: Instance, position: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Position, a.Parent = position, parent
	return a
end

local function spray(parent: Instance, size: number, rate: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "AnimeFoam"
	e.Texture = texture("SplashTexture")
	-- Built-in sprite is only a temporary fallback until the authored PNG is uploaded.
	if e.Texture == "" then e.Texture = "rbxasset://textures/particles/smoke_main.dds" end
	e.Color = ColorSequence.new(FOAM, LIGHT_WATER)
	e.Rate = rate
	e.Enabled = rate > 0
	e.Lifetime = NumberRange.new(0.18, 0.32)
	e.Speed = NumberRange.new(3, 7)
	e.Drag = 3
	e.Acceleration = Vector3.new(0, -12, 0)
	e.EmissionDirection = Enum.NormalId.Back
	e.SpreadAngle = Vector2.new(18, 18)
	e.Rotation = NumberRange.new(-180, 180)
	e.RotSpeed = NumberRange.new(-70, 70)
	e.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(0.65, size * 0.7), NumberSequenceKeypoint.new(1, 0)})
	e.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(0.65, 0.18), NumberSequenceKeypoint.new(1, 1)})
	e.LightEmission, e.LightInfluence = 0, 0.25
	e.Parent = parent
	return e
end

function WaterBulletVFX.Charge(context: any)
	local head = context.Character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then return end
	local a = attach(head, Vector3.new(0, -head.Size.Y * 0.13, -head.Size.Z * 0.55))
	a.Name = "WaterBulletGather"
	local e = spray(a, 0.45, 8)
	e.Speed, e.Acceleration, e.LockedToPart = NumberRange.new(0, 0.3), Vector3.zero, true
	context.WaterBulletGather = a
	Debris:AddItem(a, 8)
end

function WaterBulletVFX.StopCharge(context: any)
	local a = context.WaterBulletGather
	context.WaterBulletGather = nil
	if a and a.Parent then
		for _, e in a:GetChildren() do
			if e:IsA("ParticleEmitter") then e.Enabled = false end
		end
		Debris:AddItem(a, 0.35)
	end
end

function WaterBulletVFX.Create(_context: any, position: Vector3, radius: number, direction: Vector3, _speed: number, _distance: number): BasePart
	local root = piece(nil, "WaterBullet_Anime", Vector3.one * 0.1, WATER, 1)
	root.CFrame = orient(position, direction)
	local base = Vector3.new(radius * 1.8, radius * 1.8, radius * 2.65)
	local body = piece(root, "WaterBody", base, WATER, 0, "WaterBody")
	local bodyTexture = texture("BodyTexture")
	if body:IsA("MeshPart") and bodyTexture ~= "" then
		body.TextureID, body.Color = bodyTexture, Color3.new(1, 1, 1)
	end
	local flows = {}
	local flowSizes = {}
	local authoredBodySize = body:GetAttribute("AuthoredMeshSize")
	local meshScale = if typeof(authoredBodySize) == "Vector3"
		then base / authoredBodySize else Vector3.one
	for i = 1, 2 do
		local p = piece(root, "Current" .. i, base, if i == 1 then LIGHT_WATER else FOAM, 0, "WaterFlow")
		local authoredFlowSize = p:GetAttribute("AuthoredMeshSize")
		if typeof(authoredFlowSize) == "Vector3" then
			p.Size = authoredFlowSize * meshScale
		end
		if not p:IsA("MeshPart") then p.Transparency = 1 end
		flows[i] = p
		flowSizes[i] = p.Size
	end
	local tail = piece(root, "WaterTail", Vector3.new(radius * 0.75, radius * 0.75, radius * 2), WATER, 0.22, "WaterBody")
	if tail:IsA("MeshPart") and bodyTexture ~= "" then
		tail.TextureID, tail.Color = bodyTexture, Color3.new(1, 1, 1)
	end
	body.CFrame, tail.CFrame = root.CFrame, root.CFrame * CFrame.new(0, 0, radius * 1.35)
	for i, p in flows do p.CFrame = root.CFrame * CFrame.Angles(0, 0, i * math.pi) end
	for side = -1, 1, 2 do
		local trail = Instance.new("Trail")
		trail.Attachment0 = attach(root, Vector3.new(side * radius * 0.55, 0.1, radius * 0.4))
		trail.Attachment1 = attach(root, Vector3.new(side * radius * 0.35, -0.1, radius * 0.65))
		trail.FaceCamera, trail.Lifetime, trail.MinLength = true, 0.12, 0.05
		trail.Color, trail.Transparency = ColorSequence.new(LIGHT_WATER), NumberSequence.new(0.25, 1)
		trail.WidthScale = NumberSequence.new(1, 0)
		trail.Parent = root
	end
	spray(attach(root, Vector3.new(0, 0, radius * 1.7)), radius * 0.38, 14)
	visualStates[root] = {body=body, tail=tail, flows=flows, flowSizes=flowSizes, base=base, radius=radius, started=os.clock(), nextUpdate=0}
	root.Parent = workspace
	root.Destroying:Connect(function() visualStates[root] = nil end)
	return root
end

function WaterBulletVFX.Update(root: BasePart, position: Vector3, direction: Vector3)
	local s = visualStates[root]
	if not s then return end
	local now = os.clock()
	if now < s.nextUpdate then return end
	s.nextUpdate = now + 1 / 30
	local age = now - s.started
	local cf = orient(position, direction)
	local swell = 1 + math.sin(age * 17) * 0.045
	root.CFrame = cf
	s.body.Size = s.base * Vector3.new(swell, 1 / swell, 1 + math.sin(age * 12) * 0.055)
	s.body.CFrame = cf * CFrame.Angles(0, 0, age * 1.6)
	for i, p in s.flows do
		p.Size = s.flowSizes[i] * Vector3.new(swell, 1 / swell, 1 + math.sin(age * 12) * 0.055)
		p.CFrame = cf * CFrame.Angles(0, 0, age * 6 + i * math.pi)
	end
	s.tail.CFrame = cf * CFrame.new(math.sin(age * 15) * 0.07, math.cos(age * 12) * 0.06, s.radius * 1.35) * CFrame.Angles(0, 0, -age * 2)
	s.tail.Size = Vector3.new(s.radius * 0.75, s.radius * 0.75, s.radius * (2 + math.sin(age * 15) * 0.15))
end

function WaterBulletVFX.Release(_context: any, root: BasePart)
	visualStates[root] = nil
	for _, item in root:GetDescendants() do
		if item:IsA("ParticleEmitter") or item:IsA("Trail") then item.Enabled = false
		elseif item:IsA("BasePart") then
			TweenService:Create(item, TweenInfo.new(0.07), {Transparency=1}):Play()
		end
	end
	Debris:AddItem(root, 0.36)
end

function WaterBulletVFX.Impact(_context: any, _visual: BasePart, position: Vector3, normal: Vector3, radius: number)
	local root = piece(nil, "WaterBullet_Splash", Vector3.one * 0.1, WATER, 1)
	root.CFrame = orient(position + normal * 0.12, normal)
	local splash = piece(root, "WaterCrown", Vector3.new(radius, radius, radius * 0.2), LIGHT_WATER, 0.1, "WaterSplash")
	splash.CFrame = root.CFrame
	local foam = piece(root, "FoamEdge", Vector3.new(radius * 1.05, radius * 1.05, radius * 0.22), FOAM, 0.24, "WaterSplash")
	foam.CFrame = root.CFrame * CFrame.Angles(0, 0, 0.24)
	root.Parent = workspace
	local expand = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(splash, expand, {Size=Vector3.new(radius * 3, radius * 3, radius * 1.2), Transparency=1}):Play()
	TweenService:Create(foam, expand, {Size=Vector3.new(radius * 3.35, radius * 3.35, radius * 1.3), Transparency=1}):Play()
	local emitter = spray(root, radius * 1.1, 0)
	emitter.EmissionDirection = Enum.NormalId.Front
	emitter.SpreadAngle = Vector2.new(65, 65)
	emitter.Speed = NumberRange.new(5, 10)
	task.delay(0.03, function() if emitter.Parent then emitter:Emit(6) end end)
	for i = 1, 7 do
		local angle = i * math.pi * 2 / 7
		local outward = root.CFrame.RightVector * math.cos(angle) + root.CFrame.UpVector * math.sin(angle)
		local p = piece(root, "Droplet", Vector3.new(0.16, 0.16, 0.36), LIGHT_WATER, 0.08)
		p.CFrame = orient(position + normal * 0.14, (outward + normal).Unit)
		local landing = position + normal * radius * 0.9 + outward * radius * 1.5 - Vector3.yAxis * 0.6
		TweenService:Create(p, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position=landing, Size=Vector3.one * 0.04, Transparency=1}):Play()
	end
	Debris:AddItem(root, 0.65)
end


local function isFiniteNumber(value: number): boolean
	return value == value
		and value ~= math.huge
		and value ~= -math.huge
end

local function sanitizeDirection(
	character: Model,
	payload: any
): (boolean, string, Vector3?)

	if typeof(payload) ~= "table" then
		return false, "InvalidPayload", nil
	end

	local rawDirection =
		payload.Direction

	if typeof(rawDirection) ~= "Vector3"
		or not isFiniteNumber(rawDirection.X)
		or not isFiniteNumber(rawDirection.Y)
		or not isFiniteNumber(rawDirection.Z)
		or rawDirection.Magnitude < 0.001 then

		return false, "InvalidDirection", nil
	end

	local root =
		character:FindFirstChild(
			"HumanoidRootPart"
		)

	if not root
		or not root:IsA("BasePart") then

		return false, "NoRoot", nil
	end

	local direction =
		rawDirection.Unit

	local horizontalDirection =
		Vector3.new(
			direction.X,
			0,
			direction.Z
		)

	local horizontalLook =
		Vector3.new(
			root.CFrame.LookVector.X,
			0,
			root.CFrame.LookVector.Z
		)

	if horizontalDirection.Magnitude > 0.001
		and horizontalLook.Magnitude > 0.001
		and horizontalLook.Unit:Dot(
			horizontalDirection.Unit
		) < -0.25 then

		return false, "AimBehindCharacter", nil
	end

	return true, "OK", direction
end

local function refreshReleaseAim(
	context: any,
	markerPayload: any?
)
	if typeof(markerPayload) ~= "table" then
		return
	end

	local ok, _reason, direction =
		sanitizeDirection(
			context.Character,
			markerPayload
		)

	if ok and direction then
		context.RequestData.Direction =
			direction
	end
end

local function getAliveHeadRoot(
	context: any
): (BasePart?, BasePart?)

	local character: Model =
		context.Character

	local humanoid =
		character:FindFirstChildOfClass(
			"Humanoid"
		)

	if not humanoid
		or humanoid.Health <= 0 then

		return nil, nil
	end

	local head =
		character:FindFirstChild("Head")

	local root =
		character:FindFirstChild(
			"HumanoidRootPart"
		)

	if not head
		or not head:IsA("BasePart")
		or not root
		or not root:IsA("BasePart") then

		return nil, nil
	end

	return head, root
end

local function resolveDamageableEntity(
	context: any,
	instance: Instance?
): any?

	if not instance
		or not instance:IsA("BasePart") then

		return nil
	end

	local entity =
		context.CombatEntityService
		.ResolveFromInstance(
			instance
		)

	if not entity
		or entity.Character
		== context.Character
		or not entity.CanReceiveDamage
		or not context.CombatEntityService
		.IsAlive(entity)
		or entity.Character:GetAttribute(
			"CombatImmune"
		) == true
			or entity.Character:GetAttribute(
				"IsMissionNPC"
			) == true then

		return nil
	end

	return entity
end

local function safeLookAt(
	position: Vector3,
	direction: Vector3
): CFrame

	local unit =
		if direction.Magnitude > 0.001
		then direction.Unit
		else Vector3.new(0, 0, -1)

	local up =
		if math.abs(
			unit:Dot(Vector3.yAxis)
		) > 0.98
		then Vector3.xAxis
		else Vector3.yAxis

	return CFrame.lookAt(
		position,
		position + unit,
		up
	)
end


local WaterBullet = {}

WaterBullet.Id = "WaterBullet"
WaterBullet.NatureId = "Water"
WaterBullet.TechniqueCategory = "ElementalNinjutsu"
WaterBullet.MinimumLevel = 1
WaterBullet.SortOrder = 110

WaterBullet.Config = {
	DisplayName = "Water Bullet",
	NatureId = "Water",
	TechniqueCategory = "ElementalNinjutsu",
	MinimumLevel = 1,
	SortOrder = 110,

	ChakraCost = 14,
	Cooldown = 4.5,
	CastTime = 1.0,
	Damage = 16,

	Projectile = {
		Speed = 95,
		MaxDistance = 80,
		Radius = 1.6,
	},
}

WaterBullet.AllowedCastMarkers = {
	ReleaseStart = true,
	ProjectileSpawn = true,
	RecoveryStart = true,
	CastEnd = true,
}

WaterBullet.MarkerCastTimeout = 8.0
WaterBullet.ProjectileFallbackDelay = 6.0
WaterBullet.MinProjectileDelay = 0.80

function WaterBullet.SanitizeRequest(
	character: Model,
	payload: any
): (boolean, string, any?)

	local ok, reason, direction =
		sanitizeDirection(
			character,
			payload
		)

	if not ok or not direction then
		return false, reason, nil
	end

	return true, "OK", {
		Direction = direction,
	}
end

local function executeProjectile(
	context: any
)
	local head, root =
		getAliveHeadRoot(context)

	if not head or not root then
		return
	end

	local projectileConfig =
		context.Config.Projectile or {}

	local speed =
		if typeof(projectileConfig.Speed) == "number"
		then math.max(10, projectileConfig.Speed)
		else 95

	local maxDistance =
		if typeof(projectileConfig.MaxDistance) == "number"
		then math.max(10, projectileConfig.MaxDistance)
		else 80

	local radius =
		if typeof(projectileConfig.Radius) == "number"
		then math.max(0.25, projectileConfig.Radius)
		else 1.6

	local direction =
		context.RequestData.Direction

	if typeof(direction) ~= "Vector3"
		or direction.Magnitude < 0.001 then

		direction =
			root.CFrame.LookVector
	end

	direction = direction.Unit

	local position =
		head.Position
		+ direction * 2.25

	local travelled = 0.0
	local visual =
		WaterBulletVFX.Create(
			context,
			position,
			radius,
			direction,
			speed,
			maxDistance
		)

	local ignored: {Instance} = {
		context.Character,
		visual,
	}

	local params =
		RaycastParams.new()

	params.FilterType =
		Enum.RaycastFilterType.Exclude

	params.IgnoreWater = false

	local alive = true
	local connection: RBXScriptConnection?

	local function finish(hitPosition: Vector3?, hitNormal: Vector3?)
		if not alive then
			return
		end

		alive = false

		if connection then
			connection:Disconnect()
			connection = nil
		end

		if hitPosition and hitNormal then
			WaterBulletVFX.Impact(context, visual, hitPosition, hitNormal, radius)
		end
		WaterBulletVFX.Release(context, visual)
	end

	connection =
		RunService.Heartbeat:Connect(
			function(dt)
				if not alive then
					return
				end

				if not context.Player.Parent
					or context.Player.Character
					~= context.Character
					or not context.Character.Parent then

					finish()
					return
				end

				local step =
				math.min(
					speed * dt,
					maxDistance - travelled
				)

				if step <= 0 then
					finish()
					return
				end

				local displacement =
				direction * step

				for _ = 1, 10 do
					params.FilterDescendantsInstances =
					ignored

					local result =
					workspace:Spherecast(
						position,
						radius,
						displacement,
						params
					)

					if not result then
						break
					end

					local entity =
					resolveDamageableEntity(
						context,
						result.Instance
					)

					if entity then
						context.DamageService.Apply({
							TargetCharacter =
							entity.Character,

							TargetHumanoid =
							entity.Humanoid,

							TargetPlayer =
							entity.Player,

							Attacker =
							context.Player,

							Damage =
							context.Config.Damage,

							SourceType =
							"Jutsu",

							SourceId =
							WaterBullet.Id,

							Armor =
							context.Config.Armor,
						})

						finish(result.Position, result.Normal)
						return
					end

					if result.Instance:GetAttribute(
						"ProjectileIgnore"
						) == true
						or (
							result.Instance:IsA("BasePart")
							and not result.Instance.CanCollide
						) then

						table.insert(
							ignored,
							result.Instance
						)
					else
						finish(result.Position, result.Normal)
						return
					end
				end

				position += displacement
				travelled += step

				if visual.Parent then
					WaterBulletVFX.Update(visual, position, direction)
				end

				if travelled >= maxDistance then
					finish()
				end
			end
		)

	Debris:AddItem(
		visual,
		maxDistance / speed + 1
	)
end

function WaterBullet.OnCastStarted(
	context: any
)
	WaterBulletVFX.Charge(context)
end

function WaterBullet.OnCastMarker(
	context: any,
	semanticMarker: string,
	_source: string,
	markerPayload: any?
)
	if semanticMarker == "ProjectileSpawn" then
		WaterBulletVFX.StopCharge(context)
		refreshReleaseAim(
			context,
			markerPayload
		)

		executeProjectile(
			context
		)
	end
end

function WaterBullet.OnCastEnded(
	context: any,
	_reason: string
)
	WaterBulletVFX.StopCharge(context)
end

function WaterBullet.Execute(
	context: any
)
	task.delay(
		context.Config.CastTime,
		function()
			WaterBulletVFX.StopCharge(context)
			executeProjectile(
				context
			)
		end
	)
end

return WaterBullet
