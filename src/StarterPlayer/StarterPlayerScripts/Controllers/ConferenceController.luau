--!strict
-- Act 3 conference keynote on the client (spec §9): the stage camera, the slogan prompt with its closing beat ring,
-- the typing box, the crowd hype meter, and the results card. The server stamps and judges every slogan; the hype
-- meter, bouncing audience and pulsing stage lights are local guesses for feel only.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Keynote = require(Shared:WaitForChild("Keynote"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Juice = require(UI:WaitForChild("Juice"))
local Sfx = require(UI:WaitForChild("Sfx"))
local Theme = require(UI:WaitForChild("Theme"))

type Bouncer = { Part: BasePart, Base: CFrame, Phase: number }
type Show = {
	Round: Keynote.Round,
	StartedAt: number,
	Done: { [number]: boolean },
	Shown: number,
	Hype: number,
	Crowd: { Bouncer },
	Beams: { SpotLight },
	Connections: { RBXScriptConnection },
}

local START_HYPE = 0.35
local HYPE_HIT = 0.15
local HYPE_FLUB = 0.1
local HYPE_MISS = 0.12
local RING_LEAD = 1.5 -- seconds the beat ring takes to close onto a slogan's window
local RING_SIZE = 76
local BOUNCE_MIN, BOUNCE_MAX = 0.1, 1.4 -- studs
local LIGHT_AMBER = Color3.fromRGB(255, 184, 79)
-- Over the speaker's right shoulder, looking out over the podium at the crowd (podium-local +Z).
local CAMERA_OFFSET = Vector3.new(1.6, 3.4, -2.4)
local CAMERA_TARGET = Vector3.new(0, 0.5, 12)
local RESULT_SECONDS = 7
local STUCK_SECONDS = 5 -- no result this long after the last window: give the player their camera back
local DESIGN_HEIGHT = 340 -- shortcut: the stage UI scales from a fixed design height; measure if it grows
local GRADE_COLORS: { [string]: Color3 } = { S = Theme.MOOD, A = Theme.TYPED, B = Theme.ACCENT, C = Theme.MUTED }
local GRADE_STINGERS: { [string]: Sfx.SoundName } = { S = "GradeS", A = "GradeA", B = "GradeB", C = "GradeC" }

local ConferenceController = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local holder: Frame
local stage: Frame
local hypeFill: Frame
local ring: Frame
local ringStroke: UIStroke
local target: Frame
local targetStroke: UIStroke
local sloganLabel: TextLabel
local nextLabel: TextLabel
local hintLabel: TextLabel
local box: TextBox
local fxLayer: Frame
local resultPanel: Frame? = nil

local show: Show? = nil
local token = 0

local function clock(current: Show): number
	return Workspace:GetServerTimeNow() - current.StartedAt
end

local function setHype(current: Show, delta: number)
	current.Hype = math.clamp(current.Hype + delta, 0, 1)
	local color = if current.Hype >= 0.7 then Theme.MOOD elseif current.Hype >= 0.4 then Theme.ACCENT else Theme.MUTED
	TweenService:Create(hypeFill, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(current.Hype, 1),
		BackgroundColor3 = color,
	}):Play()
end

local function float(text: string, color: Color3)
	Juice.FloatText(fxLayer, UDim2.fromScale(0.5, 0.5), text, color)
end

local function restoreCamera()
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

-- Ends the performance view: camera, crowd and lights go back to how they were.
local function stopShow()
	local current = show
	if not current then
		return
	end
	show = nil
	for _, connection in current.Connections do
		connection:Disconnect()
	end
	for _, bouncer in current.Crowd do
		if bouncer.Part.Parent then
			bouncer.Part.CFrame = bouncer.Base
		end
	end
	for _, beam in current.Beams do
		beam:Destroy()
	end
	box:ReleaseFocus()
	box.Text = ""
	stage.Visible = false
	gui.Enabled = false
	restoreCamera()
end

local function submit(current: Show)
	local text = box.Text
	if string.match(text, "^%s*$") then
		return
	end
	local index = Keynote.WindowAt(current.Round, clock(current))
	if not index then
		hintLabel.Text = "WAIT FOR THE BEAT — hit Enter as the ring closes"
		hintLabel.TextColor3 = Theme.BUG
		Juice.Shake(box)
		Sfx.Play("KeyWrong")
		return
	end
	if current.Done[index] then
		return
	end
	current.Done[index] = true
	RemoteManager.FireServer(RemoteNames.ConferenceAction, string.sub(text, 1, GameConfig.MAX_REMOTE_STRING))
	box.Text = ""
	if Keynote.Matches(text, current.Round.Slogans[index].Text) then
		setHype(current, HYPE_HIT)
		float("HYPE!", Theme.TYPED)
		Sfx.Play("PromptClean")
		Juice.Pop(sloganLabel, 0.25)
		Juice.Spark(fxLayer, UDim2.fromScale(0.5, 0.55), Theme.TYPED)
	else
		setHype(current, -HYPE_FLUB)
		float("FLUBBED", Theme.BUG)
		Sfx.Play("KeyWrong")
		Juice.Shake(sloganLabel)
	end
end

local function step(current: Show)
	local t = clock(current)
	local slogans = current.Round.Slogans
	for index, slogan in slogans do
		if not current.Done[index] and t > slogan.CloseAt + Keynote.LATE_GRACE then
			current.Done[index] = true
			setHype(current, -HYPE_MISS)
			float("MISSED", Theme.BUG)
			Sfx.Play("KeyWrong")
		end
	end
	local index = 0
	for each = 1, #slogans do
		if not current.Done[each] then
			index = each
			break
		end
	end

	if index ~= current.Shown then
		current.Shown = index
		local slogan = slogans[index]
		sloganLabel.Text = if slogan then slogan.Text else "THANK YOU!"
		local upcoming = slogans[index + 1]
		nextLabel.Text = if upcoming and slogan then `NEXT: {upcoming.Text}` else ""
		hintLabel.Text = if slogan then "Type it, hit Enter as the ring closes" else "Waiting for the crowd..."
		hintLabel.TextColor3 = Theme.MUTED
	end

	local slogan = slogans[index]
	local open = slogan ~= nil and t >= slogan.OpenAt
	local approach = if slogan then math.clamp((slogan.OpenAt - t) / RING_LEAD, 0, 1) else 1
	ring.Size = UDim2.fromOffset(RING_SIZE * (1 + 1.6 * approach), RING_SIZE * (1 + 1.6 * approach))
	ringStroke.Transparency = if slogan and not open then 0.7 * approach else 1
	targetStroke.Color = if open then Theme.TYPED else Theme.MUTED
	target.BackgroundTransparency = if open then 0.55 else 1

	-- The crowd bounces harder and faster as hype builds; the stage lights pulse on every beat.
	local now = os.clock()
	local height = BOUNCE_MIN + (BOUNCE_MAX - BOUNCE_MIN) * current.Hype
	local speed = math.pi * (2 + 4 * current.Hype)
	for _, bouncer in current.Crowd do
		if bouncer.Part.Parent then
			bouncer.Part.CFrame = bouncer.Base + Vector3.yAxis * height * math.abs(math.sin(now * speed + bouncer.Phase))
		end
	end
	local beat = if slogan then 1 - math.clamp(math.abs(t - slogan.OpenAt) / 0.6, 0, 1) else 0
	for _, beam in current.Beams do
		beam.Brightness = 1 + 7 * current.Hype * (0.4 + 0.6 * beat)
		beam.Color = LIGHT_AMBER:Lerp(Theme.ACCENT, current.Hype)
	end
end

-- Client-local dressing from the podium's room: the block audience and the spotlights. Restored by stopShow.
local function dressStage(current: Show, podium: BasePart)
	local room = podium.Parent
	if not room then
		return
	end
	for _, child in room:GetChildren() do
		if not child:IsA("BasePart") then
			continue
		end
		if child.Name == "AudienceFigure" or child.Name == "AudienceHead" then
			-- Body and head share x/z, so they bounce together.
			local phase = (child.Position.X + child.Position.Z) * 0.9
			table.insert(current.Crowd, { Part = child, Base = child.CFrame, Phase = phase })
		elseif child.Name == "StageSpotlight" then
			local beam = Instance.new("SpotLight")
			beam.Face = Enum.NormalId.Bottom
			beam.Angle = 60
			beam.Range = 24
			beam.Brightness = 2
			beam.Color = LIGHT_AMBER
			beam.Parent = child
			table.insert(current.Beams, beam)
		end
	end
end

local function onStart(data: any)
	if show or type(data) ~= "table" or type(data.StartedAt) ~= "number" or type(data.Slogans) ~= "table" then
		return
	end
	local slogans: { Keynote.Slogan } = {}
	for _, slogan in data.Slogans do
		if type(slogan) == "table" and type(slogan.Text) == "string" and type(slogan.OpenAt) == "number" and type(slogan.CloseAt) == "number" then
			table.insert(slogans, { Text = slogan.Text, OpenAt = slogan.OpenAt, CloseAt = slogan.CloseAt })
		end
	end
	if #slogans == 0 then
		return
	end
	if resultPanel then
		resultPanel:Destroy()
		resultPanel = nil
	end
	token += 1
	local current: Show = {
		Round = { Slogans = slogans },
		StartedAt = data.StartedAt,
		Done = {},
		Shown = -1,
		Hype = START_HYPE,
		Crowd = {},
		Beams = {},
		Connections = {},
	}
	show = current
	setHype(current, 0)

	local podium = data.Podium
	if typeof(podium) == "Instance" and podium:IsA("BasePart") then
		dressStage(current, podium)
		local camera = Workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		local goal = CFrame.lookAt(podium.CFrame:PointToWorldSpace(CAMERA_OFFSET), podium.CFrame:PointToWorldSpace(CAMERA_TARGET))
		TweenService:Create(camera, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = goal }):Play()
	end

	box.Text = ""
	stage.Visible = true
	gui.Enabled = true
	Juice.PopIn(stage)
	Sfx.Play("CardOpen")
	table.insert(current.Connections, RunService.PreRender:Connect(function()
		step(current)
	end))
	table.insert(current.Connections, box:GetPropertyChangedSignal("Text"):Connect(function()
		if #box.Text > 0 then
			Sfx.Play("KeyClick")
		end
	end))
	table.insert(current.Connections, box.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			submit(current)
		end
		task.defer(function()
			if show == current then
				box:CaptureFocus()
			end
		end)
	end))
	box:CaptureFocus()

	local myToken = token
	local lastClose = slogans[#slogans].CloseAt + Keynote.LATE_GRACE
	task.delay(math.max(0, current.StartedAt + lastClose - Workspace:GetServerTimeNow()) + STUCK_SECONDS, function()
		if token == myToken and show == current then
			stopShow()
		end
	end)
end

local function closeResult()
	local panel = resultPanel
	if panel then
		resultPanel = nil
		Juice.CloseWindow(gui, panel)
		task.delay(0.3, function()
			panel:Destroy()
		end)
	end
end

local function centered(parent: Instance, text: string, size: number, color: Color3, order: number): TextLabel
	local label = Theme.Text(parent, text, size, color)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.LayoutOrder = order
	return label
end

local function onResult(gradeValue: any, deltaValue: any, repValue: any, multiplierValue: any)
	stopShow()
	local grade = if type(gradeValue) == "string" and GRADE_COLORS[gradeValue] then gradeValue else "C"
	local repDelta = tonumber(deltaValue) or 0
	local newRep = tonumber(repValue) or 0
	local multiplier = tonumber(multiplierValue) or 1
	local color = GRADE_COLORS[grade]
	token += 1
	local myToken = token
	if resultPanel then
		resultPanel:Destroy()
	end

	local panel = Theme.Panel(holder, UDim2.fromOffset(380, 0), UDim2.fromScale(0.5, 0.5))
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	Theme.List(panel, 8)
	resultPanel = panel
	local title = centered(panel, "KEYNOTE COMPLETE", 24, Theme.ACCENT, 1)
	title.Font = Enum.Font.GothamBlack
	local gradeLabel = centered(panel, grade, 64, color, 2)
	gradeLabel.Font = Enum.Font.GothamBlack
	local sign = if repDelta > 0 then "+" else ""
	centered(panel, `REPUTATION {sign}{repDelta}  ·  now {newRep}`, 18, if repDelta > 0 then Theme.TYPED else Theme.MUTED, 3)
	centered(panel, string.format("PAYOUT MULTIPLIER x%.2f", multiplier), 18, Theme.MOOD, 4)
	local continueButton = Theme.Button(panel, "Continue", 16)
	continueButton.LayoutOrder = 5
	continueButton.Activated:Connect(closeResult)

	Juice.OpenWindow(gui, panel)
	Sfx.Play("GradeStamp")
	task.delay(0.12, function()
		Sfx.Play(GRADE_STINGERS[grade])
	end)
	if grade == "S" or grade == "A" then
		Juice.Banner(fxLayer, `{grade} RANK!`, color, 46)
		for _ = 1, if grade == "S" then 16 else 8 do
			Juice.Spark(fxLayer, UDim2.fromScale(0.5 + (math.random() - 0.5) * 0.3, 0.5), color)
		end
	end
	task.delay(RESULT_SECONDS, function()
		if token == myToken then
			closeResult()
		end
	end)
end

local function build()
	gui = Theme.Screen("Conference", 4)
	gui.Enabled = false

	holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = gui
	local fit = Instance.new("UIScale")
	fit.Parent = holder
	local function refit()
		if gui.AbsoluteSize.Y > 0 then
			fit.Scale = math.min(1, gui.AbsoluteSize.Y / DESIGN_HEIGHT)
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)

	stage = Instance.new("Frame")
	stage.BackgroundTransparency = 1
	stage.Size = UDim2.fromScale(1, 1)
	stage.Visible = false
	stage.Parent = holder

	-- Crowd hype meter, top center (the HUD panel owns the top left).
	local meter = Theme.Panel(stage, UDim2.fromOffset(300, 52), UDim2.new(0.5, 0, 0, 8))
	meter.AnchorPoint = Vector2.new(0.5, 0)
	local meterLabel = Theme.Text(meter, "CROWD HYPE", 14, Theme.ACCENT)
	meterLabel.TextXAlignment = Enum.TextXAlignment.Center
	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = Theme.PANEL
	bar.BorderSizePixel = 0
	bar.Position = UDim2.fromOffset(0, 20)
	bar.Size = UDim2.new(1, 0, 0, 10)
	bar.Parent = meter
	hypeFill = Instance.new("Frame")
	hypeFill.BackgroundColor3 = Theme.ACCENT
	hypeFill.BorderSizePixel = 0
	hypeFill.Size = UDim2.fromScale(START_HYPE, 1)
	hypeFill.Parent = bar

	local panel = Theme.Panel(stage, UDim2.fromOffset(460, 200), UDim2.new(0.5, 0, 1, -16))
	panel.AnchorPoint = Vector2.new(0.5, 1)
	local stroke = panel:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Theme.ACCENT
	end

	-- Beat ring: the outer ring closes onto the target circle; the target lights up while the window is open.
	local beatHolder = Instance.new("Frame")
	beatHolder.BackgroundTransparency = 1
	beatHolder.Size = UDim2.fromOffset(RING_SIZE, RING_SIZE)
	beatHolder.Position = UDim2.fromOffset(4, 8)
	beatHolder.Parent = panel
	local function circle(color: Color3): (Frame, UIStroke)
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.Size = UDim2.fromOffset(RING_SIZE, RING_SIZE)
		frame.BackgroundColor3 = Theme.TYPED
		frame.BackgroundTransparency = 1
		frame.Parent = beatHolder
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = frame
		local edge = Instance.new("UIStroke")
		edge.Color = color
		edge.Thickness = 3
		edge.Parent = frame
		return frame, edge
	end
	target, targetStroke = circle(Theme.MUTED)
	ring, ringStroke = circle(Theme.ACCENT)

	sloganLabel = Theme.Text(panel, "", 40, Theme.TEXT)
	sloganLabel.Font = Enum.Font.GothamBlack
	sloganLabel.AutomaticSize = Enum.AutomaticSize.None
	sloganLabel.TextScaled = true
	sloganLabel.Position = UDim2.fromOffset(RING_SIZE + 20, 10)
	sloganLabel.Size = UDim2.new(1, -(RING_SIZE + 20), 0, 46)
	local textLimit = Instance.new("UITextSizeConstraint")
	textLimit.MaxTextSize = 40
	textLimit.Parent = sloganLabel

	nextLabel = Theme.Text(panel, "", 14, Theme.MUTED)
	nextLabel.Position = UDim2.fromOffset(RING_SIZE + 20, 60)
	nextLabel.Size = UDim2.new(1, -(RING_SIZE + 20), 0, 18)

	box = Instance.new("TextBox")
	box.BackgroundColor3 = Theme.PANEL
	box.BorderSizePixel = 0
	box.Font = Theme.FONT
	box.TextSize = 22
	box.TextColor3 = Theme.TYPED
	box.PlaceholderText = "type the slogan, press Enter"
	box.PlaceholderColor3 = Theme.TODO
	box.ClearTextOnFocus = false
	box.Text = ""
	box.Position = UDim2.fromOffset(0, 104)
	box.Size = UDim2.new(1, 0, 0, 44)
	box.Parent = panel
	local boxCorner = Instance.new("UICorner")
	boxCorner.CornerRadius = UDim.new(0, 6)
	boxCorner.Parent = box
	local boxStroke = Instance.new("UIStroke")
	boxStroke.Color = Theme.ACCENT
	boxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	boxStroke.Parent = box

	hintLabel = Theme.Text(panel, "", 14, Theme.MUTED)
	hintLabel.TextXAlignment = Enum.TextXAlignment.Center
	hintLabel.Position = UDim2.fromOffset(0, 154)
	hintLabel.Size = UDim2.new(1, 0, 0, 18)

	fxLayer = Instance.new("Frame")
	fxLayer.BackgroundTransparency = 1
	fxLayer.Size = UDim2.fromScale(1, 1)
	fxLayer.ZIndex = 2
	fxLayer.Parent = holder

	gui.Parent = player:WaitForChild("PlayerGui")
	refit()
end

function ConferenceController.Init()
	build()
end

function ConferenceController.Start()
	RemoteManager.GetRemote(RemoteNames.ConferenceStart).OnClientEvent:Connect(onStart)
	RemoteManager.GetRemote(RemoteNames.ConferenceResult).OnClientEvent:Connect(onResult)
end

return ConferenceController
