
pcall(function() setthreadidentity(8) end)
pcall(function() game:GetService("WebViewService"):Destroy() end)

local cloneref = cloneref or function(o) return o end

local Workspace   = cloneref(game:GetService("Workspace"))
local RunService  = cloneref(game:GetService("RunService"))
local Players     = cloneref(game:GetService("Players"))
local CoreGui     = cloneref(game:GetService("CoreGui"))
local parentGui = (gethui and gethui()) or CoreGui
local Camera = Workspace.CurrentCamera

local ESP = {
	Enabled = false,
	MaxDistance = 1000,
	FontSize = 11,
	Drawing = {
		Names = {Enabled=false,RGB=Color3.fromRGB(255,255,255)},
		Weapons = {Enabled=false,RGB=Color3.fromRGB(255,255,255)},
		Chams = {
			Enabled=false,Thermal=false,
			FillRGB=Color3.fromRGB(243,116,166),
			Fill_Transparency=50,
			OutlineRGB=Color3.fromRGB(243,116,166),
			Outline_Transparency=50,
			VisibleCheck=false
		},
		Boxes = {
			Full={Enabled=false,RGB=Color3.fromRGB(255,255,255)},
			Filled={Enabled=false,Transparency=0.75,RGB=Color3.fromRGB(0,0,0)},
			Gradient=true,
			GradientRGB1=Color3.fromRGB(243,116,116),
			GradientRGB2=Color3.fromRGB(0,0,0),
			GradientFill=true,
			GradientFillRGB1=Color3.fromRGB(243,116,116),
			GradientFillRGB2=Color3.fromRGB(0,0,0),
			Animate=false,
			RotationSpeed=300,
			Corner={Enabled=false,RGB=Color3.fromRGB(255,255,255),Thickness=1,Length=15}
		},
		Skeleton={Enabled=false,RGB=Color3.fromRGB(255,255,255),Thickness=1},
		TeamCheck={Enabled=false}
	}
}

local ActiveESPs = {}
local ActiveSkeletons = {}

local BONE_CONNECTIONS = {
	{"torso","head"},{"torso","shoulder1"},{"torso","shoulder2"},
	{"shoulder1","arm1"},{"shoulder2","arm2"},
	{"torso","hip1"},{"torso","hip2"},
	{"hip1","leg1"},{"hip2","leg2"}
}

local function isValid(model)
	return model and model.Parent and model:FindFirstChild("torso")
end

local function hasHighlight(model)
	for _,v in pairs(Workspace:GetChildren()) do
		if v:IsA("Highlight") and v.Adornee==model then return true end
	end
end

local function findWeapon(model)
	for _,v in pairs(model:GetChildren()) do
		if v:IsA("Model") and v:GetAttribute("item_type") then return v end
	end
end

local function createESP(model)
	if ActiveESPs[model] or not isValid(model) then return end

    local folder = Instance.new("Folder", parentGui)

	local name = Instance.new("TextLabel",folder)
	name.BackgroundTransparency=1
	name.Font=Enum.Font.Code
	name.TextSize=ESP.FontSize
	name.TextStrokeTransparency=0
	name.AnchorPoint=Vector2.new(0.5,0.5)
	name.Size=UDim2.new(0,100,0,20)

	local weapon = name:Clone()
	weapon.Parent=folder

	local box = Instance.new("Frame",folder)
	box.BorderSizePixel=0

	local outline = Instance.new("UIStroke",box)
	local grad = Instance.new("UIGradient",outline)
	local fillGrad = Instance.new("UIGradient",box)

	local cham = Instance.new("Highlight",folder)

	-- corners
	local corners={}
	for i=1,8 do
		local c=Instance.new("Frame",folder)
		c.BorderSizePixel=0
		corners[i]=c
	end

	ActiveESPs[model]={
		Model=model,
		Torso=model:FindFirstChild("torso"),
		Name=name,Weapon=weapon,
		Box=box,Outline=outline,
		Gradient=grad,FillGradient=fillGrad,
		Cham=cham,Corners=corners,
		Rot=-45,Last=tick()
	}
end

local function createSkeleton(model)
	if ActiveSkeletons[model] or not isValid(model) then return end

	local bones={}
	for _,b in ipairs({"torso","head","shoulder1","shoulder2","arm1","arm2","hip1","hip2","leg1","leg2"}) do
		bones[b]=model:FindFirstChild(b)
	end

	local lines={}
	for i=1,#BONE_CONNECTIONS do
		local l=Drawing.new("Line")
		l.Visible=false
		lines[i]=l
	end

	ActiveSkeletons[model]={Bones=bones,Lines=lines,Last=0}
end

