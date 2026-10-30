--!strict
-- Decorate mode (Act 2+): a top-down camera over the office's decorate zone, a cell grid, a shop panel and a ghost
-- preview that snaps to the grid. The client only previews with Decor.CanPlace; every buy, move and sell is a
-- request that DecorService checks again and answers with DecorResult.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Decor = require(Shared:WaitForChild("Decor"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local DecorModels = require(ReplicatedStorage:WaitForChild("World"):WaitForChild("DecorModels"))
local CutsceneController = require(script.Parent:WaitForChild("CutsceneController"))
local UI = script.Parent.Parent:WaitForChild("UI")
local ClientState = require(UI:WaitForChild("ClientState"))
local Juice = require(UI:WaitForChild("Juice"))
local Sfx = require(UI:WaitForChild("Sfx"))
local Theme = require(UI:WaitForChild("Theme"))

local ZONE = GameConfig.DECOR_ZONE
local CAMERA_HEIGHT = 45
local GRID_TRANSPARENCY = 0.6
local GHOST_TRANSPARENCY = 0.5
local POLL_SECONDS = 0.25
local REPLY_TIMEOUT = 5
local SELL_CONFIRM_SECONDS = 3
local PICK_GUARD_SECONDS = 0.2
local STICK_PRESS = 0.6
local STICK_RELEASE = 0.3
-- While one of these is open the player is in a battle, minigame or burst, and can't decorate.
local BUSY_GUIS = { "Battle", "Minigame", "Burst" }
local COLOR_OK = Color3.fromRGB(90, 255, 140)
-- Gamepad shortcut into decorate mode while the button shows; no other controller binds ButtonY.
local ENTER_ACTION = "DecorateEnter"
local ENTER_KEY = Enum.KeyCode.ButtonY
local DPAD_STEPS: { [Enum.KeyCode]: Vector2 } = {
	[Enum.KeyCode.DPadLeft] = Vector2.new(-1, 0),
	[Enum.KeyCode.DPadRight] = Vector2.new(1, 0),
	[Enum.KeyCode.DPadUp] = Vector2.new(0, -1),
	[Enum.KeyCode.DPadDown] = Vector2.new(0, 1),
}

type Ghost = { Model: Model, Highlight: Highlight, Id: string, R: number, MoveIndex: number? }
type Row = { Button: TextButton, Label: TextLabel }

local DecorateController = {}

local player = Players.LocalPlayer

-- Latest server state (StateSync).
local act = 1
local cash = 0
local decor: { Decor.Placement } = {}

-- Decorate-mode session; everything below is reset by exit().
local active = false
local origin = CFrame.identity
local world: Folder? = nil
local cursorPart: Part? = nil
local selectHighlight: Highlight? = nil
local connections: { RBXScriptConnection } = {}
local ghost: Ghost? = nil
local cursorX, cursorZ = 0, 0
local selected: number? = nil
local selectedId: string? = nil
local pending = false
local pendingToken = 0
local pendingDone = ""
local sellArmedAt = 0
local pickedAt = 0
local stickHeld = false
local savedTouchControls = true
local savedPrompts = true

local gui: ScreenGui
local decorateButton: TextButton
local root: Frame
local panel: Frame
local bar: Frame
local statusLabel: TextLabel
local placeButton: TextButton
local rotateButton: TextButton
local moveButton: TextButton
local sellButton: TextButton
local rows: { [string]: Row } = {}
local firstRow: TextButton? = nil

local function ownUnit(): Model?
	local index = player:GetAttribute("Unit")
	local floor = Workspace:FindFirstChild("Megablock")
	if not floor or index == nil then
		return nil
	end
	for _, unit in floor:GetChildren() do
		if unit:IsA("Model") and unit:GetAttribute("Unit") == index then
			return unit
		end
	end
	return nil
end

local function rootPart(): BasePart?
	local character = player.Character
	local found = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if found and found:IsA("BasePart") then found else nil
end

-- The same bounds DecorService checks: the root above the unit's floor.
local function insideOwnUnit(): boolean
	local unit = ownUnit()
	local floor = if unit then unit:FindFirstChild("Floor") else nil
	local hrp = rootPart()
	if not floor or not floor:IsA("BasePart") or not hrp then
		return false
	end
	local offset = floor.CFrame:PointToObjectSpace(hrp.Position)
	return math.abs(offset.X) <= floor.Size.X / 2 and math.abs(offset.Z) <= floor.Size.Z / 2
end

local function busyElsewhere(): boolean
	if CutsceneController.IsPlaying() then
		return true
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		for _, name in BUSY_GUIS do
			local other = playerGui:FindFirstChild(name)
			if other and other:IsA("ScreenGui") and other.Enabled then
				return true
			end
		end
	end
	return false
end

local function canDecorate(): boolean
	return act >= 2 and insideOwnUnit() and not busyElsewhere()
end

local function usingGamepad(): boolean
	return UserInputService.PreferredInput == Enum.PreferredInput.Gamepad
end

local function hint(): string
	if usingGamepad() then
		return "A place / select  ·  X rotate  ·  Y menu  ·  B back"
	elseif UserInputService.PreferredInput == Enum.PreferredInput.Touch then
		return "Pick an item, tap the floor to move it, then Place. Tap a placed item to move or sell it."
	end
	return "Pick an item, click to place, R to rotate. Click a placed item to move or sell it."
end

local function setStatus(text: string)
	statusLabel.Text = text
	statusLabel.TextColor3 = Theme.TEXT
end

local function fail(reason: string)
	statusLabel.Text = reason
	statusLabel.TextColor3 = Theme.BUG
	Juice.Shake(bar)
	Sfx.Play("KeyWrong")
end

local function hasItem(id: string): boolean
	for _, entry in decor do
		if entry.Id == id then
			return true
		end
	end
	return false
end

local function footprint(id: string, r: number): (number, number)
	return Decor.Footprint(GameConfig.DECOR[id], r)
end

-- The placed item covering a cell, as its index in the save's Decor list.
local function itemAt(x: number, z: number): number?
	for index, entry in decor do
		local def = GameConfig.DECOR[entry.Id]
		if def then
			local w, d = Decor.Footprint(def, entry.R)
			if x >= entry.X and x < entry.X + w and z >= entry.Z and z < entry.Z + d then
				return index
			end
		end
	end
	return nil
end

-- The built model of a placed item; DecorService tags each with its save index.
local function placedModel(index: number): Model?
	local unit = ownUnit()
	local contents = if unit then unit:FindFirstChild("Contents") else nil
	local folder = if contents then contents:FindFirstChild("Decor") else nil
	if not folder then
		return nil
	end
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("DecorIndex") == index then
			return child
		end
	end
	return nil
end

-- The ghost's corner cell: centred on the cursor where it fits, pushed back inside the zone where it doesn't.
local function ghostCell(current: Ghost): (number, number)
	local w, d = footprint(current.Id, current.R)
	local x = math.clamp(cursorX - (w - 1) // 2, 0, ZONE.CellsX - w)
	local z = math.clamp(cursorZ - (d - 1) // 2, 0, ZONE.CellsZ - d)
	return x, z
end

local function check(current: Ghost): (boolean, string?)
	local x, z = ghostCell(current)
	local item: Decor.Placement = { Id = current.Id, X = x, Z = z, R = current.R }
	local ok, reason = Decor.CanPlace(decor, GameConfig.DECOR, ZONE, item, current.MoveIndex)
	if ok and current.MoveIndex == nil and cash < GameConfig.DECOR[current.Id].Price then
		return false, "Not enough cash"
	end
	return ok, reason
end

local function setEnabled(button: TextButton, enabled: boolean)
	button.AutoButtonColor = enabled
	button.TextTransparency = if enabled then 0 else 0.6
end

local function refreshButtons()
	placeButton.Visible = ghost ~= nil
	setEnabled(rotateButton, ghost ~= nil)
	setEnabled(moveButton, selected ~= nil)
	setEnabled(sellButton, selected ~= nil)
end

local function refreshWorld()
	if not active then
		return
	end
	if cursorPart then
		cursorPart.CFrame = DecorModels.CellCFrame(origin, cursorX, cursorZ, 1, 1, 0) * CFrame.new(0, 0.06, 0)
		cursorPart.Transparency = if ghost then 1 else 0.5
	end
	local current = ghost
	if current then
		local x, z = ghostCell(current)
		local w, d = footprint(current.Id, current.R)
		current.Model:PivotTo(DecorModels.CellCFrame(origin, x, z, w, d, current.R))
		local color = if check(current) then COLOR_OK else Theme.BUG
		current.Highlight.FillColor = color
		current.Highlight.OutlineColor = color
	end
	refreshButtons()
end

local function perkText(def: GameConfig.DecorDef): string
	local perk = def.Perk
	if not perk then
		return "Decor"
	end
	local lines: { string } = {}
	if perk.Speed then
		table.insert(lines, `+{math.round(perk.Speed * 100)}% build speed`)
	end
	if perk.GradeAChance then
		table.insert(lines, `+{math.round(perk.GradeAChance * 100)}% grade A chance`)
	end
	return table.concat(lines, ", ")
end

local function refreshRows()
	for id, row in rows do
		local def = GameConfig.DECOR[id]
		local placed = def.Perk ~= nil and hasItem(id)
		local detail = if placed then "Placed" else perkText(def)
		row.Label.Text = `{def.Name}  <font color="#{Theme.MOOD:ToHex()}">${def.Price}</font>\n<font color="#{Theme.MUTED:ToHex()}">{detail}</font>`
		row.Label.TextTransparency = if placed or cash < def.Price then 0.45 else 0
	end
end

local function newHighlight(parent: Instance, color: Color3): Highlight
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = 0.55
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = parent
	return highlight
end

local function localPart(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, transparency: number): Part
	local newPart = Instance.new("Part")
	newPart.Anchored = true
	newPart.CanCollide = false
	newPart.CanQuery = false
	newPart.CanTouch = false
	newPart.CastShadow = false
	newPart.Material = Enum.Material.Neon
	newPart.Color = color
	newPart.Transparency = transparency
	newPart.Size = size
	newPart.CFrame = cframe
	newPart.Parent = parent
	return newPart
end

local function selectItem(index: number?)
	selected = index
	selectedId = if index and decor[index] then decor[index].Id else nil
	sellArmedAt = 0
	if selectHighlight then
		selectHighlight.Adornee = if index then placedModel(index) else nil
	end
	refreshButtons()
end

local function clearGhost()
	local current = ghost
	if current then
		current.Model:Destroy()
		current.Highlight:Destroy()
		ghost = nil
	end
end

local function makeGhost(id: string, r: number, moveIndex: number?)
	local parent = world
	if not parent then
		return
	end
	clearGhost()
	local model = DecorModels.Build(id)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = math.max(descendant.Transparency, GHOST_TRANSPARENCY)
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
		end
	end
	model.Parent = parent
	local highlight = newHighlight(parent, COLOR_OK)
	highlight.Adornee = model
	ghost = { Model = model, Highlight = highlight, Id = id, R = r, MoveIndex = moveIndex }
	refreshWorld()
end

local function send(done: string, name: string, ...: any)
	pending = true
	pendingDone = done
	pendingToken += 1
	local token = pendingToken
	RemoteManager.FireServer(name, ...)
	task.delay(REPLY_TIMEOUT, function()
		if pendingToken == token then
			pending = false
		end
	end)
end

local function pick(id: string)
	if not active then
		return
	end
	local def = GameConfig.DECOR[id]
	selectItem(nil)
	pickedAt = os.clock()
	-- Hand the gamepad from the menu to the grid.
	GuiService.SelectedObject = nil
	if def.Perk and hasItem(id) then
		clearGhost()
		refreshWorld()
		fail("Already have one")
		return
	end
	makeGhost(id, 0, nil)
	setStatus(`{def.Name}  ${def.Price}`)
end

local function confirm()
	local current = ghost
	if not active or pending or not current then
		return
	end
	local ok, reason = check(current)
	if not ok then
		fail(reason or "Can't place that there")
		return
	end
	local x, z = ghostCell(current)
	if current.MoveIndex then
		send("Moved.", RemoteNames.DecorMove, current.MoveIndex, x, z, current.R)
	else
		send("Placed.", RemoteNames.DecorPlace, current.Id, x, z, current.R)
	end
end

local function rotate()
	local current = ghost
	if current then
		current.R = (current.R + 90) % 360
		refreshWorld()
	end
end

local function startMove()
	local index = selected
	local entry = if index then decor[index] else nil
	if not active or not index or not entry then
		return
	end
	local w, d = footprint(entry.Id, entry.R)
	-- Put the cursor where ghostCell maps it back onto the item's current corner.
	cursorX, cursorZ = entry.X + (w - 1) // 2, entry.Z + (d - 1) // 2
	selectItem(nil)
	makeGhost(entry.Id, entry.R, index)
	pickedAt = os.clock()
	GuiService.SelectedObject = nil
	setStatus("Move it, then place it.")
end

local function sell()
	local index = selected
	local entry = if index then decor[index] else nil
	if not active or pending or not index or not entry then
		return
	end
	if os.clock() - sellArmedAt > SELL_CONFIRM_SECONDS then
		local def = GameConfig.DECOR[entry.Id]
		local refund = if def then math.floor(def.Price * GameConfig.DECOR_SELL_RATE) else 0
		sellArmedAt = os.clock()
		setStatus(`Sell {if def then def.Name else "it"} for ${refund}? Press Sell again.`)
		return
	end
	sellArmedAt = 0
	send("Sold.", RemoteNames.DecorSell, index)
end

local function moveCursor(dx: number, dz: number)
	cursorX = math.clamp(cursorX + dx, 0, ZONE.CellsX - 1)
	cursorZ = math.clamp(cursorZ + dz, 0, ZONE.CellsZ - 1)
	refreshWorld()
end

-- The zone cell under a screen point: the camera ray meets the floor plane, in the unit's own space.
local function cellAtScreen(x: number, y: number): (number?, number?)
	local ray = Workspace.CurrentCamera:ScreenPointToRay(x, y)
	local from = origin:PointToObjectSpace(ray.Origin)
	local direction = origin:VectorToObjectSpace(ray.Direction)
	if direction.Y >= 0 then
		return nil, nil
	end
	local hit = from + direction * (-from.Y / direction.Y)
	local cellX = math.floor((hit.X - ZONE.OffsetX) / ZONE.CellSize)
	local cellZ = math.floor((hit.Z - ZONE.OffsetZ) / ZONE.CellSize)
	if cellX < 0 or cellZ < 0 or cellX >= ZONE.CellsX or cellZ >= ZONE.CellsZ then
		return nil, nil
	end
	return cellX, cellZ
end

local function focusMenu()
	GuiService.SelectedObject = if selected then moveButton else firstRow
end

local function setAnchored(anchored: boolean)
	local hrp = rootPart()
	if hrp then
		hrp.Anchored = anchored
	end
end

local function exit()
	if not active then
		return
	end
	active = false
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	clearGhost()
	if world then
		world:Destroy()
	end
	world = nil
	cursorPart = nil
	selectHighlight = nil
	selected = nil
	selectedId = nil
	pendingToken += 1
	pending = false
	stickHeld = false
	GuiService.TouchControlsEnabled = savedTouchControls
	ProximityPromptService.Enabled = savedPrompts
	local focused = GuiService.SelectedObject
	if focused and focused:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
	root.Visible = false
	Sfx.Play("CardClose")
	-- A cutscene that cut in has already taken the camera and frozen the character, and hands both back itself.
	if not CutsceneController.IsPlaying() then
		local camera = Workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Custom
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid then
			camera.CameraSubject = humanoid
		end
		setAnchored(false)
	end
end

local function onInputBegan(input: InputObject, processed: boolean)
	local key = input.KeyCode
	-- Gamepad buttons skip `processed`: the default controls bind ButtonA to jump, which marks it processed.
	if key == Enum.KeyCode.ButtonB then
		-- Back unwinds one layer: menu focus, then the ghost or selection, then decorate mode itself.
		if GuiService.SelectedObject then
			GuiService.SelectedObject = nil
		elseif ghost or selected then
			clearGhost()
			selectItem(nil)
			refreshWorld()
			setStatus(hint())
		else
			exit()
		end
		return
	end
	if GuiService.SelectedObject then
		return -- the gamepad is driving the menu
	end
	local step = DPAD_STEPS[key]
	if step then
		moveCursor(step.X, step.Y)
	elseif key == Enum.KeyCode.ButtonA then
		if os.clock() - pickedAt < PICK_GUARD_SECONDS then
			return -- the press that picked the item from the menu
		end
		if ghost then
			confirm()
		else
			selectItem(itemAt(cursorX, cursorZ))
		end
	elseif key == Enum.KeyCode.ButtonX then
		rotate()
	elseif key == Enum.KeyCode.ButtonY then
		focusMenu()
	elseif processed then
		return
	elseif key == Enum.KeyCode.R then
		rotate()
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		local x, z = cellAtScreen(input.Position.X, input.Position.Y)
		if not x or not z then
			return
		end
		cursorX, cursorZ = x, z
		if not ghost then
			selectItem(itemAt(x, z))
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			confirm() -- a tap only moves the ghost; the Place button confirms
		end
		refreshWorld()
	end
end

local function onInputChanged(input: InputObject, processed: boolean)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		if processed then
			return
		end
		local x, z = cellAtScreen(input.Position.X, input.Position.Y)
		if x and z and (x ~= cursorX or z ~= cursorZ) then
			cursorX, cursorZ = x, z
			refreshWorld()
		end
	elseif input.KeyCode == Enum.KeyCode.Thumbstick1 and not GuiService.SelectedObject then
		-- One cell per push: the stick has to come back toward the centre before it steps again.
		local stick = input.Position
		local magnitude = Vector2.new(stick.X, stick.Y).Magnitude
		if not stickHeld and magnitude > STICK_PRESS then
			stickHeld = true
			if math.abs(stick.X) > math.abs(stick.Y) then
				moveCursor(math.sign(stick.X), 0)
			else
				moveCursor(0, -math.sign(stick.Y)) -- stick up is screen up, toward the back wall (-Z)
			end
		elseif stickHeld and magnitude < STICK_RELEASE then
			stickHeld = false
		end
	end
end

local function buildWorld(parent: Folder)
	local width = ZONE.CellsX * ZONE.CellSize
	local depth = ZONE.CellsZ * ZONE.CellSize
	for index = 0, ZONE.CellsX do
		local x = ZONE.OffsetX + index * ZONE.CellSize
		localPart(parent, Vector3.new(0.1, 0.05, depth), origin * CFrame.new(x, 0.03, ZONE.OffsetZ + depth / 2), Theme.TYPED, GRID_TRANSPARENCY)
	end
	for index = 0, ZONE.CellsZ do
		local z = ZONE.OffsetZ + index * ZONE.CellSize
		localPart(parent, Vector3.new(width, 0.05, 0.1), origin * CFrame.new(ZONE.OffsetX + width / 2, 0.03, z), Theme.TYPED, GRID_TRANSPARENCY)
	end
	local cellSize = ZONE.CellSize - 0.2
	cursorPart = localPart(parent, Vector3.new(cellSize, 0.06, cellSize), origin, Theme.ACCENT, 0.5)
	selectHighlight = newHighlight(parent, Theme.ACCENT)
end

local function enter()
	if active or not canDecorate() then
		return
	end
	local unit = ownUnit()
	local unitOrigin = if unit then unit:GetAttribute("OriginCFrame") else nil
	if not unit or typeof(unitOrigin) ~= "CFrame" then
		return
	end
	active = true
	origin = unitOrigin
	cursorX, cursorZ = ZONE.CellsX // 2, ZONE.CellsZ // 2
	pickedAt = 0

	setAnchored(true)
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local center = origin
		* Vector3.new(ZONE.OffsetX + ZONE.CellsX * ZONE.CellSize / 2, 0, ZONE.OffsetZ + ZONE.CellsZ * ZONE.CellSize / 2)
	-- Straight down, with the back wall at the top of the screen.
	camera.CFrame = CFrame.lookAt(center + Vector3.new(0, CAMERA_HEIGHT, 0), center, origin.LookVector)
	savedTouchControls = GuiService.TouchControlsEnabled
	GuiService.TouchControlsEnabled = false
	-- No station, shop or phone prompts while the player is placing things.
	savedPrompts = ProximityPromptService.Enabled
	ProximityPromptService.Enabled = false

	local folder = Instance.new("Folder")
	folder.Name = "DecorateMode"
	buildWorld(folder)
	folder.Parent = Workspace
	world = folder

	table.insert(connections, UserInputService.InputBegan:Connect(onInputBegan))
	table.insert(connections, UserInputService.InputChanged:Connect(onInputChanged))
	table.insert(connections, player.CharacterRemoving:Connect(exit))
	table.insert(connections, player:GetAttributeChangedSignal("Unit"):Connect(exit))
	table.insert(connections, unit.AncestryChanged:Connect(function()
		if not unit:IsDescendantOf(Workspace) then
			exit()
		end
	end))
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		table.insert(connections, humanoid.Died:Connect(exit))
	end

	decorateButton.Visible = false
	ContextActionService:UnbindAction(ENTER_ACTION) -- inside the mode, Y focuses the menu instead
	root.Visible = true
	Juice.PopIn(panel)
	Juice.PopIn(bar)
	Sfx.Play("CardOpen")
	refreshRows()
	setStatus(hint())
	if usingGamepad() then
		GuiService.SelectedObject = firstRow
	end
	refreshWorld()
end

local function onStateSync(view: any)
	if type(view) ~= "table" then
		return
	end
	act = tonumber(view.Act) or 1
	cash = tonumber(view.Cash) or 0
	decor = if type(view.Decor) == "table" then view.Decor else {}
	local index = selected
	if index and (not decor[index] or decor[index].Id ~= selectedId) then
		selectItem(nil)
	end
	refreshRows()
	refreshWorld()
end

local function onResult(ok: any, reason: any)
	pendingToken += 1
	pending = false
	if not active then
		return
	end
	if ok == true then
		Sfx.Play("PromptClean")
		clearGhost()
		selectItem(nil)
		refreshWorld()
		setStatus(pendingDone)
	else
		fail(if type(reason) == "string" then reason else "That didn't work.")
	end
end

local function icon(parent: GuiObject, id: string)
	local viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.fromOffset(44, 44)
	viewport.AnchorPoint = Vector2.new(0, 0.5)
	viewport.Position = UDim2.new(0, 6, 0.5, 0)
	viewport.BackgroundColor3 = Theme.BACKGROUND
	viewport.BorderSizePixel = 0
	viewport.Ambient = Color3.fromRGB(200, 190, 220)
	viewport.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = viewport

	local model = DecorModels.Build(id)
	model.Parent = viewport
	local box, size = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	-- Front three-quarter view (items face -Z), far enough back to fit the whole bounding sphere.
	camera.CFrame = CFrame.lookAt(box.Position + Vector3.new(0.5, 0.45, -1).Unit * size.Magnitude * 1.5, box.Position)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

local function barButton(parent: Instance, text: string, order: number, onActivated: () -> ()): TextButton
	local button = Theme.Button(parent, text, 15)
	button.Size = UDim2.fromOffset(84, 40)
	button.LayoutOrder = order
	button.Activated:Connect(onActivated)
	return button
end

function DecorateController.Init()
	gui = Theme.Screen("Decorate", 3)
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	decorateButton = Theme.Button(gui, "DECORATE", 16)
	decorateButton.Size = UDim2.fromOffset(150, 44)
	decorateButton.AnchorPoint = Vector2.new(0, 1)
	decorateButton.Position = UDim2.new(0, 16, 1, -16)
	decorateButton.Visible = false
	decorateButton.Activated:Connect(enter)

	root = Instance.new("Frame")
	root.Name = "DecorateMode"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Visible = false
	-- Gamepad focus stays inside decorate mode's own buttons.
	root.SelectionGroup = true
	root.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	root.Parent = gui

	-- Shop panel on the right, clear of the bottom bar.
	panel = Theme.Panel(root, UDim2.new(0, 250, 1, -136), UDim2.new(1, -12, 0, 12))
	panel.AnchorPoint = Vector2.new(1, 0)
	Theme.List(panel, 6)
	local title = Theme.Text(panel, "DECOR SHOP", 16, Theme.ACCENT)
	title.LayoutOrder = 1
	local scroll = Instance.new("ScrollingFrame")
	scroll.LayoutOrder = 2
	scroll.Size = UDim2.new(1, 0, 1, -28)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = Theme.ACCENT
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel
	Theme.List(scroll, 6)

	-- Perks first, then cheapest first.
	local ids: { string } = {}
	for id in GameConfig.DECOR do
		table.insert(ids, id)
	end
	table.sort(ids, function(a: string, b: string): boolean
		local defA, defB = GameConfig.DECOR[a], GameConfig.DECOR[b]
		if (defA.Perk ~= nil) ~= (defB.Perk ~= nil) then
			return defA.Perk ~= nil
		end
		if defA.Price ~= defB.Price then
			return defA.Price < defB.Price
		end
		return a < b
	end)
	for order, id in ids do
		local button = Theme.Button(scroll, "", 14)
		button.Size = UDim2.new(1, -8, 0, 56)
		button.LayoutOrder = order
		button.Activated:Connect(function()
			pick(id)
		end)
		icon(button, id)
		local label = Theme.Text(button, "", 14)
		label.AutomaticSize = Enum.AutomaticSize.None
		label.Size = UDim2.new(1, -60, 1, 0)
		label.Position = UDim2.fromOffset(56, 0)
		label.RichText = true
		label.TextYAlignment = Enum.TextYAlignment.Center
		rows[id] = { Button = button, Label = label }
		if order == 1 then
			firstRow = button
		end
	end

	-- Bottom bar: a status line over the action buttons. Positioned directly, so Juice.Shake can move it.
	bar = Theme.Panel(root, UDim2.fromOffset(470, 0), UDim2.new(0.5, 0, 1, -12))
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.AutomaticSize = Enum.AutomaticSize.Y
	Theme.List(bar, 6)
	statusLabel = Theme.Text(bar, "", 14)
	statusLabel.LayoutOrder = 1
	statusLabel.TextXAlignment = Enum.TextXAlignment.Center
	local buttonRow = Instance.new("Frame")
	buttonRow.LayoutOrder = 2
	buttonRow.Size = UDim2.new(1, 0, 0, 40)
	buttonRow.BackgroundTransparency = 1
	buttonRow.Parent = bar
	local rowLayout = Theme.List(buttonRow, 8)
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	placeButton = barButton(buttonRow, "Place", 1, confirm)
	rotateButton = barButton(buttonRow, "Rotate", 2, rotate)
	moveButton = barButton(buttonRow, "Move", 3, startMove)
	sellButton = barButton(buttonRow, "Sell", 4, sell)
	barButton(buttonRow, "Done", 5, exit)

	gui.Parent = player:WaitForChild("PlayerGui")
end

local function onEnterAction(_: string, state: Enum.UserInputState, _: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		enter()
	end
	return Enum.ContextActionResult.Sink
end

-- Shows or hides the DECORATE button, with its gamepad shortcut bound only while it shows.
local function showButton(shown: boolean)
	decorateButton.Visible = shown
	if not shown then
		ContextActionService:UnbindAction(ENTER_ACTION)
		return
	end
	ContextActionService:BindAction(ENTER_ACTION, onEnterAction, false, ENTER_KEY)
	local glyph = UserInputService:GetStringForKeyCode(ENTER_KEY, Enum.KeyCodeStringFormat.Abbreviated)
	decorateButton.Text = if usingGamepad() then `DECORATE ({if glyph ~= "" then glyph else "Y"})` else "DECORATE"
	-- On touch, sit above the thumbstick zone.
	local touch = UserInputService.PreferredInput == Enum.PreferredInput.Touch
	decorateButton.Position = UDim2.new(0, 16, 1, if touch then -150 else -16)
end

function DecorateController.Start()
	ClientState.OnChanged(onStateSync)
	RemoteManager.GetRemote(RemoteNames.DecorResult).OnClientEvent:Connect(onResult)

	-- The button follows state the server doesn't push (where the character stands, which UI is open), so poll it.
	task.spawn(function()
		while true do
			task.wait(POLL_SECONDS)
			local allowed = canDecorate()
			if active and not allowed then
				exit()
			end
			showButton(allowed and not active)
		end
	end)
end

return DecorateController
