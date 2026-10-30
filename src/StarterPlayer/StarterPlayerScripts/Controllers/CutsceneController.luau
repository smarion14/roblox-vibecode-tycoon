--!strict
-- Plays in-engine cutscenes in the player's own unit: letterbox bars, a scripted camera between markers, local
-- actor copies, a typed-out dialogue box, title cards and fades. Scripts come from Shared/Cutscenes; the server
-- picks which one plays and only advances the story when CutsceneDone arrives for the scene it is waiting on.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cutscenes = require(Shared:WaitForChild("Cutscenes"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Actors = require(UI:WaitForChild("Actors"))
local Juice = require(UI:WaitForChild("Juice"))
local Music = require(UI:WaitForChild("Music"))
local NameDialog = require(UI:WaitForChild("NameDialog"))
local Sfx = require(UI:WaitForChild("Sfx"))
local Theme = require(UI:WaitForChild("Theme"))

local CHAR_DELAY = 0.03
local MARKER_WAIT = 6
local BLACK_HOLD = 3
local TITLE_SECONDS = 2.8
local BAR_HEIGHT = 0.11

local CutsceneController = {}

local player = Players.LocalPlayer
local gui: ScreenGui
local topBar: Frame
local bottomBar: Frame
local fade: Frame
local dialogue: Frame
local speakerLabel: TextLabel
local bodyLabel: TextLabel
local centerLabel: TextLabel
local subLabel: TextLabel
local titleLayer: Frame
local skipButton: TextButton

local playing = false
local skipping = false
local advanced = false
local sceneToken = 0

type Scene = {
	Unit: Model,
	Markers: { [string]: BasePart },
	Actors: { [string]: Model },
	Restores: { () -> () },
}

-- Waits, but returns early when the player skips.
local function hold(seconds: number)
	local elapsed = 0
	while elapsed < seconds and not skipping do
		elapsed += task.wait()
	end
end

local function tween(target: Instance, seconds: number, goal: { [string]: any }): Tween
	local created = TweenService:Create(target, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), goal)
	created:Play()
	return created
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

local function markersIn(unit: Model): { [string]: BasePart }
	local found: { [string]: BasePart } = {}
	for _, point in CollectionService:GetTagged("CutsceneMarker") do
		local name = point:GetAttribute("Marker")
		if point:IsA("BasePart") and type(name) == "string" and point:IsDescendantOf(unit) then
			found[name] = point
		end
	end
	return found
end

-- The server may have just rebuilt the unit, so wait until every marker the script uses has replicated.
local function waitForMarkers(steps: { Cutscenes.Step }): (Model?, { [string]: BasePart })
	local deadline = os.clock() + MARKER_WAIT
	repeat
		local unit = ownUnit()
		if unit then
			local markers = markersIn(unit)
			local names: { [string]: boolean } = {}
			for name in markers do
				names[name] = true
			end
			if Cutscenes.Validate(steps, names) then
				return unit, markers
			end
		end
		task.wait(0.1)
	until os.clock() > deadline
	return nil, {}
end

-- Hides a model for this client only and remembers how to show it again.
local function hideModel(scene: Scene, model: Instance?)
	if not model then
		return
	end
	local parts: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = 1
			table.insert(parts, descendant)
		end
	end
	table.insert(scene.Restores, function()
		for _, hidden in parts do
			hidden.LocalTransparencyModifier = 0
		end
	end)
end

local function setControls(enabled: boolean)
	pcall(function()
		local module = (require :: any)(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		local controls = module:GetControls()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
end

local function hideOtherGuis(scene: Scene)
	for _, other in player:WaitForChild("PlayerGui"):GetChildren() do
		if other:IsA("ScreenGui") and other ~= gui and other.Enabled then
			other.Enabled = false
			table.insert(scene.Restores, function()
				other.Enabled = true
			end)
		end
	end
end

local function setBars(shown: boolean)
	local seconds = if skipping then 0 else 0.5
	tween(topBar, seconds, { Position = if shown then UDim2.fromScale(0, 0) else UDim2.fromScale(0, -BAR_HEIGHT) })
	tween(bottomBar, seconds, { Position = if shown then UDim2.fromScale(0, 1 - BAR_HEIGHT) else UDim2.fromScale(0, 1) })
end

local function fadeTo(to: string?, seconds: number?)
	local goal = if to == "Black" then 0 else 1
	if skipping then
		fade.BackgroundTransparency = goal
		return
	end
	tween(fade, seconds or 0.6, { BackgroundTransparency = goal })
	hold(seconds or 0.6)
end

-- Types the text out; the first press finishes the line, the next one advances.
local function say(header: string, text: string)
	speakerLabel.Text = header
	bodyLabel.Text = ""
	dialogue.Visible = true
	Juice.PopIn(dialogue)
	advanced = false
	for index = 1, utf8.len(text) or #text do
		if advanced or skipping then
			break
		end
		bodyLabel.Text = string.sub(text, 1, (utf8.offset(text, index + 1) or (#text + 1)) - 1)
		if index % 3 == 0 then
			Sfx.Play("KeyClick", 1.2)
		end
		task.wait(CHAR_DELAY)
	end
	bodyLabel.Text = text
	advanced = false
	while not advanced and not skipping do
		task.wait()
	end
	dialogue.Visible = false
end

local function shot(scene: Scene, step: Cutscenes.Step)
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local from = scene.Markers[step.From :: string]
	camera.CFrame = from.CFrame
	local seconds = step.Seconds or 1
	if step.To then
		local move = tween(camera, seconds, { CFrame = scene.Markers[step.To].CFrame })
		hold(seconds)
		move:Cancel()
	else
		hold(seconds)
	end
end

local function actor(scene: Scene, step: Cutscenes.Step)
	local kind = step.Actor :: string
	local at = scene.Markers[step.Marker :: string].CFrame
	local model = scene.Actors[kind]
	if not model then
		local spawned = Actors.Spawn(kind :: Actors.ActorKind, at)
		if spawned then
			scene.Actors[kind] = spawned
		end
	elseif step.Walk then
		local seconds = step.Seconds or 2
		task.spawn(Actors.WalkTo, model, at, seconds)
		hold(seconds + 0.05)
	else
		Actors.Place(model, at)
	end
end

local function animate(scene: Scene, step: Cutscenes.Step)
	local model = scene.Actors[step.Actor :: string]
	local track = if model then Actors.Play(model, step.Animation :: string) else nil
	if not step.Wait then
		return
	end
	if track then
		local deadline = os.clock() + 1
		while track.Length == 0 and os.clock() < deadline do
			task.wait()
		end
		hold(math.max(track.Length, 0.5))
	else
		hold(0.8)
	end
end

local function prop(scene: Scene, step: Cutscenes.Step)
	local contents = scene.Unit:FindFirstChild("Contents")
	if step.Prop == "LaptopLid" then
		local lid = contents and contents:FindFirstChild("ShopComputer")
		if lid and lid:IsA("BasePart") then
			local original = lid.CFrame
			-- Swing the lid shut around its bottom edge onto the keyboard.
			local closed = original * CFrame.new(0, -lid.Size.Y / 2, 0) * CFrame.Angles(math.rad(100), 0, 0) * CFrame.new(0, lid.Size.Y / 2, 0)
			tween(lid, if skipping then 0 else 0.35, { CFrame = closed })
			Sfx.Play("GradeStamp", 1.4)
			table.insert(scene.Restores, function()
				lid.CFrame = original
			end)
			hold(0.4)
		end
	elseif step.Prop == "CashStack" then
		local giver = scene.Markers.HandoverPlayer
		local taker = scene.Markers.HandoverBrother
		if giver and taker then
			local cash = Instance.new("Part")
			cash.Name = "CutsceneCash"
			cash.Size = Vector3.new(0.7, 0.35, 1.1)
			cash.Color = Color3.fromRGB(110, 190, 110)
			cash.Material = Enum.Material.SmoothPlastic
			cash.Anchored = true
			cash.CanCollide = false
			cash.CFrame = giver.CFrame:Lerp(taker.CFrame, 0.5) * CFrame.new(0, 3.4, 0)
			cash.Parent = Workspace
			table.insert(scene.Restores, function()
				cash:Destroy()
			end)
		end
	elseif step.Prop == "PhoneBuzz" then
		local phone = contents and contents:FindFirstChild("JobPhone")
		Sfx.Play("ChipTap")
		if phone and phone:IsA("BasePart") then
			local original = phone.CFrame
			for wiggle = 1, 6 do
				phone.CFrame = original * CFrame.Angles(0, math.rad(if wiggle % 2 == 0 then 8 else -8), 0)
				task.wait(0.05)
			end
			phone.CFrame = original
		end
		hold(0.4)
	end
end

local function centerText(step: Cutscenes.Step)
	centerLabel.Text = step.Text or ""
	centerLabel.TextTransparency = 1
	centerLabel.Visible = true
	tween(centerLabel, 0.5, { TextTransparency = 0 })
	hold(step.Seconds or 2)
	centerLabel.Visible = false
end

local function title(step: Cutscenes.Step)
	if skipping then
		return
	end
	Juice.Banner(titleLayer, step.Text or "", Theme.ACCENT, 46)
	Sfx.Play("Banner")
	if step.Sub then
		subLabel.Text = step.Sub
		subLabel.Visible = true
		Juice.PopIn(subLabel)
	end
	hold(TITLE_SECONDS)
	subLabel.Visible = false
end

local function runStep(scene: Scene, step: Cutscenes.Step)
	local kind = step.Kind
	if kind == "Fade" then
		fadeTo(step.To, step.Seconds)
	elseif kind == "CenterText" then
		centerText(step)
	elseif kind == "Shot" then
		shot(scene, step)
	elseif kind == "Actor" then
		actor(scene, step)
	elseif kind == "Animate" then
		animate(scene, step)
	elseif kind == "Prop" then
		prop(scene, step)
	elseif kind == "Line" then
		say(string.upper(step.Speaker or ""), step.Text or "")
	elseif kind == "PhoneText" then
		say(`{string.upper(step.Speaker or "")}  ·  new message`, step.Text or "")
	elseif kind == "NameStartup" then
		-- Continues only once the server accepts a name; Skip closes the dialog and leaves the name unset.
		NameDialog.Prompt("")
	elseif kind == "Title" then
		title(step)
	end
end

local function play(id: string, copy: { [string]: any })
	local ok, steps = pcall(Cutscenes.Get, id, copy)
	if not ok then
		return
	end
	local unit, markers = waitForMarkers(steps)
	if not unit then
		-- No world to stage it in: count it as seen so the story can't get stuck.
		RemoteManager.FireServer(RemoteNames.CutsceneDone, id)
		return
	end

	-- The player's actor is a copy of their character, so wait for it (and its outfit) to exist.
	local character = player.Character or player.CharacterAdded:Wait()
	local deadline = os.clock() + 3
	while not player:HasAppearanceLoaded() and os.clock() < deadline do
		task.wait(0.1)
	end

	sceneToken += 1
	playing = true
	skipping = false
	local scene: Scene = { Unit = unit, Markers = markers, Actors = {}, Restores = {} }
	hideOtherGuis(scene)
	hideModel(scene, character)
	hideModel(scene, unit:FindFirstChild("SiblingModel", true))
	setControls(false)
	setBars(true)
	skipButton.Visible = true
	Music.Play("Cutscene", 1.5)

	-- A failing step must never strand the player with controls off, so errors fall through to the restore.
	local ran, err = pcall(function()
		for _, step in steps do
			if skipping then
				break
			end
			runStep(scene, step)
		end
	end)
	if not ran then
		warn(`Cutscene {id} failed: {err}`)
	end

	-- Restore everything. A scene that ends on black stays black for the next scene's first fade to clear.
	local last = steps[#steps]
	local endsBlack = last.Kind == "Fade" and last.To == "Black"
	skipping = false
	dialogue.Visible = false
	centerLabel.Visible = false
	subLabel.Visible = false
	skipButton.Visible = false
	for _, model in scene.Actors do
		model:Destroy()
	end
	for _, restore in scene.Restores do
		restore()
	end
	local camera = Workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	setControls(true)
	setBars(false)
	Music.Stop(1.5)
	playing = false

	if endsBlack then
		fade.BackgroundTransparency = 0
		local token = sceneToken
		task.delay(BLACK_HOLD, function()
			if sceneToken == token then
				tween(fade, 0.6, { BackgroundTransparency = 1 })
			end
		end)
	else
		tween(fade, 0.6, { BackgroundTransparency = 1 })
	end
	RemoteManager.FireServer(RemoteNames.CutsceneDone, id)
end

-- StoryController owns the StoryBeat listener and hands "Cutscene" beats here, so a beat queued before the
-- client finished loading is never missed.
function CutsceneController.Play(payload: any)
	if type(payload) ~= "table" or type(payload.Id) ~= "string" or type(payload.Copy) ~= "table" then
		return
	end
	while playing do
		task.wait(0.1)
	end
	play(payload.Id, payload.Copy)
end

function CutsceneController.Init()
	gui = Theme.Screen("Cutscene", 20)
	gui.IgnoreGuiInset = true

	local function bar(position: UDim2): Frame
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, BAR_HEIGHT)
		frame.Position = position
		frame.BackgroundColor3 = Color3.new(0, 0, 0)
		frame.BorderSizePixel = 0
		frame.ZIndex = 2
		frame.Parent = gui
		return frame
	end
	topBar = bar(UDim2.fromScale(0, -BAR_HEIGHT))
	bottomBar = bar(UDim2.fromScale(0, 1))

	fade = Instance.new("Frame")
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BackgroundTransparency = 1
	fade.BorderSizePixel = 0
	fade.ZIndex = 5
	fade.Parent = gui

	titleLayer = Instance.new("Frame")
	titleLayer.Size = UDim2.fromScale(1, 1)
	titleLayer.BackgroundTransparency = 1
	titleLayer.ZIndex = 20
	titleLayer.Parent = gui

	centerLabel = Theme.Text(gui, "", 34)
	centerLabel.AutomaticSize = Enum.AutomaticSize.None
	centerLabel.Size = UDim2.fromScale(1, 0.2)
	centerLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	centerLabel.Position = UDim2.fromScale(0.5, 0.5)
	centerLabel.TextXAlignment = Enum.TextXAlignment.Center
	centerLabel.ZIndex = 6
	centerLabel.Visible = false

	subLabel = Theme.Text(gui, "", 22, Theme.MOOD)
	subLabel.AutomaticSize = Enum.AutomaticSize.None
	subLabel.Size = UDim2.new(1, 0, 0, 30)
	subLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	subLabel.Position = UDim2.fromScale(0.5, 0.52)
	subLabel.TextXAlignment = Enum.TextXAlignment.Center
	subLabel.ZIndex = 21
	subLabel.Visible = false

	dialogue = Theme.Panel(gui, UDim2.new(0.6, 0, 0, 120), UDim2.new(0.5, 0, 1 - BAR_HEIGHT, -16))
	dialogue.AnchorPoint = Vector2.new(0.5, 1)
	dialogue.ZIndex = 3
	dialogue.Visible = false
	Theme.List(dialogue, 6)
	speakerLabel = Theme.Text(dialogue, "", 14, Theme.ACCENT)
	speakerLabel.LayoutOrder = 1
	speakerLabel.ZIndex = 3
	bodyLabel = Theme.Text(dialogue, "", 22)
	bodyLabel.LayoutOrder = 2
	bodyLabel.ZIndex = 3
	local hint = Theme.Text(dialogue, "click / space ▸", 12, Theme.MUTED)
	hint.LayoutOrder = 3
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.ZIndex = 3

	skipButton = Theme.Button(gui, "Skip ▸▸", 14)
	skipButton.AnchorPoint = Vector2.new(1, 0)
	skipButton.Position = UDim2.new(1, -16, 0, 16)
	skipButton.Size = UDim2.fromOffset(110, 34)
	skipButton.ZIndex = 7
	skipButton.Visible = false
	skipButton.Activated:Connect(function()
		skipping = true
		NameDialog.Close()
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

function CutsceneController.Start()
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if not playing then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.Space
			or input.KeyCode == Enum.KeyCode.Return
			or input.KeyCode == Enum.KeyCode.ButtonA
		then
			advanced = true
		elseif input.KeyCode == Enum.KeyCode.ButtonB then
			-- Gamepads have no cursor for the Skip button.
			skipping = true
			NameDialog.Close()
		end
	end)
end

return CutsceneController
