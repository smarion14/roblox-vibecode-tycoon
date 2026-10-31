--!strict
-- Act 3: the two-floor campus. The ground floor is Act 2's work floor (same stations, desks and decorate zone, so
-- saved decor carries over) plus a lobby name panel and the conference stage in the old meeting room. Stairs and
-- an elevator lead up to the security desk, the QA lab and the press room, under the campus's own roof.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local World = ServerScriptService:WaitForChild("World")
local Props = require(World:WaitForChild("Props"))
local OfficeLayout = require(World:WaitForChild("OfficeLayout"))

local part = Props.part
local screenLabel = Props.screenLabel
local interactable = Props.interactable
local nightLight = Props.nightLight
local glow = Props.glow
local monitor = Props.monitor
local desk = Props.desk
local marker = Props.marker
local COLOR_CYAN = Props.COLOR_CYAN
local COLOR_PINK = Props.COLOR_PINK
local COLOR_AMBER = Props.COLOR_AMBER
local COLOR_SCREEN = Props.COLOR_SCREEN
local COLOR_BEZEL = Props.COLOR_BEZEL
local COLOR_GLASS = Props.COLOR_GLASS

local COLOR_SLAB = Color3.fromRGB(46, 40, 60)
local COLOR_CARPET = Color3.fromRGB(52, 46, 70)
local COLOR_ALARM_OFF = Color3.fromRGB(70, 16, 20)
local COLOR_ALARM = Color3.fromRGB(255, 40, 50)

-- Unit-local studs (half = 32). The upper floor slab spans y 16..17, so upstairs walks at y 17; the shell walls
-- end at 16 and the upper walls stand on them up to the roof at 32.
local STOREY = 16
local UPPER_Y = STOREY + 1
local ROOF_Y = STOREY * 2
local INNER = 31.5 -- inner face of the outer walls
-- Stairs climb toward the back wall in the gap between the last station and the stage room (already reserved for
-- the work band in DECOR_ZONE; its foot has its own Blocked rect).
local STAIR_X0, STAIR_X1 = 10, 15
local STAIR_FRONT, STAIR_BACK = -12, -28
local STAIR_STEPS = UPPER_Y
local WELL_X0, WELL_X1 = 9.5, 15.5 -- slab opening over the stairs
-- Elevator pads stacked in the stage room's front-left corner (reserved floor), one per floor.
local ELEVATOR_X, ELEVATOR_Z = 18.5, -12.5
-- Upstairs rooms across the front half, each 21 studs wide, entered through a glass partition at z = 4.
local ROOM_FRONT = 4
local ROOM_EDGES = { -INNER, -10.5, 10.5, INNER }
local SIDE_WINDOWS: { Props.Opening } = {
	{ X = -22, Width = 8, Bottom = 5.5, Top = 12, Glass = true },
	{ X = 20, Width = 8, Bottom = 5.5, Top = 12, Glass = true },
}
local FRONT_WINDOWS: { Props.Opening } = {
	{ X = -21, Width = 8, Bottom = 5.5, Top = 12, Glass = true },
	{ X = 0, Width = 8, Bottom = 5.5, Top = 12, Glass = true },
	{ X = 21, Width = 8, Bottom = 5.5, Top = 12, Glass = true },
}

type Room = { Title: string, Kind: string, Role: string }
-- Left to right as seen from the stairs. Kind matches Incidents; Role is the key hire that counters it.
local ROOMS: { Room } = {
	{ Title = "Security Desk", Kind = "Breach", Role = "SecurityEngineer" },
	{ Title = "QA Lab", Kind = "Vulnerability", Role = "QAManager" },
	{ Title = "Press Room", Kind = "Naysayer", Role = "PRLead" },
}
local HIRE_NAMES: { [string]: string } = {
	SecurityEngineer = GameConfig.KEY_HIRES.SecurityEngineer.Name,
	QAManager = GameConfig.KEY_HIRES.QAManager.Name,
	PRLead = GameConfig.KEY_HIRES.PRLead.Name,
}

