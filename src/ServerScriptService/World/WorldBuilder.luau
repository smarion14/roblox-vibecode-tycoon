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
-- The whole floor sits this high so nothing shares a surface with the place's default Baseplate (top at y = 0),
-- which caused z-fighting. The corridor is half a stud lower than the unit floors for the same reason.
local FLOOR_Y = 3
local CORRIDOR_DROP = 0.5

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

local function chair(parent: Instance, cframe: CFrame)
	part(parent, "ChairSeat", Vector3.new(2, 0.4, 2), cframe * CFrame.new(0, 1.8, 0), COLOR_ACCENT_DARK, Enum.Material.Fabric)
	part(parent, "ChairBack", Vector3.new(2, 2.6, 0.4), cframe * CFrame.new(0, 3.3, 0.9), COLOR_ACCENT_DARK, Enum.Material.Fabric)
	part(parent, "ChairStem", Vector3.new(0.3, 1.6, 0.3), cframe * CFrame.new(0, 0.8, 0), COLOR_BEZEL, Enum.Material.Metal)
	part(parent, "ChairBase", Vector3.new(1.8, 0.2, 1.8), cframe * CFrame.new(0, 0.1, 0), COLOR_BEZEL, Enum.Material.Metal)
end

local function plant(parent: Instance, cframe: CFrame)
	part(parent, "PlantPot", Vector3.new(1.4, 1.4, 1.4), cframe * CFrame.new(0, 0.7, 0), Color3.fromRGB(150, 90, 70), Enum.Material.Slate)
	local leaves = part(parent, "PlantLeaves", Vector3.new(2.2, 2.6, 2.2), cframe * CFrame.new(0, 2.6, 0), Color3.fromRGB(70, 140, 80), Enum.Material.Grass)
	leaves.Shape = Enum.PartType.Ball
	leaves.CanCollide = false
end

-- Frontend: a desk with dual monitors, keyboard, energy drinks and a gaming chair.
local function buildFrontendStation(unit: Model, base: CFrame): Part
	local surface = desk(unit, "FrontendDesk", 7, 3, base)
	local screen = monitor(unit, "Station_FrontendUnits", Vector2.new(3, 1.8), surface * CFrame.new(-1.6, 1.3, -0.6) * CFrame.Angles(0, math.rad(12), 0), GameConfig.STATION_NAMES.FrontendUnits, COLOR_CYAN)
	monitor(unit, "FrontendSide", Vector2.new(3, 1.8), surface * CFrame.new(1.7, 1.3, -0.6) * CFrame.Angles(0, math.rad(-12), 0), "</>  ui.tsx", COLOR_PINK)
	part(unit, "Keyboard", Vector3.new(2.4, 0.12, 0.8), surface * CFrame.new(0, 0.06, 0.6), COLOR_BEZEL, Enum.Material.SmoothPlastic)
	local glowStrip = part(unit, "KeyboardRgb", Vector3.new(2.4, 0.04, 0.8), surface * CFrame.new(0, 0.14, 0.6), COLOR_CYAN, Enum.Material.Neon)
	glowStrip.Transparency = 0.6
	part(unit, "Mouse", Vector3.new(0.3, 0.15, 0.5), surface * CFrame.new(1.6, 0.08, 0.6), COLOR_BEZEL, Enum.Material.SmoothPlastic)
	for index = 1, 3 do
		cylinder(unit, "EnergyCan", 0.7, 0.4, surface * CFrame.new(-3 + index * 0.45, 0.35, 0.9) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(80, 230, 120), Enum.Material.Metal)
	end
	chair(unit, base * CFrame.new(0, 0, 3))
	return screen
end

