--!strict
-- Code-built blockout of the megablock floor. Only built-in parts and materials, so the game runs with no uploaded art.
-- Gameplay code finds objects by CollectionService tag and attributes, never by geometry, so art can replace this later.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local World = ServerScriptService:WaitForChild("World")
local Props = require(World:WaitForChild("Props"))
local HomelabLayout = require(World:WaitForChild("HomelabLayout"))
local OfficeLayout = require(World:WaitForChild("OfficeLayout"))

local UNIT_SIZE = 44
local UNIT_GAP = 8
local WALL_HEIGHT = 16
local UNITS_PER_ROW = 3
local CORRIDOR_WIDTH = 24
-- The whole floor sits this high so nothing shares a surface with the place's default Baseplate (top at y = 0),
-- which caused z-fighting. The corridor is half a stud lower than the unit floors for the same reason.
local FLOOR_Y = 3
local CORRIDOR_DROP = 0.5

local part = Props.part
local nightLight = Props.nightLight
local COLOR_FLOOR = Props.COLOR_FLOOR
local COLOR_WALL = Props.COLOR_WALL
local COLOR_CYAN = Props.COLOR_CYAN
local COLOR_PINK = Props.COLOR_PINK
local COLOR_AMBER = Props.COLOR_AMBER
local COLOR_SCREEN = Props.COLOR_SCREEN
local COLOR_BEZEL = Props.COLOR_BEZEL

local WorldBuilder = {}

-- Rebuilds everything inside the unit's walls for an act. The shell (floor, walls, trims, sign, spawn) stays.
function WorldBuilder.BuildContents(unit: Model, act: number)
	local contents = unit:FindFirstChild("Contents") :: Folder
	contents:ClearAllChildren()
	local origin = unit:GetAttribute("OriginCFrame") :: CFrame
	if act >= 2 then
		OfficeLayout.Build(contents, origin, UNIT_SIZE / 2)
	else
		HomelabLayout.Build(contents, origin, UNIT_SIZE / 2)
	end
end

function WorldBuilder.SetSignText(unit: Model, text: string)
	local label = unit:FindFirstChild("SignText", true)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function buildUnit(floor: Folder, index: number, origin: CFrame): Model
	local unit = Instance.new("Model")
	unit.Name = `Unit{index}`
	unit:SetAttribute("Unit", index)
	unit:SetAttribute("OriginCFrame", origin)
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
	-- The owner's startup name, set by SetSignText (blank while the unit is empty or in Act 1).
	local signGui = Instance.new("SurfaceGui")
	signGui.Name = "SignGui"
	signGui.Face = Enum.NormalId.Back
	signGui.PixelsPerStud = 30
	signGui.LightInfluence = 0
	signGui.Parent = sign
	local signText = Instance.new("TextLabel")
	signText.Name = "SignText"
	signText.Size = UDim2.fromScale(1, 1)
	signText.BackgroundTransparency = 1
	signText.TextColor3 = COLOR_SCREEN
	signText.Font = Enum.Font.Arcade
	signText.TextScaled = true
	signText.Text = ""
	signText.Parent = signGui

	local spawnPad = part(unit, "UnitSpawn", Vector3.new(4, 0.2, 4), origin * CFrame.new(4, 0.1, 6), COLOR_FLOOR, Enum.Material.SmoothPlastic)
	spawnPad.Transparency = 1
	spawnPad.CanCollide = false
	CollectionService:AddTag(spawnPad, "UnitSpawn")

	local contents = Instance.new("Folder")
	contents.Name = "Contents"
	contents.Parent = unit
	WorldBuilder.BuildContents(unit, 1)
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

-- A plain brother rig the cutscene client clones when the unit has no SiblingModel (the Act 2 office).
local function buildBrotherTemplate()
	local model = Props.buildBrother()
	if model then
		model.Name = "BrotherTemplate"
		model.Parent = ReplicatedStorage:WaitForChild("Shared")
	end
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
	buildBrotherTemplate()
	return units
end

return WorldBuilder
