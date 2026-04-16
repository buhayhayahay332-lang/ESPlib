pcall(function() setthreadidentity(8) end)
pcall(function() game:GetService("WebViewService"):Destroy() end)

local cloneref = cloneref or function(o) return o end

local Workspace  = cloneref(game:GetService("Workspace"))
local RunService = cloneref(game:GetService("RunService"))
local Players    = cloneref(game:GetService("Players"))
local CoreGui    = cloneref(game:GetService("CoreGui"))
local GuiService = cloneref(game:GetService("GuiService"))

local function getLocalPlayer()
    return Players.LocalPlayer or cloneref(Players.LocalPlayer)
end

local ESP = {
    Enabled     = false,
    MaxDistance = 1000,
    FontSize    = 11,
    FadeOut = {
        OnDistance = true,
        OnDeath    = true,
        OnLeave    = true,
    },
    Drawing = {
        Chams = {
            Enabled              = false,
            Thermal              = false,
            FillRGB              = Color3.fromRGB(243, 116, 166),
            Fill_Transparency    = 50,
            OutlineRGB           = Color3.fromRGB(243, 116, 166),
            Outline_Transparency = 50,
            VisibleCheck         = false,
        },
        Names = {
            Enabled = false,
            RGB     = Color3.fromRGB(255, 255, 255),
        },
        Distances = {
            Enabled = false,
            RGB     = Color3.fromRGB(255, 255, 255),
        },
        Weapons = {
            Enabled = false,
            RGB     = Color3.fromRGB(255, 255, 255),
        },
        Boxes = {
            Animate          = false,
            RotationSpeed    = 300,
            Gradient         = true,
            GradientRGB1     = Color3.fromRGB(243, 116, 116),
            GradientRGB2     = Color3.fromRGB(0, 0, 0),
            GradientFill     = true,
            GradientFillRGB1 = Color3.fromRGB(243, 116, 116),
            GradientFillRGB2 = Color3.fromRGB(0, 0, 0),
            Filled = {
                Enabled      = false,
                Transparency = 0.75,
                RGB          = Color3.fromRGB(0, 0, 0),
            },
            Full = {
                Enabled = false,
                RGB     = Color3.fromRGB(255, 255, 255),
            },
            Corner = {
                Enabled   = false,
                RGB       = Color3.fromRGB(255, 255, 255),
                Thickness = 1,
                Length    = 15,
            },
        },
        Skeleton = {
            Enabled   = false,
            RGB       = Color3.fromRGB(255, 255, 255),
            Thickness = 1,
        },
        TeamCheck = {
            Enabled = false,
        },
    },
}

local BONE_CONNECTIONS = {
    { "torso", "shoulder1" }, { "torso", "shoulder2" },
    { "torso", "hip1" },      { "torso", "hip2" },
    { "torso", "head" },
    { "shoulder1", "arm1" },  { "shoulder2", "arm2" },
    { "hip1", "leg1" },       { "hip2", "leg2" },
}
local BONE_COUNT = #BONE_CONNECTIONS

local ESPCounter         = 0
local ActiveESPs         = {}
local ActiveSkeletons    = {}
local TeamHighlightCache = {}
local MasterConnection   = nil
local ScreenGui          = nil

local _Camera          = nil
local _CamPos          = nil
local _ViewSize        = nil
local _Tick            = 0
local _GuiInsetY       = 0
local _lastCharScan    = 0
local _lastInsetUpdate = 0
local _MaxDistSq       = ESP.MaxDistance * ESP.MaxDistance

local V2            = Vector2.new
local V3            = Vector3.new
local UDim2_new     = UDim2.new
local math_max      = math.max
local math_min      = math.min
local math_floor    = math.floor
local math_clamp    = math.clamp
local math_cos      = math.cos
local math_atan     = math.atan
local math_sin      = math.sin
local math_pi       = math.pi
local string_format = string.format

local Functions = {}

function Functions:Create(Class, Properties)
    local inst = typeof(Class) == "string" and Instance.new(Class) or Class
    for k, v in pairs(Properties) do inst[k] = v end
    return inst
end

local function getModelID(model)
    if not model then return nil end
    local id = model:GetAttribute("ID")
    if type(id) == "number" then return math_floor(id) end
    if type(id) == "string" then return tonumber(id) end
    return nil
