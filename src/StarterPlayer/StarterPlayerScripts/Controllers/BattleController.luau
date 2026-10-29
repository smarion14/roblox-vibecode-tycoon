--!strict
-- Deploy battle screen: client on a live call (left), prompt, combo and ship progress (centre), bugs closing in.
-- Server BattleUpdate snapshots are the truth; bug motion is animated locally from the server start time.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UI:WaitForChild("Theme"))
local Juice = require(UI:WaitForChild("Juice"))
local TypingInput = require(UI:WaitForChild("TypingInput"))

type BugView = {
	Id: number,
	Word: string,
	Side: number,
	SpawnOffset: number,
	ReachOffset: number,
	State: string,
	Button: TextButton,
	Shown: boolean,
}

local RESULT_SECONDS = 3
local BUG_LANES = 5
local DANGER_TRAVEL = 0.75 -- past this share of the path a bug starts pulsing as a warning

local REACTIONS = {
	happy = { "Oh nice, that loads fast.", "This is exactly what I pictured.", "My team is going to love this." },
	neutral = { "Okay, keep going.", "Hmm, interesting choice.", "Is that how it's supposed to look?" },
	annoyed = { "Wait, is it supposed to flash like that?", "It froze again.", "I'm not paying for broken." },
}

local BattleController = {}

local gui: ScreenGui
local root: Frame
local rootFlash: Frame
local clientName: TextLabel
local face: TextLabel
local reaction: TextLabel
local moodFill: Frame
local comboLabel: TextLabel
local progressFill: Frame
local promptHolder: Frame
local bugLayer: Frame
local resultLabel: TextLabel

local field: TypingInput.TypingField? = nil
local mode: TypingInput.Mode = "Keyboard"
local bugs: { BugView } = {}
local serverStart = 0
local shipRequired = 4
local currentPrompt = ""
local pendingSubmit = false
local lastJudged = 0
local lastMoodBand = ""
local lastCombo = 0
local renderConnection: RBXScriptConnection? = nil

local function serverElapsed(): number
	return Workspace:GetServerTimeNow() - serverStart
end

local function moodBand(mood: number): string
	if mood > 70 then
		return "happy"
	elseif mood >= 40 then
		return "neutral"
	end
	return "annoyed"
end

local function setMood(mood: number)
	moodFill.Size = UDim2.fromScale(math.clamp(mood / 100, 0, 1), 1)
	local band = moodBand(mood)
	face.Text = if band == "happy" then "😄" elseif band == "neutral" then "😐" else "😬"
	if band ~= lastMoodBand then
		lastMoodBand = band
		local lines = REACTIONS[band]
		reaction.Text = `"{lines[math.random(1, #lines)]}"`
	end
end

local function clearBattle()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	if field then
		field:Destroy()
		field = nil
	end
	for _, bug in bugs do
		bug.Button:Destroy()
	end
	table.clear(bugs)
end

-- Mirrors the server's rule: a bug can't be squashed faster than its word could be typed after it appears.
local function squashable(bug: BugView, elapsed: number): boolean
	local earliest = bug.SpawnOffset + #bug.Word / GameConfig.BATTLE_RULES.MaxCharsPerSecond
	return bug.State == "Pending" and elapsed >= earliest
end

local function trySquashWord(word: string): boolean
	local elapsed = serverElapsed()
	for _, bug in bugs do
		if bug.Word == word and squashable(bug, elapsed) then
			RemoteManager.FireServer(RemoteNames.BattleSquash, word)
			return true
		end
	end
	return false
end

local function renderBugs()
	local elapsed = serverElapsed()
	for _, bug in bugs do
		local visible = bug.State == "Pending" and elapsed >= bug.SpawnOffset
		bug.Button.Visible = visible
		if visible then
			if not bug.Shown then
				bug.Shown = true
				Juice.PopIn(bug.Button)
			end
			local travel = math.clamp((elapsed - bug.SpawnOffset) / (bug.ReachOffset - bug.SpawnOffset), 0, 1)
			local x = if bug.Side < 0 then 0.5 * travel else 1 - 0.5 * travel
			local lane = (bug.Id % BUG_LANES) / BUG_LANES
			local phase = elapsed * 10 + bug.Id
			-- Crawl: a side-to-side wiggle and a small bob so the bug looks alive.
			bug.Button.Rotation = math.sin(phase) * 8
			bug.Button.Position = UDim2.new(x, 0, 0.1 + lane * 0.8, math.sin(phase * 1.7) * 3)

			-- Warning phase: close to the prompt the bug flashes and throbs.
			local danger = travel >= DANGER_TRAVEL
			local throb = if danger then 1 + 0.12 * math.abs(math.sin(elapsed * 14)) else 1
			local scale = bug.Button:FindFirstChildOfClass("UIScale")
			if scale and scale.Scale >= 0.99 then
				scale.Scale = throb
			end
			bug.Button.BackgroundColor3 = if danger and math.sin(elapsed * 14) > 0
				then Color3.fromRGB(120, 20, 40)
				else Color3.fromRGB(42, 15, 28)
		end
	end
