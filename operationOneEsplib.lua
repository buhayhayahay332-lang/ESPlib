pcall(function() setthreadidentity(8) end)
pcall(function() game:GetService("WebViewService"):Destroy() end)

local cloneref = cloneref or function(o) return o end

local Workspace  = cloneref(game:GetService("Workspace"))
local RunService = cloneref(game:GetService("RunService"))
local Players    = cloneref(game:GetService("Players"))
local CoreGui    = cloneref(game:GetService("CoreGui"))
local GuiService = cloneref(game:GetService("GuiService"))

local ESP = {
    Enabled     = false,
    MaxDistance = 1000,
    FontSize    = 11,
    FadeOut = { OnDistance = true, OnDeath = true, OnLeave = true },
    Drawing = {
        Chams = {
            Enabled = false, Thermal = false,
            FillRGB = Color3.fromRGB(243, 116, 166),
            Fill_Transparency = 50,
            OutlineRGB = Color3.fromRGB(243, 116, 166),
            Outline_Transparency = 50,
            VisibleCheck = false,
        },
        Names = { Enabled = false, RGB = Color3.fromRGB(255, 255, 255) },
        Distances = { Enabled = false, RGB = Color3.fromRGB(255, 255, 255) },
        Weapons = { Enabled = false, RGB = Color3.fromRGB(255, 255, 255) },
        Boxes = {
            Animate = false, RotationSpeed = 300,
            Gradient = true,
            GradientRGB1 = Color3.fromRGB(243, 116, 116),
            GradientRGB2 = Color3.fromRGB(0, 0, 0),
            GradientFill = true,
            GradientFillRGB1 = Color3.fromRGB(243, 116, 116),
            GradientFillRGB2 = Color3.fromRGB(0, 0, 0),
            Filled = { Enabled = false, Transparency = 0.75, RGB = Color3.fromRGB(0, 0, 0) },
            Full = { Enabled = false, RGB = Color3.fromRGB(255, 255, 255) },
            Corner = { Enabled = false, RGB = Color3.fromRGB(255, 255, 255), Thickness = 1, Length = 15 },
        },
        Skeleton = { Enabled = false, RGB = Color3.fromRGB(255, 255, 255), Thickness = 1 },
        TeamCheck = { Enabled = false },
    },
}

local BONE_CONNECTIONS = {
    { "torso", "shoulder1" }, { "torso", "shoulder2" },
    { "torso", "hip1" }, { "torso", "hip2" }, { "torso", "head" },
    { "shoulder1", "arm1" }, { "shoulder2", "arm2" },
    { "hip1", "leg1" }, { "hip2", "leg2" },
}

local ESPCounter = 0
local ActiveESPs = {}         
local ActiveSkeletons = {}     
local MasterConnection = nil

local _Camera, _CamPos, _ViewSize, _Tick, _GuiInsetY = nil, nil, nil, nil, 0
local ScreenGui = nil

local function Create(Class, Properties)
    local inst = typeof(Class) == "string" and Instance.new(Class) or Class
    for k, v in pairs(Properties) do inst[k] = v end
    return inst
end

local function getRealCharacters()
    local realChars = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local charModel = Workspace:FindFirstChild(player.Name)
        if charModel and charModel:GetAttribute("ID") then
            -- Optionally verify ID matches player's attribute
            local playerID = player:GetAttribute("ID")
            if playerID and charModel:GetAttribute("ID") == playerID then
                realChars[charModel] = player
            end
        end
    end
    return realChars
end

local function getCharacterFromViewmodel(viewmodel)
    local charId = viewmodel:GetAttribute("CharacterId")
    if charId then
        for char, player in pairs(getRealCharacters()) do
            if char:GetAttribute("ID") == charId then
                return char, player
            end
        end
    end
    local char = Workspace:FindFirstChild(viewmodel.Name)
    if char and getRealCharacters()[char] then
        return char, getRealCharacters()[char]
    end
    if viewmodel.Parent and getRealCharacters()[viewmodel.Parent] then
        return viewmodel.Parent, getRealCharacters()[viewmodel.Parent]
    end
    local torso = viewmodel:FindFirstChild("torso")
    if torso then
        local nearestDist = math.huge
        local nearestChar = nil
        for char in pairs(getRealCharacters()) do
            local charTorso = char:FindFirstChild("torso")
            if charTorso then
                local dist = (torso.Position - charTorso.Position).Magnitude
                if dist < nearestDist then
                    nearestDist = dist
                    nearestChar = char
                end
            end
        end
        if nearestChar and nearestDist < 5 then
            return nearestChar, getRealCharacters()[nearestChar]
        end
    end
    return nil, nil