end

local function hasTeamHighlight(model)
    if not model then return false end
    local cached = TeamHighlightCache[model]
    if cached ~= nil then return cached end

    local modelId = getModelID(model)
    for _, child in pairs(Workspace:GetChildren()) do
        if child:IsA("Highlight") then
            local ad = child.Adornee
            if ad == model then
                TeamHighlightCache[model] = true
                return true
            end
            if modelId and ad and ad:IsA("Model") and getModelID(ad) == modelId then
                TeamHighlightCache[model] = true
                return true
            end
        end
    end
    TeamHighlightCache[model] = false
    return false
end

Workspace.ChildAdded:Connect(function(c)
    if c:IsA("Highlight") then table.clear(TeamHighlightCache) end
end)
Workspace.ChildRemoved:Connect(function(c)
    if c:IsA("Highlight") then table.clear(TeamHighlightCache) end
end)

local _playerNameCache = {}  

Players.PlayerAdded:Connect(function(p)
    _playerNameCache[p.UserId] = p.Name
end)
Players.PlayerRemoving:Connect(function(p)
    _playerNameCache[p.UserId] = nil
end)
for _, p in pairs(Players:GetPlayers()) do
    _playerNameCache[p.UserId] = p.Name
end

local function getPlayerNameFromModel(model)
    local id = getModelID(model)
    if id then
        local cached = _playerNameCache[id]
        if cached then return cached end
        local plr = Players:GetPlayerByUserId(id)
        if plr then
            _playerNameCache[id] = plr.Name
            return plr.Name
        end
    end
    local n = model.Name
    if n ~= "Viewmodel" and n ~= "LocalViewmodel" then
        return n
    end
    return "Unknown"
end

local Viewmodels = Workspace:FindFirstChild("Viewmodels")

local function isValidCharacterTarget(model)
    if not model or not model.Parent or not model:IsA("Model") then return false end
    if Viewmodels and model.Parent == Viewmodels then return false end
    local id = getModelID(model)
    if not id then return false end
    local lp = getLocalPlayer()
    if lp and id == lp.UserId then return false end
    local hum = model:FindFirstChildOfClass("Humanoid")
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp or not hrp:IsA("BasePart") then return false end
    return true
end

local function isValidViewmodel(model)
    if not model or not model.Parent then return false end
    if model.Name == "LocalViewmodel" then return false end
    if not Viewmodels or model.Parent ~= Viewmodels then return false end
    local torso = model:FindFirstChild("torso")
    if not torso or not torso:IsA("BasePart") then return false end
    return true
end

local function findWeaponInCharacter(character)
    if not character then return nil end
    for _, child in pairs(character:GetChildren()) do
        if child:IsA("Model") and child:GetAttribute("item_type") then
            return child
        end
    end
    return nil
end

local function findLinkedViewmodelByID(id)
    if not id or not Viewmodels then return nil end
    for _, vm in pairs(Viewmodels:GetChildren()) do
        if vm:IsA("Model") and getModelID(vm) == id then return vm end
    end
    return nil
end

local function getProjectedCharacterBounds(model, hrp, humanoid)
    if not model or not hrp or not humanoid then return nil end
    local center, onCenter = _Camera:WorldToViewportPoint(hrp.Position)
    if not onCenter or center.Z <= 0 then return nil end

    local baseHeight = (humanoid.RigType == Enum.HumanoidRigType.R15) and 5.8 or 5.0
    local charHeight = math_clamp(baseHeight + humanoid.HipHeight * 2, 4.5, 9)

    local top, onTop = _Camera:WorldToViewportPoint(hrp.Position + V3(0,  charHeight * 0.5, 0))
    local bot, onBot = _Camera:WorldToViewportPoint(hrp.Position + V3(0, -charHeight * 0.5, 0))
    if not (onTop or onBot) or top.Z <= 0 or bot.Z <= 0 then return nil end

    local y0 = math_min(top.Y, bot.Y)
    local y1 = math_max(top.Y, bot.Y)
    local h  = math_max(2, y1 - y0)
    local w  = h * 0.42
    local cx = center.X
    return cx - w * 0.5, y0, cx + w * 0.5, y1
end

