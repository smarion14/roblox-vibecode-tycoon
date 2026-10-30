--!strict
-- Act 2: the player's own office downtown. Upgraded stations along the back wall, an employee desk in front of
-- each one, a glass meeting room with the deploy wall screen, a reception desk with the shop computer and phone.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Props = require(ServerScriptService:WaitForChild("World"):WaitForChild("Props"))

local part = Props.part
local screenLabel = Props.screenLabel
local interactable = Props.interactable
local nightLight = Props.nightLight
local glow = Props.glow
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

local COLOR_GLASS = Color3.fromRGB(170, 210, 230)
local COLOR_NOTE = Color3.fromRGB(255, 230, 110)
local COLOR_CARPET = Color3.fromRGB(52, 46, 70)

local OfficeLayout = {}

-- Frontend: a long desk with three monitors, a mechanical keyboard and a proper chair.
local function buildFrontendStation(contents: Instance, base: CFrame): Part
	local surface = desk(contents, "FrontendDesk", 8, 3.4, base)
	local screen = monitor(contents, "Station_FrontendUnits", Vector2.new(3, 1.8), surface * CFrame.new(0, 1.3, -0.8), GameConfig.STATION_NAMES.FrontendUnits, COLOR_CYAN)
	monitor(contents, "FrontendLeft", Vector2.new(2.6, 1.6), surface * CFrame.new(-2.9, 1.2, -0.5) * CFrame.Angles(0, math.rad(20), 0), "</>  app.tsx", COLOR_PINK)
	monitor(contents, "FrontendRight", Vector2.new(2.6, 1.6), surface * CFrame.new(2.9, 1.2, -0.5) * CFrame.Angles(0, math.rad(-20), 0), "npm run dev", COLOR_AMBER)
	part(contents, "Keyboard", Vector3.new(2.6, 0.14, 0.9), surface * CFrame.new(0, 0.07, 0.7), COLOR_BEZEL, Enum.Material.SmoothPlastic)
	local glowStrip = part(contents, "KeyboardRgb", Vector3.new(2.6, 0.04, 0.9), surface * CFrame.new(0, 0.16, 0.7), COLOR_PINK, Enum.Material.Neon)
	glowStrip.Transparency = 0.6
	part(contents, "DeskMat", Vector3.new(5, 0.03, 1.6), surface * CFrame.new(0, 0.02, 0.7), Color3.fromRGB(30, 24, 44), Enum.Material.Fabric)
	-- Link the station screen to its chair; BurstService seats the player here during the burst.
	local seatLink = Instance.new("ObjectValue")
	seatLink.Name = "StationSeat"
	seatLink.Value = chair(contents, base * CFrame.new(0, 0, 3))
	seatLink.Parent = screen
	return screen
end

-- Backend: two full-height rack cabinets side by side, rows of servers and a KVM screen between them.
local function buildServerRack(contents: Instance, base: CFrame): Part
	local width, height, depth = 2.6, 11, 3.4
	for _, x in { -1.4, 1.4 } do
		local cabinet = base * CFrame.new(x, 0, 0)
		part(contents, "RackCabinet", Vector3.new(width, height, depth), cabinet * CFrame.new(0, height / 2, 0), COLOR_RACK, Enum.Material.DiamondPlate)
		for slot = 1, 9 do
			local y = 0.6 + slot * 1.05
			local server = part(contents, "RackServer", Vector3.new(width - 0.3, 0.8, 0.2), cabinet * CFrame.new(0, y, depth / 2 + 0.05), COLOR_SERVER, Enum.Material.Metal)
			server.CanCollide = false
			for bay = 1, 3 do
				led(contents, cabinet * CFrame.new(-0.9 + bay * 0.35, y + 0.15, depth / 2 + 0.18), if (bay + slot) % 2 == 0 then COLOR_CYAN else Color3.fromRGB(120, 255, 120))
			end
		end
	end
	return monitor(contents, "Station_BackendEndpoints", Vector2.new(2.4, 1.4), base * CFrame.new(0, 4.6, depth / 2 + 0.6), GameConfig.STATION_NAMES.BackendEndpoints, COLOR_CYAN)
end