end

local function isRealViewmodel(viewmodel)
    local torso = viewmodel:FindFirstChild("torso")
    return torso and torso.Transparency ~= 1
end

local function isTeammateViewmodel(viewmodel)
    for _, child in ipairs(Workspace:GetChildren()) do
        if child:IsA("Highlight") and child.Adornee == viewmodel then
            return true
        end
    end
    return false
end

local function createSkeletonESP(viewmodel)
    if not viewmodel or ActiveSkeletons[viewmodel] then return end
    local bones = {}
    local required = { "torso","head","shoulder1","shoulder2","arm1","arm2","hip1","hip2","leg1","leg2" }
    for _, name in ipairs(required) do
        local b = viewmodel:FindFirstChild(name)
        if not b or not b:IsA("BasePart") then return end
        bones[name] = b
    end
    local lines = {}
    for _ in ipairs(BONE_CONNECTIONS) do
        local line = Drawing.new("Line")
        line.Visible = false
        line.Color = ESP.Drawing.Skeleton.RGB
        line.Thickness = ESP.Drawing.Skeleton.Thickness
        line.Transparency = 1
        table.insert(lines, line)
    end
    ActiveSkeletons[viewmodel] = { lines = lines, bones = bones }
end

local function removeSkeleton(viewmodel)
    local sd = ActiveSkeletons[viewmodel]
    if not sd then return end
    for _, line in ipairs(sd.lines) do line.Visible = false; line:Remove() end
    ActiveSkeletons[viewmodel] = nil
end

local function processSkeleton(viewmodel, skData)
    local lines = skData.lines
    local function hideLines()
        for _, l in ipairs(lines) do l.Visible = false end
    end
    if not ESP.Enabled or not ESP.Drawing.Skeleton.Enabled then hideLines() return end
    if not viewmodel or not viewmodel.Parent then
        hideLines(); for _, l in ipairs(lines) do l:Remove() end
        ActiveSkeletons[viewmodel] = nil
        return
    end
    if not isRealViewmodel(viewmodel) then hideLines() return end
    if ESP.Drawing.TeamCheck.Enabled and isTeammateViewmodel(viewmodel) then hideLines() return end

    local torso = skData.bones["torso"]
    if not torso or torso.Transparency >= 1 then hideLines() return end
    local dist = (_CamPos - torso.Position).Magnitude
    if dist > ESP.MaxDistance then hideLines() return end
    for i, conn in ipairs(BONE_CONNECTIONS) do
        local b1, b2 = skData.bones[conn[1]], skData.bones[conn[2]]
        local line = lines[i]
        if b1 and b2 and line then
            local p1, on1 = _Camera:WorldToViewportPoint(b1.Position)
            local p2, on2 = _Camera:WorldToViewportPoint(b2.Position)
            if on1 and on2 then
                line.From = Vector2.new(p1.X, p1.Y)
                line.To = Vector2.new(p2.X, p2.Y)
                line.Color = ESP.Drawing.Skeleton.RGB
                line.Thickness = ESP.Drawing.Skeleton.Thickness
                line.Visible = true
            else
                line.Visible = false
            end
        elseif line then
            line.Visible = false
        end
    end
end

