--!strict
-- Act 1: a homelab squeezed into the sibling's living room. Four stations along the back wall, one per component.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Props = require(ServerScriptService:WaitForChild("World"):WaitForChild("Props"))

local part = Props.part
local screenLabel = Props.screenLabel
local interactable = Props.interactable
local glow = Props.glow
local buildSibling = Props.buildSibling
local cylinder = Props.cylinder
local led = Props.led
local monitor = Props.monitor
local desk = Props.desk
local chair = Props.chair
local plant = Props.plant
local marker = Props.marker

local COLOR_CYAN = Props.COLOR_CYAN
local COLOR_PINK = Props.COLOR_PINK
local COLOR_AMBER = Props.COLOR_AMBER
local COLOR_SCREEN = Props.COLOR_SCREEN
local COLOR_DESK = Props.COLOR_DESK
local COLOR_BEZEL = Props.COLOR_BEZEL
local COLOR_RACK = Props.COLOR_RACK
local COLOR_SERVER = Props.COLOR_SERVER
local COLOR_COUCH = Props.COLOR_COUCH

local HomelabLayout = {}

-- Frontend: a desk with dual monitors, keyboard, energy drinks and a gaming chair.
local function buildFrontendStation(unit: Instance, base: CFrame): Part
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
	-- Link the station screen to its chair; BurstService seats the player here during the burst.
	local seatLink = Instance.new("ObjectValue")
	seatLink.Name = "StationSeat"
	seatLink.Value = chair(unit, base * CFrame.new(0, 0, 3))
	seatLink.Parent = screen
	return screen
end

-- Backend: a tall rack cabinet of servers with blinking LEDs, patch cables and a KVM screen.
local function buildServerRack(unit: Instance, base: CFrame): Part
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
local function buildDatabaseShelf(unit: Instance, base: CFrame): Part
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
local function buildAiRig(unit: Instance, base: CFrame): Part
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
local function buildDeployDesk(unit: Instance, base: CFrame): Part
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
local function buildLounge(unit: Instance, base: CFrame): (Part, Part)
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
local function buildDecor(unit: Instance, origin: CFrame, half: number)
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
	local cable = part(unit, "CableRun", Vector3.new(half * 2 - 6, 0.25, 0.4), origin * CFrame.new(0, 0.13, -half + 1.2), COLOR_BEZEL, Enum.Material.SmoothPlastic)
	cable.CanCollide = false

	-- Desk-lamp style accent strip under the back trim that glows all day.
	local strip = part(unit, "LedStrip", Vector3.new(half * 2 - 4, 0.15, 0.15), origin * CFrame.new(0, 9, -half + 0.6), COLOR_PINK, Enum.Material.Neon)
	strip.Transparency = 0.3
	strip.CanCollide = false
end

-- Cutscene markers for Act1Intro and Act1End (names match Cutscenes.HOMELAB_MARKERS).
local function buildMarkers(contents: Instance, origin: CFrame)
	local function at(x: number, y: number, z: number): Vector3
		return (origin * CFrame.new(x, y, z)).Position
	end
	local function look(name: string, from: Vector3, target: Vector3)
		marker(contents, name, CFrame.lookAt(from, target))
	end
	-- Cameras.
	look("CamWide", at(10, 12, 20), at(-8, 2, 10))
	look("CamCouch", at(-8, 5, 3), at(-8, 3, 12))
	look("CamShoulder", at(-6.5, 7, 17), at(-8, 2.5, 6.5))
	look("CamFace", at(-8, 4.5, 7), at(-8, 4, 11.3))
	look("CamDoor", at(1.5, 5, 20), at(1.5, 3.5, 12))
	-- Actors (floor level, except the couch seat at cushion height).
	look("CouchSeat", at(-8, 2.3, 11.3), at(-8, 2.3, 0))
	look("BrotherEnter", at(-14, 0, 18), at(-14, 0, 0))
	look("BrotherBehindCouch", at(-8, 0, 15.5), at(-8, 0, 0))
	look("HandoverPlayer", at(0, 0, 12), at(3, 0, 12))
	look("HandoverBrother", at(3, 0, 12), at(0, 0, 12))
	look("BrotherDoor", at(6, 0, 20), at(0, 0, 12))
end

function HomelabLayout.Build(contents: Instance, origin: CFrame, half: number)
	local back = origin * CFrame.new(0, 0, -half + 3)
	local stationBuilders: { [string]: (Instance, CFrame) -> Part } = {
		FrontendUnits = buildFrontendStation,
		BackendEndpoints = buildServerRack,
		DatabaseTables = buildDatabaseShelf,
		PromptTokens = buildAiRig,
	}
	for slot, component in GameConfig.COMPONENTS do
		local x = -half + 6 + (slot - 1) * ((half * 2 - 12) / 3)
		local screen = stationBuilders[component](contents, back * CFrame.new(x, 0, 0))
		screen:SetAttribute("Component", component)
		interactable(screen, "Station", "Build", GameConfig.STATION_NAMES[component])
	end

	local deploy = buildDeployDesk(contents, origin * CFrame.new(half - 3, 0, 4) * CFrame.Angles(0, math.rad(-90), 0))
	interactable(deploy, "DeployTerminal", "Ship it", "Deploy Terminal")

	local laptop, phone = buildLounge(contents, origin * CFrame.new(-8, 0, 10))
	interactable(laptop, "ShopComputer", "Browse", "Laptop")
	interactable(phone, "JobPhone", "Check jobs", "Phone")

	buildDecor(contents, origin, half)

	local siblingRoot = buildSibling(contents, origin * CFrame.new(-16, 0, 4) * CFrame.Angles(0, math.rad(90), 0))
	if siblingRoot then
		interactable(siblingRoot, "Sibling", "Talk", "Your Sibling")
	end

	buildMarkers(contents, origin)
end

return HomelabLayout