-- Backend: a tall rack cabinet of servers with blinking LEDs, patch cables and a KVM screen.
local function buildServerRack(unit: Model, base: CFrame): Part
	local width, height, depth = 3.6, 9, 3.4
	part(unit, "RackCabinet", Vector3.new(width, height, depth), base * CFrame.new(0, height / 2, 0), COLOR_RACK, Enum.Material.DiamondPlate)
	for slot = 1, 7 do
		local y = 0.8 + slot * 1.05
		local server = part(unit, "RackServer", Vector3.new(width - 0.4, 0.8, 0.2), base * CFrame.new(0, y, depth / 2 + 0.05), COLOR_SERVER, Enum.Material.Metal)
		server.CanCollide = false
		for bay = 1, 4 do
			led(unit, base * CFrame.new(-1.2 + bay * 0.35, y + 0.15, depth / 2 + 0.18), if bay % 2 == 0 then COLOR_CYAN else Color3.fromRGB(120, 255, 120))
		end
		-- Patch cables hanging from each server.
		local cable = part(unit, "PatchCable", Vector3.new(0.08, 0.8, 0.08), base * CFrame.new(1.2, y - 0.4, depth / 2 + 0.2), if slot % 2 == 0 then COLOR_PINK else COLOR_AMBER, Enum.Material.SmoothPlastic)
		cable.CanCollide = false
	end
	local screen = monitor(unit, "Station_BackendEndpoints", Vector2.new(2.4, 1.4), base * CFrame.new(0, 4.6, depth / 2 + 0.5), GameConfig.STATION_NAMES.BackendEndpoints, COLOR_CYAN)
	return screen
end

-- Database: a wire shelf with a NAS full of drive bays and a small console monitor.
local function buildDatabaseShelf(unit: Model, base: CFrame): Part
	local width, depth = 4, 2.4
	for _, x in { -width / 2, width / 2 } do
		for _, z in { -depth / 2, depth / 2 } do
			part(unit, "ShelfPost", Vector3.new(0.15, 7, 0.15), base * CFrame.new(x, 3.5, z), COLOR_BEZEL, Enum.Material.Metal)
		end
	end
	for _, y in { 0.6, 3.2, 6 } do
		part(unit, "ShelfBoard", Vector3.new(width, 0.12, depth), base * CFrame.new(0, y, 0), COLOR_BEZEL, Enum.Material.Metal)
	end
	-- NAS on the bottom shelf.
	part(unit, "Nas", Vector3.new(2.6, 1.6, 2), base * CFrame.new(0, 1.46, 0), COLOR_SERVER, Enum.Material.SmoothPlastic)
	for bay = 1, 4 do
		part(unit, "DriveBay", Vector3.new(0.5, 1.2, 0.05), base * CFrame.new(-1.05 + (bay - 1) * 0.7, 1.46, 1.02), COLOR_RACK, Enum.Material.Metal)
		led(unit, base * CFrame.new(-1.05 + (bay - 1) * 0.7, 1.95, 1.08), COLOR_AMBER)
	end
	-- External drives stacked on the top shelf.
	for index = 1, 3 do
		part(unit, "ExternalDrive", Vector3.new(1, 0.3, 1.4), base * CFrame.new(-0.8, 6.2 + index * 0.32, 0), COLOR_RACK, Enum.Material.SmoothPlastic)
	end
	local screen = monitor(unit, "Station_DatabaseTables", Vector2.new(2.4, 1.4), base * CFrame.new(0, 4.3, 0.4), GameConfig.STATION_NAMES.DatabaseTables, COLOR_CYAN)
	return screen
end

