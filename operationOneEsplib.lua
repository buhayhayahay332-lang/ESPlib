pcall(function() setthreadidentity(8) end)
pcall(function() game:GetService("WebViewService"):Destroy() end)

local cloneref = cloneref or function(o) return o end

local Workspace   = cloneref(game:GetService("Workspace"))
local RunService  = cloneref(game:GetService("RunService"))
local Players     = cloneref(game:GetService("Players"))
local Lighting    = cloneref(game:GetService("Lighting"))
local CoreGui     = cloneref(game:GetService("CoreGui"))

local LocalPlayer = cloneref(Players.LocalPlayer)

-- camera re-read each frame instead of captured once
-- prevents stale reference if camera changes
local function GetCamera()
	return Workspace.CurrentCamera
end

local ESPCounter = 0
local ActiveESPs = {}
local ActiveSkeletons = {}

local ESP = {
	Enabled = false,
	MaxDistance = 1000,
	FontSize = 11,
	FadeOut = {
		OnDistance = true,
		OnDeath = true,
		OnLeave = true,
	},
	Drawing = {
		Chams = {
			Enabled = false,
			Thermal = false,
			FillRGB = Color3.fromRGB(243, 116, 166),
			Fill_Transparency = 50,
			OutlineRGB = Color3.fromRGB(243, 116, 166),
			Outline_Transparency = 50,
			VisibleCheck = false,
		},
		Names = {
			Enabled = false,
			RGB = Color3.fromRGB(255, 255, 255),
		},
		Distances = {
			Enabled = false,
			Position = "Text",
			RGB = Color3.fromRGB(255, 255, 255),
		},
		Weapons = {
			Enabled = false,
			RGB = Color3.fromRGB(255, 255, 255),
		},
		Boxes = {
			Animate = false,
			RotationSpeed = 300,
			Gradient = true,
			GradientRGB1 = Color3.fromRGB(243, 116, 116),
			GradientRGB2 = Color3.fromRGB(0, 0, 0),
			GradientFill = true,
			GradientFillRGB1 = Color3.fromRGB(243, 116, 116),
			GradientFillRGB2 = Color3.fromRGB(0, 0, 0),
			Filled = {
				Enabled = false,
				Transparency = 0.75,
				RGB = Color3.fromRGB(0, 0, 0),
			},
			Full = {
				Enabled = false,
				RGB = Color3.fromRGB(255, 255, 255),
			},
			Corner = {
				Enabled = false,
				RGB = Color3.fromRGB(255, 255, 255),
				Thickness = 1,
				Length = 15,
			},
		},
		Skeleton = {
			Enabled = false,
			RGB = Color3.fromRGB(255, 255, 255),
			Thickness = 1,
		},
		TeamCheck = {
			Enabled = false,
		},
	},
}

local BONE_CONNECTIONS = {
	{ "torso", "shoulder1" },
	{ "torso", "shoulder2" },
	{ "torso", "hip1" },
	{ "torso", "hip2" },
	{ "torso", "head" },
	{ "shoulder1", "arm1" },
	{ "shoulder2", "arm2" },
	{ "hip1", "leg1" },
	{ "hip2", "leg2" },
}

local Functions = {}

function Functions:Create(Class, Properties)
	local _Instance = typeof(Class) == "string" and Instance.new(Class) or Class
	for Property, Value in pairs(Properties) do
		_Instance[Property] = Value
	end
	return _Instance
end

function Functions:FadeOutOnDist(element, distance)
	local transparency = math.max(0.1, 1 - (distance / ESP.MaxDistance))
	if element:IsA("TextLabel") then
		element.TextTransparency = 1 - transparency
	elseif element:IsA("ImageLabel") then
		element.ImageTransparency = 1 - transparency
	elseif element:IsA("UIStroke") then
		element.Transparency = 1 - transparency
	elseif element:IsA("Frame") then
		element.BackgroundTransparency = 1 - transparency
	elseif element:IsA("Highlight") then
		element.FillTransparency = 1 - transparency
		element.OutlineTransparency = 1 - transparency
	end
end

function Functions:CleanAllESPs()
	for model, espFolder in pairs(ActiveESPs) do
		if espFolder and espFolder.Parent then
			espFolder:Destroy()
		end
	end
	ActiveESPs = {}
	self:CleanAllSkeletons()
end