-- Database: a locked server cabinet with a glass door over rows of drive bays, and a console in front.
local function buildDatabaseCabinet(contents: Instance, base: CFrame): Part
	local width, height, depth = 4, 8, 3
	part(contents, "DbCabinet", Vector3.new(width, height, depth), base * CFrame.new(0, height / 2, 0), COLOR_RACK, Enum.Material.Metal)
	for row = 1, 5 do
		for bay = 1, 6 do
			local x = -width / 2 + 0.2 + bay * 0.52
			part(contents, "DriveBay", Vector3.new(0.4, 1, 0.05), base * CFrame.new(x, row * 1.3, depth / 2 + 0.03), COLOR_SERVER, Enum.Material.Metal).CanCollide = false
			led(contents, base * CFrame.new(x, row * 1.3 + 0.4, depth / 2 + 0.08), COLOR_AMBER)
		end
	end
	local door = part(contents, "DbGlassDoor", Vector3.new(width - 0.2, height - 0.4, 0.1), base * CFrame.new(0, height / 2, depth / 2 + 0.2), COLOR_GLASS, Enum.Material.Glass)
	door.Transparency = 0.7
	door.CanCollide = false
	-- Console on a small pedestal in front of the cabinet.
	part(contents, "ConsolePedestal", Vector3.new(1.2, 3.2, 1.2), base * CFrame.new(0, 1.6, depth / 2 + 1.6), COLOR_BEZEL, Enum.Material.Metal)
	return monitor(contents, "Station_DatabaseTables", Vector2.new(2.4, 1.4), base * CFrame.new(0, 4.3, depth / 2 + 1.7), GameConfig.STATION_NAMES.DatabaseTables, COLOR_CYAN)
end

-- AI: a glass cooling cabinet full of glowing GPUs, with its monitor on top.
local function buildAiCabinet(contents: Instance, base: CFrame): Part
	local width, height, depth = 4.4, 6, 3
	part(contents, "CoolingBase", Vector3.new(width, 0.4, depth), base * CFrame.new(0, 0.2, 0), COLOR_BEZEL, Enum.Material.Metal)
	part(contents, "CoolingTop", Vector3.new(width, 0.4, depth), base * CFrame.new(0, height + 0.2, 0), COLOR_BEZEL, Enum.Material.Metal)
	local glass = part(contents, "CoolingGlass", Vector3.new(width, height, depth), base * CFrame.new(0, height / 2 + 0.2, 0), COLOR_GLASS, Enum.Material.Glass)
	glass.Transparency = 0.75
	glow(glass, COLOR_CYAN, 10)
	for shelf = 1, 2 do
		for card = 1, 5 do
			local x = -width / 2 + card * 0.73
			local y = shelf * 2.4 - 0.6
			part(contents, "Gpu", Vector3.new(0.35, 1.4, 2), base * CFrame.new(x, y, 0), COLOR_SERVER, Enum.Material.Metal).CanCollide = false
			part(contents, "GpuGlow", Vector3.new(0.05, 1.4, 2), base * CFrame.new(x + 0.2, y, 0), if card % 2 == 0 then COLOR_PINK else COLOR_CYAN, Enum.Material.Neon).CanCollide = false
		end
	end
	-- Coolant pipes up the side.
	for _, z in { -0.8, 0.8 } do
		cylinder(contents, "CoolantPipe", height, 0.3, base * CFrame.new(width / 2 + 0.25, height / 2 + 0.2, z) * CFrame.Angles(0, 0, math.rad(90)), COLOR_CYAN, Enum.Material.Glass)
	end
	return monitor(contents, "Station_PromptTokens", Vector2.new(3, 1.6), base * CFrame.new(0, height + 1.6, 0.6), GameConfig.STATION_NAMES.PromptTokens, COLOR_CYAN)
end

-- An empty desk for a hire: tagged EmployeeDesk with its Role, a disabled seat named EmployeeSeat, and a
-- "NOW HIRING" sticky note that EmployeeService hides once that role is hired.
local function buildEmployeeDesk(contents: Instance, base: CFrame, role: string)
	local top = part(contents, "EmployeeDesk", Vector3.new(4.4, 0.25, 2.4), base * CFrame.new(0, 3, 0), COLOR_DESK, Enum.Material.Wood)
	top:SetAttribute("Role", role)
	CollectionService:AddTag(top, "EmployeeDesk")
	for _, x in { -1.9, 1.9 } do
		part(contents, "EmployeeDeskLeg", Vector3.new(0.25, 3, 2), base * CFrame.new(x, 1.5, 0), COLOR_BEZEL, Enum.Material.Metal)
	end
	local surface = base * CFrame.new(0, 3.125, 0)
	monitor(contents, "EmployeeMonitor", Vector2.new(2.2, 1.3), surface * CFrame.new(0, 1.1, -0.5), GameConfig.STATION_NAMES[role], COLOR_CYAN)

	local seat = chair(top, base * CFrame.new(0, 0, 2.2))
	seat.Name = "EmployeeSeat"

	local note = Instance.new("SurfaceGui")
	note.Name = "HiringNote"
	note.Face = Enum.NormalId.Top
	note.PixelsPerStud = 40
	note.LightInfluence = 0
	note.Parent = top
	local paper = Instance.new("TextLabel")
	paper.AnchorPoint = Vector2.new(1, 1)
	paper.Position = UDim2.fromScale(0.95, 0.92)
	paper.Size = UDim2.fromScale(0.3, 0.5)
	paper.Rotation = -6
	paper.BackgroundColor3 = COLOR_NOTE
	paper.TextColor3 = Color3.fromRGB(40, 30, 20)
	paper.Font = Enum.Font.PermanentMarker
	paper.TextScaled = true
	paper.Text = "NOW HIRING"
	paper.Parent = note