-- AI: an open-frame GPU rig with glowing cards and fans, plus its monitor.
local function buildAiRig(unit: Model, base: CFrame): Part
	local surface = desk(unit, "AiDesk", 5, 3, base)
	local frameW, frameH, frameD = 4, 2.2, 2
	for _, x in { -frameW / 2, frameW / 2 } do
		for _, z in { -frameD / 2, frameD / 2 } do
			part(unit, "RigFrame", Vector3.new(0.12, frameH, 0.12), surface * CFrame.new(x, frameH / 2, z - 0.2), COLOR_BEZEL, Enum.Material.Metal)
		end
	end
	part(unit, "RigTop", Vector3.new(frameW, 0.1, frameD), surface * CFrame.new(0, frameH, -0.2), COLOR_BEZEL, Enum.Material.Metal)
	for card = 1, 4 do
		local x = -1.5 + (card - 1)
		local gpu = part(unit, "Gpu", Vector3.new(0.35, 1.4, 1.8), surface * CFrame.new(x, 1.2, -0.2), COLOR_SERVER, Enum.Material.Metal)
		gpu.CanCollide = false
		local edge = part(unit, "GpuGlow", Vector3.new(0.05, 1.4, 1.8), surface * CFrame.new(x + 0.2, 1.2, -0.2), if card % 2 == 0 then COLOR_PINK else COLOR_CYAN, Enum.Material.Neon)
		edge.CanCollide = false
		cylinder(unit, "GpuFan", 0.1, 0.9, surface * CFrame.new(x - 0.2, 1.2, 0.3), COLOR_RACK, Enum.Material.SmoothPlastic)
	end
	local screen = monitor(unit, "Station_PromptTokens", Vector2.new(3, 1.6), surface * CFrame.new(0, frameH + 1.1, -0.3), GameConfig.STATION_NAMES.PromptTokens, COLOR_CYAN)
	return screen
end

-- Deploy: a standing desk with an ultrawide screen and a big ship button.
local function buildDeployDesk(unit: Model, base: CFrame): Part
	part(unit, "StandingDeskTop", Vector3.new(7, 0.25, 2.6), base * CFrame.new(0, 3.8, 0), COLOR_DESK, Enum.Material.Wood)
	for _, x in { -3, 3 } do
		part(unit, "StandingDeskLeg", Vector3.new(0.4, 3.8, 1.6), base * CFrame.new(x, 1.9, 0), COLOR_BEZEL, Enum.Material.Metal)
	end
	local screen = monitor(unit, "DeployTerminal", Vector2.new(5.6, 2), base * CFrame.new(0, 5.6, -0.6), "DEPLOY", COLOR_PINK)
	part(unit, "ShipButtonBase", Vector3.new(0.9, 0.2, 0.9), base * CFrame.new(2.6, 4, 0.6), COLOR_BEZEL, Enum.Material.Metal)
	local button = cylinder(unit, "ShipButton", 0.3, 0.7, base * CFrame.new(2.6, 4.2, 0.6) * CFrame.Angles(0, 0, math.rad(90)), COLOR_PINK, Enum.Material.Neon)
	button.CastShadow = false
	return screen
end

