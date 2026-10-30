--!strict
-- Shared prop builders for every unit layout. Every offset is relative to a parent CFrame, never a world position.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local COLOR_FLOOR = Color3.fromRGB(78, 62, 58)
local COLOR_WALL = Color3.fromRGB(70, 60, 92)
local COLOR_CYAN = Color3.fromRGB(125, 252, 208)
local COLOR_PINK = Color3.fromRGB(255, 79, 216)
local COLOR_AMBER = Color3.fromRGB(255, 184, 79)
local COLOR_SCREEN = Color3.fromRGB(11, 7, 22)
local COLOR_DESK = Color3.fromRGB(96, 70, 56)
local COLOR_BEZEL = Color3.fromRGB(28, 26, 34)
local COLOR_RACK = Color3.fromRGB(22, 22, 28)
local COLOR_SERVER = Color3.fromRGB(46, 46, 56)
local COLOR_COUCH = Color3.fromRGB(86, 70, 110)
local COLOR_ACCENT_DARK = Color3.fromRGB(40, 30, 60)

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local newPart = Instance.new("Part")
	newPart.Name = name
	newPart.Size = size
	newPart.CFrame = cframe
	newPart.Color = color
	newPart.Material = material
	newPart.Anchored = true
	newPart.TopSurface = Enum.SurfaceType.Smooth
	newPart.BottomSurface = Enum.SurfaceType.Smooth
	newPart.Parent = parent
	return newPart
end

local function screenLabel(target: BasePart, text: string, color: Color3)
	local gui = Instance.new("SurfaceGui")
	-- Screens are built facing their local +Z (into the room), which is a part's Back face.
	gui.Face = Enum.NormalId.Back
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = target

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = COLOR_SCREEN
	label.TextColor3 = color
	label.Font = Enum.Font.Code
	label.TextScaled = true
	label.Text = text
	label.Parent = gui
end

local function interactable(target: BasePart, tag: string, actionText: string, objectText: string)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = target
	CollectionService:AddTag(target, tag)
end