local function createSkeletonESP(character)
    if not character or ActiveSkeletons[character] then return end
    if not isValidViewmodel(character) then return end

    local bones = {}
    local required = { "torso","head","shoulder1","shoulder2","arm1","arm2","hip1","hip2","leg1","leg2" }
    for _, name in ipairs(required) do
        local b = character:FindFirstChild(name)
        if not b or not b:IsA("BasePart") then return end
        bones[name] = b
    end

    local lines = {}
    local skRGB   = ESP.Drawing.Skeleton.RGB
    local skThick = ESP.Drawing.Skeleton.Thickness
    for i = 1, BONE_COUNT do
        local line = Drawing.new("Line")
        line.Visible      = false
        line.Color        = skRGB
        line.Thickness    = skThick
        line.Transparency = 1
        lines[i] = line
    end

    ActiveSkeletons[character] = { lines = lines, bones = bones }
end

local function removeSkeleton(character)
    local sd = ActiveSkeletons[character]
    if not sd then return end
    local lines = sd.lines
    for i = 1, #lines do
        local l = lines[i]
        l.Visible = false
        l:Remove()
    end
    ActiveSkeletons[character] = nil
end

function Functions:CleanAllSkeletons()
    for model in pairs(ActiveSkeletons) do
        removeSkeleton(model)
    end
end

local function ProcessSkeleton(character, skData)
    local lines = skData.lines

    local function hideLines()
        for i = 1, #lines do lines[i].Visible = false end
    end

    if not ESP.Enabled or not ESP.Drawing.Skeleton.Enabled then hideLines() return end
    if not character or not character.Parent then
        hideLines()
        for i = 1, #lines do lines[i]:Remove() end
        ActiveSkeletons[character] = nil
        return
    end
    if ESP.Drawing.TeamCheck.Enabled and hasTeamHighlight(character) then hideLines() return end

    local bones = skData.bones
    local torso  = bones["torso"]
    if not torso or torso.Transparency >= 1 then hideLines() return end

    local torsoPos = torso.Position
    local dx = torsoPos.X - _CamPos.X
    local dy = torsoPos.Y - _CamPos.Y
    local dz = torsoPos.Z - _CamPos.Z
    if dx*dx + dy*dy + dz*dz > _MaxDistSq then hideLines() return end

    local skColor = ESP.Drawing.Skeleton.RGB
    local skThick = ESP.Drawing.Skeleton.Thickness
    local cam     = _Camera

    for i = 1, BONE_COUNT do
        local conn = BONE_CONNECTIONS[i]
        local b1, b2 = bones[conn[1]], bones[conn[2]]
        local line   = lines[i]
        if b1 and b2 then
            local p1, on1 = cam:WorldToViewportPoint(b1.Position)
            local p2, on2 = cam:WorldToViewportPoint(b2.Position)
            if on1 and on2 then
                line.From      = V2(p1.X, p1.Y)
                line.To        = V2(p2.X, p2.Y)
                line.Color     = skColor
                line.Thickness = skThick
                line.Visible   = true
            else
                line.Visible = false
            end
        else
            line.Visible = false
        end
    end
end

