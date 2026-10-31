--!strict
-- Act 3 incidents on the client (spec §6): the red HUD alert (kind, countdown, arrow toward the room) with its alarm,
-- spinning alarm lights in the player's own unit, and the three response screens. The server holds every round and
-- judges every answer; this only draws them and sends taps and answer sheets.
--   Firewall (Breach):          packets slide down three lanes; tap red ones before the core, let green ones pass.
--   Triage   (Vulnerability):   sort each bug report into Critical / Minor / Not a bug.
--   Clap back (Naysayer):       pick the best of three replies to each hostile post.
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Juice = require(UI:WaitForChild("Juice"))
local Sfx = require(UI:WaitForChild("Sfx"))
local Theme = require(UI:WaitForChild("Theme"))

type AlertState = { Kind: string, Deadline: number, Room: string }
type Choice = { Label: string, Value: any, Color: Color3 }
type SheetItem = { Key: string, Prompt: string, Choices: { Choice } }
type PacketView = { Id: number, Red: boolean, Lane: number, ArriveAt: number, Button: TextButton, Done: boolean }
type Spin = { Base: CFrame, Color: Color3, Material: Enum.Material, Beam: SpotLight }

local INCIDENT_NAMES: { [string]: string } = {
	Breach = "BREACH",
	Vulnerability = "VULNERABILITY REPORT",
	Naysayer = "NAYSAYER STORM",
}
local ALERT_WIDTH = 300
local HUD_RIGHT = 304 -- HudController's panel ends at 12 + 280; the alert stays clear of it on narrow screens
local UPSTAIRS_RISE = 8 -- a desk this many studs above the player is on the next floor
local URGENT_SECONDS = 15
local ALARM_RED = Color3.fromRGB(255, 40, 50)
local ALERT_BACKGROUND = Color3.fromHex("2a0812")
-- shortcut: the alarm reuses BugGotThrough as a two-tone low siren (no Creator Store siren id verified); swap in Sfx.
local ALARM_PITCHES = { 0.45, 0.6, 0.45, 0.6 }
local ALARM_STEP_SECONDS = 0.45
local SPIN_RADIANS_PER_SECOND = math.pi * 2
local LANE_COUNT = 3
local LATE_SHARE = 0.2 -- the last fifth of a lane is tinted: taps there may land after the server's cut-off
local FIREWALL_BODY = 260
local CORE_HEIGHT = 28
local LANE_ACTION = "IncidentFirewallLanes"
local LANE_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.DPadLeft] = 1,
	[Enum.KeyCode.Left] = 1,
	[Enum.KeyCode.DPadUp] = 2,
	[Enum.KeyCode.Up] = 2,
	[Enum.KeyCode.DPadRight] = 3,
	[Enum.KeyCode.Right] = 3,
}
local TRIAGE_CHOICES: { Choice } = {
	{ Label = "CRITICAL", Value = "Critical", Color = Theme.BUG },
	{ Label = "MINOR", Value = "Minor", Color = Theme.MOOD },
	{ Label = "NOT A BUG", Value = "NotABug", Color = Theme.TYPED },
}
local GRADE_COLORS: { [string]: Color3 } = { S = Theme.MOOD, A = Theme.TYPED, B = Theme.ACCENT, C = Theme.MUTED }
local GRADE_STINGERS: { [string]: Sfx.SoundName } = { S = "GradeS", A = "GradeA", B = "GradeB", C = "GradeC" }
local RESULT_SECONDS = 6

local IncidentController = {}

local player = Players.LocalPlayer

-- Alert
local alertGui: ScreenGui
local alertHolder: Frame
local alertBanner: Frame
local alertStroke: UIStroke
local alertArrow: TextLabel
local alertTitle: TextLabel
local alertDetail: TextLabel
local alert: AlertState? = nil
local alertDesk: BasePart? = nil

-- Lights
local spinning: { [BasePart]: Spin } = {}

-- Response screen
local gui: ScreenGui
local panel: Frame
local titleLabel: TextLabel
local hintLabel: TextLabel
local body: Frame
local timerBack: Frame
local timerFill: Frame
local timerTween: Tween? = nil
local cleanup: { RBXScriptConnection } = {}
local roundOpen = false
local roundToken = 0