-- Lounge: the sibling's couch, a rug, coffee table with the laptop, and the phone on the couch arm.
local function buildLounge(unit: Model, base: CFrame): (Part, Part)
	part(unit, "Rug", Vector3.new(14, 0.05, 9), base * CFrame.new(0, 0.03, -2), Color3.fromRGB(70, 50, 90), Enum.Material.Fabric).CanCollide = false
	part(unit, "Couch", Vector3.new(10, 1.8, 3.6), base * CFrame.new(0, 0.9, 1.5), COLOR_COUCH, Enum.Material.Fabric)
	part(unit, "CouchCushion", Vector3.new(9.4, 0.5, 3), base * CFrame.new(0, 2.05, 1.3), COLOR_COUCH:Lerp(Color3.new(1, 1, 1), 0.08), Enum.Material.Fabric)
	part(unit, "CouchBack", Vector3.new(10, 2.6, 1), base * CFrame.new(0, 2.6, 3.3), COLOR_COUCH, Enum.Material.Fabric)
	part(unit, "CouchArmLeft", Vector3.new(0.9, 2.6, 3.6), base * CFrame.new(-5, 1.3, 1.5), COLOR_COUCH, Enum.Material.Fabric)
	part(unit, "CouchArmRight", Vector3.new(0.9, 2.6, 3.6), base * CFrame.new(5, 1.3, 1.5), COLOR_COUCH, Enum.Material.Fabric)
	-- Low coffee table in front of the couch.
	local tray = base * CFrame.new(0, 1.6, -3.5)
	part(unit, "CoffeeTable", Vector3.new(5.2, 0.2, 2.6), tray, COLOR_DESK, Enum.Material.Wood)
	for _, x in { -2.3, 2.3 } do
		for _, z in { -1, 1 } do
			part(unit, "CoffeeTableLeg", Vector3.new(0.25, 1.5, 0.25), tray * CFrame.new(x, -0.85, z), COLOR_BEZEL, Enum.Material.Metal)
		end
	end
	part(unit, "LaptopBase", Vector3.new(1.8, 0.1, 1.2), tray * CFrame.new(0, 0.15, 0.2), COLOR_BEZEL, Enum.Material.SmoothPlastic)
	local laptop = part(unit, "ShopComputer", Vector3.new(1.8, 1.1, 0.08), tray * CFrame.new(0, 0.75, -0.4) * CFrame.Angles(math.rad(-12), 0, 0), COLOR_SCREEN, Enum.Material.Glass)
	screenLabel(laptop, "SHOP", COLOR_AMBER)
	glow(laptop, COLOR_AMBER, 6)
	local phone = part(unit, "JobPhone", Vector3.new(0.6, 0.12, 1.1), base * CFrame.new(5, 2.67, 1.2), COLOR_SCREEN, Enum.Material.Glass)
	glow(phone, COLOR_CYAN, 6)
	return laptop, phone
end