-- Building lights that only switch on at night. LightingController toggles everything with this tag.
local function nightLight(target: BasePart, color: Color3, range: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = 2
	light.Parent = target
	target:SetAttribute("NightColor", color)
	CollectionService:AddTag(target, "NightLight")
end

local function glow(target: BasePart, color: Color3, range: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = 1.5
	light.Parent = target
end

local function buildSibling(unit: Instance, cframe: CFrame): BasePart?
	local ok, model = pcall(function(): Model
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		-- Fallback stand-in so the sibling prompt always exists.
		local stand = part(unit, "Sibling", Vector3.new(2, 5, 1), cframe * CFrame.new(0, 2.5, 0), COLOR_AMBER, Enum.Material.SmoothPlastic)
		return stand
	end

	model.Name = "SiblingModel"
	model:PivotTo(cframe * CFrame.new(0, 3, 0))
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	model.Parent = unit
	return model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Small builders for the homelab props. Every offset is relative to a parent CFrame, never a world position.
local function cylinder(parent: Instance, name: string, length: number, diameter: number, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local newPart = part(parent, name, Vector3.new(length, diameter, diameter), cframe, color, material)
	newPart.Shape = Enum.PartType.Cylinder
	newPart.CanCollide = false
	return newPart
end

-- Tiny status LED; LightingController blinks everything tagged BlinkLed.
local function led(parent: Instance, cframe: CFrame, color: Color3)
	local light = part(parent, "Led", Vector3.new(0.15, 0.15, 0.05), cframe, color, Enum.Material.Neon)
	light.CanCollide = false
	light.CastShadow = false
	CollectionService:AddTag(light, "BlinkLed")
end

-- A screen part facing local +Z with text on it. Returns the screen.
local function monitor(parent: Instance, name: string, size: Vector2, cframe: CFrame, label: string, color: Color3): Part
	part(parent, name .. "Bezel", Vector3.new(size.X + 0.2, size.Y + 0.2, 0.15), cframe * CFrame.new(0, 0, -0.1), COLOR_BEZEL, Enum.Material.SmoothPlastic)
	local screen = part(parent, name, Vector3.new(size.X, size.Y, 0.1), cframe, COLOR_SCREEN, Enum.Material.Glass)
	screen.CanCollide = false
	screenLabel(screen, label, color)
	glow(screen, color, 8)
	-- Stand under the screen.
	part(parent, name .. "Stand", Vector3.new(0.3, 0.8, 0.3), cframe * CFrame.new(0, -size.Y / 2 - 0.4, -0.2), COLOR_BEZEL, Enum.Material.Metal)
	return screen
end

local function desk(parent: Instance, name: string, width: number, depth: number, cframe: CFrame): CFrame
	local topHeight = 3
	part(parent, name .. "Top", Vector3.new(width, 0.25, depth), cframe * CFrame.new(0, topHeight, 0), COLOR_DESK, Enum.Material.Wood)
	for _, x in { -width / 2 + 0.3, width / 2 - 0.3 } do
		for _, z in { -depth / 2 + 0.3, depth / 2 - 0.3 } do
			part(parent, name .. "Leg", Vector3.new(0.25, topHeight, 0.25), cframe * CFrame.new(x, topHeight / 2, z), COLOR_BEZEL, Enum.Material.Metal)
		end
	end
	return cframe * CFrame.new(0, topHeight + 0.125, 0) -- desk surface
end

-- The seat is a real Seat, disabled by default so walking into it doesn't sit you down.
-- BurstService enables it and seats the player for the length of a burst. It faces local -Z (the desk).
local function chair(parent: Instance, cframe: CFrame): Seat
	local seat = Instance.new("Seat")
	seat.Name = "ChairSeat"
	seat.Size = Vector3.new(2, 0.4, 2)
	seat.CFrame = cframe * CFrame.new(0, 1.8, 0)
	seat.Color = COLOR_ACCENT_DARK
	seat.Material = Enum.Material.Fabric
	seat.Anchored = true
	seat.Disabled = true
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.BottomSurface = Enum.SurfaceType.Smooth
	seat.Parent = parent
	part(parent, "ChairBack", Vector3.new(2, 2.6, 0.4), cframe * CFrame.new(0, 3.3, 0.9), COLOR_ACCENT_DARK, Enum.Material.Fabric)
	part(parent, "ChairStem", Vector3.new(0.3, 1.6, 0.3), cframe * CFrame.new(0, 0.8, 0), COLOR_BEZEL, Enum.Material.Metal)
	part(parent, "ChairBase", Vector3.new(1.8, 0.2, 1.8), cframe * CFrame.new(0, 0.1, 0), COLOR_BEZEL, Enum.Material.Metal)
	return seat
end

local function plant(parent: Instance, cframe: CFrame)
	part(parent, "PlantPot", Vector3.new(1.4, 1.4, 1.4), cframe * CFrame.new(0, 0.7, 0), Color3.fromRGB(150, 90, 70), Enum.Material.Slate)
	local leaves = part(parent, "PlantLeaves", Vector3.new(2.2, 2.6, 2.2), cframe * CFrame.new(0, 2.6, 0), Color3.fromRGB(70, 140, 80), Enum.Material.Grass)
	leaves.Shape = Enum.PartType.Ball
	leaves.CanCollide = false
end

-- A cutscene marker: an invisible, non-colliding part the CutsceneController aims cameras and places actors with.
-- Cameras look along the part's front (LookVector); actor markers sit at floor level facing where the actor faces.
local function marker(parent: Instance, name: string, cframe: CFrame)
	local point = part(parent, `Marker_{name}`, Vector3.new(1, 1, 1), cframe, COLOR_CYAN, Enum.Material.SmoothPlastic)
	point.Transparency = 1
	point.CanCollide = false
	point.CanQuery = false
	point.CanTouch = false
	point.CastShadow = false
	point:SetAttribute("Marker", name)
	CollectionService:AddTag(point, "CutsceneMarker")
end

return {
	part = part,
	screenLabel = screenLabel,
	interactable = interactable,
	nightLight = nightLight,
	glow = glow,
	buildSibling = buildSibling,
	cylinder = cylinder,
	led = led,
	monitor = monitor,
	desk = desk,
	chair = chair,
	plant = plant,
	marker = marker,
	COLOR_FLOOR = COLOR_FLOOR,
	COLOR_WALL = COLOR_WALL,
	COLOR_CYAN = COLOR_CYAN,
	COLOR_PINK = COLOR_PINK,
	COLOR_AMBER = COLOR_AMBER,
	COLOR_SCREEN = COLOR_SCREEN,
	COLOR_DESK = COLOR_DESK,
	COLOR_BEZEL = COLOR_BEZEL,
	COLOR_RACK = COLOR_RACK,
	COLOR_SERVER = COLOR_SERVER,
	COLOR_COUCH = COLOR_COUCH,
	COLOR_ACCENT_DARK = COLOR_ACCENT_DARK,
}