local function ProcessESP(model, espData)
    local el = espData.elements

    local function Hide()
        el.Box.Visible    = false
        el.Name.Visible   = false
        el.Weapon.Visible = false
        el.Chams.Enabled  = false
        el.LTH.Visible = false  el.LTV.Visible = false
        el.RTH.Visible = false  el.RTV.Visible = false
        el.LBH.Visible = false  el.LBV.Visible = false
        el.RBH.Visible = false  el.RBV.Visible = false
    end

    if not ESP.Enabled then Hide() return end

    if not model or not model.Parent then
        Hide()
        task.defer(function()
            if espData.folder then espData.folder:Destroy() end
            ActiveESPs[model] = nil
        end)
        return
    end
    
    if not isValidCharacterTarget(model) then
        Hide()
        task.defer(function()
            if espData.folder then espData.folder:Destroy() end
            ActiveESPs[model] = nil
        end)
        return
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local hrp      = model:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not hrp then
        Hide()
        return
    end
    
    if ESP.Drawing.TeamCheck.Enabled and hasTeamHighlight(model) then Hide() return end

    local hrpPos = hrp.Position
    local dx = hrpPos.X - _CamPos.X
    local dy = hrpPos.Y - _CamPos.Y
    local dz = hrpPos.Z - _CamPos.Z
    local distSq = dx*dx + dy*dy + dz*dz

    local Pos, OnScreen = _Camera:WorldToViewportPoint(hrpPos)
    local Dist          = math_max(0.001, distSq ^ 0.5) / 3.5714285714

    if not OnScreen or Dist > ESP.MaxDistance then Hide() return end

    if ESP.FadeOut.OnDistance then
        local fade = math_max(0.1, 1 - Dist / ESP.MaxDistance)
        local inv  = 1 - fade
        el.Outline.Transparency       = inv
        el.Name.TextTransparency      = inv
        el.Weapon.TextTransparency    = inv
        el.LTH.BackgroundTransparency = inv  el.LTV.BackgroundTransparency = inv
        el.RTH.BackgroundTransparency = inv  el.RTV.BackgroundTransparency = inv
        el.LBH.BackgroundTransparency = inv  el.LBV.BackgroundTransparency = inv
        el.RBH.BackgroundTransparency = inv  el.RBV.BackgroundTransparency = inv
    end

    local x0, y0, x1, y1 = getProjectedCharacterBounds(model, hrp, humanoid)
    if not x0 then
        local scaleFactor = math_max(hrp.Size.Y, 2) * _ViewSize.Y / (Pos.Z * 2)
        local fw = 2.5  * scaleFactor
        local fh = 4.75 * scaleFactor
        x0 = Pos.X - fw * 0.5  x1 = Pos.X + fw * 0.5
        y0 = Pos.Y - fh * 0.5  y1 = Pos.Y + fh * 0.5
    end
    local padX = math_max(2, (x1 - x0) * 0.10)
    local padY = math_max(2, (y1 - y0) * 0.07)
    x0 = x0 - padX  x1 = x1 + padX
    y0 = y0 - padY  y1 = y1 + padY
    local w  = math_max(2, x1 - x0)
    local h  = math_max(2, y1 - y0)
    local yi = _GuiInsetY

    local cLen   = ESP.Drawing.Boxes.Corner.Length
    local cThick = ESP.Drawing.Boxes.Corner.Thickness
    local dynCL  = math_min(cLen, w * 0.2, h * 0.2)

    local chams = el.Chams
    chams.Adornee      = model
    chams.Enabled      = ESP.Drawing.Chams.Enabled
    chams.FillColor    = ESP.Drawing.Chams.FillRGB
    chams.OutlineColor = ESP.Drawing.Chams.OutlineRGB
    chams.DepthMode    = ESP.Drawing.Chams.VisibleCheck and "Occluded" or "AlwaysOnTop"
    
    if ESP.Drawing.Chams.Enabled then
        if ESP.Drawing.Chams.Thermal then
            local b = math_atan(math_sin(_Tick * 2)) * 2 / math_pi
            chams.FillTransparency    = (ESP.Drawing.Chams.Fill_Transparency / 100) * (1 - b * 0.1)
            chams.OutlineTransparency = (ESP.Drawing.Chams.Outline_Transparency / 100)
        else
            chams.FillTransparency    = ESP.Drawing.Chams.Fill_Transparency / 100
            chams.OutlineTransparency = ESP.Drawing.Chams.Outline_Transparency / 100
        end
    end

    local cv = ESP.Drawing.Boxes.Corner.Enabled
    local cc = ESP.Drawing.Boxes.Corner.RGB
    local y0yi = y0 - yi
    local y1yi = y1 - yi
    el.LTH.Visible = cv  el.LTH.Position = UDim2_new(0, x0,          0, y0yi)           el.LTH.Size = UDim2_new(0, dynCL,  0, cThick) el.LTH.BackgroundColor3 = cc
    el.LTV.Visible = cv  el.LTV.Position = UDim2_new(0, x0,          0, y0yi)           el.LTV.Size = UDim2_new(0, cThick, 0, dynCL)  el.LTV.BackgroundColor3 = cc
    el.RTH.Visible = cv  el.RTH.Position = UDim2_new(0, x1 - dynCL,  0, y0yi)           el.RTH.Size = UDim2_new(0, dynCL,  0, cThick) el.RTH.BackgroundColor3 = cc
    el.RTV.Visible = cv  el.RTV.Position = UDim2_new(0, x1 - cThick, 0, y0yi)           el.RTV.Size = UDim2_new(0, cThick, 0, dynCL)  el.RTV.BackgroundColor3 = cc
    el.LBH.Visible = cv  el.LBH.Position = UDim2_new(0, x0,          0, y1yi - cThick)  el.LBH.Size = UDim2_new(0, dynCL,  0, cThick) el.LBH.BackgroundColor3 = cc
    el.LBV.Visible = cv  el.LBV.Position = UDim2_new(0, x0,          0, y1yi - dynCL)   el.LBV.Size = UDim2_new(0, cThick, 0, dynCL)  el.LBV.BackgroundColor3 = cc
    el.RBH.Visible = cv  el.RBH.Position = UDim2_new(0, x1 - dynCL,  0, y1yi - cThick)  el.RBH.Size = UDim2_new(0, dynCL,  0, cThick) el.RBH.BackgroundColor3 = cc
    el.RBV.Visible = cv  el.RBV.Position = UDim2_new(0, x1 - cThick, 0, y1yi - dynCL)   el.RBV.Size = UDim2_new(0, cThick, 0, dynCL)  el.RBV.BackgroundColor3 = cc

    local full   = ESP.Drawing.Boxes.Full.Enabled
    local filled = ESP.Drawing.Boxes.Filled.Enabled
    el.Box.Position               = UDim2_new(0, x0, 0, y0 - yi)
    el.Box.Size                   = UDim2_new(0, w,  0, h)
    el.Box.Visible                = full or (cv and filled)
    el.Box.BackgroundTransparency = filled and ESP.Drawing.Boxes.Filled.Transparency or 1
    el.Outline.Enabled            = full and ESP.Drawing.Boxes.Gradient

    if ESP.Drawing.Boxes.Animate then
        local dt = _Tick - espData.lastTick
        espData.rotAngle = espData.rotAngle
            + dt * ESP.Drawing.Boxes.RotationSpeed
            * math_cos(math_pi / 4 * _Tick - math_pi / 2)
        el.Gradient1.Rotation = espData.rotAngle
        el.Gradient2.Rotation = espData.rotAngle
    else
        el.Gradient1.Rotation = -45
        el.Gradient2.Rotation = -45
    end
    espData.lastTick = _Tick

    el.Name.Visible = ESP.Drawing.Names.Enabled
    if ESP.Drawing.Names.Enabled then
        local nameText = getPlayerNameFromModel(model)
        if ESP.Drawing.Distances.Enabled then
            nameText = string_format("%s [%d]", nameText, math_floor(Dist))
        end
        el.Name.Text       = string_format('(<font color="rgb(255,255,255)">T</font>) %s', nameText)
        el.Name.TextColor3 = ESP.Drawing.Names.RGB
        el.Name.Position   = UDim2_new(0, Pos.X, 0, y0 - 9 - yi)
    end

    el.Weapon.Visible = ESP.Drawing.Weapons.Enabled
    if ESP.Drawing.Weapons.Enabled then
        local wm = findWeaponInCharacter(model)
        if not wm then
            local vm = findLinkedViewmodelByID(getModelID(model))
            if vm then wm = findWeaponInCharacter(vm) end
        end
        if wm then
            el.Weapon.Text       = wm.Name
            el.Weapon.TextColor3 = ESP.Drawing.Weapons.RGB
            el.Weapon.Position   = UDim2_new(0, Pos.X, 0, y1 + 9 - yi)
        else
            el.Weapon.Visible = false
        end
    end