function Functions:CleanAllSkeletons()
	for model, skeletonData in pairs(ActiveSkeletons) do
		if skeletonData then
			for _, line in ipairs(skeletonData.lines) do
				if line then
					line.Visible = false
					line:Remove()
				end
			end
			if skeletonData.connection then
				skeletonData.connection:Disconnect()
			end
		end
	end
	ActiveSkeletons = {}
end

function Functions:RemoveSkeleton(character)
	local skeletonData = ActiveSkeletons[character]
	if not skeletonData then
		return
	end
	for _, line in ipairs(skeletonData.lines) do
		if line then
			line:Remove()
		end
	end
	if skeletonData.connection then
		skeletonData.connection:Disconnect()
	end
	ActiveSkeletons[character] = nil
end

local function hasTeamHighlight(model)
	if not model then
		return false
	end
	-- use cloneref'd Workspace instead of raw workspace global
	for _, child in pairs(Workspace:GetChildren()) do
		if child:IsA("Highlight") and child.Adornee == model then
			return true
		end
	end
	return false
end

local function isValidPlayer(model)
	if not model then
		return false
	end
	if not model.Parent then
		return false
	end
	if model.Name == "LocalViewmodel" then
		return false
	end
	local viewmodels = Workspace:FindFirstChild("Viewmodels")
	if not viewmodels or model.Parent ~= viewmodels then
		return false
	end
	local torso = model:FindFirstChild("torso")
	if not torso or not torso:IsA("BasePart") then
		return false
	end
	return true
end