end

local function onStarted(info: any)
	if type(info) ~= "table" or type(info.Bugs) ~= "table" then
		return
	end
	clearBattle()
	serverStart = tonumber(info.ServerStart) or Workspace:GetServerTimeNow()
	shipRequired = tonumber(info.ShipPromptsRequired) or 4
	clientName.Text = tostring(info.ClientName)
	lastMoodBand = ""
	setMood(tonumber(info.Mood) or 70)
	comboLabel.Text = "x0"
	lastCombo = 0
	progressFill.Size = UDim2.fromScale(0, 1)
	resultLabel.Visible = false
	pendingSubmit = false
	lastJudged = 0
	mode = TypingInput.DetectMode()

	for _, bug in info.Bugs do
		local button = Instance.new("TextButton")
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Size = UDim2.fromOffset(90, 30)
		button.BackgroundColor3 = Color3.fromRGB(42, 15, 28)
		button.TextColor3 = Theme.BUG
		button.Font = Theme.FONT
		button.TextSize = 16
		button.Text = `🐛 {bug.Word}`
		button.Visible = false
		button.AutoButtonColor = mode == "Touch"
		button.Parent = bugLayer
		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.BUG
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = button

		local view: BugView = {
			Id = bug.Id,
			Word = bug.Word,
			Side = bug.Side,
			SpawnOffset = bug.SpawnOffset,
			ReachOffset = bug.ReachOffset,
			State = "Pending",
			Button = button,
			Shown = false,
		}
		button.Activated:Connect(function()
			if mode == "Touch" and squashable(view, serverElapsed()) then
				RemoteManager.FireServer(RemoteNames.BattleSquash, view.Word)
			end
		end)
		table.insert(bugs, view)
	end

	local newField = TypingInput.Create(promptHolder, mode)
	newField.OnSubmit = function(text: string)
		if not pendingSubmit then
			pendingSubmit = true
			RemoteManager.FireServer(RemoteNames.BattleSubmitPrompt, text)
		end
	end
	newField.OnWord = trySquashWord
	field = newField
	currentPrompt = tostring(info.PromptText)
	newField:SetPrompt(currentPrompt)

	renderConnection = RunService.RenderStepped:Connect(renderBugs)
	gui.Enabled = true
end

local function onUpdate(snapshot: any)
	if type(snapshot) ~= "table" or not field then
		return
	end
	setMood(tonumber(snapshot.Mood) or 0)
	local combo = tonumber(snapshot.Combo) or 0
	comboLabel.Text = `x{combo}`
	if combo > lastCombo then
		Juice.Pop(comboLabel, 0.35)
	elseif combo == 0 and lastCombo > 0 then
		Juice.Shake(comboLabel, nil)
	end
	lastCombo = combo
	progressFill.Size = UDim2.fromScale(math.clamp((tonumber(snapshot.Progress) or 0) / shipRequired, 0, 1), 1)

	if type(snapshot.BugStates) == "table" then
		for _, bug in bugs do
			local state = snapshot.BugStates[bug.Id]
			if type(state) == "string" then
				if bug.State == "Pending" and state == "Squashed" then
					Juice.Splat(bugLayer, bug.Button.Position)
				elseif bug.State == "Pending" and state == "Hit" then
					-- Contact: the bug got through. Shake the whole screen and flash it red.
					Juice.Shake(root, rootFlash)
				end
				bug.State = state
			end
		end
	end

	local promptText = tostring(snapshot.PromptText)
	local judged = tonumber(snapshot.PromptsJudged) or 0
	if promptText ~= currentPrompt then
		currentPrompt = promptText
		field:SetPrompt(promptText)
	elseif judged > lastJudged then
		field:Clear() -- rejected: retype the same prompt
	end
	if judged > lastJudged then
		lastJudged = judged
		pendingSubmit = false
	end
end

