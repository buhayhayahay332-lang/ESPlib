pcall(function() setthreadidentity(8) end)

local cloneref = cloneref or function(obj) return obj end
local gethui = gethui or function() return game:GetService("CoreGui") end
local protect_gui = protect_gui or function(gui) end

local Workspace = cloneref(game:GetService("Workspace"))
local RunService = cloneref(game:GetService("RunService"))
local CoreGui = cloneref(game:GetService("CoreGui"))

local ESP = {
    Enabled = true,
    Skeleton = {
        Enabled = true,
        Color = Color3.fromRGB(255, 255, 255),
        Thickness = 2,
    },
    WeaponNames = {
        Enabled = true,
        Color = Color3.fromRGB(255, 255, 0),
        Size = 14,
    },
    Chams = {
        Enabled = true,
        Thermal = false,                   
        FillRGB = Color3.fromRGB(255, 80, 80),
        OutlineRGB = Color3.fromRGB(255, 255, 255),
        Fill_Transparency = 50,           
        Outline_Transparency = 50,
        VisibleCheck = false,              
    },
    TeamCheck = {
        Enabled = true,
        HighlightColor = Color3.fromRGB(0, 150, 0),
    },
    MaxDistance = 150,
}

local BONE_CONNECTIONS = {
    { "torso", "shoulder1" }, { "torso", "shoulder2" },
    { "torso", "hip1" },      { "torso", "hip2" },
    { "torso", "head" },
    { "shoulder1", "arm1" },  { "shoulder2", "arm2" },
    { "hip1", "leg1" },       { "hip2", "leg2" },
}

local activeSkeletons = {}  
local activeWeaponNames = {}
local activeChams = {}      
local renderConnection = nil
local viewmodelsFolder = nil
local ScreenGui = nil
local _Tick = 0

local function isClone(viewmodel)
    local torso = viewmodel:FindFirstChild("torso")
    return torso and torso.Transparency == 1
end

local function isTeammateByHighlight(viewmodel)
    if not ESP.TeamCheck.Enabled then return false end
    for _, child in pairs(Workspace:GetChildren()) do
        if child:IsA("Highlight") and child.Adornee == viewmodel then
            if child.FillColor == ESP.TeamCheck.HighlightColor then
                return true
            end
        end
    end
    return false
end

local function isValidViewmodel(viewmodel)
    if not viewmodel or not viewmodel.Parent then return false end
    if viewmodel.Name == "LocalViewmodel" then return false end
    if not viewmodelsFolder or viewmodel.Parent ~= viewmodelsFolder then return false end
    local torso = viewmodel:FindFirstChild("torso")
    if not torso or not torso:IsA("BasePart") then return false end
    if isClone(viewmodel) then return false end
    return true
end

local function findWeaponInViewmodel(viewmodel)
    for _, child in pairs(viewmodel:GetChildren()) do
        if child:IsA("Model") and child:GetAttribute("item_type") then
            return child
        end
    end
    return nil
end

local function createSkeleton(viewmodel)
    if not isValidViewmodel(viewmodel) then return end
    if activeSkeletons[viewmodel] then return end

    local bones = {}
    local required = { "torso","head","shoulder1","shoulder2","arm1","arm2","hip1","hip2","leg1","leg2" }
    for _, name in ipairs(required) do
        local part = viewmodel:FindFirstChild(name)
        if not part or not part:IsA("BasePart") then return end
        bones[name] = part
    end

    local lines = {}
    for _ = 1, #BONE_CONNECTIONS do
        local line = Drawing.new("Line")
        line.Visible = false
        line.Color = ESP.Skeleton.Color
        line.Thickness = ESP.Skeleton.Thickness
        line.Transparency = 1
        table.insert(lines, line)
    end

    activeSkeletons[viewmodel] = { lines = lines, bones = bones }
end