local function findWeaponInCharacter(character)
	if not character then
		return nil
	end
	for _, child in pairs(character:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("item_type") then
			return child
		end
	end
	return nil
end

local function createSkeletonESP(character)
	if not character or ActiveSkeletons[character] then
		return
	end
	if not isValidPlayer(character) then
		return
	end

	local bones = {}
	local hasAllBones = true
	local requiredBones = { "torso", "head", "shoulder1", "shoulder2", "arm1", "arm2", "hip1", "hip2", "leg1", "leg2" }

	for _, boneName in ipairs(requiredBones) do
		local bone = character:FindFirstChild(boneName)
		if bone and bone:IsA("BasePart") then
			bones[boneName] = bone
		else
			hasAllBones = false
			break
		end
	end

	if not hasAllBones then
		return
	end

	local skeletonLines = {}
	for _, connection in ipairs(BONE_CONNECTIONS) do
		local line = Drawing.new("Line")
		line.Visible = false
		line.Color = ESP.Drawing.Skeleton.RGB
		line.Thickness = ESP.Drawing.Skeleton.Thickness
		line.Transparency = 1
		table.insert(skeletonLines, line)
	end

	local skeletonData = {
		lines = skeletonLines,
		bones = bones,
		character = character,
	}

	ActiveSkeletons[character] = skeletonData

	local connection = RunService.RenderStepped:Connect(function()
		if not ESP.Enabled or not ESP.Drawing.Skeleton.Enabled then
			for _, line in ipairs(skeletonLines) do
				line.Visible = false
			end
			return
		end

		if ESP.Drawing.TeamCheck.Enabled and hasTeamHighlight(character) then
			for _, line in ipairs(skeletonLines) do
				line.Visible = false
			end
			return
		end

		local torso = bones["torso"]
		if not torso or torso.Transparency >= 1 then
			for _, line in ipairs(skeletonLines) do
				line.Visible = false
			end
			return
		end

		local camera = GetCamera()
		local distance = (camera.CFrame.Position - torso.Position).Magnitude

		if distance > ESP.MaxDistance then
			for _, line in ipairs(skeletonLines) do
				line.Visible = false
			end
			return
		end

		for i, connection in ipairs(BONE_CONNECTIONS) do
			local bone1Name, bone2Name = connection[1], connection[2]
			local bone1, bone2 = bones[bone1Name], bones[bone2Name]
			local line = skeletonLines[i]

			if bone1 and bone2 and line then
				local pos1, onScreen1 = camera:WorldToViewportPoint(bone1.Position)
				local pos2, onScreen2 = camera:WorldToViewportPoint(bone2.Position)

				if onScreen1 and onScreen2 then
					line.From = Vector2.new(pos1.X, pos1.Y)
					line.To = Vector2.new(pos2.X, pos2.Y)
					line.Visible = true
					line.Color = ESP.Drawing.Skeleton.RGB
					line.Thickness = ESP.Drawing.Skeleton.Thickness
				else
					line.Visible = false
				end
			elseif line then
				line.Visible = false
			end
		end
	end)

	skeletonData.connection = connection
end

if CoreGui:FindFirstChild("ESPHolder") then
	CoreGui["ESPHolder"]:Destroy()
end

local ScreenGui = Functions:Create("ScreenGui", { Parent = CoreGui, Name = "ESPHolder" })

local function CreateESP(CharacterModel)
	if not CharacterModel then
		return
	end
	if not isValidPlayer(CharacterModel) then
		return
	end
	if ActiveESPs[CharacterModel] then
		return
	end

	ESPCounter = ESPCounter + 1
	local GuiName = "ESP_" .. CharacterModel.Name .. "_" .. ESPCounter
	local ESPFolder = Functions:Create("Folder", { Parent = ScreenGui, Name = GuiName })
	ActiveESPs[CharacterModel] = ESPFolder

	local Name = Functions:Create("TextLabel", {
		Parent = ESPFolder,
		Name = "NameLabel",
		Position = UDim2.new(0.5, 0, 0, -11),
		Size = UDim2.new(0, 100, 0, 20),
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
		Parent = ESPFolder,
		Name = "WeaponLabel",
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0, 100, 0, 20),
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
		Parent = ESPFolder,
		Name = "Box",
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
	})

	local Gradient1 = Functions:Create("UIGradient", {
		Parent = Box,
		Enabled = ESP.Drawing.Boxes.GradientFill,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, ESP.Drawing.Boxes.GradientFillRGB1),
			ColorSequenceKeypoint.new(1, ESP.Drawing.Boxes.GradientFillRGB2),
		}),
	})

	local Outline = Functions:Create("UIStroke", {
		Parent = Box,
		Enabled = ESP.Drawing.Boxes.Gradient,
		Transparency = 0,
		Color = Color3.fromRGB(255, 255, 255),
		LineJoinMode = Enum.LineJoinMode.Miter,
	})

	local Gradient2 = Functions:Create("UIGradient", {
		Parent = Outline,
		Enabled = ESP.Drawing.Boxes.Gradient,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, ESP.Drawing.Boxes.GradientRGB1),
			ColorSequenceKeypoint.new(1, ESP.Drawing.Boxes.GradientRGB2),
		}),
	})

	local Chams = Functions:Create("Highlight", {
		Parent = ESPFolder,
		Name = "Chams",
		FillTransparency = 1,
		OutlineTransparency = 0,
		OutlineColor = Color3.fromRGB(119, 120, 255),
		DepthMode = "AlwaysOnTop",
	})

	local cornerThickness = ESP.Drawing.Boxes.Corner.Thickness
	local cornerLength = ESP.Drawing.Boxes.Corner.Length
	local cornerProps = {
		Parent = ESPFolder,
		BackgroundColor3 = ESP.Drawing.Boxes.Corner.RGB,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 0),
	}

	local LeftTopHorizontal = Functions:Create("Frame", cornerProps)
	LeftTopHorizontal.Name = "LeftTopHorizontal"
	LeftTopHorizontal.Size = UDim2.new(0, cornerLength, 0, cornerThickness)

	local LeftTopVertical = Functions:Create("Frame", cornerProps)
	LeftTopVertical.Name = "LeftTopVertical"
	LeftTopVertical.Size = UDim2.new(0, cornerThickness, 0, cornerLength)

	local RightTopHorizontal = Functions:Create("Frame", cornerProps)
	RightTopHorizontal.Name = "RightTopHorizontal"
	RightTopHorizontal.Size = UDim2.new(0, cornerLength, 0, cornerThickness)

	local RightTopVertical = Functions:Create("Frame", cornerProps)
	RightTopVertical.Name = "RightTopVertical"
	RightTopVertical.Size = UDim2.new(0, cornerThickness, 0, cornerLength)

	local LeftBottomHorizontal = Functions:Create("Frame", cornerProps)
	LeftBottomHorizontal.Name = "LeftBottomHorizontal"
	LeftBottomHorizontal.Size = UDim2.new(0, cornerLength, 0, cornerThickness)

	local LeftBottomVertical = Functions:Create("Frame", cornerProps)
	LeftBottomVertical.Name = "LeftBottomVertical"
	LeftBottomVertical.Size = UDim2.new(0, cornerThickness, 0, cornerLength)

	local RightBottomHorizontal = Functions:Create("Frame", cornerProps)
	RightBottomHorizontal.Name = "RightBottomHorizontal"
	RightBottomHorizontal.Size = UDim2.new(0, cornerLength, 0, cornerThickness)

	local RightBottomVertical = Functions:Create("Frame", cornerProps)
	RightBottomVertical.Name = "RightBottomVertical"
	RightBottomVertical.Size = UDim2.new(0, cornerThickness, 0, cornerLength)

	local RotationAngle = -45
	local LastTick = tick()

	local function HideESP()
		Box.Visible = false
		Name.Visible = false
		Weapon.Visible = false
		LeftTopHorizontal.Visible = false
		LeftTopVertical.Visible = false
		RightTopHorizontal.Visible = false
		RightTopVertical.Visible = false
		LeftBottomHorizontal.Visible = false
		LeftBottomVertical.Visible = false
		RightBottomHorizontal.Visible = false
		RightBottomVertical.Visible = false
		Chams.Enabled = false
	end

	local Connection
	local function CleanupESP()
		if Connection then
			Connection:Disconnect()
		end
		if ESPFolder then
			ESPFolder:Destroy()
		end
		ActiveESPs[CharacterModel] = nil
		Functions:RemoveSkeleton(CharacterModel)
	end

	Connection = RunService.RenderStepped:Connect(function()
		if not ESP.Enabled then
			HideESP()
			return
		end

		if not CharacterModel or not CharacterModel.Parent then
			CleanupESP()
			return
		end

		if not isValidPlayer(CharacterModel) then
			CleanupESP()
			return
		end

		local torso = CharacterModel:FindFirstChild("torso")
		if not torso or torso.Transparency >= 1 then
			HideESP()
			return
		end

		if ESP.Drawing.TeamCheck.Enabled and hasTeamHighlight(CharacterModel) then
			HideESP()
			return
		end

		-- re-read camera each frame
		local Camera = GetCamera()
		local Pos, OnScreen = Camera:WorldToScreenPoint(torso.Position)
		local Dist = (Camera.CFrame.Position - torso.Position).Magnitude / 3.5714285714

		if OnScreen and Dist <= ESP.MaxDistance then
			local Size = torso.Size.Y
			local scaleFactor = (Size * Camera.ViewportSize.Y) / (Pos.Z * 2)
			local w, h = 2.5 * scaleFactor, 4.75 * scaleFactor
			local verticalOffset = h * 0.175
			local dynamicCornerLength = math.min(cornerLength, w * 0.2, h * 0.2)

			if ESP.FadeOut.OnDistance then
				Functions:FadeOutOnDist(Box, Dist)
				Functions:FadeOutOnDist(Outline, Dist)
				Functions:FadeOutOnDist(Name, Dist)
				Functions:FadeOutOnDist(Weapon, Dist)
				Functions:FadeOutOnDist(Chams, Dist)
				Functions:FadeOutOnDist(LeftTopHorizontal, Dist)
				Functions:FadeOutOnDist(LeftTopVertical, Dist)
				Functions:FadeOutOnDist(RightTopHorizontal, Dist)
				Functions:FadeOutOnDist(RightTopVertical, Dist)
				Functions:FadeOutOnDist(LeftBottomHorizontal, Dist)
				Functions:FadeOutOnDist(LeftBottomVertical, Dist)
				Functions:FadeOutOnDist(RightBottomHorizontal, Dist)
				Functions:FadeOutOnDist(RightBottomVertical, Dist)
			end

			Chams.Adornee = CharacterModel
			Chams.Enabled = ESP.Drawing.Chams.Enabled
			Chams.FillColor = ESP.Drawing.Chams.FillRGB
			Chams.OutlineColor = ESP.Drawing.Chams.OutlineRGB

			if ESP.Drawing.Chams.Thermal then
				local breathe_effect = math.atan(math.sin(tick() * 2)) * 2 / math.pi
				Chams.FillTransparency = (ESP.Drawing.Chams.Fill_Transparency / 100) * (1 - (breathe_effect * 0.1))
				Chams.OutlineTransparency = ESP.Drawing.Chams.Outline_Transparency
			end
			Chams.DepthMode = ESP.Drawing.Chams.VisibleCheck and "Occluded" or "AlwaysOnTop"

			local cornerVisible = ESP.Drawing.Boxes.Corner.Enabled
			local cColor = ESP.Drawing.Boxes.Corner.RGB

			LeftTopHorizontal.Visible = cornerVisible
			LeftTopHorizontal.Position = UDim2.new(0, Pos.X - w / 2, 0, Pos.Y - h / 2 + verticalOffset)
			LeftTopHorizontal.Size = UDim2.new(0, dynamicCornerLength, 0, cornerThickness)
			LeftTopHorizontal.BackgroundColor3 = cColor

			LeftTopVertical.Visible = cornerVisible
			LeftTopVertical.Position = UDim2.new(0, Pos.X - w / 2, 0, Pos.Y - h / 2 + verticalOffset)
			LeftTopVertical.Size = UDim2.new(0, cornerThickness, 0, dynamicCornerLength)
			LeftTopVertical.BackgroundColor3 = cColor

			RightTopHorizontal.Visible = cornerVisible
			RightTopHorizontal.Position = UDim2.new(0, Pos.X + w / 2 - dynamicCornerLength, 0, Pos.Y - h / 2 + verticalOffset)
			RightTopHorizontal.Size = UDim2.new(0, dynamicCornerLength, 0, cornerThickness)
			RightTopHorizontal.BackgroundColor3 = cColor

			RightTopVertical.Visible = cornerVisible
			RightTopVertical.Position = UDim2.new(0, Pos.X + w / 2 - cornerThickness, 0, Pos.Y - h / 2 + verticalOffset)
			RightTopVertical.Size = UDim2.new(0, cornerThickness, 0, dynamicCornerLength)
			RightTopVertical.BackgroundColor3 = cColor

			LeftBottomHorizontal.Visible = cornerVisible
			LeftBottomHorizontal.Position = UDim2.new(0, Pos.X - w / 2, 0, Pos.Y + h / 2 + verticalOffset - cornerThickness)
			LeftBottomHorizontal.Size = UDim2.new(0, dynamicCornerLength, 0, cornerThickness)
			LeftBottomHorizontal.BackgroundColor3 = cColor

			LeftBottomVertical.Visible = cornerVisible
			LeftBottomVertical.Position = UDim2.new(0, Pos.X - w / 2, 0, Pos.Y + h / 2 + verticalOffset - dynamicCornerLength)
			LeftBottomVertical.Size = UDim2.new(0, cornerThickness, 0, dynamicCornerLength)
			LeftBottomVertical.BackgroundColor3 = cColor

			RightBottomHorizontal.Visible = cornerVisible
			RightBottomHorizontal.Position = UDim2.new(0, Pos.X + w / 2 - dynamicCornerLength, 0, Pos.Y + h / 2 + verticalOffset - cornerThickness)
			RightBottomHorizontal.Size = UDim2.new(0, dynamicCornerLength, 0, cornerThickness)
			RightBottomHorizontal.BackgroundColor3 = cColor

			RightBottomVertical.Visible = cornerVisible
			RightBottomVertical.Position = UDim2.new(0, Pos.X + w / 2 - cornerThickness, 0, Pos.Y + h / 2 + verticalOffset - dynamicCornerLength)
			RightBottomVertical.Size = UDim2.new(0, cornerThickness, 0, dynamicCornerLength)
			RightBottomVertical.BackgroundColor3 = cColor

			Box.Position = UDim2.new(0, Pos.X - w / 2, 0, Pos.Y - h / 2 + verticalOffset)
			Box.Size = UDim2.new(0, w, 0, h)

			local full = ESP.Drawing.Boxes.Full.Enabled
			local corner = ESP.Drawing.Boxes.Corner.Enabled
			local filled = ESP.Drawing.Boxes.Filled.Enabled

			Box.Visible = full or (corner and filled)

			if filled then
				Box.BackgroundTransparency = ESP.Drawing.Boxes.Filled.Transparency
			else
				Box.BackgroundTransparency = 1
			end

			Outline.Enabled = full and ESP.Drawing.Boxes.Gradient

			local CurrentTick = tick()
			local DeltaTime = CurrentTick - LastTick
			RotationAngle = RotationAngle
				+ DeltaTime * ESP.Drawing.Boxes.RotationSpeed * math.cos(math.pi / 4 * CurrentTick - math.pi / 2)

			if ESP.Drawing.Boxes.Animate then
				Gradient1.Rotation = RotationAngle
				Gradient2.Rotation = RotationAngle
			else
				Gradient1.Rotation = -45
				Gradient2.Rotation = -45
			end

			LastTick = CurrentTick

			Name.Visible = ESP.Drawing.Names.Enabled
			local nameText = CharacterModel.Name

			if ESP.Drawing.Distances.Enabled then
				nameText = string.format("%s [%d]", nameText, math.floor(Dist))
			end

			Name.Text = string.format('(<font color="rgb(%d, %d, %d)">T</font>) %s', 255, 255, 255, nameText)
			Name.TextColor3 = ESP.Drawing.Names.RGB
			Name.Position = UDim2.new(0, Pos.X, 0, Pos.Y - h / 2 - 9 + verticalOffset)

			Weapon.Visible = ESP.Drawing.Weapons.Enabled
			if ESP.Drawing.Weapons.Enabled then
				local weaponModel = findWeaponInCharacter(CharacterModel)
				if weaponModel then
					Weapon.Text = weaponModel.Name
					Weapon.TextColor3 = ESP.Drawing.Weapons.RGB
					Weapon.Position = UDim2.new(0, Pos.X, 0, Pos.Y + h / 2 + 9 + verticalOffset)
				else
					Weapon.Visible = false
				end
			end

			if ESP.Drawing.Skeleton.Enabled and not ActiveSkeletons[CharacterModel] then
				createSkeletonESP(CharacterModel)
			end
		else
			HideESP()
			Functions:RemoveSkeleton(CharacterModel)
		end
	end)