local function onEnded(result: any, payout: any)
	clearBattle()
	local shipped = type(result) == "table" and result.Status == "Shipped"
	resultLabel.Text = if shipped
		then `SHIPPED   +${tonumber(payout) or 0}`
		else "LAUNCH FAILED   your components are safe, try again"
	resultLabel.TextColor3 = if shipped then Theme.TYPED else Theme.BUG
	resultLabel.Visible = true
	task.delay(RESULT_SECONDS, function()
		if not field then
			gui.Enabled = false
		end
	end)
end

local function bar(parent: Instance, color: Color3, order: number): Frame
	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, 0, 0, 10)
	back.BackgroundColor3 = Theme.PANEL
	back.BorderSizePixel = 0
	back.LayoutOrder = order
	back.Parent = parent
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back
	return fill
end

function BattleController.Init()
	gui = Theme.Screen("Battle", 6)
	gui.Enabled = false

	root = Theme.Panel(gui, UDim2.fromScale(0.9, 0.8), UDim2.fromScale(0.5, 0.5))
	root.AnchorPoint = Vector2.new(0.5, 0.5)

	rootFlash = Instance.new("Frame")
	rootFlash.Size = UDim2.fromScale(1, 1)
	rootFlash.BackgroundTransparency = 1
	rootFlash.BorderSizePixel = 0
	rootFlash.ZIndex = 8
	rootFlash.Parent = root

	-- Left: the client on a live call.
	local left = Instance.new("Frame")
	left.BackgroundTransparency = 1
	left.Size = UDim2.fromScale(0.28, 1)
	left.Parent = root
	Theme.List(left, 8)
	face = Theme.Text(left, "😐", 48)
	face.LayoutOrder = 1
	clientName = Theme.Text(left, "", 16)
	clientName.LayoutOrder = 2
	Theme.Text(left, "ON CALL · LIVE DEMO", 12, Theme.MUTED).LayoutOrder = 3
	reaction = Theme.Text(left, "", 14)
	reaction.LayoutOrder = 4
	Theme.Text(left, "CLIENT MOOD", 12, Theme.MUTED).LayoutOrder = 5
	moodFill = bar(left, Theme.MOOD, 6)

	-- Centre: ship progress, combo, prompt and the bug lane.
	local centre = Instance.new("Frame")
	centre.BackgroundTransparency = 1
	centre.Position = UDim2.fromScale(0.3, 0)
	centre.Size = UDim2.fromScale(0.7, 1)
	centre.Parent = root

	local top = Instance.new("Frame")
	top.BackgroundTransparency = 1
	top.Size = UDim2.new(1, 0, 0, 60)
	top.Parent = centre
	Theme.List(top, 4)
	Theme.Text(top, "SHIP PROGRESS", 12, Theme.MUTED).LayoutOrder = 1
	progressFill = bar(top, Theme.TYPED, 2)

	comboLabel = Theme.Text(centre, "x0", 34, Theme.ACCENT)
	comboLabel.Position = UDim2.fromOffset(0, 62)
	comboLabel.TextXAlignment = Enum.TextXAlignment.Right

	bugLayer = Instance.new("Frame")
	bugLayer.BackgroundTransparency = 1
	bugLayer.Position = UDim2.fromOffset(0, 110)
	bugLayer.Size = UDim2.new(1, 0, 1, -280)
	bugLayer.Parent = centre

	promptHolder = Instance.new("Frame")
	promptHolder.BackgroundTransparency = 1
	promptHolder.AnchorPoint = Vector2.new(0, 1)
	promptHolder.Position = UDim2.fromScale(0, 1)
	promptHolder.Size = UDim2.new(1, 0, 0, 160)
	promptHolder.Parent = centre
	Theme.List(promptHolder, 4)

	resultLabel = Theme.Text(root, "", 30, Theme.TYPED)
	resultLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	resultLabel.Position = UDim2.fromScale(0.5, 0.5)
	resultLabel.Size = UDim2.fromScale(0.8, 0.2)
	resultLabel.TextXAlignment = Enum.TextXAlignment.Center
	resultLabel.ZIndex = 5
	resultLabel.Visible = false

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function BattleController.Start()
	RemoteManager.GetRemote(RemoteNames.BattleStarted).OnClientEvent:Connect(onStarted)
	RemoteManager.GetRemote(RemoteNames.BattleUpdate).OnClientEvent:Connect(onUpdate)
	RemoteManager.GetRemote(RemoteNames.BattleEnded).OnClientEvent:Connect(onEnded)
end

return BattleController