end

-- Meeting room on the right: glass partitions, a table, and the deploy terminal as a wall screen.
local function buildMeetingRoom(contents: Instance, origin: CFrame, half: number): Part
	local left, front, back = 10, 16, -4
	local function glassWall(size: Vector3, cframe: CFrame)
		local pane = part(contents, "GlassPartition", size, cframe, COLOR_GLASS, Enum.Material.Glass)
		pane.Transparency = 0.8
	end
	-- Side partition with a doorway from z = 4 to 8.
	glassWall(Vector3.new(0.2, 9, 8), origin * CFrame.new(left, 4.5, back + 4))
	glassWall(Vector3.new(0.2, 9, 8), origin * CFrame.new(left, 4.5, front - 4))
	glassWall(Vector3.new(half - left, 9, 0.2), origin * CFrame.new((left + half) / 2, 4.5, back))
	part(contents, "MeetingCarpet", Vector3.new(half - left - 1, 0.05, front - back), origin * CFrame.new((left + half) / 2, 0.03, (front + back) / 2), COLOR_CARPET, Enum.Material.Fabric).CanCollide = false

	local tableBase = origin * CFrame.new(15, 0, 6)
	part(contents, "MeetingTable", Vector3.new(4, 0.3, 7), tableBase * CFrame.new(0, 3, 0), COLOR_DESK, Enum.Material.Wood)
	part(contents, "MeetingTableBase", Vector3.new(1, 2.85, 4), tableBase * CFrame.new(0, 1.43, 0), COLOR_BEZEL, Enum.Material.Metal)
	for _, z in { -2.2, 0, 2.2 } do
		for _, x in { -2.8, 2.8 } do
			part(contents, "MeetingChair", Vector3.new(1.6, 1.8, 1.6), tableBase * CFrame.new(x, 0.9, z), Color3.fromRGB(40, 30, 60), Enum.Material.Fabric)
		end
	end

	local screen = monitor(contents, "DeployTerminal", Vector2.new(7, 3.4), origin * CFrame.new(half - 0.8, 6, 6) * CFrame.Angles(0, math.rad(-90), 0), "DEPLOY", COLOR_PINK)
	local light = part(contents, "MeetingLight", Vector3.new(5, 0.3, 1), tableBase * CFrame.new(0, 11, 0), COLOR_AMBER, Enum.Material.Neon)
	light.CanCollide = false
	nightLight(light, COLOR_AMBER, 16)
	return screen
end

-- Reception desk by the door: the shop computer and the job phone.
local function buildReception(contents: Instance, base: CFrame): (Part, Part)
	local surface = desk(contents, "ReceptionDesk", 5, 2.6, base)
	part(contents, "ReceptionFront", Vector3.new(5, 3, 0.2), base * CFrame.new(0, 1.5, -1.3), COLOR_DESK, Enum.Material.Wood)
	local computer = monitor(contents, "ShopComputer", Vector2.new(2.4, 1.4), surface * CFrame.new(-0.6, 1, -0.4), "SHOP", COLOR_AMBER)
	part(contents, "Keyboard", Vector3.new(1.8, 0.1, 0.6), surface * CFrame.new(-0.6, 0.05, 0.6), COLOR_BEZEL, Enum.Material.SmoothPlastic)
	local phone = part(contents, "JobPhone", Vector3.new(0.6, 0.12, 1.1), surface * CFrame.new(1.7, 0.06, 0.3), COLOR_SCREEN, Enum.Material.Glass)
	glow(phone, COLOR_CYAN, 6)
	return computer, phone
end

