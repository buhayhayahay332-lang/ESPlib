 pcall(function() setthreadidentity(8) end)
pcall(function() game:GetService("WebViewService"):Destroy() end)

local cloneref = cloneref or function(o) return o end

local Workspace  = cloneref(game:GetService("Workspace"))
local RunService = cloneref(game:GetService("RunService"))
local Players    = cloneref(game:GetService("Players"))
local CoreGui    = cloneref(game:GetService("CoreGui"))
local GuiService = cloneref(game:GetService("GuiService"))

local LocalPlayer = cloneref(Players.LocalPlayer)


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
            Animate       = false,
            RotationSpeed = 300,
            Gradient      = true,
            GradientRGB1  = Color3.fromRGB(243, 116, 116),
            GradientRGB2  = Color3.fromRGB(0, 0, 0),
            GradientFill  = true,
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


local ESPCounter      = 0
local ActiveESPs      = {}  
local ActiveSkeletons = {}  
local TeamHighlightCache = {} 
local MasterConnection = nil

local _Camera   = nil
local _CamPos   = nil
local _ViewSize = nil
local _Tick     = nil
local _GuiInsetY = 0
local ScreenGui = nil


local Functions = {}

function Functions:Create(Class, Properties)
    local inst = typeof(Class) == "string" and Instance.new(Class) or Class
    for k, v in pairs(Properties) do inst[k] = v end
    return inst
end

local function hasTeamHighlight(model)
    if not model then
        return false
    end
    if TeamHighlightCache[model] ~= nil then
        return TeamHighlightCache[model]
    end
    for _, child in pairs(Workspace:GetChildren()) do
        if child:IsA("Highlight") and child.Adornee == model then
            TeamHighlightCache[model] = true
            return true
        end
    end
    TeamHighlightCache[model] = false
    return false
end

Workspace.ChildAdded:Connect(function(child)
    if child:IsA("Highlight") then
        table.clear(TeamHighlightCache)
    end
end)
Workspace.ChildRemoved:Connect(function(child)
    if child:IsA("Highlight") then
        table.clear(TeamHighlightCache)
    end
end)

local function isValidPlayer(model)
    if not model or not model.Parent then return false end
    if model.Name == "LocalViewmodel" then return false end
    local viewmodels = Workspace:FindFirstChild("Viewmodels")
    if not viewmodels or model.Parent ~= viewmodels then return false end
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

local function getProjectedModelBounds(model)
    if not model then return nil end

    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local any = false

    local widthParts = {
        model:FindFirstChild("head"),
        model:FindFirstChild("torso"),
    }
    local heightParts = {
        model:FindFirstChild("head"),
        model:FindFirstChild("torso"),
        model:FindFirstChild("hip1"),
        model:FindFirstChild("hip2"),
        model:FindFirstChild("leg1"),
        model:FindFirstChild("leg2"),
    }

    local widthSet = {}
    for _, p in ipairs(widthParts) do
        if p then widthSet[p] = true end
    end

    for _, d in ipairs(heightParts) do
        if d and d:IsA("BasePart") and d.Transparency < 1 then
            local half = d.Size * 0.5
            local corners = {
                d.CFrame * Vector3.new(-half.X, -half.Y, -half.Z),
                d.CFrame * Vector3.new(-half.X, -half.Y,  half.Z),
                d.CFrame * Vector3.new(-half.X,  half.Y, -half.Z),
                d.CFrame * Vector3.new(-half.X,  half.Y,  half.Z),
                d.CFrame * Vector3.new( half.X, -half.Y, -half.Z),
                d.CFrame * Vector3.new( half.X, -half.Y,  half.Z),
                d.CFrame * Vector3.new( half.X,  half.Y, -half.Z),
                d.CFrame * Vector3.new( half.X,  half.Y,  half.Z),
            }

            for _, worldPos in ipairs(corners) do
                local p, on = _Camera:WorldToViewportPoint(worldPos)
                if on and p.Z > 0 then
                    any = true
                    if p.Y < minY then minY = p.Y end
                    if p.Y > maxY then maxY = p.Y end
                    if widthSet[d] then
                        if p.X < minX then minX = p.X end
                        if p.X > maxX then maxX = p.X end
                    end
                end
            end
        end
    end

    if minX == math.huge or maxX == -math.huge then
        local torso = model:FindFirstChild("torso")
        if torso and torso:IsA("BasePart") then
            local p, on = _Camera:WorldToViewportPoint(torso.Position)
            if on and p.Z > 0 then
                minX = p.X - 8
                maxX = p.X + 8
            end
        end
    end

    if not any then return nil end
    return minX, minY, maxX, maxY