-- Decor: bookshelf with a router, mini fridge, whiteboard, plants and a cable run across the floor.
local function buildDecor(unit: Model, origin: CFrame, half: number)
	-- Bookshelf against the left wall.
	local shelf = origin * CFrame.new(-half + 1.4, 0, -4) * CFrame.Angles(0, math.rad(90), 0)
	part(unit, "Bookshelf", Vector3.new(5, 7, 1.8), shelf * CFrame.new(0, 3.5, 0), COLOR_DESK, Enum.Material.Wood)
	local bookColors = { COLOR_PINK, COLOR_CYAN, COLOR_AMBER, Color3.fromRGB(120, 110, 220), Color3.fromRGB(220, 90, 90) }
	for row = 1, 3 do
		for slot = 1, 8 do
			local book = part(unit, "Book", Vector3.new(0.4, 1.3, 1.2), shelf * CFrame.new(-2 + slot * 0.5, row * 2.1 - 0.4, 0.4), bookColors[(row + slot) % #bookColors + 1], Enum.Material.SmoothPlastic)
			book.CanCollide = false
		end
	end
	-- Router on top with antennas and blinking lights.
	local router = shelf * CFrame.new(0, 7, 0)
	part(unit, "Router", Vector3.new(1.8, 0.4, 1.2), router * CFrame.new(0, 0.2, 0), COLOR_SERVER, Enum.Material.SmoothPlastic)
	for index = -1, 1 do
		part(unit, "Antenna", Vector3.new(0.1, 1.2, 0.1), router * CFrame.new(index * 0.7, 0.9, -0.4) * CFrame.Angles(math.rad(-10), 0, math.rad(index * 12)), COLOR_BEZEL, Enum.Material.SmoothPlastic).CanCollide = false
		led(unit, router * CFrame.new(index * 0.4, 0.25, 0.62), Color3.fromRGB(120, 255, 120))
	end

	-- Mini fridge with a little glow.
	part(unit, "MiniFridge", Vector3.new(2.4, 3.4, 2.4), origin * CFrame.new(-half + 2, 1.7, 8), Color3.fromRGB(200, 200, 210), Enum.Material.SmoothPlastic)

	-- Whiteboard on the right wall with the plan for the month.
	local board = part(unit, "Whiteboard", Vector3.new(0.2, 4, 7), origin * CFrame.new(half - 0.7, 7, -10), Color3.fromRGB(240, 240, 245), Enum.Material.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Left
	gui.PixelsPerStud = 30
	gui.Parent = board
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.fromRGB(30, 30, 60)
	text.Font = Enum.Font.PermanentMarker
	text.TextScaled = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Text = "TODO\n1. ship apps\n2. PAY RENT\n3. sleep???"
	text.Parent = gui

	plant(unit, origin * CFrame.new(half - 2.5, 0, -half + 2.5))
	plant(unit, origin * CFrame.new(-half + 2.5, 0, half - 3))

	-- Cable run from the rack along the back wall: the homelab tax.
	local cable = part(unit, "CableRun", Vector3.new(UNIT_SIZE - 6, 0.25, 0.4), origin * CFrame.new(0, 0.13, -half + 1.2), COLOR_BEZEL, Enum.Material.SmoothPlastic)
	cable.CanCollide = false

	-- Desk-lamp style accent strip under the back trim that glows all day.
	local strip = part(unit, "LedStrip", Vector3.new(UNIT_SIZE - 4, 0.15, 0.15), origin * CFrame.new(0, 9, -half + 0.6), COLOR_PINK, Enum.Material.Neon)
	strip.Transparency = 0.3
	strip.CanCollide = false
end

local function buildUnit(floor: Folder, index: number, origin: CFrame): Model
	local unit = Instance.new("Model")
	unit.Name = `Unit{index}`
	unit:SetAttribute("Unit", index)
	unit.Parent = floor

	local half = UNIT_SIZE / 2
	part(unit, "Floor", Vector3.new(UNIT_SIZE, 1, UNIT_SIZE), origin * CFrame.new(0, -0.5, 0), COLOR_FLOOR, Enum.Material.WoodPlanks)
	part(unit, "BackWall", Vector3.new(UNIT_SIZE, WALL_HEIGHT, 1), origin * CFrame.new(0, WALL_HEIGHT / 2, -half), COLOR_WALL, Enum.Material.Plaster)
	part(unit, "LeftWall", Vector3.new(1, WALL_HEIGHT, UNIT_SIZE), origin * CFrame.new(-half, WALL_HEIGHT / 2, 0), COLOR_WALL, Enum.Material.Plaster)
	part(unit, "RightWall", Vector3.new(1, WALL_HEIGHT, UNIT_SIZE), origin * CFrame.new(half, WALL_HEIGHT / 2, 0), COLOR_WALL, Enum.Material.Plaster)
	local trim = part(unit, "NeonTrim", Vector3.new(UNIT_SIZE, 0.4, 0.4), origin * CFrame.new(0, WALL_HEIGHT - 0.5, -half + 0.8), COLOR_PINK, Enum.Material.Neon)
	nightLight(trim, COLOR_PINK, 24)
	local leftTrim = part(unit, "NeonTrimLeft", Vector3.new(0.4, 0.4, UNIT_SIZE), origin * CFrame.new(-half + 0.8, WALL_HEIGHT - 0.5, 0), COLOR_CYAN, Enum.Material.Neon)
	nightLight(leftTrim, COLOR_CYAN, 18)
	local rightTrim = part(unit, "NeonTrimRight", Vector3.new(0.4, 0.4, UNIT_SIZE), origin * CFrame.new(half - 0.8, WALL_HEIGHT - 0.5, 0), COLOR_CYAN, Enum.Material.Neon)
	nightLight(rightTrim, COLOR_CYAN, 18)
	-- Sign over the open front, lit at night.
	local sign = part(unit, "UnitSign", Vector3.new(14, 2, 0.4), origin * CFrame.new(0, WALL_HEIGHT + 1.5, half - 1), COLOR_AMBER, Enum.Material.Neon)
	nightLight(sign, COLOR_AMBER, 20)

	-- Act 1: a homelab squeezed into the sibling's living room. Four stations along the back wall, one per component.
	local back = origin * CFrame.new(0, 0, -half + 3)
	local stationBuilders: { [string]: (Model, CFrame) -> Part } = {
		FrontendUnits = buildFrontendStation,
		BackendEndpoints = buildServerRack,
		DatabaseTables = buildDatabaseShelf,
		PromptTokens = buildAiRig,
	}
	for slot, component in GameConfig.COMPONENTS do
		local x = -half + 6 + (slot - 1) * ((UNIT_SIZE - 12) / 3)
		local screen = stationBuilders[component](unit, back * CFrame.new(x, 0, 0))
		screen:SetAttribute("Component", component)
		interactable(screen, "Station", "Build", GameConfig.STATION_NAMES[component])
	end

	local deploy = buildDeployDesk(unit, origin * CFrame.new(half - 3, 0, 4) * CFrame.Angles(0, math.rad(-90), 0))
	interactable(deploy, "DeployTerminal", "Ship it", "Deploy Terminal")

	local laptop, phone = buildLounge(unit, origin * CFrame.new(-8, 0, 10))
	interactable(laptop, "ShopComputer", "Browse", "Laptop")
	interactable(phone, "JobPhone", "Check jobs", "Phone")

	buildDecor(unit, origin, half)

	local siblingRoot = buildSibling(unit, origin * CFrame.new(-16, 0, 4) * CFrame.Angles(0, math.rad(90), 0))
	if siblingRoot then
		interactable(siblingRoot, "Sibling", "Talk", "Your Sibling")
	end

	local spawnPad = part(unit, "UnitSpawn", Vector3.new(4, 0.2, 4), origin * CFrame.new(4, 0.1, 6), COLOR_FLOOR, Enum.Material.SmoothPlastic)
	spawnPad.Transparency = 1
	spawnPad.CanCollide = false
	CollectionService:AddTag(spawnPad, "UnitSpawn")

	return unit
end

-- Corridor street lamps between the two rows of units, lit at night.
local function buildLamps(floor: Folder, rowWidth: number)
	local count = 6
	for index = 1, count do
		local x = -rowWidth / 2 + (index - 0.5) * (rowWidth / count)
		local ground = FLOOR_Y - CORRIDOR_DROP
		part(floor, "LampPost", Vector3.new(0.6, 12, 0.6), CFrame.new(x, ground + 6, 0), COLOR_BEZEL, Enum.Material.Metal)
		local head = part(floor, "LampHead", Vector3.new(2.4, 0.6, 2.4), CFrame.new(x, ground + 12.2, 0), COLOR_CYAN, Enum.Material.Neon)
		nightLight(head, Color3.fromRGB(200, 230, 255), 32)
	end
end

-- Starting values only: LightingController on each client drives the day/night cycle from here.
local function applyLighting()
	Lighting.ClockTime = GameConfig.DAY_CYCLE.StartClock
	Lighting.Brightness = 2.5
	Lighting.GlobalShadows = true
	Lighting.Ambient = Color3.fromRGB(120, 112, 135)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 132, 155)

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.25
	atmosphere.Color = Color3.fromRGB(205, 185, 225)
	atmosphere.Decay = Color3.fromRGB(150, 120, 190)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 1.2
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
	local corridorTop = FLOOR_Y - CORRIDOR_DROP
	local corridorBottom = 0.05
	part(
		floor,
		"Corridor",
		Vector3.new(rowWidth + 20, corridorTop - corridorBottom, rows * UNIT_SIZE + CORRIDOR_WIDTH + 20),
		CFrame.new(0, (corridorTop + corridorBottom) / 2, 0),
		Color3.fromRGB(40, 34, 50),
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
			then CFrame.new(x, FLOOR_Y, -z)
			else CFrame.new(x, FLOOR_Y, z) * CFrame.Angles(0, math.pi, 0)
		table.insert(units, buildUnit(floor, index, origin))
	end

	buildLamps(floor, rowWidth)
	applyLighting()
	return units
end

return WorldBuilder