-- Coffee machine, logo wall, plants and pendant lights.
local function buildDecor(contents: Instance, origin: CFrame, half: number)
	local counter = origin * CFrame.new(-half + 1.8, 0, -4)
	part(contents, "CoffeeCounter", Vector3.new(2.6, 3.2, 5), counter * CFrame.new(0, 1.6, 0), COLOR_DESK, Enum.Material.Wood)
	part(contents, "CoffeeMachine", Vector3.new(1.6, 2, 1.4), counter * CFrame.new(0, 4.2, -1), COLOR_SERVER, Enum.Material.Metal)
	led(contents, counter * CFrame.new(0.82, 4.8, -1), Color3.fromRGB(120, 255, 120))
	for index = 1, 3 do
		cylinder(contents, "Mug", 0.5, 0.45, counter * CFrame.new(0, 3.45, 0.4 + index * 0.6) * CFrame.Angles(0, 0, math.rad(90)), if index == 2 then COLOR_PINK else Color3.fromRGB(235, 235, 240), Enum.Material.SmoothPlastic)
	end

	-- Logo wall on the left: a neon brace mark on a dark panel.
	local logo = part(contents, "LogoWall", Vector3.new(0.3, 5, 9), origin * CFrame.new(-half + 0.7, 7, 8), Color3.fromRGB(28, 20, 44), Enum.Material.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Right
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = logo
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextColor3 = COLOR_PINK
	text.Font = Enum.Font.Arcade
	text.TextScaled = true
	text.Text = "{ ship it }"
	text.Parent = gui
	glow(logo, COLOR_PINK, 10)

	plant(contents, origin * CFrame.new(-half + 2.5, 0, half - 2.5))
	plant(contents, origin * CFrame.new(half - 2.5, 0, half - 2.5))
	plant(contents, origin * CFrame.new(8, 0, -6))
	plant(contents, origin * CFrame.new(-8, 0, -6))

	part(contents, "OfficeCarpet", Vector3.new(half * 2 - 2, 0.04, 16), origin * CFrame.new(0, 0.02, -12), COLOR_CARPET, Enum.Material.Fabric).CanCollide = false
	for _, x in { -12, 0 } do
		local pendant = part(contents, "PendantLight", Vector3.new(6, 0.3, 1), origin * CFrame.new(x, 11, -10), COLOR_CYAN, Enum.Material.Neon)
		pendant.CanCollide = false
		nightLight(pendant, COLOR_CYAN, 20)
	end
end

-- Cutscene markers for Act2Intro (names match Cutscenes.OFFICE_MARKERS).
local function buildMarkers(contents: Instance, origin: CFrame)
	local function at(x: number, y: number, z: number): Vector3
		return (origin * CFrame.new(x, y, z)).Position
	end
	local function look(name: string, from: Vector3, target: Vector3)
		marker(contents, name, CFrame.lookAt(from, target))
	end
	look("CamOutside", at(0, 8, 34), at(0, 4, 10))
	look("CamInside", at(0, 7, 18), at(0, 3, -10))
	look("CamDesks", at(0, 9, 2), at(0, 3, -12))
	look("CamSign", at(-6, 5, 12), at(-6, 4.5, 19))
	look("PlayerDoor", at(0, 0, 21), at(0, 0, 0))
	look("PlayerCenter", at(0, 0, 4), at(0, 0, -10))
end

function OfficeLayout.Build(contents: Instance, origin: CFrame, half: number)
	local back = origin * CFrame.new(0, 0, -half + 3)
	local stationBuilders: { [string]: (Instance, CFrame) -> Part } = {
		FrontendUnits = buildFrontendStation,
		BackendEndpoints = buildServerRack,
		DatabaseTables = buildDatabaseCabinet,
		PromptTokens = buildAiCabinet,
	}
	for slot, component in GameConfig.COMPONENTS do
		local x = -half + 6 + (slot - 1) * ((half * 2 - 12) / 3)
		local screen = stationBuilders[component](contents, back * CFrame.new(x, 0, 0))
		screen:SetAttribute("Component", component)
		interactable(screen, "Station", "Build", GameConfig.STATION_NAMES[component])
		buildEmployeeDesk(contents, origin * CFrame.new(x, 0, -9), component)
	end

	local deploy = buildMeetingRoom(contents, origin, half)
	interactable(deploy, "DeployTerminal", "Ship it", "Deploy Terminal")

	local computer, phone = buildReception(contents, origin * CFrame.new(-14, 0, 10) * CFrame.Angles(0, math.rad(90), 0))
	interactable(computer, "ShopComputer", "Browse", "Computer")
	interactable(phone, "JobPhone", "Check jobs", "Phone")

	-- The startup's poster by the door; interacting renames the startup.
	local sign = part(contents, "StartupSign", Vector3.new(4, 3, 0.3), origin * CFrame.new(-6, 4.5, 19) * CFrame.Angles(0, math.pi, 0), COLOR_SCREEN, Enum.Material.SmoothPlastic)
	screenLabel(sign, "YOUR STARTUP\nHERE", COLOR_PINK)
	part(contents, "StartupSignStand", Vector3.new(0.3, 3, 0.3), origin * CFrame.new(-6, 1.5, 19.2), COLOR_BEZEL, Enum.Material.Metal)
	interactable(sign, "StartupSign", "Rename", "Startup Sign")

	buildDecor(contents, origin, half)
	buildMarkers(contents, origin)
end

return OfficeLayout