local function updateSkeleton(viewmodel, data)
    local lines = data.lines
    local bones = data.bones
    local camera = workspace.CurrentCamera
    local camPos = camera.CFrame.Position
    local torso = bones.torso
    if not torso then
        for _, line in ipairs(lines) do line.Visible = false end
        return
    end

    local dist = (torso.Position - camPos).Magnitude
    if dist > ESP.MaxDistance then
        for _, line in ipairs(lines) do line.Visible = false end
        return
    end

    for i, conn in ipairs(BONE_CONNECTIONS) do
        local b1 = bones[conn[1]]
        local b2 = bones[conn[2]]
        local line = lines[i]
        if b1 and b2 then
            local p1, on1 = camera:WorldToViewportPoint(b1.Position)
            local p2, on2 = camera:WorldToViewportPoint(b2.Position)
            if on1 and on2 then
                line.From = Vector2.new(p1.X, p1.Y)
                line.To = Vector2.new(p2.X, p2.Y)
                line.Color = ESP.Skeleton.Color
                line.Thickness = ESP.Skeleton.Thickness
                line.Visible = true
            else
                line.Visible = false
            end
        else
            line.Visible = false
        end
    end
end

local function removeSkeleton(viewmodel)
    local data = activeSkeletons[viewmodel]
    if data then
        for _, line in ipairs(data.lines) do
            line.Visible = false
            line:Remove()
        end
        activeSkeletons[viewmodel] = nil
    end
end

local function createWeaponName(viewmodel)
    if not isValidViewmodel(viewmodel) then return end
    if activeWeaponNames[viewmodel] then return end

    local text = Drawing.new("Text")
    text.Size = ESP.WeaponNames.Size
    text.Center = true
    text.Outline = true
    text.OutlineColor = Color3.fromRGB(0, 0, 0)
    text.Color = ESP.WeaponNames.Color
    text.Visible = false
    activeWeaponNames[viewmodel] = text
end

local function updateWeaponName(viewmodel)
    local text = activeWeaponNames[viewmodel]
    if not text then return end

    local torso = viewmodel:FindFirstChild("torso")
    if not torso then
        text.Visible = false
        return
    end

    local camera = workspace.CurrentCamera
    local pos, onScreen = camera:WorldToViewportPoint(torso.Position + Vector3.new(0, 3.5, 0))
    local dist = (torso.Position - camera.CFrame.Position).Magnitude

    if not onScreen or dist > ESP.MaxDistance then
        text.Visible = false
        return
    end

    local weapon = findWeaponInViewmodel(viewmodel)
    local weaponName = weapon and weapon.Name or ""
    if weaponName == "" then
        text.Visible = false
        return
    end

    text.Text = weaponName
    text.Position = Vector2.new(pos.X, pos.Y - 30)
    text.Color = ESP.WeaponNames.Color
    text.Size = ESP.WeaponNames.Size
    text.Visible = true
end

local function removeWeaponName(viewmodel)
    local text = activeWeaponNames[viewmodel]
    if text then
        text.Visible = false
        text:Remove()
        activeWeaponNames[viewmodel] = nil
    end
end

local function createChams(viewmodel)
    if not isValidViewmodel(viewmodel) then return end
    if activeChams[viewmodel] then return end

    local highlight = Instance.new("Highlight")
    highlight.Adornee = viewmodel
    highlight.DepthMode = ESP.Chams.VisibleCheck and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = viewmodel
    activeChams[viewmodel] = highlight
end

local function updateChams(viewmodel, highlight)
    local torso = viewmodel:FindFirstChild("torso")
    if not torso then
        highlight.Enabled = false
        return
    end

    local dist = (torso.Position - workspace.CurrentCamera.CFrame.Position).Magnitude
    if dist > ESP.MaxDistance then
        highlight.Enabled = false
        return
    end

    highlight.Enabled = ESP.Chams.Enabled
    if not highlight.Enabled then return end

    highlight.FillColor = ESP.Chams.FillRGB
    highlight.OutlineColor = ESP.Chams.OutlineRGB
    highlight.FillTransparency = ESP.Chams.Fill_Transparency / 100
    highlight.OutlineTransparency = ESP.Chams.Outline_Transparency / 100

    if ESP.Chams.Thermal then
        local b = math.atan(math.sin(_Tick * 2)) * 2 / math.pi
        highlight.FillTransparency = (ESP.Chams.Fill_Transparency / 100) * (1 - b * 0.1)
        highlight.OutlineTransparency = (ESP.Chams.Outline_Transparency / 100)
    end

    highlight.DepthMode = ESP.Chams.VisibleCheck and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
end