end

local function StartMasterLoop()
    if MasterConnection then
        MasterConnection:Disconnect()
        MasterConnection = nil
    end

    MasterConnection = RunService.RenderStepped:Connect(function()
        _Camera   = Workspace.CurrentCamera
        _CamPos   = _Camera.CFrame.Position
        _ViewSize = _Camera.ViewportSize
        _Tick     = tick()
        _MaxDistSq = ESP.MaxDistance * ESP.MaxDistance

        if _Tick - _lastInsetUpdate > 2 then
            _lastInsetUpdate = _Tick
            local ok, inset = pcall(function() return GuiService:GetGuiInset() end)
            if ok and inset then
                _GuiInsetY = ScreenGui and ScreenGui.IgnoreGuiInset and 0 or inset.Y
            else
                _GuiInsetY = 0
            end
        end

        if _Tick - _lastCharScan > 1 then
            _lastCharScan = _Tick
            local lp = getLocalPlayer()
            for _, plr in pairs(Players:GetPlayers()) do
                if plr ~= lp and plr.Character then
                    task.defer(CreateESP, plr.Character)
                end
            end
            for _, model in pairs(Workspace:GetChildren()) do
                if model:IsA("Model") and isValidCharacterTarget(model) then
                    task.defer(CreateESP, model)
                end
            end
        end

        for model, espData in next, ActiveESPs do
            ProcessESP(model, espData)
        end
        for model, skData in next, ActiveSkeletons do
            ProcessSkeleton(model, skData)
        end
    end)
