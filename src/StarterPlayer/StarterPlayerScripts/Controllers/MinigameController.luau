--!strict
-- Screens for the non-typing station minigames. The server sends each puzzle step and judges every action;
-- this controller animates it, predicts taps for snappy feel, and closes when the result card arrives.
--   Patch Panel  (Server Rack):      tap tiles to rotate cables from the router to the server.
--   RAID Rebuild (Database Console): watch the drive bays flash, then repeat the sequence.
--   Training Run (AI Model Rig):     press when the loss needle is in the green zone.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PatchPanel = require(Shared:WaitForChild("PatchPanel"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local TrainingRun = require(Shared:WaitForChild("TrainingRun"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Juice = require(UI:WaitForChild("Juice"))
local Sfx = require(UI:WaitForChild("Sfx"))
local Theme = require(UI:WaitForChild("Theme"))

local TILE_SIZE = 62
local TILE_GAP = 6
local ARM_THICKNESS = 10
local BAY_COLORS = { Theme.ACCENT, Theme.TYPED, Theme.MOOD, Color3.fromRGB(150, 120, 255) }
local BAY_PITCHES = { 0.8, 1.0, 1.2, 1.45 } -- each bay has its own note, like a little synth
local HIT_COLORS: { [string]: Color3 } = { Perfect = Theme.MOOD, Good = Theme.TYPED, Miss = Theme.BUG }
local HIT_TEXT: { [string]: string } = { Perfect = "PERFECT!", Good = "GOOD", Miss = "MISS" }
local LOSS_FACTOR: { [string]: number } = { Perfect = 0.5, Good = 0.72, Miss = 1 }

local MinigameController = {}

local gui: ScreenGui
local panel: Frame
local titleLabel: TextLabel
local hintLabel: TextLabel
local body: Frame
local timerBack: Frame
local timerFill: Frame
local timerTween: Tween? = nil
local cleanup: { RBXScriptConnection } = {}
local kind = ""

local function clearBody()
	for _, connection in cleanup do
		connection:Disconnect()
	end
	table.clear(cleanup)
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if timerTween then
		timerTween:Cancel()
		timerTween = nil
	end
end

local function runTimer(seconds: number)
	if timerTween then
		timerTween:Cancel()
	end
	timerBack.Visible = true
	timerFill.Size = UDim2.fromScale(1, 1)
	local tween = TweenService:Create(timerFill, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) })
	tween:Play()
	timerTween = tween
end

local function open(title: string, hint: string, bodyHeight: number)
	clearBody()
	titleLabel.Text = title
	hintLabel.Text = hint
	body.Size = UDim2.new(1, 0, 0, bodyHeight)
	timerBack.Visible = false
	Juice.OpenWindow(gui, panel)
	Sfx.Play("CardOpen")
end

local function close()
	clearBody()
	kind = ""
	Juice.CloseWindow(gui, panel)
end

local function act(action: string, data: any)
	RemoteManager.FireServer(RemoteNames.MinigameAction, action, data)
end

-- Patch Panel ----------------------------------------------------------------

type TileView = { Button: TextButton, Glyph: Frame, Arms: { Frame }, Rotation: number }

local patchTiles: { TileView } = {}
local patchPuzzle: PatchPanel.Puzzle? = nil
local patchRotations: { number } = {}

-- Draws a tile's cable at rotation 0; the glyph frame is turned to show the rotation.
local function buildGlyph(button: TextButton, shape: string): (Frame, { Frame })
	local glyph = Instance.new("Frame")
	glyph.BackgroundTransparency = 1
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.Parent = button

	local arms: { Frame } = {}
	local function arm(position: UDim2, size: UDim2, anchor: Vector2)
		local piece = Instance.new("Frame")
		piece.BorderSizePixel = 0
		piece.BackgroundColor3 = Theme.TODO
		piece.AnchorPoint = anchor
		piece.Position = position
		piece.Size = size
		piece.Parent = glyph
		table.insert(arms, piece)
	end
	local half = UDim2.new(0, ARM_THICKNESS, 0.5, ARM_THICKNESS / 2)
	arm(UDim2.fromScale(0.5, 0), half, Vector2.new(0.5, 0)) -- north
	if shape == "Straight" then
		arm(UDim2.fromScale(0.5, 1), half, Vector2.new(0.5, 1)) -- south
	else
		arm(UDim2.fromScale(1, 0.5), UDim2.new(0.5, ARM_THICKNESS / 2, 0, ARM_THICKNESS), Vector2.new(1, 0.5)) -- east
	end
	local hub = Instance.new("Frame")
	hub.BorderSizePixel = 0
	hub.BackgroundColor3 = Theme.TODO
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromOffset(ARM_THICKNESS + 4, ARM_THICKNESS + 4)
	hub.Parent = glyph
	table.insert(arms, hub)
	return glyph, arms
end

-- Lights up every tile the cable currently reaches, starting from the router.
local function paintCable()
	local puzzle = patchPuzzle
	if not puzzle then
		return
	end
	local trace = PatchPanel.Trace(puzzle, patchRotations)
	local lit: { [number]: boolean } = {}
	for _, at in trace.Path do
		lit[at] = true
	end
	for at, tile in patchTiles do
		local color = if lit[at] then Theme.TYPED else Theme.TODO
		for _, piece in tile.Arms do
			piece.BackgroundColor3 = color
		end
	end
end

local function startPatch(data: any)
	open("PATCH PANEL", "Tap tiles to rotate the cables. Connect the router 📶 to the server 🖥.", 4 * (TILE_SIZE + TILE_GAP) + 10)
	local cols, rows = tonumber(data.Cols) or 5, tonumber(data.Rows) or 4
	local tiles: { PatchPanel.Tile } = {}
	for _, shape in data.Shapes do
		table.insert(tiles, { Shape = if shape == "Straight" then "Straight" else "Corner" })
	end
	patchPuzzle = {
		Cols = cols,
		Rows = rows,
		StartRow = tonumber(data.StartRow) or 1,
		EndRow = tonumber(data.EndRow) or 1,
		Tiles = tiles,
		Start = {},
		Solution = {},
		PathLength = 0,
	}
	patchRotations = {}
	table.clear(patchTiles)
	body.Size = UDim2.new(1, 0, 0, rows * (TILE_SIZE + TILE_GAP) + 10)

	local gridWidth = cols * (TILE_SIZE + TILE_GAP) - TILE_GAP
	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.AnchorPoint = Vector2.new(0.5, 0)
	grid.Position = UDim2.fromScale(0.5, 0)
	grid.Size = UDim2.fromOffset(gridWidth, rows * (TILE_SIZE + TILE_GAP))
	grid.Parent = body

	for at, shape in data.Shapes do
		local col = (at - 1) % cols
		local row = (at - 1) // cols
		local button = Instance.new("TextButton")
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundColor3 = Theme.PANEL
		button.Size = UDim2.fromOffset(TILE_SIZE, TILE_SIZE)
		button.Position = UDim2.fromOffset(col * (TILE_SIZE + TILE_GAP), row * (TILE_SIZE + TILE_GAP))
		button.Parent = grid
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = button

		local glyph, arms = buildGlyph(button, shape)
		local rotation = tonumber(data.Rotations[at]) or 0
		glyph.Rotation = rotation * 90
		patchRotations[at] = rotation
		local view: TileView = { Button = button, Glyph = glyph, Arms = arms, Rotation = rotation * 90 }
		patchTiles[at] = view

		table.insert(cleanup, button.Activated:Connect(function()
			-- Predict the turn locally so it feels instant; the server's answer confirms it.
			patchRotations[at] = (patchRotations[at] + 1) % 4
			view.Rotation += 90
			TweenService:Create(glyph, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = view.Rotation }):Play()
			Juice.Pop(button, 0.12)
			Sfx.Play("ChipTap", 0.9 + math.random() * 0.25)
			paintCable()
			act("Rotate", at)
		end))
	end

	-- Router and server markers on the edges of the grid.
	local function marker(text: string, row: number, left: boolean)
		local label = Theme.Text(grid, text, 30)
		label.AutomaticSize = Enum.AutomaticSize.None
		label.Size = UDim2.fromOffset(40, TILE_SIZE)
		label.AnchorPoint = Vector2.new(if left then 1 else 0, 0)
		label.Position = UDim2.fromOffset(if left then -8 else gridWidth + 8, (row - 1) * (TILE_SIZE + TILE_GAP))
		label.TextXAlignment = Enum.TextXAlignment.Center
	end
	marker("📶", tonumber(data.StartRow) or 1, true)
	marker("🖥", tonumber(data.EndRow) or 1, false)

	paintCable()
	runTimer(tonumber(data.TimeLimit) or 25)
end

local function onPatchRotated(data: any)
	local at = tonumber(data.Index)
	local view = at and patchTiles[at]
	if not view or not at then
		return
	end
	local rotation = tonumber(data.Rotation) or 0
	if patchRotations[at] ~= rotation then
		-- The prediction drifted (a dropped tap): snap to the server's rotation.
		patchRotations[at] = rotation
		view.Rotation = rotation * 90
		view.Glyph.Rotation = view.Rotation
		paintCable()
	end
	if data.Solved then
		Sfx.Play("PromptClean")
		for _, tile in patchTiles do
			Juice.Pop(tile.Button, 0.2)
		end
		Juice.Banner(gui :: any, "CONNECTED!", Theme.TYPED, 44)
	end
end

-- RAID Rebuild ---------------------------------------------------------------

local bays: { TextButton } = {}
local roundPips: { Frame } = {}
local raidSteps: { number } = {}
local raidInputs: { number } = {}
local raidAccepting = false
local raidStatus: TextLabel? = nil

local function lightBay(bay: number, seconds: number)
	local button = bays[bay]
	if not button then
		return
	end
	button.BackgroundColor3 = BAY_COLORS[bay]
	Juice.Pop(button, 0.15)
	Sfx.Play("ChipTap", BAY_PITCHES[bay])
	task.delay(seconds, function()
		if button.Parent then
			TweenService:Create(button, TweenInfo.new(0.15), { BackgroundColor3 = Theme.PANEL }):Play()
		end
	end)
end

local function setRaidStatus(text: string, color: Color3)
	local status = raidStatus
	if status then
		status.Text = text
		status.TextColor3 = color
		Juice.Pop(status, 0.25)
	end
end

local function startRaid(data: any)
	open("RAID REBUILD", "Watch the drive bays light up, then tap them back in the same order.", 190)
	table.clear(bays)
	table.clear(roundPips)
	raidAccepting = false

	local status = Theme.Text(body, "GET READY", 20, Theme.MOOD)
	status.Font = Enum.Font.GothamBlack
	status.AutomaticSize = Enum.AutomaticSize.None
	status.Size = UDim2.new(1, 0, 0, 26)
	status.TextXAlignment = Enum.TextXAlignment.Center
	raidStatus = status

	local bayCount = tonumber(data.Bays) or 4
	local bayWidth = 84
	local rowWidth = bayCount * (bayWidth + 12) - 12
	for bay = 1, bayCount do
		local button = Instance.new("TextButton")
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundColor3 = Theme.PANEL
		button.AnchorPoint = Vector2.new(0.5, 0)
		button.Position = UDim2.new(0.5, -rowWidth / 2 + (bay - 1) * (bayWidth + 12) + bayWidth / 2, 0, 34)
		button.Size = UDim2.fromOffset(bayWidth, 110)
		button.Parent = body
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = button
		local stroke = Instance.new("UIStroke")
		stroke.Color = BAY_COLORS[bay]
		stroke.Thickness = 2
		stroke.Parent = button
		local ledStrip = Instance.new("Frame")
		ledStrip.BorderSizePixel = 0
		ledStrip.BackgroundColor3 = BAY_COLORS[bay]
		ledStrip.AnchorPoint = Vector2.new(0.5, 0)
		ledStrip.Position = UDim2.new(0.5, 0, 0, 8)
		ledStrip.Size = UDim2.new(0.6, 0, 0, 6)
		ledStrip.Parent = button
		table.insert(bays, button)

		table.insert(cleanup, button.Activated:Connect(function()
			if not raidAccepting then
				return
			end
			lightBay(bay, 0.18)
			table.insert(raidInputs, bay)
			local index = #raidInputs
			if raidSteps[index] ~= bay then
				-- Local feedback only; the server judges the round.
				raidAccepting = false
				Sfx.Play("KeyWrong")
				Juice.Shake(button, nil)
				act("Round", raidInputs)
			elseif index >= #raidSteps then
				raidAccepting = false
				act("Round", raidInputs)
			end
		end))
	end

	local rounds = tonumber(data.Rounds) or 4
	local pipRow = Instance.new("Frame")
	pipRow.BackgroundTransparency = 1
	pipRow.AnchorPoint = Vector2.new(0.5, 0)
	pipRow.Position = UDim2.new(0.5, 0, 0, 158)
	pipRow.Size = UDim2.fromOffset(rounds * 26, 16)
	pipRow.Parent = body
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.Parent = pipRow
	for _ = 1, rounds do
		local pip = Instance.new("Frame")
		pip.Size = UDim2.fromOffset(14, 14)
		pip.BackgroundColor3 = Theme.PANEL
		pip.Parent = pipRow
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = pip
		local ring = Instance.new("UIStroke")
		ring.Color = Theme.BORDER
		ring.Parent = pip
		table.insert(roundPips, pip)
	end
end

local function onRaidFlash(data: any)
	raidSteps = {}
	for _, bay in data.Steps do
		table.insert(raidSteps, tonumber(bay) or 0)
	end
	table.clear(raidInputs)
	raidAccepting = false
	local step = tonumber(data.StepSeconds) or 0.55
	setRaidStatus(`ROUND {tonumber(data.Round) or 1}  ·  WATCH`, Theme.MOOD)
	task.spawn(function()
		task.wait(tonumber(data.LeadIn) or 0.7)
		for _, bay in raidSteps do
			if kind ~= "RaidRebuild" then
				return
			end
			lightBay(bay, step * 0.7)
			task.wait(step)
		end
		if kind == "RaidRebuild" then
			raidAccepting = true
			setRaidStatus("YOUR TURN!", Theme.TYPED)
			runTimer(tonumber(data.InputSeconds) or 8)
		end
	end)
end

local function onRaidResult(data: any)
	local round = tonumber(data.Round) or 0
	local pip = roundPips[round]
	if data.Perfect then
		Sfx.Play("PromptClean")
		setRaidStatus("ROUND CLEAR!", Theme.TYPED)
		if pip then
			pip.BackgroundColor3 = Theme.TYPED
			Juice.Pop(pip, 0.8)
		end
		for _, button in bays do
			Juice.Pop(button, 0.1)
		end
	else
		setRaidStatus("REBUILD FAILED", Theme.BUG)
		if pip then
			pip.BackgroundColor3 = Theme.BUG
		end
		Juice.Shake(panel, nil)
	end
end

-- Training Run ---------------------------------------------------------------

local epoch: TrainingRun.Epoch? = nil
local epochShownAt = 0
local epochOpen = false
local needle: Frame? = nil
local zone: Frame? = nil
local sweetSpot: Frame? = nil
local lossLabel: TextLabel? = nil
local epochPips: { Frame } = {}
local loss = 2.4

local function press()
	if kind ~= "TrainingRun" or not epochOpen then
		return
	end
	epochOpen = false
	Sfx.Play("KeyClick")
	act("Press", os.clock() - epochShownAt)
end

local function startTraining(data: any)
	open("TRAINING RUN", "Press TRAIN (or Space) while the needle is in the green zone. Gold = perfect.", 170)
	table.clear(epochPips)
	loss = 2.4
	epoch = nil

	local lossText = Theme.Text(body, string.format("loss  %.2f", loss), 18, Theme.MOOD)
	lossText.AutomaticSize = Enum.AutomaticSize.None
	lossText.Size = UDim2.new(1, 0, 0, 22)
	lossText.TextXAlignment = Enum.TextXAlignment.Center
	lossLabel = lossText

	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 30)
	bar.Size = UDim2.new(1, -20, 0, 36)
	bar.BackgroundColor3 = Theme.PANEL
	bar.Parent = body
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 8)
	barCorner.Parent = bar

	local zoneFrame = Instance.new("Frame")
	zoneFrame.BorderSizePixel = 0
	zoneFrame.BackgroundColor3 = Theme.TYPED
	zoneFrame.BackgroundTransparency = 0.45
	zoneFrame.AnchorPoint = Vector2.new(0.5, 0)
	zoneFrame.Size = UDim2.fromScale(0.2, 1)
	zoneFrame.Position = UDim2.fromScale(0.5, 0)
	zoneFrame.Parent = bar
	zone = zoneFrame
	local sweet = Instance.new("Frame")
	sweet.BorderSizePixel = 0
	sweet.BackgroundColor3 = Theme.MOOD
	sweet.BackgroundTransparency = 0.2
	sweet.AnchorPoint = Vector2.new(0.5, 0)
	sweet.Position = UDim2.fromScale(0.5, 0)
	sweet.Size = UDim2.fromScale(0.5, 1)
	sweet.Parent = zoneFrame
	sweetSpot = sweet

	local needleFrame = Instance.new("Frame")
	needleFrame.BorderSizePixel = 0
	needleFrame.BackgroundColor3 = Color3.new(1, 1, 1)
	needleFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	needleFrame.Position = UDim2.fromScale(0.5, 0.5)
	needleFrame.Size = UDim2.new(0, 4, 1, 12)
	needleFrame.ZIndex = 3
	needleFrame.Parent = bar
	needle = needleFrame

	local trainButton = Theme.Button(body, "TRAIN!", 20)
	trainButton.AnchorPoint = Vector2.new(0.5, 0)
	trainButton.Position = UDim2.new(0.5, 0, 0, 80)
	trainButton.Size = UDim2.fromOffset(200, 44)
	table.insert(cleanup, trainButton.Activated:Connect(press))
	table.insert(cleanup, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and (input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA) then
			press()
		end
	end))

	local count = tonumber(data.EpochCount) or 4
	local pipRow = Instance.new("Frame")
	pipRow.BackgroundTransparency = 1
	pipRow.AnchorPoint = Vector2.new(0.5, 0)
	pipRow.Position = UDim2.new(0.5, 0, 0, 136)
	pipRow.Size = UDim2.fromOffset(count * 26, 16)
	pipRow.Parent = body
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.Parent = pipRow
	for _ = 1, count do
		local pip = Instance.new("Frame")
		pip.Size = UDim2.fromOffset(14, 14)
		pip.BackgroundColor3 = Theme.PANEL
		pip.Parent = pipRow
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = pip
		table.insert(epochPips, pip)
	end

	table.insert(cleanup, RunService.RenderStepped:Connect(function()
		local current = epoch
		local needleNow = needle
		if current and needleNow and epochOpen then
			needleNow.Position = UDim2.fromScale(TrainingRun.NeedleAt(current, os.clock() - epochShownAt), 0.5)
		end
	end))