local function getProjectedBounds(character)
    if not character then return nil end
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local any = false
    local torso = character:FindFirstChild("torso")
    local head = character:FindFirstChild("head")
    local parts = {}
    if torso then table.insert(parts, torso) end
    if head then table.insert(parts, head) end
    for _, part in ipairs(parts) do
        if part:IsA("BasePart") and part.Transparency < 1 then
            local half = part.Size * 0.5
            local corners = {
                part.CFrame * Vector3.new(-half.X, -half.Y, -half.Z),
                part.CFrame * Vector3.new(-half.X, -half.Y,  half.Z),
                part.CFrame * Vector3.new(-half.X,  half.Y, -half.Z),
                part.CFrame * Vector3.new(-half.X,  half.Y,  half.Z),
                part.CFrame * Vector3.new( half.X, -half.Y, -half.Z),
                part.CFrame * Vector3.new( half.X, -half.Y,  half.Z),
                part.CFrame * Vector3.new( half.X,  half.Y, -half.Z),
                part.CFrame * Vector3.new( half.X,  half.Y,  half.Z),
            }
            for _, worldPos in ipairs(corners) do
                local p, on = _Camera:WorldToViewportPoint(worldPos)
                if on and p.Z > 0 then
                    any = true
                    if p.X < minX then minX = p.X end
                    if p.X > maxX then maxX = p.X end
                    if p.Y < minY then minY = p.Y end
                    if p.Y > maxY then maxY = p.Y end
                end
            end
        end
    end
    if not any then
        if torso then
            local p, on = _Camera:WorldToViewportPoint(torso.Position)
            if on and p.Z > 0 then
                minX = p.X - 8; maxX = p.X + 8; minY = p.Y - 15; maxY = p.Y + 15
                any = true
            end
        end
    end
    if not any then return nil end
    return minX, minY, maxX, maxY
end

local function findWeapon(character)
    for _, child in pairs(character:GetChildren()) do
        if child:IsA("Model") and child:GetAttribute("item_type") then
            return child
        end
    end
    return nil
end

