--!strict
-- Code-built models for every office decor item (GameConfig.DECOR), shared by the server (placed decor) and the
-- client (decorate-mode ghost previews). Each model's pivot is its footprint's center at floor level and it faces
-- local -Z at rotation 0. Built only from parts and built-in materials, in the same palette as the world.
-- Must not require server modules: the small part helpers below mirror ServerScriptService.World.Props.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))

local COLOR_CYAN = Color3.fromRGB(125, 252, 208)
local COLOR_PINK = Color3.fromRGB(255, 79, 216)
local COLOR_AMBER = Color3.fromRGB(255, 184, 79)
local COLOR_SCREEN = Color3.fromRGB(11, 7, 22)
local COLOR_DESK = Color3.fromRGB(96, 70, 56)
local COLOR_BEZEL = Color3.fromRGB(28, 26, 34)
local COLOR_SERVER = Color3.fromRGB(46, 46, 56)
local COLOR_COUCH = Color3.fromRGB(86, 70, 110)
local COLOR_ACCENT_DARK = Color3.fromRGB(40, 30, 60)
local COLOR_POT = Color3.fromRGB(150, 90, 70)
local COLOR_LEAVES = Color3.fromRGB(70, 140, 80)
local COLOR_FABRIC_WARM = Color3.fromRGB(240, 200, 150)
local COLOR_CAT = Color3.fromRGB(230, 150, 70)

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- turns a cylinder's X axis vertical

local DecorModels = {}

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

local function trim(target: Part): Part
	target.CanCollide = false
	target.CastShadow = false
	return target
end