end


local function createSkeletonESP(character)
    if not character or ActiveSkeletons[character] then return end
    if not isValidPlayer(character) then return end

    local bones = {}
    local required = { "torso","head","shoulder1","shoulder2",
                       "arm1","arm2","hip1","hip2","leg1","leg2" }
    for _, name in ipairs(required) do
        local b = character:FindFirstChild(name)
        if not b or not b:IsA("BasePart") then return end
        bones[name] = b
    end

    local lines = {}
    for _ in ipairs(BONE_CONNECTIONS) do
        local line = Drawing.new("Line")
        line.Visible      = false
        line.Color        = ESP.Drawing.Skeleton.RGB
        line.Thickness    = ESP.Drawing.Skeleton.Thickness
        line.Transparency = 1
        table.insert(lines, line)
    end

    ActiveSkeletons[character] = { lines = lines, bones = bones }
end

local function removeSkeleton(character)
    local sd = ActiveSkeletons[character]
    if not sd then return end
    for _, line in ipairs(sd.lines) do
        line.Visible = false
        line:Remove()
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
        for _, l in ipairs(lines) do l.Visible = false end
    end

    if not ESP.Enabled or not ESP.Drawing.Skeleton.Enabled then
        hideLines() return
    end
    if not character or not character.Parent then
        hideLines()
        for _, l in ipairs(lines) do l:Remove() end
        ActiveSkeletons[character] = nil
        return
    end
    if ESP.Drawing.TeamCheck.Enabled and hasTeamHighlight(character) then
        hideLines() return
    end

    local torso = skData.bones["torso"]
    if not torso or torso.Transparency >= 1 then hideLines() return end

    local dist = (_CamPos - torso.Position).Magnitude
    if dist > ESP.MaxDistance then hideLines() return end

    local skColor = ESP.Drawing.Skeleton.RGB
    local skThick = ESP.Drawing.Skeleton.Thickness

    for i, conn in ipairs(BONE_CONNECTIONS) do
        local b1, b2 = skData.bones[conn[1]], skData.bones[conn[2]]
        local line   = lines[i]
        if b1 and b2 and line then
            local p1, on1 = _Camera:WorldToViewportPoint(b1.Position)
            local p2, on2 = _Camera:WorldToViewportPoint(b2.Position)
            if on1 and on2 then
                line.From      = Vector2.new(p1.X, p1.Y)
                line.To        = Vector2.new(p2.X, p2.Y)
                line.Color     = skColor
                line.Thickness = skThick
                line.Visible   = true
            else
                line.Visible = false
            end
        elseif line then
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

    if not model or not model.Parent or not isValidPlayer(model) then
        task.defer(function()
            if espData.folder then espData.folder:Destroy() end
            ActiveESPs[model] = nil
            removeSkeleton(model)
        end)
        return
    end

    local torso = model:FindFirstChild("torso")
    if not torso or torso.Transparency >= 1 then Hide() return end
    if ESP.Drawing.TeamCheck.Enabled and hasTeamHighlight(model) then Hide() return end

    local Pos, OnScreen = _Camera:WorldToViewportPoint(torso.Position)
    local Dist = (_CamPos - torso.Position).Magnitude / 3.5714285714

    if not OnScreen or Dist > ESP.MaxDistance then
        Hide()
        removeSkeleton(model)
        return
    end

    if ESP.FadeOut.OnDistance then
        local fade = math.max(0.1, 1 - (Dist / ESP.MaxDistance))
        local inv  = 1 - fade
        el.Outline.Transparency       = inv
        el.Name.TextTransparency      = inv
        el.Weapon.TextTransparency    = inv
        el.LTH.BackgroundTransparency = inv  el.LTV.BackgroundTransparency = inv
        el.RTH.BackgroundTransparency = inv  el.RTV.BackgroundTransparency = inv
        el.LBH.BackgroundTransparency = inv  el.LBV.BackgroundTransparency = inv
        el.RBH.BackgroundTransparency = inv  el.RBV.BackgroundTransparency = inv
    end

    local x0, y0, x1, y1 = getProjectedModelBounds(model)
    if not x0 then
        local scaleFactor = (torso.Size.Y * _ViewSize.Y) / (Pos.Z * 2)
        local fw = 2.5  * scaleFactor
        local fh = 4.75 * scaleFactor
        x0, y0 = Pos.X - fw * 0.5, Pos.Y - fh * 0.5
        x1, y1 = Pos.X + fw * 0.5, Pos.Y + fh * 0.5
    end
    local w = math.max(2, x1 - x0)
    local h = math.max(2, y1 - y0)

    local padX = math.max(2, w * 0.10)
    local padY = math.max(2, h * 0.07)
    x0 = x0 - padX
    x1 = x1 + padX
    y0 = y0 - padY
    y1 = y1 + padY
    w = math.max(2, x1 - x0)
    h = math.max(2, y1 - y0)

    local cLen  = ESP.Drawing.Boxes.Corner.Length
    local cThick = ESP.Drawing.Boxes.Corner.Thickness
    local dynCL = math.min(cLen, w * 0.2, h * 0.2)
    local yInset = _GuiInsetY or 0

    local chams = el.Chams
    chams.Adornee      = model
    chams.Enabled      = ESP.Drawing.Chams.Enabled
    chams.FillColor    = ESP.Drawing.Chams.FillRGB
    chams.OutlineColor = ESP.Drawing.Chams.OutlineRGB
    chams.DepthMode    = ESP.Drawing.Chams.VisibleCheck and "Occluded" or "AlwaysOnTop"
    if ESP.Drawing.Chams.Thermal then
        local b = math.atan(math.sin(_Tick * 2)) * 2 / math.pi
        chams.FillTransparency    = (ESP.Drawing.Chams.Fill_Transparency    / 100) * (1 - b * 0.1)
        chams.OutlineTransparency = (ESP.Drawing.Chams.Outline_Transparency / 100)
    end

    local cv = ESP.Drawing.Boxes.Corner.Enabled
    local cc = ESP.Drawing.Boxes.Corner.RGB
    el.LTH.Visible = cv  el.LTH.Position = UDim2.new(0, x0,               0, y0 - yInset)                el.LTH.Size = UDim2.new(0, dynCL,  0, cThick) el.LTH.BackgroundColor3 = cc
    el.LTV.Visible = cv  el.LTV.Position = UDim2.new(0, x0,               0, y0 - yInset)                el.LTV.Size = UDim2.new(0, cThick, 0, dynCL)  el.LTV.BackgroundColor3 = cc
    el.RTH.Visible = cv  el.RTH.Position = UDim2.new(0, x1 - dynCL,      0, y0 - yInset)                el.RTH.Size = UDim2.new(0, dynCL,  0, cThick) el.RTH.BackgroundColor3 = cc
    el.RTV.Visible = cv  el.RTV.Position = UDim2.new(0, x1 - cThick,     0, y0 - yInset)                el.RTV.Size = UDim2.new(0, cThick, 0, dynCL)  el.RTV.BackgroundColor3 = cc
    el.LBH.Visible = cv  el.LBH.Position = UDim2.new(0, x0,               0, y1 - cThick - yInset)       el.LBH.Size = UDim2.new(0, dynCL,  0, cThick) el.LBH.BackgroundColor3 = cc
    el.LBV.Visible = cv  el.LBV.Position = UDim2.new(0, x0,               0, y1 - dynCL - yInset)        el.LBV.Size = UDim2.new(0, cThick, 0, dynCL)  el.LBV.BackgroundColor3 = cc
    el.RBH.Visible = cv  el.RBH.Position = UDim2.new(0, x1 - dynCL,      0, y1 - cThick - yInset)       el.RBH.Size = UDim2.new(0, dynCL,  0, cThick) el.RBH.BackgroundColor3 = cc
    el.RBV.Visible = cv  el.RBV.Position = UDim2.new(0, x1 - cThick,     0, y1 - dynCL - yInset)        el.RBV.Size = UDim2.new(0, cThick, 0, dynCL)  el.RBV.BackgroundColor3 = cc

    local full   = ESP.Drawing.Boxes.Full.Enabled
    local filled = ESP.Drawing.Boxes.Filled.Enabled
    el.Box.Position = UDim2.new(0, x0, 0, y0 - yInset)
    el.Box.Size     = UDim2.new(0, w,  0, h)
    el.Box.Visible  = full or (cv and filled)
    el.Box.BackgroundTransparency = filled and ESP.Drawing.Boxes.Filled.Transparency or 1
    el.Outline.Enabled = full and ESP.Drawing.Boxes.Gradient

    if ESP.Drawing.Boxes.Animate then
        local dt = _Tick - espData.lastTick
        espData.rotAngle = espData.rotAngle
            + dt * ESP.Drawing.Boxes.RotationSpeed
            * math.cos(math.pi / 4 * _Tick - math.pi / 2)
        el.Gradient1.Rotation = espData.rotAngle
        el.Gradient2.Rotation = espData.rotAngle
    else
        el.Gradient1.Rotation = -45
        el.Gradient2.Rotation = -45
    end
    espData.lastTick = _Tick

    el.Name.Visible = ESP.Drawing.Names.Enabled
    if ESP.Drawing.Names.Enabled then
        local nameText = model.Name
        if ESP.Drawing.Distances.Enabled then
            nameText = string.format("%s [%d]", nameText, math.floor(Dist))
        end
        el.Name.Text       = string.format('(<font color="rgb(255,255,255)">T</font>) %s', nameText)
        el.Name.TextColor3 = ESP.Drawing.Names.RGB
        el.Name.Position   = UDim2.new(0, Pos.X, 0, y0 - 9 - yInset)
    end

    el.Weapon.Visible = ESP.Drawing.Weapons.Enabled
    if ESP.Drawing.Weapons.Enabled then
        local wm = findWeaponInCharacter(model)
        if wm then
            el.Weapon.Text       = wm.Name
            el.Weapon.TextColor3 = ESP.Drawing.Weapons.RGB
            el.Weapon.Position   = UDim2.new(0, Pos.X, 0, y1 + 9 - yInset)
        else
            el.Weapon.Visible = false
        end
    end

    if ESP.Drawing.Skeleton.Enabled and not ActiveSkeletons[model] then
        createSkeletonESP(model)
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
        local okInset, inset = pcall(function()
            return GuiService:GetGuiInset()
        end)
        if okInset and inset then
            if ScreenGui and ScreenGui.IgnoreGuiInset then
                _GuiInsetY = 0
            else
                _GuiInsetY = inset.Y
            end
        else
            _GuiInsetY = 0
        end

        for model, espData in pairs(ActiveESPs) do
            ProcessESP(model, espData)
        end
        for model, skData in pairs(ActiveSkeletons) do
            ProcessSkeleton(model, skData)
        end
    end)
