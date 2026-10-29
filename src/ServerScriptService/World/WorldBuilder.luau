--!strict
-- Code-built blockout of the megablock floor. Only built-in parts and materials, so the game runs with no uploaded art.
-- Gameplay code finds objects by CollectionService tag and attributes, never by geometry, so art can replace this later.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local UNIT_SIZE = 44
local UNIT_GAP = 8
local WALL_HEIGHT = 16
local UNITS_PER_ROW = 3
local CORRIDOR_WIDTH = 24

local COLOR_FLOOR = Color3.fromRGB(18, 12, 30)
local COLOR_WALL = Color3.fromRGB(32, 22, 52)
local COLOR_CYAN = Color3.fromRGB(125, 252, 208)
local COLOR_PINK = Color3.fromRGB(255, 79, 216)
local COLOR_AMBER = Color3.fromRGB(255, 184, 79)
local COLOR_SCREEN = Color3.fromRGB(11, 7, 22)
local COLOR_FURNITURE = Color3.fromRGB(60, 48, 70)

local WorldBuilder = {}

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

local function glow(target: BasePart, color: Color3, range: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = 1.5
	light.Parent = target
end

-- A desk with a screen facing the room. Returns the screen, which carries the prompt.
local function terminal(unit: Model, name: string, origin: CFrame, label: string, color: Color3): Part
	part(unit, name .. "Desk", Vector3.new(6, 3, 3), origin * CFrame.new(0, 1.5, 0), COLOR_FURNITURE, Enum.Material.Metal)
	local screen = part(unit, name, Vector3.new(4.5, 2.6, 0.3), origin * CFrame.new(0, 4.6, 0.6), COLOR_SCREEN, Enum.Material.Glass)
	screenLabel(screen, label, color)
	glow(screen, color, 10)
	return screen
end

local function buildSibling(unit: Model, cframe: CFrame): BasePart?
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

local function buildUnit(floor: Folder, index: number, origin: CFrame): Model
	local unit = Instance.new("Model")
	unit.Name = `Unit{index}`
	unit:SetAttribute("Unit", index)
	unit.Parent = floor

	local half = UNIT_SIZE / 2
	part(unit, "Floor", Vector3.new(UNIT_SIZE, 1, UNIT_SIZE), origin * CFrame.new(0, -0.5, 0), COLOR_FLOOR, Enum.Material.SmoothPlastic)
	part(unit, "BackWall", Vector3.new(UNIT_SIZE, WALL_HEIGHT, 1), origin * CFrame.new(0, WALL_HEIGHT / 2, -half), COLOR_WALL, Enum.Material.Concrete)
	part(unit, "LeftWall", Vector3.new(1, WALL_HEIGHT, UNIT_SIZE), origin * CFrame.new(-half, WALL_HEIGHT / 2, 0), COLOR_WALL, Enum.Material.Concrete)
	part(unit, "RightWall", Vector3.new(1, WALL_HEIGHT, UNIT_SIZE), origin * CFrame.new(half, WALL_HEIGHT / 2, 0), COLOR_WALL, Enum.Material.Concrete)
	local trim = part(unit, "NeonTrim", Vector3.new(UNIT_SIZE, 0.4, 0.4), origin * CFrame.new(0, WALL_HEIGHT - 0.5, -half + 0.8), COLOR_PINK, Enum.Material.Neon)
	glow(trim, COLOR_PINK, 24)

	-- Act 1: the sibling's couch and a folding table.
	part(unit, "Couch", Vector3.new(10, 2.5, 4), origin * CFrame.new(-10, 1.25, 12), COLOR_FURNITURE, Enum.Material.Fabric)
	part(unit, "CouchBack", Vector3.new(10, 3, 1), origin * CFrame.new(-10, 2.5, 14), COLOR_FURNITURE, Enum.Material.Fabric)
	part(unit, "FoldingTable", Vector3.new(6, 0.4, 3), origin * CFrame.new(4, 3, 10), Color3.fromRGB(120, 110, 100), Enum.Material.Plastic)

	-- Four workstations along the back wall, one per component.
	for slot, component in GameConfig.COMPONENTS do
		local x = -half + 6 + (slot - 1) * ((UNIT_SIZE - 12) / 3)
		local stationOrigin = origin * CFrame.new(x, 0, -half + 4)
		local screen = terminal(unit, `Station_{component}`, stationOrigin, GameConfig.STATION_NAMES[component], COLOR_CYAN)
		screen:SetAttribute("Component", component)
		interactable(screen, "Station", "Build", GameConfig.STATION_NAMES[component])
	end

	local deploy = terminal(unit, "DeployTerminal", origin * CFrame.new(12, 0, 4) * CFrame.Angles(0, math.rad(-90), 0), "DEPLOY", COLOR_PINK)
	interactable(deploy, "DeployTerminal", "Ship it", "Deploy Terminal")

	local shop = part(unit, "ShopComputer", Vector3.new(2, 1.4, 0.2), origin * CFrame.new(4, 3.9, 10), COLOR_SCREEN, Enum.Material.Glass)
	screenLabel(shop, "SHOP", COLOR_AMBER)
	interactable(shop, "ShopComputer", "Browse", "Laptop")

	local phone = part(unit, "JobPhone", Vector3.new(0.6, 0.15, 1.1), origin * CFrame.new(-6, 2.6, 12), COLOR_SCREEN, Enum.Material.Glass)
	glow(phone, COLOR_CYAN, 6)
	interactable(phone, "JobPhone", "Check jobs", "Phone")

	local siblingRoot = buildSibling(unit, origin * CFrame.new(-14, 0, 2) * CFrame.Angles(0, math.rad(90), 0))
	if siblingRoot then
		interactable(siblingRoot, "Sibling", "Talk", "Your Sibling")
	end

	local spawnPad = part(unit, "UnitSpawn", Vector3.new(4, 0.2, 4), origin * CFrame.new(0, 0.1, 6), COLOR_FLOOR, Enum.Material.SmoothPlastic)
	spawnPad.Transparency = 1
	spawnPad.CanCollide = false
	CollectionService:AddTag(spawnPad, "UnitSpawn")

	return unit
end

local function applyLighting()
	Lighting.ClockTime = 0
	Lighting.Brightness = 1
	Lighting.Ambient = Color3.fromRGB(40, 25, 60)
	Lighting.OutdoorAmbient = Color3.fromRGB(30, 20, 50)
	Lighting.FogColor = Color3.fromRGB(20, 10, 35)

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.35
	atmosphere.Color = Color3.fromRGB(120, 60, 160)
	atmosphere.Decay = Color3.fromRGB(40, 20, 70)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 2
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.8
	bloom.Size = 30
	bloom.Threshold = 0.9
	bloom.Parent = Lighting

	local grade = Instance.new("ColorCorrectionEffect")
	grade.TintColor = Color3.fromRGB(235, 220, 255)
	grade.Contrast = 0.15
	grade.Saturation = 0.1
	grade.Parent = Lighting
end

function WorldBuilder.BuildFloor(): { Model }
	local floor = Instance.new("Folder")
	floor.Name = "Megablock"
	floor.Parent = Workspace

	local rows = math.ceil(GameConfig.MAX_PLAYERS / UNITS_PER_ROW)
	local rowWidth = UNITS_PER_ROW * UNIT_SIZE + (UNITS_PER_ROW - 1) * UNIT_GAP
	part(
		floor,
		"Corridor",
		Vector3.new(rowWidth + 20, 1, rows * UNIT_SIZE + CORRIDOR_WIDTH + 20),
		CFrame.new(0, -1.5, 0),
		Color3.fromRGB(12, 8, 20),
		Enum.Material.Concrete
	)

	local units: { Model } = {}
	for index = 1, GameConfig.MAX_PLAYERS do
		local column = (index - 1) % UNITS_PER_ROW
		local row = (index - 1) // UNITS_PER_ROW
		local x = -rowWidth / 2 + UNIT_SIZE / 2 + column * (UNIT_SIZE + UNIT_GAP)
		local z = (UNIT_SIZE + CORRIDOR_WIDTH) / 2
		-- Row 0 faces +z into the corridor, row 1 faces -z, so open fronts look at each other.
		local origin = if row == 0
			then CFrame.new(x, 0, -z)
			else CFrame.new(x, 0, z) * CFrame.Angles(0, math.pi, 0)
		table.insert(units, buildUnit(floor, index, origin))
	end

	applyLighting()
	return units
end

return WorldBuilder