local function cylinder(parent: Instance, name: string, length: number, diameter: number, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local newPart = part(parent, name, Vector3.new(length, diameter, diameter), cframe, color, material)
	newPart.Shape = Enum.PartType.Cylinder
	return newPart
end

local function ball(parent: Instance, name: string, diameter: number, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local newPart = part(parent, name, Vector3.new(diameter, diameter, diameter), cframe, color, material)
	newPart.Shape = Enum.PartType.Ball
	return newPart
end

-- Lamps and neon follow the building-light rule: LightingController switches every NightLight part on at night.
-- Only the parts given a range carry a PointLight, so a string of bulbs lights the room with one light.
local function nightLight(target: BasePart, color: Color3, range: number?)
	if range then
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = range
		light.Brightness = 2
		light.Parent = target
	end
	target:SetAttribute("NightColor", color)
	CollectionService:AddTag(target, "NightLight")
end

local function label(target: BasePart, face: Enum.NormalId, text: string, color: Color3, background: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = target
	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = if background then 0 else 1
	textLabel.BackgroundColor3 = background or COLOR_SCREEN
	textLabel.TextColor3 = color
	textLabel.Font = Enum.Font.Arcade
	textLabel.TextScaled = true
	textLabel.Text = text
	textLabel.Parent = gui
	return textLabel
end

local function pottedPlant(model: Model): Part
	part(model, "PlantPot", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 0.6, 0), COLOR_POT, Enum.Material.Slate)
	local leaves = ball(model, "PlantLeaves", 1.8, CFrame.new(0, 2.1, 0), COLOR_LEAVES, Enum.Material.Grass)
	leaves.CanCollide = false
	return leaves
end

-- Perk: employees build faster. A wooden cabinet with an espresso machine and a mug under the spout.
local function coffeeMachine(model: Model)
	part(model, "CoffeeCabinet", Vector3.new(1.8, 3, 1.6), CFrame.new(0, 1.5, 0), COLOR_DESK, Enum.Material.Wood)
	part(model, "CoffeeMachine", Vector3.new(1.3, 1.6, 1), CFrame.new(0, 3.8, 0.2), COLOR_SERVER, Enum.Material.Metal)
	trim(part(model, "CoffeeSpout", Vector3.new(0.5, 0.25, 0.5), CFrame.new(-0.2, 3.9, -0.45), COLOR_BEZEL, Enum.Material.Metal))
	trim(cylinder(model, "CoffeeMug", 0.4, 0.35, CFrame.new(-0.2, 3.2, -0.5) * UPRIGHT, Color3.fromRGB(235, 235, 240), Enum.Material.SmoothPlastic))
	trim(part(model, "CoffeeLed", Vector3.new(0.12, 0.12, 0.05), CFrame.new(0.4, 4.2, -0.32), Color3.fromRGB(120, 255, 120), Enum.Material.Neon))
	trim(cylinder(model, "CoffeeBeans", 0.6, 0.5, CFrame.new(0.45, 3.3, -0.4) * UPRIGHT, COLOR_AMBER, Enum.Material.Glass))
end

-- Perk: better part grades. A long soft couch with a warm cushion, seat facing -Z.
local function loungeCouch(model: Model)
	part(model, "CouchBase", Vector3.new(5.8, 1.2, 1.9), CFrame.new(0, 0.6, 0), COLOR_COUCH, Enum.Material.Fabric)
	part(model, "CouchCushion", Vector3.new(5, 0.45, 1.3), CFrame.new(0, 1.42, -0.2), COLOR_COUCH:Lerp(Color3.new(1, 1, 1), 0.08), Enum.Material.Fabric)
	part(model, "CouchBack", Vector3.new(5.8, 1.8, 0.5), CFrame.new(0, 2.1, 0.7), COLOR_COUCH, Enum.Material.Fabric)
	for _, x in { -2.7, 2.7 } do
		part(model, "CouchArm", Vector3.new(0.4, 1.9, 1.9), CFrame.new(x, 0.95, 0), COLOR_COUCH, Enum.Material.Fabric)
	end
	trim(part(model, "CouchPillow", Vector3.new(0.9, 0.9, 0.3), CFrame.new(-1.8, 2.05, 0.3) * CFrame.Angles(math.rad(-15), 0, math.rad(10)), COLOR_AMBER, Enum.Material.Fabric))
	trim(part(model, "CouchThrow", Vector3.new(1.4, 0.06, 1.3), CFrame.new(1.6, 1.67, -0.2), COLOR_FABRIC_WARM, Enum.Material.Fabric))
end

-- Perk: employees build faster. An upright cabinet with a lit screen, controls and a neon marquee.
local function arcadeCabinet(model: Model)
	part(model, "ArcadeBody", Vector3.new(1.8, 5.6, 1.5), CFrame.new(0, 2.8, 0.2), COLOR_ACCENT_DARK, Enum.Material.SmoothPlastic)
	local screen = trim(part(model, "ArcadeScreen", Vector3.new(1.4, 1.1, 0.1), CFrame.new(0, 4.1, -0.58) * CFrame.Angles(math.rad(10), 0, 0), COLOR_SCREEN, Enum.Material.Glass))
	label(screen, Enum.NormalId.Front, "INSERT\nCOIN", COLOR_CYAN, COLOR_SCREEN)
	local glow = Instance.new("PointLight")
	glow.Color = COLOR_CYAN
	glow.Range = 6
	glow.Brightness = 1.5
	glow.Parent = screen
	part(model, "ArcadePanel", Vector3.new(1.7, 0.25, 0.4), CFrame.new(0, 3.1, -0.75), COLOR_BEZEL, Enum.Material.SmoothPlastic)
	trim(ball(model, "ArcadeStick", 0.25, CFrame.new(-0.4, 3.4, -0.75), COLOR_PINK, Enum.Material.SmoothPlastic))
	for index, color in { COLOR_AMBER, COLOR_CYAN } do
		trim(cylinder(model, "ArcadeButton", 0.1, 0.22, CFrame.new(0.1 + index * 0.3, 3.27, -0.75) * UPRIGHT, color, Enum.Material.Neon))
	end
	local marquee = trim(part(model, "ArcadeMarquee", Vector3.new(1.8, 0.5, 0.15), CFrame.new(0, 5.35, -0.6), COLOR_PINK, Enum.Material.Neon))
	nightLight(marquee, COLOR_PINK, 10)
end

local function plant(model: Model)
	pottedPlant(model)
end

local function rug(model: Model)
	trim(part(model, "RugBase", Vector3.new(5.6, 0.06, 3.6), CFrame.new(0, 0.03, 0), Color3.fromRGB(110, 60, 105), Enum.Material.Fabric))
	trim(part(model, "RugInner", Vector3.new(4.6, 0.08, 2.6), CFrame.new(0, 0.04, 0), Color3.fromRGB(70, 50, 95), Enum.Material.Fabric))
	trim(part(model, "RugStripe", Vector3.new(4.6, 0.1, 0.3), CFrame.new(0, 0.05, 0), COLOR_AMBER, Enum.Material.Fabric))
end

-- Warm reading lamp: a fabric shade over an amber bulb.
local function floorLamp(model: Model)
	cylinder(model, "LampBase", 0.15, 1.2, CFrame.new(0, 0.075, 0) * UPRIGHT, COLOR_BEZEL, Enum.Material.Metal)
	part(model, "LampPole", Vector3.new(0.15, 5, 0.15), CFrame.new(0, 2.6, 0), COLOR_BEZEL, Enum.Material.Metal)
	local shade = trim(cylinder(model, "LampShade", 1.1, 1.5, CFrame.new(0, 5.5, 0) * UPRIGHT, COLOR_FABRIC_WARM, Enum.Material.Fabric))
	shade.Transparency = 0.3
	local bulb = trim(ball(model, "LampBulb", 0.6, CFrame.new(0, 5.3, 0), COLOR_AMBER, Enum.Material.Neon))
	nightLight(bulb, COLOR_AMBER, 16)
end

-- A dark board on two posts with "GOOD VIBES" and a neon tube frame, facing -Z.
local function neonSign(model: Model)
	for _, x in { -1.5, 1.5 } do
		part(model, "SignPost", Vector3.new(0.2, 3, 0.2), CFrame.new(x, 1.5, 0.3), COLOR_BEZEL, Enum.Material.Metal)
	end
	local board = part(model, "SignBoard", Vector3.new(3.8, 1.8, 0.2), CFrame.new(0, 3.9, 0.3), COLOR_SCREEN, Enum.Material.SmoothPlastic)
	label(board, Enum.NormalId.Front, "GOOD VIBES", COLOR_PINK)
	local tubes: { { Size: Vector3, At: CFrame } } = {
		{ Size = Vector3.new(3.8, 0.12, 0.12), At = CFrame.new(0, 4.85, 0.15) },
		{ Size = Vector3.new(3.8, 0.12, 0.12), At = CFrame.new(0, 2.95, 0.15) },
		{ Size = Vector3.new(0.12, 1.9, 0.12), At = CFrame.new(-1.9, 3.9, 0.15) },
		{ Size = Vector3.new(0.12, 1.9, 0.12), At = CFrame.new(1.9, 3.9, 0.15) },
	}
	for index, tube in tubes do
		local neon = trim(part(model, "SignTube", tube.Size, tube.At, COLOR_PINK, Enum.Material.Neon))
		nightLight(neon, COLOR_PINK, if index == 1 then 14 else nil)
	end
end

-- A framed retro poster on a stand at wall height.
local function posterFrame(model: Model)
	part(model, "PosterFoot", Vector3.new(1.4, 0.15, 1), CFrame.new(0, 0.075, 0.2), COLOR_BEZEL, Enum.Material.Metal)
	part(model, "PosterPost", Vector3.new(0.2, 3.9, 0.2), CFrame.new(0, 1.95, 0.45), COLOR_BEZEL, Enum.Material.Metal)
	part(model, "PosterFrame", Vector3.new(1.8, 2.6, 0.15), CFrame.new(0, 5.2, 0.35), COLOR_BEZEL, Enum.Material.Wood)
	local poster = trim(part(model, "Poster", Vector3.new(1.6, 2.4, 0.05), CFrame.new(0, 5.2, 0.25), COLOR_PINK, Enum.Material.SmoothPlastic))
	local text = label(poster, Enum.NormalId.Front, "SHIP\nIT", COLOR_AMBER)
	-- A sunset backdrop behind the text (a gradient on the label itself would tint the text too).
	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(1, 1, 1)
	backdrop.ZIndex = 0
	backdrop.Parent = text.Parent
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(COLOR_PINK, COLOR_ACCENT_DARK)
	gradient.Rotation = 90
	gradient.Parent = backdrop
end

local function beanbag(model: Model)
	local color = Color3.fromRGB(200, 90, 150)
	ball(model, "BeanbagSeat", 1.8, CFrame.new(0, 0.6, 0), color, Enum.Material.Fabric)
	trim(ball(model, "BeanbagBack", 1.3, CFrame.new(0, 1.2, 0.4), color:Lerp(Color3.new(0, 0, 0), 0.1), Enum.Material.Fabric))
end

local function bookshelf(model: Model)
	part(model, "ShelfBack", Vector3.new(3.8, 6, 0.2), CFrame.new(0, 3, 0.8), COLOR_DESK, Enum.Material.Wood)
	for _, x in { -1.8, 1.8 } do
		part(model, "ShelfSide", Vector3.new(0.2, 6, 1.6), CFrame.new(x, 3, 0.1), COLOR_DESK, Enum.Material.Wood)
	end
	for _, y in { 0.1, 2, 4, 5.92 } do
		part(model, "ShelfBoard", Vector3.new(3.4, 0.15, 1.5), CFrame.new(0, y, 0.05), COLOR_DESK, Enum.Material.Wood)
	end
	local bookColors = { COLOR_PINK, COLOR_CYAN, COLOR_AMBER, Color3.fromRGB(120, 110, 220), Color3.fromRGB(220, 90, 90) }
	for row, y in { 0.85, 2.75, 4.75 } do
		for slot = 1, 8 do
			if (slot + row) % 5 == 0 then
				continue -- a gap now and then, so it looks lived in
			end
			trim(part(model, "Book", Vector3.new(0.35, 1.3, 1.1), CFrame.new(-1.75 + slot * 0.39, y, 0.1), bookColors[(row + slot) % #bookColors + 1], Enum.Material.SmoothPlastic))
		end
	end
end

-- A wooden arch with a sagging string of warm bulbs.
local function stringLights(model: Model)
	for _, x in { -1.8, 1.8 } do
		part(model, "ArchPost", Vector3.new(0.25, 6, 0.25), CFrame.new(x, 3, 0), COLOR_DESK, Enum.Material.Wood)
	end
	part(model, "ArchBeam", Vector3.new(3.85, 0.25, 0.25), CFrame.new(0, 6.1, 0), COLOR_DESK, Enum.Material.Wood)
	local count = 9
	local previous: Vector3? = nil
	for index = 0, count - 1 do
		local x = -1.6 + index * (3.2 / (count - 1))
		local position = Vector3.new(x, 5.9 - 0.6 * (1 - (x / 1.6) ^ 2), 0)
		local bulb = trim(ball(model, "Bulb", 0.22, CFrame.new(position), COLOR_AMBER, Enum.Material.Neon))
		nightLight(bulb, COLOR_AMBER, if index == count // 2 then 14 else nil)
		if previous then
			local length = (position - previous).Magnitude
			trim(part(model, "Wire", Vector3.new(0.04, 0.04, length), CFrame.lookAt((position + previous) / 2, position), COLOR_BEZEL, Enum.Material.SmoothPlastic))
		end
		previous = position
	end
end

local function fairyPlant(model: Model)
	pottedPlant(model)
	for index = 1, 8 do
		local angle = index * math.pi / 4
		local y = 2.1 + (if index % 2 == 0 then 0.45 else -0.3)
		local bulb = trim(ball(model, "FairyBulb", 0.16, CFrame.new(math.cos(angle) * 0.85, y, math.sin(angle) * 0.85), COLOR_AMBER, Enum.Material.Neon))
		nightLight(bulb, COLOR_AMBER, if index == 1 then 10 else nil)
	end
end

-- A round bed with a sleeping orange cat.
local function catBed(model: Model)
	cylinder(model, "CatBed", 0.5, 1.8, CFrame.new(0, 0.25, 0) * UPRIGHT, Color3.fromRGB(150, 100, 140), Enum.Material.Fabric)
	trim(cylinder(model, "CatCushion", 0.32, 1.4, CFrame.new(0, 0.4, 0) * UPRIGHT, COLOR_FABRIC_WARM, Enum.Material.Fabric))
	trim(cylinder(model, "CatBody", 0.85, 0.55, CFrame.new(0.1, 0.8, 0.1), COLOR_CAT, Enum.Material.Fabric))
	local head = trim(ball(model, "CatHead", 0.5, CFrame.new(-0.45, 0.78, -0.1), COLOR_CAT, Enum.Material.Fabric))
	for _, x in { -0.57, -0.35 } do
		trim(part(model, "CatEar", Vector3.new(0.12, 0.18, 0.08), CFrame.new(x, 1.05, -0.12), COLOR_CAT, Enum.Material.Fabric))
	end
	trim(cylinder(model, "CatTail", 0.6, 0.14, CFrame.new(0.4, 0.62, -0.3) * CFrame.Angles(0, math.rad(40), 0), COLOR_CAT, Enum.Material.Fabric))
	local snore = Instance.new("BillboardGui")
	snore.Size = UDim2.fromOffset(60, 30)
	snore.StudsOffset = Vector3.new(0.3, 0.9, 0)
	snore.MaxDistance = 40
	snore.Parent = head
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextColor3 = COLOR_CYAN
	text.Font = Enum.Font.Arcade
	text.TextScaled = true
	text.Text = "z Z"
	text.Parent = snore
end

local function sideTable(model: Model)
	cylinder(model, "TableBase", 0.1, 1.1, CFrame.new(0, 0.05, 0) * UPRIGHT, COLOR_BEZEL, Enum.Material.Metal)
	cylinder(model, "TableStem", 2.3, 0.25, CFrame.new(0, 1.2, 0) * UPRIGHT, COLOR_BEZEL, Enum.Material.Metal)
	cylinder(model, "TableTop", 0.15, 1.6, CFrame.new(0, 2.42, 0) * UPRIGHT, COLOR_DESK, Enum.Material.Wood)
	trim(cylinder(model, "Mug", 0.45, 0.4, CFrame.new(0.2, 2.72, -0.1) * UPRIGHT, COLOR_PINK, Enum.Material.SmoothPlastic))
	trim(part(model, "MugHandle", Vector3.new(0.08, 0.25, 0.08), CFrame.new(0.44, 2.72, -0.1), COLOR_PINK, Enum.Material.SmoothPlastic))
	trim(cylinder(model, "Coffee", 0.02, 0.32, CFrame.new(0.2, 2.94, -0.1) * UPRIGHT, Color3.fromRGB(70, 40, 25), Enum.Material.SmoothPlastic))
end

-- Fixed office item: the reception desk with the shop computer and the job phone (their prompts travel with it).
-- The screen faces local -Z, where the player stands.
local function prompt(target: BasePart, tag: string, actionText: string, objectText: string)
	local newPrompt = Instance.new("ProximityPrompt")
	newPrompt.ActionText = actionText
	newPrompt.ObjectText = objectText
	newPrompt.HoldDuration = 0
	newPrompt.MaxActivationDistance = 10
	newPrompt.RequiresLineOfSight = false
	newPrompt.Parent = target
	CollectionService:AddTag(target, tag)
end

local function receptionDesk(model: Model)
	part(model, "ReceptionTop", Vector3.new(5, 0.25, 2.6), CFrame.new(0, 3, 0), COLOR_DESK, Enum.Material.Wood)
	part(model, "ReceptionFront", Vector3.new(5, 3, 0.2), CFrame.new(0, 1.5, 1.2), COLOR_DESK, Enum.Material.Wood)
	for _, x in { -2.3, 2.3 } do
		part(model, "ReceptionLeg", Vector3.new(0.25, 3, 2.4), CFrame.new(x, 1.5, 0), COLOR_BEZEL, Enum.Material.Metal)
	end
	part(model, "ShopComputerBezel", Vector3.new(2.6, 1.6, 0.15), CFrame.new(-0.6, 4.1, 0.5), COLOR_BEZEL, Enum.Material.SmoothPlastic)
	local screen = part(model, "ShopComputer", Vector3.new(2.4, 1.4, 0.1), CFrame.new(-0.6, 4.1, 0.4), COLOR_SCREEN, Enum.Material.Glass)
	label(screen, Enum.NormalId.Front, "SHOP", COLOR_AMBER, COLOR_SCREEN)
	nightLight(screen, COLOR_AMBER, 6)
	prompt(screen, "ShopComputer", "Browse", "Computer")
	part(model, "ShopComputerStand", Vector3.new(0.3, 0.8, 0.3), CFrame.new(-0.6, 3.5, 0.6), COLOR_BEZEL, Enum.Material.Metal)
	part(model, "Keyboard", Vector3.new(1.8, 0.1, 0.6), CFrame.new(-0.6, 3.18, -0.5), COLOR_BEZEL, Enum.Material.SmoothPlastic)
	local phone = part(model, "JobPhone", Vector3.new(0.6, 0.12, 1.1), CFrame.new(1.7, 3.19, -0.3), COLOR_SCREEN, Enum.Material.Glass)
	nightLight(phone, COLOR_CYAN, 6)
	prompt(phone, "JobPhone", "Check jobs", "Phone")
end

local BUILDERS: { [string]: (Model) -> () } = {
	ReceptionDesk = receptionDesk,
	CoffeeMachine = coffeeMachine,
	LoungeCouch = loungeCouch,
	ArcadeCabinet = arcadeCabinet,
	Plant = plant,
	Rug = rug,
	FloorLamp = floorLamp,
	NeonSign = neonSign,
	PosterFrame = posterFrame,
	Beanbag = beanbag,
	Bookshelf = bookshelf,
	StringLights = stringLights,
	FairyPlant = fairyPlant,
	CatBed = catBed,
	SideTable = sideTable,
}

for id in GameConfig.DECOR do
	assert(BUILDERS[id], `DecorModels: no model for decor item "{id}"`)
end

-- A new, unparented model of a catalog item; PivotTo it into place.
function DecorModels.Build(id: string): Model
	local builder = BUILDERS[id]
	assert(builder, `DecorModels: no model for decor item "{id}"`)
	local model = Instance.new("Model")
	model.Name = id
	builder(model)
	model.WorldPivot = CFrame.identity
	return model
end

-- Where an item sits: cell (x, z) with footprint (w, d) cells at rotation r, in the unit whose floor origin is given.
function DecorModels.CellCFrame(origin: CFrame, x: number, z: number, w: number, d: number, r: number): CFrame
	local zone = GameConfig.DECOR_ZONE
	return origin
		* CFrame.new(zone.OffsetX + (x + w / 2) * zone.CellSize, 0, zone.OffsetZ + (z + d / 2) * zone.CellSize)
		* CFrame.Angles(0, math.rad(-r), 0)
end

return DecorModels