local function processRealCharacter(character, player, espData)
    local el = espData.elements
    local function Hide()
        el.Box.Visible = false
        el.Name.Visible = false
        el.Weapon.Visible = false
        el.Chams.Enabled = false
        for _, name in ipairs({"LTH","LTV","RTH","RTV","LBH","LBV","RBH","RBV"}) do
            if el[name] then el[name].Visible = false end
        end
    end
    if not ESP.Enabled then Hide() return end
    if not character or not character.Parent then
        task.defer(function() if espData.folder then espData.folder:Destroy() end ActiveESPs[character] = nil end)
        return
    end
    local torso = character:FindFirstChild("torso")
    if not torso or torso.Transparency >= 1 then Hide() return end
    if ESP.Drawing.TeamCheck.Enabled and player and player.Team == Players.LocalPlayer.Team then
        Hide() return
    end
    local pos, onScreen = _Camera:WorldToViewportPoint(torso.Position)
    local dist = (_CamPos - torso.Position).Magnitude / 3.5714285714
    if not onScreen or dist > ESP.MaxDistance then Hide() return end
    local x0, y0, x1, y1 = getProjectedBounds(character)
    if not x0 then Hide() return end
    local w = math.max(2, x1 - x0)
    local h = math.max(2, y1 - y0)
    local padX, padY = math.max(2, w * 0.1), math.max(2, h * 0.07)
    x0, x1 = x0 - padX, x1 + padX
    y0, y1 = y0 - padY, y1 + padY
    w, h = x1 - x0, y1 - y0
    local yInset = _GuiInsetY or 0
    local chams = el.Chams
    chams.Adornee = character
    chams.Enabled = ESP.Drawing.Chams.Enabled
    chams.FillColor = ESP.Drawing.Chams.FillRGB
    chams.OutlineColor = ESP.Drawing.Chams.OutlineRGB
    chams.DepthMode = ESP.Drawing.Chams.VisibleCheck and "Occluded" or "AlwaysOnTop"
    if ESP.Drawing.Chams.Thermal then
        local b = math.atan(math.sin(_Tick * 2)) * 2 / math.pi
        chams.FillTransparency = (ESP.Drawing.Chams.Fill_Transparency / 100) * (1 - b * 0.1)
        chams.OutlineTransparency = ESP.Drawing.Chams.Outline_Transparency / 100
    end
    local cv, cc, cThick, cLen = ESP.Drawing.Boxes.Corner.Enabled, ESP.Drawing.Boxes.Corner.RGB, ESP.Drawing.Boxes.Corner.Thickness, ESP.Drawing.Boxes.Corner.Length
    local dynCL = math.min(cLen, w * 0.2, h * 0.2)
    el.LTH.Visible = cv; el.LTH.Position = UDim2.new(0, x0, 0, y0 - yInset); el.LTH.Size = UDim2.new(0, dynCL, 0, cThick); el.LTH.BackgroundColor3 = cc
    el.LTV.Visible = cv; el.LTV.Position = UDim2.new(0, x0, 0, y0 - yInset); el.LTV.Size = UDim2.new(0, cThick, 0, dynCL); el.LTV.BackgroundColor3 = cc
    el.RTH.Visible = cv; el.RTH.Position = UDim2.new(0, x1 - dynCL, 0, y0 - yInset); el.RTH.Size = UDim2.new(0, dynCL, 0, cThick); el.RTH.BackgroundColor3 = cc
    el.RTV.Visible = cv; el.RTV.Position = UDim2.new(0, x1 - cThick, 0, y0 - yInset); el.RTV.Size = UDim2.new(0, cThick, 0, dynCL); el.RTV.BackgroundColor3 = cc
    el.LBH.Visible = cv; el.LBH.Position = UDim2.new(0, x0, 0, y1 - cThick - yInset); el.LBH.Size = UDim2.new(0, dynCL, 0, cThick); el.LBH.BackgroundColor3 = cc
    el.LBV.Visible = cv; el.LBV.Position = UDim2.new(0, x0, 0, y1 - dynCL - yInset); el.LBV.Size = UDim2.new(0, cThick, 0, dynCL); el.LBV.BackgroundColor3 = cc
    el.RBH.Visible = cv; el.RBH.Position = UDim2.new(0, x1 - dynCL, 0, y1 - cThick - yInset); el.RBH.Size = UDim2.new(0, dynCL, 0, cThick); el.RBH.BackgroundColor3 = cc
    el.RBV.Visible = cv; el.RBV.Position = UDim2.new(0, x1 - cThick, 0, y1 - dynCL - yInset); el.RBV.Size = UDim2.new(0, cThick, 0, dynCL); el.RBV.BackgroundColor3 = cc
    local full, filled = ESP.Drawing.Boxes.Full.Enabled, ESP.Drawing.Boxes.Filled.Enabled
    el.Box.Position = UDim2.new(0, x0, 0, y0 - yInset)
    el.Box.Size = UDim2.new(0, w, 0, h)
    el.Box.Visible = full or (cv and filled)
    el.Box.BackgroundTransparency = filled and ESP.Drawing.Boxes.Filled.Transparency or 1
    el.Outline.Enabled = full and ESP.Drawing.Boxes.Gradient
    if ESP.Drawing.Boxes.Animate then
        local dt = _Tick - espData.lastTick
        espData.rotAngle = espData.rotAngle + dt * ESP.Drawing.Boxes.RotationSpeed * math.cos(math.pi/4 * _Tick - math.pi/2)
        el.Gradient1.Rotation = espData.rotAngle
        el.Gradient2.Rotation = espData.rotAngle
    else
        el.Gradient1.Rotation = -45
        el.Gradient2.Rotation = -45
    end
    espData.lastTick = _Tick
    -- Name
    el.Name.Visible = ESP.Drawing.Names.Enabled
    if ESP.Drawing.Names.Enabled then
        local nameText = player and player.Name or character.Name
        if ESP.Drawing.Distances.Enabled then
            nameText = string.format("%s [%d]", nameText, math.floor(dist))
        end
        el.Name.Text = nameText
        el.Name.TextColor3 = ESP.Drawing.Names.RGB
        el.Name.Position = UDim2.new(0, pos.X, 0, y0 - 9 - yInset)
    end
    -- Weapon
    el.Weapon.Visible = ESP.Drawing.Weapons.Enabled
    if ESP.Drawing.Weapons.Enabled then
        local weapon = findWeapon(character)
        if weapon then
            el.Weapon.Text = weapon.Name
            el.Weapon.TextColor3 = ESP.Drawing.Weapons.RGB
            el.Weapon.Position = UDim2.new(0, pos.X, 0, y1 + 9 - yInset)
        else
            el.Weapon.Visible = false
        end
    end
end

