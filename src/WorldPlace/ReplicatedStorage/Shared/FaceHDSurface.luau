--!strict
-- Client-only renderer. Based on the Astra HEAD overlay solution:
-- independent Part outside character, matching Head SpecialMesh * 1.001, welded.
-- No decal pixels are cropped/repositioned. NEVER parent surface inside a Humanoid model.
local ContentProvider = game:GetService("ContentProvider")
local FaceHDSurface = {}
local surfaces = setmetatable({}, {__mode = "k"})
local FOLDER_NAME = "WAYLESS_FaceHD_ClientSurfaces"
local ORDER = {"cejas", "ojos", "nariz", "boca", "venas"}

local function normalizeHead(head: BasePart)
    if not head:IsA("Part") then return nil end
    local mesh = head:FindFirstChildOfClass("SpecialMesh")
    if not mesh then
        mesh = Instance.new("SpecialMesh")
        mesh.Name = "Mesh"
        mesh.Parent = head
    end
    mesh.MeshId = ""
    mesh.TextureId = ""
    mesh.MeshType = Enum.MeshType.Head
    mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
    mesh.Offset = Vector3.zero
    mesh.VertexColor = Vector3.one
    return mesh
end

local function folder(): Folder
    local old = workspace:FindFirstChild(FOLDER_NAME)
    if old and old:IsA("Folder") then return old end
    local f = Instance.new("Folder")
    f.Name = FOLDER_NAME
    f.Parent = workspace
    return f
end

function FaceHDSurface.Attach(character: Model)
    local existing = surfaces[character]
    if existing and existing.Alive then return existing end
    local head = character:FindFirstChild("Head")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not head or not head:IsA("Part") or not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R6 then return nil end
    local mesh = normalizeHead(head)
    if not mesh then return nil end

    local surface = Instance.new("Part")
    surface.Name = character.Name .. "_FaceHD_LOCAL"
    surface.Size = head.Size
    surface.CFrame = head.CFrame
    surface.Transparency = 1
    surface.Massless = true
    surface.CastShadow = false
    surface.CanCollide = false
    surface.CanTouch = false
    surface.CanQuery = false
    local copy = mesh:Clone()
    copy.Name = "FaceHDMesh"
    copy.Scale = mesh.Scale * 1.001
    copy.Parent = surface
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = head
    weld.Part1 = surface
    weld.Parent = surface
    surface.Parent = folder()

    local decals = {}
    for i, layer in ipairs(ORDER) do
        local decal = Instance.new("Decal")
        decal.Name = "WAYLESS_HD_" .. layer
        decal.Face = Enum.NormalId.Front
        decal.Transparency = 1
        pcall(function() decal.ZIndex = i * 10 end)
        decal.Parent = surface
        decals[layer] = decal
    end
    local self: any = {Alive = true, Character = character, Head = head, Part = surface,
        Decals = decals, Active = false, Connections = {}, OriginalDecals = {}, Applying = false, Version = 0}
    surfaces[character] = self
    local function updateOpacity()
        if not self.Alive then return end
        local alpha = math.clamp(math.max(head.Transparency, head.LocalTransparencyModifier), 0, 1)
        for _, d in pairs(decals) do
            local nextOpacity = (self.Active and d.Texture ~= "") and alpha or 1
            if d.Transparency ~= nextOpacity then d.Transparency = nextOpacity end
        end
    end
    local function hideOriginals()
        if not self.Alive or not self.Active or self.Applying then return end
        self.Applying = true
        for _, child in ipairs(head:GetChildren()) do
            if child:IsA("Decal") and child.Face == Enum.NormalId.Front then
                if self.OriginalDecals[child] == nil then
                    self.OriginalDecals[child] = child.Transparency
                    table.insert(self.Connections, child:GetPropertyChangedSignal("Transparency"):Connect(function()
                        if self.Alive and self.Active and not self.Applying and child.Parent and child.Transparency ~= 1 then
                            child.Transparency = 1
                        end
                    end))
                end
                if child.Transparency ~= 1 then child.Transparency = 1 end
            end
        end
        self.Applying = false
    end
    local function applyNow(images: {[string]: string})
        for _, layer in ipairs(ORDER) do
            local value = images[layer] or ""
            if decals[layer].Texture ~= value then decals[layer].Texture = value end
        end
        self.Active = true
        hideOriginals()
        updateOpacity()
    end
    self.Apply = function(images: {[string]: string})
        if not self.Alive then return end
        -- Requires ALL four pieces to prevent a half-rendered face.
        local snapshot = {}
        for _, layer in ipairs({"cejas", "ojos", "nariz", "boca"}) do
            if typeof(images[layer]) ~= "string" or images[layer] == "" then return end
        end
        for _, layer in ipairs(ORDER) do snapshot[layer] = images[layer] or "" end
        if self.Active then
            applyNow(snapshot)
            return
        end
        -- Preload before hiding the original decals; if Roblox refuses an
        -- image, keep the original neutral face visible as a safe fallback.
        self.Version += 1
        local revision = self.Version
        task.spawn(function()
            local urls = {}
            for _, layer in ipairs(ORDER) do
                local url = snapshot[layer]
                if url ~= "" then table.insert(urls, url) end
            end
            local failed = false
            local ok = pcall(function()
                ContentProvider:PreloadAsync(urls, function(_, status)
                    if status ~= Enum.AssetFetchStatus.Success then failed = true end
                end)
            end)
            if not self.Alive or revision ~= self.Version then return end
            if not ok or failed then
                warn("[WAYLESS FaceHD] Unable to preload some facial images; preserving previous appearance")
                return
            end
            applyNow(snapshot)
        end)
    end
    self.Stop = function()
        if not self.Alive then return end
        self.Alive = false
        self.Version += 1
        for _, conn in ipairs(self.Connections) do conn:Disconnect() end
        for decal, original in pairs(self.OriginalDecals) do
            if decal.Parent then decal.Transparency = original end
        end
        surface:Destroy()
        surfaces[character] = nil
    end
    table.insert(self.Connections, head.ChildAdded:Connect(function(c)
        if c:IsA("Decal") then task.defer(hideOriginals) end
    end))
    table.insert(self.Connections, head:GetPropertyChangedSignal("Transparency"):Connect(updateOpacity))
    table.insert(self.Connections, head:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(updateOpacity))
    table.insert(self.Connections, character.Destroying:Connect(self.Stop))
    table.insert(self.Connections, head.AncestryChanged:Connect(function()
        if not head:IsDescendantOf(workspace) then self.Stop() end
    end))
    return self
end

return FaceHDSurface