end

Functions.RefreshESPs = function()
	Functions:CleanAllESPs()
	local viewmodels = Workspace:FindFirstChild("Viewmodels")
	if not viewmodels then
		return
	end
	for _, model in pairs(viewmodels:GetChildren()) do
		if model:IsA("Model") then
			task.spawn(function()
				task.wait(0.1)
				CreateESP(model)
			end)
		end
	end
end

local function MonitorViewmodels()
	local viewmodels = Workspace:FindFirstChild("Viewmodels")
	if not viewmodels then
		return
	end

	for _, v in pairs(viewmodels:GetChildren()) do
		if v:IsA("Model") then
			task.spawn(function()
				task.wait(0.1)
				CreateESP(v)
			end)
		end
	end

	viewmodels.ChildAdded:Connect(function(v)
		if v:IsA("Model") then
			task.spawn(function()
				task.wait(0.2)
				CreateESP(v)
			end)
		end
	end)

	viewmodels.ChildRemoved:Connect(function(v)
		if ActiveESPs[v] then
			ActiveESPs[v]:Destroy()
			ActiveESPs[v] = nil
		end
		Functions:RemoveSkeleton(v)
	end)
end

MonitorViewmodels()

ESP.RefreshESPs = function()
	Functions.RefreshESPs()
end