local function removeChams(viewmodel)
    local highlight = activeChams[viewmodel]
    if highlight then
        highlight:Destroy()
        activeChams[viewmodel] = nil
    end
end

local function refreshAll()
    if not viewmodelsFolder then
        viewmodelsFolder = Workspace:FindFirstChild("Viewmodels")
    end
    if not viewmodelsFolder then return end

    for _, vm in pairs(viewmodelsFolder:GetChildren()) do
        if vm:IsA("Model") and isValidViewmodel(vm) then
            local isTeammate = isTeammateByHighlight(vm)
            if isTeammate and ESP.TeamCheck.Enabled then
                removeSkeleton(vm)
                removeWeaponName(vm)
                removeChams(vm)
            else
                if ESP.Skeleton.Enabled then createSkeleton(vm) end
                if ESP.WeaponNames.Enabled then createWeaponName(vm) end
                if ESP.Chams.Enabled then createChams(vm) end
            end
        else
            removeSkeleton(vm)
            removeWeaponName(vm)
            removeChams(vm)
        end
    end
end

local function cleanAll()
    for vm in pairs(activeSkeletons) do removeSkeleton(vm) end
    for vm in pairs(activeWeaponNames) do removeWeaponName(vm) end
    for vm in pairs(activeChams) do removeChams(vm) end
end

local function startRender()
    if renderConnection then renderConnection:Disconnect() end
    renderConnection = RunService.RenderStepped:Connect(function()
        _Tick = tick()

        if not ESP.Enabled then
            for vm, data in pairs(activeSkeletons) do
                for _, line in ipairs(data.lines) do line.Visible = false end
            end
            for vm, text in pairs(activeWeaponNames) do text.Visible = false end
            for vm, highlight in pairs(activeChams) do highlight.Enabled = false end
            return
        end

        for vm, data in pairs(activeSkeletons) do
            if isValidViewmodel(vm) and not (ESP.TeamCheck.Enabled and isTeammateByHighlight(vm)) then
                updateSkeleton(vm, data)
            else
                for _, line in ipairs(data.lines) do line.Visible = false end
            end
        end

        for vm, text in pairs(activeWeaponNames) do
            if isValidViewmodel(vm) and not (ESP.TeamCheck.Enabled and isTeammateByHighlight(vm)) then
                updateWeaponName(vm)
            else
                text.Visible = false
            end
        end

        for vm, highlight in pairs(activeChams) do
            if isValidViewmodel(vm) and not (ESP.TeamCheck.Enabled and isTeammateByHighlight(vm)) then
                updateChams(vm, highlight)
            else
                highlight.Enabled = false
            end
        end
    end)
end

local function setupListeners()
    local function onViewmodelsFolder()
        viewmodelsFolder = Workspace:FindFirstChild("Viewmodels")
        if viewmodelsFolder then
            refreshAll()
            viewmodelsFolder.ChildAdded:Connect(function(child)
                if child:IsA("Model") then task.defer(refreshAll) end
            end)
            viewmodelsFolder.ChildRemoved:Connect(function(child)
                if child:IsA("Model") then
                    removeSkeleton(child)
                    removeWeaponName(child)
                    removeChams(child)
                end
            end)
        end
    end

    onViewmodelsFolder()
    Workspace.ChildAdded:Connect(function(child)
        if child.Name == "Viewmodels" then onViewmodelsFolder() end
    end)
end

local parentGui = gethui()
if not parentGui then parentGui = CoreGui end

local guiHideName = "ViewmodelESP_" .. tostring(math.random(100000000, 999999999))
ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = guiHideName
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.DisplayOrder = 999999
ScreenGui.Parent = parentGui

pcall(function()
    if syn and syn.protect_gui then
        syn.protect_gui(ScreenGui)
    elseif protect_gui then
        protect_gui(ScreenGui)
    end
end)

ESP.Refresh = refreshAll
ESP.CleanAll = cleanAll
ESP.UpdateConfig = function(newConfig)
    for k, v in pairs(newConfig) do
        if type(v) == "table" and ESP[k] then
            for k2, v2 in pairs(v) do
                ESP[k][k2] = v2
            end
        else
            ESP[k] = v
        end
    end
    refreshAll()
end

startRender()
setupListeners()
refreshAll()

return ESP