end


local guiHideName = "ESP_" .. tostring(math.random(100000000, 999999999))
local parentGui   = gethui and gethui() 
if not parentGui and CoreGui then
    parentGui = CoreGui
end

local function cleanupESPGuids(container)
    if not container then return end
    for _, v in pairs(container:GetChildren()) do
        if v:IsA("ScreenGui") and v.Name:sub(1, 4) == "ESP_" then
            v:Destroy()
        end
    end
end

cleanupESPGuids(CoreGui)
if parentGui ~= gethui then
    cleanupESPGuids(parentGui)
end

ScreenGui = Functions:Create("ScreenGui", {
    Parent        = parentGui,
    Name          = guiHideName,
    ResetOnSpawn  = false,
    IgnoreGuiInset = true,
    DisplayOrder   = 999999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

pcall(function()
    if syn and syn.protect_gui then
        syn.protect_gui(ScreenGui)
    elseif protect_gui then
        protect_gui(ScreenGui)
    end
end)


local function CreateESP(CharacterModel)
    if not CharacterModel then return end
    if not isValidPlayer(CharacterModel) then return end
    if ActiveESPs[CharacterModel] then return end

    ESPCounter = ESPCounter + 1
    local folder = Functions:Create("Folder", {
        Parent = ScreenGui,
        Name   = "E_" .. ESPCounter,
    })

    local Name = Functions:Create("TextLabel", {
        Parent               = folder,  Name = "N",
        Position             = UDim2.new(0.5, 0, 0, -11),
        Size                 = UDim2.new(0, 100, 0, 20),
        AnchorPoint          = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        TextColor3           = Color3.fromRGB(255, 255, 255),
        Font                 = Enum.Font.Code,
        TextSize             = ESP.FontSize,
        TextStrokeTransparency = 0,
        TextStrokeColor3     = Color3.fromRGB(0, 0, 0),
        RichText             = true,
    })

    local Weapon = Functions:Create("TextLabel", {
        Parent               = folder,  Name = "W",
        Position             = UDim2.new(0.5, 0, 0, 0),
        Size                 = UDim2.new(0, 100, 0, 20),
        AnchorPoint          = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        TextColor3           = Color3.fromRGB(255, 255, 255),
        Font                 = Enum.Font.Code,
        TextSize             = ESP.FontSize,
        TextStrokeTransparency = 0,
        TextStrokeColor3     = Color3.fromRGB(0, 0, 0),
        RichText             = true,
    })

    local Box = Functions:Create("Frame", {
        Parent               = folder,  Name = "B",
        BackgroundColor3     = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.75,
        BorderSizePixel      = 0,
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
        Parent             = folder,  Name = "C",
        FillTransparency   = 1,
        OutlineTransparency = 0,
        OutlineColor       = Color3.fromRGB(119, 120, 255),
        DepthMode          = "AlwaysOnTop",
    })

    local cThick = ESP.Drawing.Boxes.Corner.Thickness
    local cLen   = ESP.Drawing.Boxes.Corner.Length
    local cc     = ESP.Drawing.Boxes.Corner.RGB

    local function mc(name, w, h)
        return Functions:Create("Frame", {
            Parent               = folder,  Name = name,
            BackgroundColor3     = cc,
            BackgroundTransparency = 0,
            BorderSizePixel      = 0,
            Position             = UDim2.new(0, 0, 0, 0),
            Size                 = UDim2.new(0, w, 0, h),
        })
    end

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
    local viewmodels = Workspace:FindFirstChild("Viewmodels")
    if not viewmodels then return end
    for _, model in pairs(viewmodels:GetChildren()) do
        if model:IsA("Model") then
            task.defer(CreateESP, model)
        end
    end
end

ESP.CleanAllESPs = function() Functions:CleanAllESPs() end


local function MonitorViewmodels()
    local viewmodels = Workspace:FindFirstChild("Viewmodels")
    if not viewmodels then return end

    for _, v in pairs(viewmodels:GetChildren()) do
        if v:IsA("Model") then task.defer(CreateESP, v) end
    end

    viewmodels.ChildAdded:Connect(function(v)
        if v:IsA("Model") then
            task.defer(CreateESP, v)
            if ESP.Drawing.Skeleton.Enabled then
                task.defer(createSkeletonESP, v)
            end
        end
    end)

    viewmodels.ChildRemoved:Connect(function(v)
        local espData = ActiveESPs[v]
        if espData then
            if espData.folder then espData.folder:Destroy() end
            ActiveESPs[v] = nil
        end
        removeSkeleton(v)
        TeamHighlightCache[v] = nil
    end)
end


ESP.ToggleSkeleton = function(enabled)
    ESP.Drawing.Skeleton.Enabled = enabled
    if not enabled then
        Functions:CleanAllSkeletons()
    else
        local viewmodels = Workspace:FindFirstChild("Viewmodels")
        if viewmodels then
            for _, model in pairs(viewmodels:GetChildren()) do
                if model:IsA("Model") and isValidPlayer(model) then
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
ESP.SetCornerLength    = function(l) if type(l) == "number" and l > 0 then ESP.Drawing.Boxes.Corner.Length    = l end end


MonitorViewmodels()
StartMasterLoop()

return ESP