ESP.CleanAllESPs = function()
	Functions:CleanAllESPs()
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
	if typeof(color) == "Color3" then
		ESP.Drawing.Skeleton.RGB = color
		for _, skeletonData in pairs(ActiveSkeletons) do
			if skeletonData and skeletonData.lines then
				for _, line in ipairs(skeletonData.lines) do
					line.Color = color
				end
			end
		end
	end
end

ESP.SetSkeletonThickness = function(thickness)
	if type(thickness) == "number" and thickness > 0 then
		ESP.Drawing.Skeleton.Thickness = thickness
		for _, skeletonData in pairs(ActiveSkeletons) do
			if skeletonData and skeletonData.lines then
				for _, line in ipairs(skeletonData.lines) do
					line.Thickness = thickness
				end
			end
		end
	end
end

ESP.SetCornerColor = function(color)
	if typeof(color) == "Color3" then
		ESP.Drawing.Boxes.Corner.RGB = color
	end
end

ESP.SetCornerThickness = function(thickness)
	if type(thickness) == "number" and thickness > 0 then
		ESP.Drawing.Boxes.Corner.Thickness = thickness
	end
end

ESP.SetCornerLength = function(length)
	if type(length) == "number" and length > 0 then
		ESP.Drawing.Boxes.Corner.Length = length
	end
end

return ESP