end

local function onEpoch(data: any)
	local current: TrainingRun.Epoch = {
		Speed = tonumber(data.Speed) or 0.5,
		Phase = tonumber(data.Phase) or 0,
		ZoneCenter = tonumber(data.ZoneCenter) or 0.5,
		ZoneWidth = tonumber(data.ZoneWidth) or 0.2,
	}
	epoch = current
	epochShownAt = os.clock()
	epochOpen = true
	local zoneFrame = zone
	if zoneFrame then
		zoneFrame.Position = UDim2.fromScale(current.ZoneCenter, 0)
		zoneFrame.Size = UDim2.fromScale(current.ZoneWidth, 1)
		Juice.Pop(zoneFrame, 0.25)
	end
	local sweet = sweetSpot
	if sweet then
		sweet.Size = UDim2.fromScale(0.5, 1)
	end
	runTimer(tonumber(data.Seconds) or 6)
	Sfx.Play("Banner")
end

local function onEpochResult(data: any)
	epochOpen = false
	local hit = tostring(data.Hit)
	local color = HIT_COLORS[hit] or Theme.BUG
	local index = tonumber(data.Index) or 0
	local pip = epochPips[index]
	if pip then
		pip.BackgroundColor3 = color
		Juice.Pop(pip, 0.8)
	end
	local needleNow = needle
	if needleNow and type(data.Needle) == "number" then
		needleNow.Position = UDim2.fromScale(data.Needle, 0.5) -- freeze where the server says you pressed
	end
	if needleNow and needleNow.Parent then
		Juice.FloatText(needleNow.Parent :: any, UDim2.new(needleNow.Position.X.Scale, 0, 0, -10), HIT_TEXT[hit] or hit, color)
	end

	loss *= LOSS_FACTOR[hit] or 1
	local label = lossLabel
	if label then
		label.Text = string.format("loss  %.2f", loss)
		label.TextColor3 = if hit == "Miss" then Theme.BUG else Theme.MOOD
		Juice.Pop(label, 0.3)
	end
	if hit == "Perfect" then
		Sfx.Play("GradeA")
	elseif hit == "Good" then
		Sfx.Play("PromptClean")
	else
		Sfx.Play("KeyWrong")
		Juice.Shake(panel, nil)
	end