local function usingGamepad(): boolean
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

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

-- Alert ----------------------------------------------------------------------

local function findDesk(kind: string): BasePart?
	local unit = ownUnit()
	if not unit then
		return nil
	end
	for _, desk in CollectionService:GetTagged("IncidentDesk") do
		if desk:IsA("BasePart") and desk:GetAttribute("Kind") == kind and desk:IsDescendantOf(unit) then
			return desk
		end
	end
	return nil
end

local function playAlarm()
	task.spawn(function()
		for _, pitch in ALARM_PITCHES do
			if not alert then
				return
			end
			Sfx.Play("BugGotThrough", pitch)
			task.wait(ALARM_STEP_SECONDS)
		end
	end)
end

local function refreshAlertVisibility()
	alertGui.Enabled = alert ~= nil and not roundOpen
end

local function onIncidentState(payload: any)
	local previous = alert
	if type(payload) == "table" and type(payload.Kind) == "string" and type(payload.Deadline) == "number" then
		alert = {
			Kind = payload.Kind,
			Deadline = payload.Deadline,
			Room = if type(payload.Room) == "string" then payload.Room else payload.Kind,
		}
	else
		alert = nil
	end
	local current = alert
	if current and (not previous or previous.Kind ~= current.Kind) then
		alertDesk = findDesk(current.Kind)
		alertTitle.Text = `⚠ {INCIDENT_NAMES[current.Kind] or string.upper(current.Kind)}`
		refreshAlertVisibility()
		Juice.SlideIn(alertBanner, UDim2.fromOffset(0, -50))
		playAlarm()
	elseif not current and previous then
		Juice.SlideOut(alertBanner, UDim2.fromOffset(0, -50))
		task.delay(0.25, refreshAlertVisibility)
	else
		refreshAlertVisibility()
	end
end