end

local guiHideName = "ESP_" .. tostring(math.random(100000000, 999999999))
local parentGui   = gethui and gethui() or CoreGui

local function cleanupOldGuis(container)
    if not container then return end
    for _, v in pairs(container:GetChildren()) do
        if v:IsA("ScreenGui") and v.Name:sub(1, 4) == "ESP_" then v:Destroy() end
    end
end

cleanupOldGuis(CoreGui)
if parentGui ~= CoreGui then cleanupOldGuis(parentGui) end

ScreenGui = Functions:Create("ScreenGui", {
    Parent         = parentGui,
    Name           = guiHideName,
    ResetOnSpawn   = false,
    IgnoreGuiInset = true,
    DisplayOrder   = 999999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

pcall(function()
    if syn and syn.protect_gui then syn.protect_gui(ScreenGui)
    elseif protect_gui then protect_gui(ScreenGui) end
end)

function CreateESP(CharacterModel)
    if not CharacterModel then return end
    if not isValidCharacterTarget(CharacterModel) then return end
    if ActiveESPs[CharacterModel] then return end

    ESPCounter = ESPCounter + 1
    local folder = Functions:Create("Folder", { Parent = ScreenGui, Name = "E_" .. ESPCounter })

    local cThick = ESP.Drawing.Boxes.Corner.Thickness
    local cLen   = ESP.Drawing.Boxes.Corner.Length
    local cc     = ESP.Drawing.Boxes.Corner.RGB

    local function mc(name, w, h)
        return Functions:Create("Frame", {
            Parent = folder, Name = name,
            BackgroundColor3 = cc,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            Position = UDim2_new(0, 0, 0, 0),
            Size = UDim2_new(0, w, 0, h),
        })
    end

    local Name = Functions:Create("TextLabel", {
        Parent = folder, Name = "N",
        Position = UDim2_new(0.5, 0, 0, -11),
        Size = UDim2_new(0, 100, 0, 20),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.Code,
        TextSize = ESP.FontSize,
        TextStrokeTransparency = 0,
        TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
        RichText = true,
    })

    local Weapon = Functions:Create("TextLabel", {
        Parent = folder, Name = "W",
        Position = UDim2_new(0.5, 0, 0, 0),
        Size = UDim2_new(0, 100, 0, 20),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Font = Enum.Font.Code,
        TextSize = ESP.FontSize,
        TextStrokeTransparency = 0,
        TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
        RichText = true,
    })

    local Box = Functions:Create("Frame", {
        Parent = folder, Name = "B",
        BackgroundColor3 = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.75,
        BorderSizePixel = 0,
    })

    local Gradient1 = Functions:Create("UIGradient", {
        Parent  = Box,
        Enabled = ESP.Drawing.Boxes.GradientFill,
        Color   = ColorSequence.new({
            ColorSequenceKeypoint.new(0, ESP.Drawing.Boxes.GradientFillRGB1),
            ColorSequenceKeypoint.new(1, ESP.Drawing.Boxes.GradientFillRGB2),
        }),
    })

    local Outline = Functions:Create("UIStroke", {
        Parent       = Box,
        Enabled      = ESP.Drawing.Boxes.Gradient,
        Transparency = 0,
        Color        = Color3.fromRGB(255, 255, 255),
        LineJoinMode = Enum.LineJoinMode.Miter,
    })

    local Gradient2 = Functions:Create("UIGradient", {
        Parent  = Outline,
        Enabled = ESP.Drawing.Boxes.Gradient,
        Color   = ColorSequence.new({
            ColorSequenceKeypoint.new(0, ESP.Drawing.Boxes.GradientRGB1),
            ColorSequenceKeypoint.new(1, ESP.Drawing.Boxes.GradientRGB2),
        }),
    })

    local Chams = Functions:Create("Highlight", {
        Parent              = folder, Name = "C",
        FillTransparency    = 1,
        OutlineTransparency = 0,
        OutlineColor        = Color3.fromRGB(119, 120, 255),
        DepthMode           = "AlwaysOnTop",
    })

    ActiveESPs[CharacterModel] = {
        folder   = folder,
        rotAngle = -45,
        lastTick = tick(),
        elements = {
            Name      = Name,
            Weapon    = Weapon,
            Box       = Box,
            Gradient1 = Gradient1,
            Gradient2 = Gradient2,
            Outline   = Outline,
            Chams     = Chams,
            LTH = mc("LTH", cLen,   cThick),
            LTV = mc("LTV", cThick, cLen),
            RTH = mc("RTH", cLen,   cThick),
            RTV = mc("RTV", cThick, cLen),
            LBH = mc("LBH", cLen,   cThick),
            LBV = mc("LBV", cThick, cLen),
            RBH = mc("RBH", cLen,   cThick),
            RBV = mc("RBV", cThick, cLen),
        },
    }
end

function Functions:CleanAllESPs()
    for model, espData in pairs(ActiveESPs) do
        if espData.folder then espData.folder:Destroy() end
        ActiveESPs[model] = nil
    end
    self:CleanAllSkeletons()
end

ESP.RefreshESPs = function()
    Functions:CleanAllESPs()
    local lp = getLocalPlayer()
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= lp and plr.Character then
            task.defer(CreateESP, plr.Character)
        end
    end
    for _, model in pairs(Workspace:GetChildren()) do
        if model:IsA("Model") and isValidCharacterTarget(model) then
            task.defer(CreateESP, model)
        end
    end
end

ESP.CleanAllESPs = function() Functions:CleanAllESPs() end

local function MonitorViewmodels()
    if not Viewmodels then return end

    for _, v in pairs(Viewmodels:GetChildren()) do
        if v:IsA("Model") and ESP.Drawing.Skeleton.Enabled then
            task.defer(createSkeletonESP, v)
        end
    end

    Viewmodels.ChildAdded:Connect(function(v)
        if v:IsA("Model") and ESP.Drawing.Skeleton.Enabled then
            task.defer(createSkeletonESP, v)
        end
    end)

    Viewmodels.ChildRemoved:Connect(function(v)
        removeSkeleton(v)
        TeamHighlightCache[v] = nil
    end)
end

ESP.ToggleSkeleton = function(enabled)
    ESP.Drawing.Skeleton.Enabled = enabled
    if not enabled then
        Functions:CleanAllSkeletons()
    else
        if Viewmodels then
            for _, model in pairs(Viewmodels:GetChildren()) do
                if model:IsA("Model") and isValidViewmodel(model) then
                    createSkeletonESP(model)
                end
            end
        end
    end
end

ESP.SetSkeletonColor = function(color)
    if typeof(color) ~= "Color3" then return end
    ESP.Drawing.Skeleton.RGB = color
    for _, sd in pairs(ActiveSkeletons) do
        if sd and sd.lines then
            for _, line in ipairs(sd.lines) do line.Color = color end
        end
    end
end

ESP.SetSkeletonThickness = function(thickness)
    if type(thickness) ~= "number" or thickness <= 0 then return end
    ESP.Drawing.Skeleton.Thickness = thickness
    for _, sd in pairs(ActiveSkeletons) do
        if sd and sd.lines then
            for _, line in ipairs(sd.lines) do line.Thickness = thickness end
        end
    end
end

ESP.SetCornerColor     = function(c) if typeof(c) == "Color3" then ESP.Drawing.Boxes.Corner.RGB = c end end
ESP.SetCornerThickness = function(t) if type(t) == "number" and t > 0 then ESP.Drawing.Boxes.Corner.Thickness = t end end
ESP.SetCornerLength    = function(l) if type(l) == "number" and l > 0 then ESP.Drawing.Boxes.Corner.Length = l end end

MonitorViewmodels()
StartMasterLoop()

return ESP