local function createESPForCharacter(character, player)
    if ActiveESPs[character] then return end
    ESPCounter = ESPCounter + 1
    local folder = Create("Folder", { Parent = ScreenGui, Name = "E_" .. ESPCounter })
    local Name = Create("TextLabel", {
        Parent = folder, Name = "N", Position = UDim2.new(0.5,0,0,-11), Size = UDim2.new(0,100,0,20),
        AnchorPoint = Vector2.new(0.5,0.5), BackgroundTransparency = 1, TextColor3 = Color3.new(1,1,1),
        Font = Enum.Font.Code, TextSize = ESP.FontSize, TextStrokeTransparency = 0, TextStrokeColor3 = Color3.new(0,0,0), RichText = true,
    })
    local Weapon = Create("TextLabel", {
        Parent = folder, Name = "W", Position = UDim2.new(0.5,0,0,0), Size = UDim2.new(0,100,0,20),
        AnchorPoint = Vector2.new(0.5,0.5), BackgroundTransparency = 1, TextColor3 = Color3.new(1,1,1),
        Font = Enum.Font.Code, TextSize = ESP.FontSize, TextStrokeTransparency = 0, TextStrokeColor3 = Color3.new(0,0,0), RichText = true,
    })
    local Box = Create("Frame", {
        Parent = folder, Name = "B", BackgroundColor3 = Color3.new(0,0,0), BackgroundTransparency = 0.75, BorderSizePixel = 0,
    })
    local Gradient1 = Create("UIGradient", { Parent = Box, Enabled = ESP.Drawing.Boxes.GradientFill, Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, ESP.Drawing.Boxes.GradientFillRGB1),
        ColorSequenceKeypoint.new(1, ESP.Drawing.Boxes.GradientFillRGB2),
    }) })
    local Outline = Create("UIStroke", { Parent = Box, Enabled = ESP.Drawing.Boxes.Gradient, Transparency = 0, Color = Color3.new(1,1,1), LineJoinMode = Enum.LineJoinMode.Miter })
    local Gradient2 = Create("UIGradient", { Parent = Outline, Enabled = ESP.Drawing.Boxes.Gradient, Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, ESP.Drawing.Boxes.GradientRGB1),
        ColorSequenceKeypoint.new(1, ESP.Drawing.Boxes.GradientRGB2),
    }) })
    local Chams = Create("Highlight", { Parent = folder, Name = "C", FillTransparency = 1, OutlineTransparency = 0, OutlineColor = Color3.fromRGB(119,120,255), DepthMode = "AlwaysOnTop" })
    local cThick, cLen, cc = ESP.Drawing.Boxes.Corner.Thickness, ESP.Drawing.Boxes.Corner.Length, ESP.Drawing.Boxes.Corner.RGB
    local function mc(name, w, h) return Create("Frame", { Parent = folder, Name = name, BackgroundColor3 = cc, BackgroundTransparency = 0, BorderSizePixel = 0, Size = UDim2.new(0,w,0,h) }) end
    ActiveESPs[character] = {
        folder = folder, rotAngle = -45, lastTick = tick(),
        elements = {
            Name = Name, Weapon = Weapon, Box = Box, Gradient1 = Gradient1, Gradient2 = Gradient2, Outline = Outline, Chams = Chams,
            LTH = mc("LTH", cLen, cThick), LTV = mc("LTV", cThick, cLen),
            RTH = mc("RTH", cLen, cThick), RTV = mc("RTV", cThick, cLen),
            LBH = mc("LBH", cLen, cThick), LBV = mc("LBV", cThick, cLen),
            RBH = mc("RBH", cLen, cThick), RBV = mc("RBV", cThick, cLen),
        },
    }
end

local function monitorCharacters()
    local function refreshCharacters()
        for character, player in pairs(getRealCharacters()) do
            if not ActiveESPs[character] then
                createESPForCharacter(character, player)
            end
        end
        for character in pairs(ActiveESPs) do
            if not character.Parent or not getRealCharacters()[character] then
                if ActiveESPs[character].folder then ActiveESPs[character].folder:Destroy() end
                ActiveESPs[character] = nil
            end
        end
    end
    refreshCharacters()
    Workspace.ChildAdded:Connect(function(child)
        if child:IsA("Model") and child:GetAttribute("ID") then
            task.defer(refreshCharacters)
        end
    end)
    Workspace.ChildRemoved:Connect(function(child)
        if child:IsA("Model") then
            task.defer(refreshCharacters)
        end
    end)
end

local function monitorViewmodelsForSkeleton()
    local viewmodelsFolder = Workspace:FindFirstChild("Viewmodels")
    if not viewmodelsFolder then return end
    local function refreshSkeleton()
        for _, vm in pairs(viewmodelsFolder:GetChildren()) do
            if vm:IsA("Model") and not ActiveSkeletons[vm] then
                if isRealViewmodel(vm) then
                    createSkeletonESP(vm)
                end
            end
        end
        for vm in pairs(ActiveSkeletons) do
            if not vm.Parent or not isRealViewmodel(vm) then
                removeSkeleton(vm)
            end
        end
    end
    refreshSkeleton()
    viewmodelsFolder.ChildAdded:Connect(function(vm)
        if vm:IsA("Model") then task.defer(refreshSkeleton) end
    end)
    viewmodelsFolder.ChildRemoved:Connect(function(vm)
        if vm:IsA("Model") then task.defer(refreshSkeleton) end
    end)