end

-- Wiring -------------------------------------------------------------------

local function onStart(gameKind: any, data: any)
	if type(data) ~= "table" then
		return
	end
	kind = tostring(gameKind)
	if kind == "PatchPanel" and type(data.Shapes) == "table" and type(data.Rotations) == "table" then
		startPatch(data)
	elseif kind == "RaidRebuild" then
		startRaid(data)
	elseif kind == "TrainingRun" then
		startTraining(data)
	end
end

local function onUpdate(event: any, data: any)
	if type(data) ~= "table" then
		return
	end
	if event == "Rotated" and kind == "PatchPanel" then
		onPatchRotated(data)
	elseif event == "Flash" and kind == "RaidRebuild" and type(data.Steps) == "table" then
		onRaidFlash(data)
	elseif event == "RoundResult" and kind == "RaidRebuild" then
		onRaidResult(data)
	elseif event == "Epoch" and kind == "TrainingRun" then
		onEpoch(data)
	elseif event == "EpochResult" and kind == "TrainingRun" then
		onEpochResult(data)
	end
end

function MinigameController.Init()
	gui = Theme.Screen("Minigame", 4)
	gui.Enabled = false

	panel = Theme.Panel(gui, UDim2.fromOffset(460, 0), UDim2.new(0.5, 0, 1, -40))
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	Theme.List(panel, 8)

	titleLabel = Theme.Text(panel, "", 24, Theme.ACCENT)
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.LayoutOrder = 0
	hintLabel = Theme.Text(panel, "", 14, Theme.MUTED)
	hintLabel.TextXAlignment = Enum.TextXAlignment.Center
	hintLabel.LayoutOrder = 1

	timerBack = Instance.new("Frame")
	timerBack.Size = UDim2.new(1, 0, 0, 6)
	timerBack.BackgroundColor3 = Theme.PANEL
	timerBack.BorderSizePixel = 0
	timerBack.LayoutOrder = 2
	timerBack.Visible = false
	timerBack.Parent = panel
	timerFill = Instance.new("Frame")
	timerFill.Size = UDim2.fromScale(1, 1)
	timerFill.BackgroundColor3 = Theme.ACCENT
	timerFill.BorderSizePixel = 0
	timerFill.Parent = timerBack

	body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 0, 200)
	body.LayoutOrder = 3
	body.Parent = panel

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function MinigameController.Start()
	RemoteManager.GetRemote(RemoteNames.MinigameStart).OnClientEvent:Connect(onStart)
	RemoteManager.GetRemote(RemoteNames.MinigameUpdate).OnClientEvent:Connect(onUpdate)
	-- The result card takes over when the server grades the run.
	RemoteManager.GetRemote(RemoteNames.BurstFinished).OnClientEvent:Connect(function()
		if kind ~= "" then
			task.delay(0.4, close)
		end
	end)
end

return MinigameController