local CampusLayout = {}

local function glassWall(parent: Instance, size: Vector3, cframe: CFrame)
	local pane = part(parent, "GlassPartition", size, cframe, COLOR_GLASS, Enum.Material.Glass)
	pane.Transparency = 0.8
end

-- A floor-level box between two x and two z bounds (unit-local), `height` tall from `bottom`.
local function box(parent: Instance, name: string, origin: CFrame, x0: number, x1: number, z0: number, z1: number, bottom: number, height: number, color: Color3, material: Enum.Material): Part
	return part(parent, name, Vector3.new(x1 - x0, height, z1 - z0), origin * CFrame.new((x0 + x1) / 2, bottom + height / 2, (z0 + z1) / 2), color, material)
end

local function elevatorPad(parent: Instance, origin: CFrame, floorY: number, targetY: number, action: string)
	local pad = part(parent, "ElevatorPad", Vector3.new(4, 0.2, 4), origin * CFrame.new(ELEVATOR_X, floorY + 0.1, ELEVATOR_Z), COLOR_CYAN, Enum.Material.Neon)
	pad.Transparency = 0.4
	pad.CanCollide = false
	pad:SetAttribute("TargetY", targetY)
	interactable(pad, "Elevator", action, "Elevator")
end

-- The old meeting room becomes the conference stage: a raised stage along the back wall with a podium, a keynote
-- backdrop, spotlights, and a crowd of block figures facing it. The deploy wall screen stays where Act 2 had it.
local function buildStage(contents: Instance, origin: CFrame, half: number)
	OfficeLayout.BuildBackRoom(contents, origin, half)
	local left, right = 16.5, INNER
	local centerX = (16 + INNER) / 2
	box(contents, "Stage", origin, left, right, -INNER, -27, 0, 1.2, COLOR_BEZEL, Enum.Material.DiamondPlate)
	local edge = part(contents, "StageEdge", Vector3.new(right - left, 0.15, 0.15), origin * CFrame.new(centerX, 1.2, -27), COLOR_PINK, Enum.Material.Neon)
	edge.CanCollide = false

	local podium = part(contents, "Podium", Vector3.new(2.4, 3.6, 1.4), origin * CFrame.new(centerX, 1.2 + 1.8, -28.6), COLOR_SCREEN, Enum.Material.SmoothPlastic)
	glow(podium, COLOR_CYAN, 6)
	interactable(podium, "ConferenceStage", "Give keynote", "Conference Stage")

	local backdrop = part(contents, "StageBackdrop", Vector3.new(11, 4.5, 0.2), origin * CFrame.new(centerX, 8, -INNER + 0.2), COLOR_SCREEN, Enum.Material.Glass)
	screenLabel(backdrop, "KEYNOTE", COLOR_CYAN)

	for _, x in { centerX - 4, centerX + 4 } do
		local spot = part(contents, "StageSpotlight", Vector3.new(1.4, 1, 1.4), origin * CFrame.new(x, 13, -24), COLOR_AMBER, Enum.Material.Neon)
		spot.CanCollide = false
		nightLight(spot, COLOR_AMBER, 18)
	end

	-- Four columns, three rows, with an aisle from the doorway to the stage.
	local shirts = { COLOR_PINK, COLOR_CYAN, COLOR_AMBER, Color3.fromRGB(120, 100, 170) }
	for row, z in { -24, -20, -16 } do
		for column, x in { 18, 20.5, 27, 29.5 } do
			local shirt = shirts[(row + column) % #shirts + 1]
			part(contents, "AudienceFigure", Vector3.new(1.6, 2.6, 1), origin * CFrame.new(x, 1.3, z), shirt, Enum.Material.SmoothPlastic)
			part(contents, "AudienceHead", Vector3.new(1, 1, 1), origin * CFrame.new(x, 3.1, z), Color3.fromRGB(200, 170, 140), Enum.Material.SmoothPlastic)
		end
	end
end

-- The lobby's giant name panel hangs over the front of the floor, facing the door, clear of the decorate cells.
local function buildLobby(contents: Instance, origin: CFrame)
	local panel = part(contents, "NamePanel", Vector3.new(24, 5, 0.4), origin * CFrame.new(0, 11.5, 2), COLOR_SCREEN, Enum.Material.SmoothPlastic)
	panel.CanCollide = false
	screenLabel(panel, "", COLOR_PINK)
	-- Named so WorldBuilder.SetSignText puts the startup's name on it.
	local label = panel:FindFirstChild("TextLabel", true) :: TextLabel
	label.Name = "SignText"
	label.Font = Enum.Font.Arcade
	local underline = part(contents, "NamePanelTrim", Vector3.new(24, 0.3, 0.3), origin * CFrame.new(0, 8.8, 2.2), COLOR_PINK, Enum.Material.Neon)
	underline.CanCollide = false
	nightLight(underline, COLOR_PINK, 20)
	for _, x in { -11, 11 } do
		part(contents, "NamePanelCable", Vector3.new(0.1, 2, 0.1), origin * CFrame.new(x, 15, 2), COLOR_BEZEL, Enum.Material.Metal).CanCollide = false
	end
end

local function buildStairs(contents: Instance, origin: CFrame)
	local width = STAIR_X1 - STAIR_X0
	local centerX = (STAIR_X0 + STAIR_X1) / 2
	local tread = (STAIR_FRONT - STAIR_BACK) / STAIR_STEPS
	for step = 1, STAIR_STEPS do
		local z = STAIR_FRONT - (step - 0.5) * tread
		part(contents, "Stair", Vector3.new(width, step, tread), origin * CFrame.new(centerX, step / 2, z), COLOR_BEZEL, Enum.Material.Metal)
		local nose = part(contents, "StairNose", Vector3.new(width, 0.06, 0.15), origin * CFrame.new(centerX, step + 0.03, z + tread / 2 - 0.075), COLOR_CYAN, Enum.Material.Neon)
		nose.CanCollide = false
	end
	-- Glass rails along both sides of the flight, tilted to its slope.
	local run, rise = STAIR_FRONT - STAIR_BACK, STAIR_STEPS
	local angle = math.atan2(rise, run)
	for _, x in { STAIR_X0 - 0.15, STAIR_X1 + 0.15 } do
		local rail = part(contents, "StairRail", Vector3.new(0.3, 3, math.sqrt(run * run + rise * rise)), origin * CFrame.new(x, rise / 2 + 1.5, (STAIR_FRONT + STAIR_BACK) / 2) * CFrame.Angles(angle, 0, 0), COLOR_GLASS, Enum.Material.Glass)
		rail.Transparency = 0.6
	end
end

local function buildRoom(upper: Instance, origin: CFrame, room: Room, x0: number, x1: number)
	local cx = (x0 + x1) / 2
	box(upper, "RoomCarpet", origin, x0, x1, ROOM_FRONT, INNER, UPPER_Y, 0.04, COLOR_CARPET, Enum.Material.Fabric).CanCollide = false
	-- Glass front with a doorway in the middle, and a sign over it.
	local doorHalf = 2
	glassWall(upper, Vector3.new(cx - doorHalf - x0, 9, 0.2), origin * CFrame.new((x0 + cx - doorHalf) / 2, UPPER_Y + 4.5, ROOM_FRONT))
	glassWall(upper, Vector3.new(x1 - cx - doorHalf, 9, 0.2), origin * CFrame.new((cx + doorHalf + x1) / 2, UPPER_Y + 4.5, ROOM_FRONT))
	local sign = part(upper, "RoomSign", Vector3.new(6, 1.2, 0.2), origin * CFrame.new(cx, UPPER_Y + 10, ROOM_FRONT) * CFrame.Angles(0, math.pi, 0), COLOR_SCREEN, Enum.Material.SmoothPlastic)
	screenLabel(sign, string.upper(room.Title), COLOR_CYAN)

	-- The incident console faces the doorway; the screen carries the Respond prompt.
	local surface = desk(upper, "IncidentConsole", 6, 3, origin * CFrame.new(cx - 4, UPPER_Y, 20) * CFrame.Angles(0, math.pi, 0))
	local screen = monitor(upper, "IncidentScreen", Vector2.new(3.2, 1.8), surface * CFrame.new(0, 1.3, -0.6), room.Title, COLOR_PINK)
	screen:SetAttribute("Kind", room.Kind)
	interactable(screen, "IncidentDesk", "Respond", room.Title)

	-- Red alarm light, off until the incident service switches it on.
	local alarm = part(upper, "AlarmLight", Vector3.new(1.6, 0.6, 1.6), origin * CFrame.new(cx - 4, ROOF_Y - 0.3, 24), COLOR_ALARM_OFF, Enum.Material.SmoothPlastic)
	alarm.CanCollide = false
	alarm:SetAttribute("Kind", room.Kind)
	CollectionService:AddTag(alarm, "IncidentLight")
	local alarmGlow = Instance.new("PointLight")
	alarmGlow.Color = COLOR_ALARM
	alarmGlow.Range = 18
	alarmGlow.Brightness = 3
	alarmGlow.Enabled = false
	alarmGlow.Parent = alarm

	OfficeLayout.BuildEmployeeDesk(upper, origin * CFrame.new(cx + 5, UPPER_Y, 12), room.Role, HIRE_NAMES[room.Role])
end

local function buildUpperFloor(upper: Instance, origin: CFrame, half: number)
	-- Slab with the stairwell cut out of it; its underside lights the ground floor.
	box(upper, "UpperFloor", origin, -INNER, WELL_X0, -INNER, INNER, STOREY, 1, COLOR_SLAB, Enum.Material.Concrete)
	box(upper, "UpperFloor", origin, WELL_X1, INNER, -INNER, INNER, STOREY, 1, COLOR_SLAB, Enum.Material.Concrete)
	box(upper, "UpperFloor", origin, WELL_X0, WELL_X1, -INNER, STAIR_BACK, STOREY, 1, COLOR_SLAB, Enum.Material.Concrete)
	box(upper, "UpperFloor", origin, WELL_X0, WELL_X1, STAIR_FRONT, INNER, STOREY, 1, COLOR_SLAB, Enum.Material.Concrete)
	for _, x in { -16, 22 } do
		for _, z in { -16, 12 } do
			Props.ceilingLight(upper, origin * CFrame.new(x, STOREY - 0.1, z))
		end
	end
	-- Glass rails round the stairwell, open at the back where the flight arrives.
	local railHeight = 3.5
	for _, x in { WELL_X0 - 0.15, WELL_X1 + 0.15 } do
		box(upper, "WellRail", origin, x - 0.15, x + 0.15, STAIR_BACK, STAIR_FRONT, UPPER_Y, railHeight, COLOR_GLASS, Enum.Material.Glass).Transparency = 0.6
	end
	box(upper, "WellRail", origin, WELL_X0, WELL_X1, STAIR_FRONT, STAIR_FRONT + 0.3, UPPER_Y, railHeight, COLOR_GLASS, Enum.Material.Glass).Transparency = 0.6

	-- Upper walls in the shell's style: solid back, windows on the sides and front, no door.
	local wallBase = origin * CFrame.new(0, STOREY, 0)
	part(upper, "UpperBackWall", Vector3.new(half * 2, STOREY, 1), wallBase * CFrame.new(0, STOREY / 2, -half), Props.COLOR_WALL, Enum.Material.Plaster)
	Props.wallWithOpenings(upper, "UpperLeftWall", half * 2, STOREY, wallBase * CFrame.new(-half, 0, 0) * CFrame.Angles(0, math.rad(90), 0), SIDE_WINDOWS)
	Props.wallWithOpenings(upper, "UpperRightWall", half * 2, STOREY, wallBase * CFrame.new(half, 0, 0) * CFrame.Angles(0, math.rad(-90), 0), SIDE_WINDOWS)
	Props.wallWithOpenings(upper, "UpperFrontWall", half * 2, STOREY, wallBase * CFrame.new(0, 0, half), FRONT_WINDOWS)
	local trim = part(upper, "UpperNeonTrim", Vector3.new(half * 2, 0.4, 0.4), origin * CFrame.new(0, ROOF_Y - 0.5, -half + 0.8), COLOR_PINK, Enum.Material.Neon)
	trim.CanCollide = false
	nightLight(trim, COLOR_PINK, 24)

	-- Roof, with ceiling panels over the corridor and each room.
	part(upper, "Roof", Vector3.new(half * 2 + 1, 1, half * 2 + 1), origin * CFrame.new(0, ROOF_Y + 0.5, 0), COLOR_SLAB, Enum.Material.Concrete)
	for _, spot in { Vector2.new(-16, -16), Vector2.new(16, -16), Vector2.new(-21, 18), Vector2.new(0, 18), Vector2.new(21, 18) } do
		Props.ceilingLight(upper, origin * CFrame.new(spot.X, ROOF_Y - 0.1, spot.Y))
	end

	-- Room dividers, then the three rooms.
	for _, x in { ROOM_EDGES[2], ROOM_EDGES[3] } do
		glassWall(upper, Vector3.new(0.2, 9, INNER - ROOM_FRONT), origin * CFrame.new(x, UPPER_Y + 4.5, (ROOM_FRONT + INNER) / 2))
	end
	for index, room in ROOMS do
		buildRoom(upper, origin, room, ROOM_EDGES[index], ROOM_EDGES[index + 1])
	end
	elevatorPad(upper, origin, UPPER_Y, 0, "Go down")
end

-- Cutscene markers for Act3Intro and the Finale (names match Cutscenes.CAMPUS_MARKERS). The entrance and lobby
-- markers are 24 studs apart, inside the doorway's width, so the 3-second walks run at about 8 studs/s.
local function buildMarkers(contents: Instance, origin: CFrame)
	local function at(x: number, y: number, z: number): Vector3
		return (origin * CFrame.new(x, y, z)).Position
	end
	local function look(name: string, from: Vector3, target: Vector3)
		marker(contents, name, CFrame.lookAt(from, target))
	end
	look("PlayerEntrance", at(-1.5, 0, 36), at(-1.5, 0, 0))
	look("PlayerLobby", at(-1.5, 0, 12), at(-1.5, 0, 0))
	look("BrotherEntrance", at(1.5, 0, 36), at(1.5, 0, 0))
	look("BrotherLobby", at(1.5, 0, 12), at(1.5, 0, 0))
	look("CamLobbyWide", at(18, 10, 28), at(-2, 5, 6))
	look("CamLobbyName", at(0, 6, 15), at(0, 11.5, 2))
	look("CamAlarm", at(-4, 8, 0), at(12.5, 12, -24))
	look("CamFinale", at(0, 5, 4), at(0, 4, 14))
end

function CampusLayout.Build(contents: Instance, origin: CFrame, half: number)
	OfficeLayout.BuildWorkFloor(contents, origin, half)
	buildStage(contents, origin, half)
	buildLobby(contents, origin)
	buildStairs(contents, origin)
	elevatorPad(contents, origin, 0, UPPER_Y, "Go up")

	local upper = Instance.new("Folder")
	upper.Name = "UpperFloor"
	buildUpperFloor(upper, origin, half)
	-- Everything upstairs counts as roof for decorate mode, which hides Ceiling parts so its top-down camera can see
	-- the ground floor.
	for _, descendant in upper:GetDescendants() do
		if descendant:IsA("BasePart") then
			CollectionService:AddTag(descendant, "Ceiling")
		end
	end
	upper.Parent = contents

	buildMarkers(contents, origin)
end

return CampusLayout