RunService.RenderStepped:Connect(function()
	if not ESP.Enabled then return end
	Camera=Workspace.CurrentCamera

	for model,data in pairs(ActiveESPs) do
		local torso=data.Torso
		if not torso or not model.Parent then continue end

		if ESP.Drawing.TeamCheck.Enabled and hasHighlight(model) then continue end

		local dist=(Camera.CFrame.Position-torso.Position).Magnitude
		if dist>ESP.MaxDistance then continue end

		local pos,onScreen=Camera:WorldToViewportPoint(torso.Position)
		if not onScreen then continue end

		local scale=(torso.Size.Y*Camera.ViewportSize.Y)/(pos.Z*2)
		local w,h=2.5*scale,4.75*scale

		-- FULL BOX
		data.Box.Size=UDim2.new(0,w,0,h)
		data.Box.Position=UDim2.new(0,pos.X-w/2,0,pos.Y-h/2)
		data.Box.Visible=ESP.Drawing.Boxes.Full.Enabled

		-- CORNERS
		local cl=ESP.Drawing.Boxes.Corner.Length
		local ct=ESP.Drawing.Boxes.Corner.Thickness
		local ccol=ESP.Drawing.Boxes.Corner.RGB

		for i,c in ipairs(data.Corners) do
			c.BackgroundColor3=ccol
			c.Visible=ESP.Drawing.Boxes.Corner.Enabled
		end

		-- simple corner positioning
		local x,y=pos.X,pos.Y
		local x1,y1=x-w/2,y-h/2
		local x2,y2=x+w/2,y+h/2

		-- 8 corners
		data.Corners[1].Position=UDim2.new(0,x1,0,y1)
		data.Corners[1].Size=UDim2.new(0,cl,0,ct)
		data.Corners[2].Position=UDim2.new(0,x1,0,y1)
		data.Corners[2].Size=UDim2.new(0,ct,0,cl)

		data.Corners[3].Position=UDim2.new(0,x2-cl,0,y1)
		data.Corners[3].Size=UDim2.new(0,cl,0,ct)
		data.Corners[4].Position=UDim2.new(0,x2-ct,0,y1)
		data.Corners[4].Size=UDim2.new(0,ct,0,cl)

		data.Corners[5].Position=UDim2.new(0,x1,0,y2-ct)
		data.Corners[5].Size=UDim2.new(0,cl,0,ct)
		data.Corners[6].Position=UDim2.new(0,x1,0,y2-cl)
		data.Corners[6].Size=UDim2.new(0,ct,0,cl)

		data.Corners[7].Position=UDim2.new(0,x2-cl,0,y2-ct)
		data.Corners[7].Size=UDim2.new(0,cl,0,ct)
		data.Corners[8].Position=UDim2.new(0,x2-ct,0,y2-cl)
		data.Corners[8].Size=UDim2.new(0,ct,0,cl)

		-- NAME + DIST
		if ESP.Drawing.Names.Enabled then
			data.Name.Text=model.Name.." ["..math.floor(dist).."]"
			data.Name.Position=UDim2.new(0,pos.X,0,y1-10)
			data.Name.TextColor3=ESP.Drawing.Names.RGB
			data.Name.Visible=true
		else data.Name.Visible=false end

		-- WEAPON
		if ESP.Drawing.Weapons.Enabled then
			local wpn=findWeapon(model)
			if wpn then
				data.Weapon.Text=wpn.Name
				data.Weapon.Position=UDim2.new(0,pos.X,0,y2+10)
				data.Weapon.Visible=true
			end
		else data.Weapon.Visible=false end

		-- CHAMS
		local c=data.Cham
		c.Adornee=model
		c.Enabled=ESP.Drawing.Chams.Enabled
		c.FillColor=ESP.Drawing.Chams.FillRGB
		c.OutlineColor=ESP.Drawing.Chams.OutlineRGB
		c.DepthMode=ESP.Drawing.Chams.VisibleCheck and "Occluded" or "AlwaysOnTop"

		if ESP.Drawing.Chams.Thermal then
			local breathe=math.sin(tick()*2)
			c.FillTransparency=(ESP.Drawing.Chams.Fill_Transparency/100)*(1-breathe*0.1)
		end

		-- SKELETON
		if ESP.Drawing.Skeleton.Enabled and not ActiveSkeletons[model] then
			createSkeleton(model)
		end
	end

	-- skeleton update
	for model,sk in pairs(ActiveSkeletons) do
		if tick()-sk.Last<0.03 then continue end
		sk.Last=tick()

		for i,conn in ipairs(BONE_CONNECTIONS) do
			local b1=sk.Bones[conn[1]]
			local b2=sk.Bones[conn[2]]
			local l=sk.Lines[i]

			if b1 and b2 then
				local p1,v1=Camera:WorldToViewportPoint(b1.Position)
				local p2,v2=Camera:WorldToViewportPoint(b2.Position)
				if v1 and v2 then
					l.From=Vector2.new(p1.X,p1.Y)
					l.To=Vector2.new(p2.X,p2.Y)
					l.Visible=true
					l.Color=ESP.Drawing.Skeleton.RGB
					l.Thickness=ESP.Drawing.Skeleton.Thickness
				else l.Visible=false end
			end
		end
	end
end)

-- monitor
local function monitor()
	local vm=Workspace:FindFirstChild("Viewmodels")
	if not vm then return end
	for _,m in pairs(vm:GetChildren()) do createESP(m) end
	vm.ChildAdded:Connect(createESP)
	vm.ChildRemoved:Connect(function(m)
		ActiveESPs[m]=nil
		ActiveSkeletons[m]=nil
	end)
end

monitor()

-- API
function ESP.RefreshESPs()
	for _,v in pairs(ActiveESPs) do v.Name.Parent:Destroy() end
	ActiveESPs={}
	monitor()
end

function ESP.CleanAllESPs()
	for _,v in pairs(ActiveESPs) do v.Name.Parent:Destroy() end
	ActiveESPs={}
end

function ESP.ToggleSkeleton(e) ESP.Drawing.Skeleton.Enabled=e end
function ESP.SetSkeletonColor(c) ESP.Drawing.Skeleton.RGB=c end
function ESP.SetSkeletonThickness(t) ESP.Drawing.Skeleton.Thickness=t end
function ESP.SetCornerColor(c) ESP.Drawing.Boxes.Corner.RGB=c end
function ESP.SetCornerThickness(t) ESP.Drawing.Boxes.Corner.Thickness=t end
function ESP.SetCornerLength(l) ESP.Drawing.Boxes.Corner.Length=l end

return ESP