end

local function startRender()
    MasterConnection = RunService.RenderStepped:Connect(function()
        _Camera = Workspace.CurrentCamera
        _CamPos = _Camera.CFrame.Position
        _ViewSize = _Camera.ViewportSize
        _Tick = tick()
        local ok, inset = pcall(function() return GuiService:GetGuiInset() end)
        _GuiInsetY = (ok and inset and ScreenGui and ScreenGui.IgnoreGuiInset) and 0 or (inset and inset.Y or 0)
        for character, espData in pairs(ActiveESPs) do
            local player = getRealCharacters()[character]
            if player then
                processRealCharacter(character, player, espData)
            else
                if espData.folder then espData.folder:Destroy() end
                ActiveESPs[character] = nil
            end
        end
        for viewmodel, skData in pairs(ActiveSkeletons) do
            processSkeleton(viewmodel, skData)
        end
    end)
end

local guiHideName = "ESP_" .. tostring(math.random(100000000, 999999999))
local parentGui = gethui and gethui() or CoreGui
local function cleanupESPGuids(container)
    if not container then return end
    for _, v in pairs(container:GetChildren()) do
        if v:IsA("ScreenGui") and v.Name:sub(1,4) == "ESP_" then v:Destroy() end
    end
end
cleanupESPGuids(CoreGui)
if parentGui ~= gethui then cleanupESPGuids(parentGui) end
ScreenGui = Create("ScreenGui", {
    Parent = parentGui, Name = guiHideName, ResetOnSpawn = false, IgnoreGuiInset = true,
    DisplayOrder = 999999, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
pcall(function()
    if syn and syn.protect_gui then syn.protect_gui(ScreenGui)
    elseif protect_gui then protect_gui(ScreenGui) end
end)

ESP.Refresh = function()
    for char in pairs(ActiveESPs) do if ActiveESPs[char].folder then ActiveESPs[char].folder:Destroy() end end
    table.clear(ActiveESPs)
    for vm in pairs(ActiveSkeletons) do removeSkeleton(vm) end
    table.clear(ActiveSkeletons)
    monitorCharacters()
    monitorViewmodelsForSkeleton()
end
ESP.CleanAll = function()
    for char, data in pairs(ActiveESPs) do if data.folder then data.folder:Destroy() end end
    table.clear(ActiveESPs)
    for vm in pairs(ActiveSkeletons) do removeSkeleton(vm) end
    table.clear(ActiveSkeletons)
end
ESP.ToggleSkeleton = function(enabled)
    ESP.Drawing.Skeleton.Enabled = enabled
    if not enabled then for vm in pairs(ActiveSkeletons) do removeSkeleton(vm) end
    else monitorViewmodelsForSkeleton() end
end
ESP.SetSkeletonColor = function(c) if typeof(c)=="Color3" then ESP.Drawing.Skeleton.RGB = c
    for _, sd in pairs(ActiveSkeletons) do for _, l in ipairs(sd.lines) do l.Color = c end end end end
ESP.SetSkeletonThickness = function(t) if type(t)=="number" and t>0 then ESP.Drawing.Skeleton.Thickness = t
    for _, sd in pairs(ActiveSkeletons) do for _, l in ipairs(sd.lines) do l.Thickness = t end end end end
ESP.SetCornerColor = function(c) if typeof(c)=="Color3" then ESP.Drawing.Boxes.Corner.RGB = c end end
ESP.SetCornerThickness = function(t) if type(t)=="number" and t>0 then ESP.Drawing.Boxes.Corner.Thickness = t end end
ESP.SetCornerLength = function(l) if type(l)=="number" and l>0 then ESP.Drawing.Boxes.Corner.Length = l end end
getgenv().toggle_esp = function(enabled) ESP.Enabled = enabled end
getgenv().set_esp_fov = function(fov) ESP.MaxDistance = fov end

monitorCharacters()
monitorViewmodelsForSkeleton()
startRender()
return ESP