local function updateAlert()
	local current = alert
	if not current or not alertGui.Enabled then
		return
	end
	alertHolder.Position = UDim2.fromOffset(math.max(alertGui.AbsoluteSize.X / 2, HUD_RIGHT + ALERT_WIDTH / 2), 12)

	local left = math.max(0, math.ceil(current.Deadline - Workspace:GetServerTimeNow()))
	local clock = string.format("%d:%02d", left // 60, left % 60)
	local pulse = (math.sin(os.clock() * (if left <= URGENT_SECONDS then 14 else 6)) + 1) / 2
	alertStroke.Transparency = pulse * 0.6
	alertDetail.TextColor3 = if left <= URGENT_SECONDS then Theme.BUG:Lerp(Theme.TEXT, pulse) else Theme.TEXT

	local desk = alertDesk
	if not desk or not desk.Parent then
		desk = findDesk(current.Kind)
		alertDesk = desk
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = Workspace.CurrentCamera
	local where = current.Room
	if desk and root and root:IsA("BasePart") and camera then
		if desk.Position.Y - root.Position.Y > UPSTAIRS_RISE then
			alertArrow.Rotation = 0 -- another floor: point up toward the stairs and elevator
			where = `UPSTAIRS · {current.Room}`
		else
			local relative = camera.CFrame:PointToObjectSpace(desk.Position)
			alertArrow.Rotation = math.deg(math.atan2(relative.X, -relative.Z))
		end
	end
	alertDetail.Text = `{where}  ·  {clock}`
end

-- Alarm lights -----------------------------------------------------------------

local function refreshLight(light: Instance)
	if not light:IsA("BasePart") then
		return
	end
	local unit = ownUnit()
	local on = light:GetAttribute("Active") == true and unit ~= nil and light:IsDescendantOf(unit)
	local spin = spinning[light]
	if on and not spin then
		-- A spot light on the spinning housing sweeps the room like a beacon; the server's PointLight is the glow.
		local beam = Instance.new("SpotLight")
		beam.Color = ALARM_RED
		beam.Brightness = 5
		beam.Range = 26
		beam.Angle = 50
		beam.Face = Enum.NormalId.Front
		beam.Parent = light
		spinning[light] = { Base = light.CFrame, Color = light.Color, Material = light.Material, Beam = beam }
		light.Color = ALARM_RED
		light.Material = Enum.Material.Neon
	elseif not on and spin then
		spinning[light] = nil
		spin.Beam:Destroy()
		light.CFrame = spin.Base
		light.Color = spin.Color
		light.Material = spin.Material
	end
end

local function watchLight(light: Instance)
	light:GetAttributeChangedSignal("Active"):Connect(function()
		refreshLight(light)
	end)
	refreshLight(light)
end

local function refreshAllLights()
	for _, light in CollectionService:GetTagged("IncidentLight") do
		refreshLight(light)
	end
end

local function spinLights()
	for light, spin in spinning do
		if not light.Parent then
			spinning[light] = nil -- the unit was rebuilt; the beam went with the part
			continue
		end
		local angle = (os.clock() * SPIN_RADIANS_PER_SECOND) % (math.pi * 2)
		light.CFrame = spin.Base * CFrame.Angles(0, angle, 0)
	end
end

-- Response screen ------------------------------------------------------------

local function clearBody()
	for _, connection in cleanup do
		connection:Disconnect()
	end
	table.clear(cleanup)
	ContextActionService:UnbindAction(LANE_ACTION)
	body:ClearAllChildren()
	if timerTween then
		timerTween:Cancel()
		timerTween = nil
	end
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
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

-- bodyHeight nil: the body sizes to a vertical list of its rows.
local function open(title: string, hint: string, bodyHeight: number?): number
	clearBody()
	roundToken += 1
	titleLabel.Text = title
	hintLabel.Text = hint
	timerBack.Visible = false
	if bodyHeight then
		body.AutomaticSize = Enum.AutomaticSize.None
		body.Size = UDim2.new(1, 0, 0, bodyHeight)
	else
		body.AutomaticSize = Enum.AutomaticSize.Y
		body.Size = UDim2.new(1, 0, 0, 0)
		Theme.List(body, 8)
	end
	roundOpen = true
	refreshAlertVisibility()
	Juice.OpenWindow(gui, panel)
	Sfx.Play("CardOpen")
	return roundToken
end

local function close()
	clearBody()
	roundToken += 1
	roundOpen = false
	refreshAlertVisibility()
	Juice.CloseWindow(gui, panel)
end

local function centered(parent: Instance, text: string, size: number, color: Color3): TextLabel
	local label = Theme.Text(parent, text, size, color)
	label.TextXAlignment = Enum.TextXAlignment.Center
	return label
end

-- Firewall -------------------------------------------------------------------

local function startFirewall(data: any)
	local token = open("FIREWALL", "Tap the red packets before they hit the core. Let green ones pass. Tap early!", FIREWALL_BODY)
	local travel = tonumber(data.TravelSeconds) or 3.5
	local startedAt = os.clock()
	local views: { PacketView } = {}
	local lastArrival = 0
	GuiService.SelectedObject = nil -- the D-pad picks lanes here, not buttons

	local laneHeight = FIREWALL_BODY - CORE_HEIGHT - 6
	local lanes: { Frame } = {}
	for lane = 1, LANE_COUNT do
		local frame = Instance.new("Frame")
		frame.BackgroundColor3 = Theme.PANEL
		frame.BackgroundTransparency = 0.3
		frame.BorderSizePixel = 0
		frame.ClipsDescendants = true
		frame.Position = UDim2.new((lane - 1) / LANE_COUNT, 4, 0, 0)
		frame.Size = UDim2.new(1 / LANE_COUNT, -8, 0, laneHeight)
		frame.Parent = body
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = frame
		local late = Instance.new("Frame")
		late.BackgroundColor3 = Theme.BUG
		late.BackgroundTransparency = 0.85
		late.BorderSizePixel = 0
		late.Position = UDim2.fromScale(0, 1 - LATE_SHARE)
		late.Size = UDim2.fromScale(1, LATE_SHARE)
		late.Parent = frame
		local hint = centered(frame, ({ "◀", "▲", "▶" })[lane], 14, Theme.TODO)
		hint.Position = UDim2.fromOffset(0, 4)
		lanes[lane] = frame
	end

	local core = Instance.new("TextLabel")
	core.BackgroundColor3 = Theme.TYPED
	core.BackgroundTransparency = 0.6
	core.BorderSizePixel = 0
	core.Font = Enum.Font.GothamBlack
	core.TextSize = 16
	core.TextColor3 = Theme.TEXT
	core.Text = "◆  CORE  ◆"
	core.AnchorPoint = Vector2.new(0, 1)
	core.Position = UDim2.fromScale(0, 1)
	core.Size = UDim2.new(1, 0, 0, CORE_HEIGHT)
	core.Parent = body
	local coreCorner = Instance.new("UICorner")
	coreCorner.CornerRadius = UDim.new(0, 6)
	coreCorner.Parent = core

	local function flashCore(color: Color3)
		core.BackgroundColor3 = color
		core.BackgroundTransparency = 0.1
		TweenService:Create(core, TweenInfo.new(0.35), { BackgroundColor3 = Theme.TYPED, BackgroundTransparency = 0.6 }):Play()
		Juice.Pop(core, 0.12)
	end

	local function retire(view: PacketView)
		view.Done = true
		local button = view.Button
		local fade = TweenService:Create(button, TweenInfo.new(0.15), { BackgroundTransparency = 1, TextTransparency = 1 })
		fade.Completed:Once(function()
			button:Destroy()
		end)
		fade:Play()
	end

	local function tap(view: PacketView)
		if view.Done or token ~= roundToken or not view.Button.Visible then
			return
		end
		RemoteManager.FireServer(RemoteNames.IncidentAction, view.Id)
		local lane = lanes[view.Lane]
		local at = UDim2.new(0.5, 0, view.Button.Position.Y.Scale, -16)
		if view.Red then
			Sfx.Play("KeyClick")
			Sfx.Play("ChipTap", 1.25)
			Juice.FloatText(lane, at, "BLOCKED", Theme.TYPED)
			for _ = 1, 5 do
				Juice.Spark(lane, at, Theme.TYPED)
			end
		else
			Sfx.Play("KeyWrong")
			Juice.FloatText(lane, at, "FRIENDLY!", Theme.BUG)
		end
		retire(view)
	end

	for _, packet in data.Packets do
		if type(packet) ~= "table" then
			continue
		end
		local id, lane, arriveAt = tonumber(packet.Id), tonumber(packet.Lane), tonumber(packet.ArriveAt)
		if not id or not lane or not arriveAt or not lanes[lane] then
			continue
		end
		local red = packet.Red == true
		local button = Instance.new("TextButton")
		button.AutoButtonColor = false
		button.Selectable = false
		button.BackgroundColor3 = if red then Theme.BUG else Theme.TYPED
		button.BackgroundTransparency = 0.15
		button.Font = Enum.Font.GothamBlack
		button.TextSize = 14
		button.TextColor3 = Theme.BACKGROUND
		button.Text = if red then "☠ 0x" .. string.format("%02X", id * 37 % 256) else "✓ OK"
		button.AnchorPoint = Vector2.new(0.5, 1)
		button.Size = UDim2.new(1, -14, 0, 34)
		button.Position = UDim2.fromScale(0.5, 0)
		button.Visible = false
		button.ZIndex = 3
		button.Parent = lanes[lane]
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = button
		local view: PacketView = { Id = id, Red = red, Lane = lane, ArriveAt = arriveAt, Button = button, Done = false }
		table.insert(views, view)
		lastArrival = math.max(lastArrival, arriveAt)
		table.insert(cleanup, button.Activated:Connect(function()
			tap(view)
		end))
	end

	local status = centered(body, "", 18, Theme.MOOD)
	status.Font = Enum.Font.GothamBlack
	status.Position = UDim2.fromOffset(0, laneHeight / 2 - 12)
	status.ZIndex = 5

	-- Each lane key taps the packet nearest the core in that lane; sunk so the arrows don't also turn the camera.
	local keys: { Enum.KeyCode } = {}
	for key in LANE_KEYS do
		table.insert(keys, key)
	end
	ContextActionService:BindActionAtPriority(LANE_ACTION, function(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
		local lane = LANE_KEYS[input.KeyCode]
		if state == Enum.UserInputState.Begin and lane then
			local front: PacketView? = nil
			for _, view in views do
				if view.Lane == lane and not view.Done and view.Button.Visible and (not front or view.ArriveAt < front.ArriveAt) then
					front = view
				end
			end
			if front then
				tap(front)
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, table.unpack(keys))

	local finished = false
	table.insert(cleanup, RunService.RenderStepped:Connect(function()
		local t = os.clock() - startedAt
		for _, view in views do
			if view.Done then
				continue
			end
			local progress = 1 - (view.ArriveAt - t) / travel
			if progress >= 1 then
				-- Reached the core: a red one got through, a green one was let in as it should be.
				view.Button.Visible = false
				view.Done = true
				view.Button:Destroy()
				if view.Red then
					Sfx.Play("BugGotThrough")
					flashCore(Theme.BUG)
					Juice.Shake(panel, nil)
					Juice.FloatText(core, UDim2.fromScale((view.Lane - 0.5) / LANE_COUNT, 0), "BREACH!", Theme.BUG)
				else
					Sfx.Play("PromptClean")
					flashCore(Theme.TYPED)
				end
			elseif progress >= 0 then
				view.Button.Visible = true
				view.Button.Position = UDim2.new(0.5, 0, progress, 0)
			end
		end
		if not finished and t > lastArrival then
			finished = true
			status.Text = "SCANNING TRAFFIC…"
			Juice.Pop(status, 0.3)
		end
	end))
end

-- Triage and Clap back: one card at a time, one answer sheet sent at the end -------------------

local function startSheet(title: string, hint: string, items: { SheetItem }, timeLimit: number)
	local token = open(title, hint, nil)
	local answers: { [string]: any } = {}
	local answered = 0
	local current = 0
	local sent = false

	local counter = centered(body, "", 14, Theme.MUTED)
	counter.LayoutOrder = 1

	local card = Theme.Panel(body, UDim2.new(1, 0, 0, 0), UDim2.new())
	card.BackgroundColor3 = Theme.PANEL
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.LayoutOrder = 2
	Theme.List(card, 8)
	local prompt = Theme.Text(card, "", 18)
	prompt.LayoutOrder = 0

	local submit = Theme.Button(body, "SUBMIT", 16)
	submit.LayoutOrder = 3
	local function setSubmitEnabled(enabled: boolean)
		submit.Active = enabled
		submit.AutoButtonColor = enabled
		submit.Selectable = enabled
		submit.TextTransparency = if enabled then 0 else 0.6
	end
	setSubmitEnabled(false)

	local choiceButtons: { TextButton } = {}

	local function send()
		if sent or answered == 0 or token ~= roundToken then
			return -- the server ignores a blank sheet, so don't send one
		end
		sent = true
		RemoteManager.FireServer(RemoteNames.IncidentAction, answers)
		for _, button in choiceButtons do
			button:Destroy()
		end
		table.clear(choiceButtons)
		prompt.Text = "Sent. Waiting for the verdict…"
		prompt.TextXAlignment = Enum.TextXAlignment.Center
		prompt.TextColor3 = Theme.MOOD
		submit.Visible = false
		if timerTween then
			timerTween:Cancel()
		end
		Sfx.Play("Shipped")
		Juice.Pop(card, 0.15)
	end

	local function show(index: number)
		for _, button in choiceButtons do
			button:Destroy()
		end
		table.clear(choiceButtons)
		local item = items[index]
		if not item then
			send()
			return
		end
		current = index
		counter.Text = `{index} / {#items}`
		prompt.Text = item.Prompt
		Juice.Pop(card, 0.08)
		for order, choice in item.Choices do
			local button = Theme.Button(card, choice.Label, 16)
			button.LayoutOrder = order
			button.TextColor3 = choice.Color
			button.TextWrapped = true
			button.AutomaticSize = Enum.AutomaticSize.Y
			local padding = Instance.new("UIPadding")
			padding.PaddingTop = UDim.new(0, 6)
			padding.PaddingBottom = UDim.new(0, 6)
			padding.PaddingLeft = UDim.new(0, 8)
			padding.PaddingRight = UDim.new(0, 8)
			padding.Parent = button
			table.insert(choiceButtons, button)
			button.Activated:Connect(function()
				if sent or current ~= index or token ~= roundToken then
					return
				end
				answers[item.Key] = choice.Value -- string keys: the remote keeps a sparse map intact
				answered += 1
				setSubmitEnabled(true)
				Sfx.Play("KeyClick")
				Juice.FloatText(body, UDim2.new(0.5, 0, 0, 10), choice.Label, choice.Color)
				show(index + 1)
			end)
		end
		if usingGamepad() then
			GuiService.SelectedObject = choiceButtons[1]
		end
	end

	table.insert(cleanup, submit.Activated:Connect(send))
	show(1)
	runTimer(timeLimit)
	-- Send what was answered just before the server's own cut-off; an empty sheet waits it out.
	task.delay(timeLimit, function()
		if token == roundToken and not sent then
			if answered > 0 then
				send()
			else
				prompt.Text = "Time's up."
				prompt.TextColor3 = Theme.BUG
				for _, button in choiceButtons do
					button:Destroy()
				end
				table.clear(choiceButtons)
				Sfx.Play("KeyWrong")
			end
		end
	end)
end

local function startTriage(data: any)
	local items: { SheetItem } = {}
	for _, report in data.Reports do
		if type(report) == "table" and tonumber(report.Id) and type(report.Text) == "string" then
			table.insert(items, { Key = tostring(report.Id), Prompt = report.Text, Choices = TRIAGE_CHOICES })
		end
	end
	startSheet("TRIAGE", "Sort each bug report before the queue piles up.", items, tonumber(data.TimeLimit) or 20)
end

local function startClapBack(data: any)
	local items: { SheetItem } = {}
	for index, post in data.Posts do
		if type(post) ~= "table" or type(post.Post) ~= "string" or type(post.Replies) ~= "table" then
			continue
		end
		local choices: { Choice } = {}
		for replyIndex, reply in post.Replies do
			if type(reply) == "string" then
				table.insert(choices, { Label = reply, Value = replyIndex, Color = Theme.TEXT })
			end
		end
		table.insert(items, { Key = tostring(index), Prompt = `@naysayer: {post.Post}`, Choices = choices })
	end
	startSheet("CLAP BACK", "Pick the best reply to each post. Fast.", items, tonumber(data.TimeLimit) or 30)
end

-- Result -----------------------------------------------------------------------

local function showResult(gradeValue: any, deltaValue: any, repValue: any)
	local grade = if type(gradeValue) == "string" and GRADE_COLORS[gradeValue] then gradeValue else "C"
	local repDelta = tonumber(deltaValue) or 0
	local newRep = tonumber(repValue) or 0
	local color = GRADE_COLORS[grade]
	local good = grade == "S" or grade == "A"
	local token = open("INCIDENT CLEARED", if good then "Handled like a pro." else "Cleared, but no bonus this time.", nil)

	local gradeLabel = centered(body, grade, 64, color)
	gradeLabel.Font = Enum.Font.GothamBlack
	gradeLabel.LayoutOrder = 1
	gradeLabel.Rotation = math.random(-15, 15)
	local scale = Instance.new("UIScale")
	scale.Scale = 3
	scale.Parent = gradeLabel
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(gradeLabel, TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
	Sfx.Play("GradeStamp")
	task.delay(0.12, function()
		Sfx.Play(GRADE_STINGERS[grade])
	end)
	if good then
		Juice.Banner(gui :: any, `{grade} RANK!`, color, 46)
		for _ = 1, if grade == "S" then 16 else 8 do
			Juice.Spark(gui :: any, UDim2.fromScale(0.5 + (math.random() - 0.5) * 0.3, 0.6), color)
		end
	end

	local sign = if repDelta > 0 then "+" else ""
	local repLabel = centered(body, `REPUTATION {sign}{repDelta}  ·  now {newRep}`, 18, if repDelta > 0 then Theme.TYPED else Theme.MUTED)
	repLabel.LayoutOrder = 2
	task.delay(0.35, function()
		if token == roundToken then
			Juice.Pop(repLabel, 0.3)
			Sfx.Play(if repDelta > 0 then "PartEarned" else "ChipTap")
		end
	end)

	local continue = Theme.Button(body, "Continue", 16)
	continue.LayoutOrder = 3
	table.insert(cleanup, continue.Activated:Connect(close))
	if usingGamepad() then
		GuiService.SelectedObject = continue
	end
	runTimer(RESULT_SECONDS)
	task.delay(RESULT_SECONDS, function()
		if token == roundToken then
			close()
		end
	end)
end

-- Wiring -------------------------------------------------------------------

local function onStart(kind: any, data: any)
	if type(data) ~= "table" then
		return
	end
	if kind == "Breach" and type(data.Packets) == "table" then
		startFirewall(data)
	elseif kind == "Vulnerability" and type(data.Reports) == "table" then
		startTriage(data)
	elseif kind == "Naysayer" and type(data.Posts) == "table" then
		startClapBack(data)
	end
end

local function buildAlert()
	alertGui = Theme.Screen("IncidentAlert", 3)
	alertGui.Enabled = false

	alertHolder = Instance.new("Frame")
	alertHolder.BackgroundTransparency = 1
	alertHolder.AnchorPoint = Vector2.new(0.5, 0)
	alertHolder.Size = UDim2.fromOffset(ALERT_WIDTH, 64)
	alertHolder.Parent = alertGui

	alertBanner = Theme.Panel(alertHolder, UDim2.fromScale(1, 1), UDim2.new())
	alertBanner.BackgroundColor3 = ALERT_BACKGROUND
	alertBanner.BackgroundTransparency = 0.05
	alertStroke = alertBanner:FindFirstChildOfClass("UIStroke") :: UIStroke
	alertStroke.Color = Theme.BUG
	alertStroke.Thickness = 2

	alertArrow = centered(alertBanner, "▲", 30, Theme.BUG)
	alertArrow.Font = Enum.Font.GothamBlack
	alertArrow.AutomaticSize = Enum.AutomaticSize.None
	alertArrow.Size = UDim2.fromOffset(40, 44)

	alertTitle = Theme.Text(alertBanner, "", 18, Theme.BUG)
	alertTitle.Font = Enum.Font.GothamBlack
	alertTitle.AutomaticSize = Enum.AutomaticSize.None
	alertTitle.TextWrapped = false
	alertTitle.TextTruncate = Enum.TextTruncate.AtEnd
	alertTitle.Position = UDim2.fromOffset(48, 0)
	alertTitle.Size = UDim2.new(1, -48, 0, 22)

	alertDetail = Theme.Text(alertBanner, "", 14, Theme.TEXT)
	alertDetail.AutomaticSize = Enum.AutomaticSize.None
	alertDetail.TextWrapped = false
	alertDetail.TextTruncate = Enum.TextTruncate.AtEnd
	alertDetail.Position = UDim2.fromOffset(48, 24)
	alertDetail.Size = UDim2.new(1, -48, 0, 18)

	alertGui.Parent = player:WaitForChild("PlayerGui")
end

local function buildScreen()
	gui = Theme.Screen("Incident", 4)
	gui.Enabled = false

	panel = Theme.Panel(gui, UDim2.fromOffset(460, 0), UDim2.new(0.5, 0, 1, -24))
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	local stroke = panel:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Theme.BUG
	end
	Theme.List(panel, 8)

	titleLabel = centered(panel, "", 24, Theme.BUG)
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.LayoutOrder = 0
	hintLabel = centered(panel, "", 14, Theme.MUTED)
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
	timerFill.BackgroundColor3 = Theme.BUG
	timerFill.BorderSizePixel = 0
	timerFill.Parent = timerBack

	body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 0, 200)
	body.LayoutOrder = 3
	body.Parent = panel

	gui.Parent = player:WaitForChild("PlayerGui")
end

function IncidentController.Init()
	buildAlert()
	buildScreen()
end

function IncidentController.Start()
	RemoteManager.GetRemote(RemoteNames.IncidentState).OnClientEvent:Connect(onIncidentState)
	RemoteManager.GetRemote(RemoteNames.IncidentStart).OnClientEvent:Connect(onStart)
	RemoteManager.GetRemote(RemoteNames.IncidentResult).OnClientEvent:Connect(showResult)

	CollectionService:GetInstanceAddedSignal("IncidentLight"):Connect(watchLight)
	for _, light in CollectionService:GetTagged("IncidentLight") do
		watchLight(light)
	end
	player:GetAttributeChangedSignal("Unit"):Connect(refreshAllLights)

	RunService.Heartbeat:Connect(function()
		updateAlert()
		spinLights()
	end)
end

return IncidentController
