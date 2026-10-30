--!strict
-- Deploy battle screen: a Galaga-style shooter. Your app (the ship) slides along the bottom and fires on its own;
-- bugs fly in from the top, hold formation, then dive at YOUR CODE. Station part grades set the loadout.
-- Left: the client on a live call. Centre: wave, ship progress, loadout, combo and the playfield.
-- Bug paths come from BattleState.BugPosition on the shared server clock; BattleUpdate snapshots are the truth.
-- Act 2 (BattleStarted.Squad): hired roles fly as wingmen, crash reports and lag spikes join the waves, the boss
-- fires volleys, and the ship streams its x so the server can judge bullets and lag against it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BattleState = require(Shared:WaitForChild("BattleState"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Juice = require(UI:WaitForChild("Juice"))
local Music = require(UI:WaitForChild("Music"))
local ResultsScreen = require(UI:WaitForChild("ResultsScreen"))
local Sfx = require(UI:WaitForChild("Sfx"))
local Theme = require(UI:WaitForChild("Theme"))

type BugView = {
	Bug: BattleState.Bug, -- flight plan with times relative to the battle start
	Label: TextLabel,
	HpFill: Frame?,
	MaxHp: number,
	State: string,
	Shown: boolean,
	HiddenAt: number?, -- set when a local bullet hit it; the server confirms or it reappears
}

-- Turn: field widths per second it can steer toward a bug (0 = flies straight). Weapon: nil for the ship's own shots.
type Bullet = { Frame: Frame, X: number, Y: number, VX: number, VY: number, Turn: number, Weapon: string? }
type Wingman = { Label: TextLabel, Offset: number, Weapon: string?, Interval: number, NextAt: number }
type BossBullet = { Def: BattleState.Bullet, Frame: Frame, Shown: boolean, Done: boolean }

local RESULTS_DELAY = 1.1 -- let the SHIPPED banner land before the results card
local SHIP_Y = 0.9
local SHIP_KEY_SPEED = 1.1 -- field widths per second with keys or a stick
local SHIP_DRAG_SPEED = 2.6 -- how fast the ship chases a drag or mouse target
local BULLET_SPEED = 1.6 -- field heights per second
local HOMING_TURN = 0.9 -- field widths per second a homing bullet can slide sideways
local MINION_HIT_PX = 20
local BOSS_HIT_PX = Vector2.new(70, 34)
local PREDICTION_TIMEOUT = 0.8 -- a hit the server never confirms reappears after this long
local PRAISE_CHANCE = 0.45
local INSTRUCTION_KEYBOARD = "Move with ← → or A / D (or drag). Your app fires on its own. Don't let bugs reach YOUR CODE."
local INSTRUCTION_TOUCH = "Drag to move. Your app fires on its own. Don't let bugs reach YOUR CODE."
local INSTRUCTION_SQUAD = " Your squad flies with you. Dodge the boss's bullets."

-- Act 2 squad
local WING_OFFSETS = { -0.14, -0.07, 0.07, 0.14 } -- wingman slots beside the ship, filled in role order
local WING_Y = SHIP_Y + 0.02
local SPREAD_DEGREES = 15
local BEAM_HALF_WIDTH = 0.03
local BEAM_MAX_HITS = 4
local MISSILE_TURN = 2.4
local SHIP_SEND_INTERVAL = 0.1
local SLOW_SPEED_SCALE = 0.5
local LAG_COLOR = Color3.fromHex("b06cff")
local ROLE_COLORS: { [string]: Color3 } = {
	FrontendUnits = Theme.TYPED,
	BackendEndpoints = Theme.ACCENT,
	DatabaseTables = Theme.MOOD,
	PromptTokens = LAG_COLOR,
}

local PRAISE = { "clean!", "squashed!", "nice!", "gone!", "patched!", "fixed!" }
local COMBO_CALLOUTS: { [number]: string } = {
	[3] = "NICE!",
	[5] = "AMAZING!",
	[8] = "ON FIRE!",
	[10] = "SHIP! SHIP! SHIP!",
	[15] = "UNSTOPPABLE!",
	[20] = "10x ENGINEER!",
	[25] = "LEGENDARY DEV!",
}

-- What the client says on the call when something good happens.
local CLIENT_LINES: { [string]: { string } } = {
	Squash = {
		"Wow, this app is great!",
		"Ooh, smooth!",
		"That bug's gone? Nice.",
		"Clean work!",
		"I like where this is going.",
		"My customers will love this!",
		"Fast AND pretty?",
		"Okay, I'm impressed.",
	},
	BossHit = { "You're breaking it apart!", "Keep going, keep going!", "Get that thing!", "It's cracking!" },
	BossDown = { "YOU DID IT! That was the big one!", "Is it fixed?! It's FIXED!", "Best developer ever!" },
	Combo = { "You're on a roll!", "Are you even human?", "This is going viral!", "Teach me your ways!" },
}
local HAPPY_FACES = { "😍", "🤩", "😆", "🥳" }
local MAX_BUBBLES = 3
local BUBBLE_SECONDS = 3.5
local SQUASH_LINE_COOLDOWN = 0.7 -- kills can land every half second; don't bury the sidebar in bubbles

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
local bubbleStack: Frame
local faceBand = ""
local faceToken = 0
local lastSquashLine = 0
local bubbleOrder = 0
local moodFill: Frame
local comboLabel: TextLabel
local waveLabel: TextLabel
local progressFill: Frame
local instructionLabel: TextLabel
local loadoutLabel: TextLabel
local field: Frame
local ship: TextLabel
local shieldLabel: TextLabel
local shieldBubble: Frame
local shieldStroke: UIStroke

local bugs: { BugView } = {}
local bullets: { Bullet } = {}
local serverStart = 0
local waveCount = 2
local announcedWave = 0
local lastMoodBand = ""
local lastCombo = 0
local lastShield = 0
local rollbackShown = false
local shipX = 0.5
local dragTarget: number? = nil
local fireInterval = 0.32
local homing = false
local nextShotAt = 0
local renderConnection: RBXScriptConnection? = nil
local inputConnections: { RBXScriptConnection } = {}
local maxProgress = 0 -- shards add bugs mid-battle, so the server's ratio can dip; the bar never goes back
local lastMood = 0

-- Act 2 squad state; times are relative to the battle start like bug paths.
local squadOn = false
local wingmen: { Wingman } = {}
local bossBullets: { BossBullet } = {}
local volleySpeed = 0.35
local volleyHitRadius = 0.035
local hasWingShield = false
local wingShieldReadyAt = 0
local slowUntil = 0
local bossDiedAt: number? = nil
local lastBulletHits = 0
local nextShipSendAt = 0

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

-- Chat bubble from the client: pops in from the face with an overshoot, settles, then fades out.
-- Good news gets a green edge, complaints a red one. Only the newest few stay on screen.
local function clientSay(text: string, positive: boolean)
	bubbleOrder += 1
	local bubble = Instance.new("Frame")
	bubble.AutomaticSize = Enum.AutomaticSize.Y
	bubble.Size = UDim2.new(1, 0, 0, 0)
	bubble.BackgroundColor3 = Theme.PANEL
	bubble.LayoutOrder = -bubbleOrder -- newest on top
	bubble.Parent = bubbleStack
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = bubble
	local stroke = Instance.new("UIStroke")
	stroke.Color = if positive then Theme.TYPED else Theme.BUG
	stroke.Thickness = 2
	stroke.Parent = bubble
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = bubble
	local label = Theme.Text(bubble, `"{text}"`, 15, if positive then Theme.TEXT else Theme.BUG)

	local scale = Instance.new("UIScale")
	scale.Scale = 0.2
	scale.Parent = bubble
	bubble.Rotation = math.random(-6, 6)
	TweenService:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(bubble, TweenInfo.new(0.4, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Rotation = 0 }):Play()

	local bubbles: { Frame } = {}
	for _, child in bubbleStack:GetChildren() do
		if child:IsA("Frame") then
			table.insert(bubbles, child)
		end
	end
	table.sort(bubbles, function(a: Frame, b: Frame): boolean
		return a.LayoutOrder < b.LayoutOrder
	end)
	for index = MAX_BUBBLES + 1, #bubbles do
		bubbles[index]:Destroy()
	end

	task.delay(BUBBLE_SECONDS, function()
		if bubble.Parent then
			TweenService:Create(bubble, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(stroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			local fade = TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 })
			fade.Completed:Once(function()
				bubble:Destroy()
			end)
			fade:Play()
		end
	end)
end

local function bandFace(): string
	return if faceBand == "happy" then "😄" elseif faceBand == "neutral" then "😐" else "😬"
end

-- The client lights up for a moment: delighted face, a wiggle and a bounce, plus a green pulse on the mood bar.
local function clientCheer(text: string)
	faceToken += 1
	local token = faceToken
	face.Text = HAPPY_FACES[math.random(1, #HAPPY_FACES)]
	Juice.Pop(face, 0.55)
	face.Rotation = math.random(-15, 15)
	TweenService:Create(face, TweenInfo.new(0.45, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
	moodFill.BackgroundColor3 = Theme.TYPED
	TweenService:Create(moodFill, TweenInfo.new(0.5), { BackgroundColor3 = Theme.MOOD }):Play()
	clientSay(text, true)
	task.delay(0.9, function()
		if faceToken == token then
			face.Text = bandFace()
		end
	end)
end

local function cheerFrom(kind: string)
	local lines = CLIENT_LINES[kind]
	clientCheer(lines[math.random(1, #lines)])
end

local function setMood(mood: number)
	moodFill.Size = UDim2.fromScale(math.clamp(mood / 100, 0, 1), 1)
	local band = moodBand(mood)
	faceBand = band
	if band ~= lastMoodBand then
		local dropped = lastMoodBand ~= ""
		lastMoodBand = band
		face.Text = bandFace()
		Juice.Pop(face, 0.4)
		-- A drop in mood is worth saying out loud; the opening line is set in onStarted.
		if dropped and band ~= "happy" then
			local lines = REACTIONS[band]
			clientSay(lines[math.random(1, #lines)], false)
		end
	end
end

local function clearBattle()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	for _, connection in inputConnections do
		connection:Disconnect()
	end
	table.clear(inputConnections)
	for _, bug in bugs do
		bug.Label:Destroy()
	end
	table.clear(bugs)
	for _, bullet in bullets do
		bullet.Frame:Destroy()
	end
	table.clear(bullets)
	-- Boss bullets still in flight when the battle ends stop being drawn here.
	for _, wing in wingmen do
		wing.Label:Destroy()
	end
	table.clear(wingmen)
	for _, bullet in bossBullets do
		bullet.Frame:Destroy()
	end
	table.clear(bossBullets)
	squadOn = false
	hasWingShield = false
	shieldBubble.Visible = false
	ship.BackgroundTransparency = 1
	dragTarget = nil
end

local function announceWave(elapsed: number)
	for _, view in bugs do
		if view.Bug.Wave > announcedWave and elapsed >= view.Bug.SpawnAt - 0.8 then
			announcedWave = view.Bug.Wave
			Sfx.Play("Banner")
			if view.Bug.Wave > waveCount then
				waveLabel.Text = "BOSS WAVE"
				Music.Play("Boss", 1.5)
				Juice.Banner(root, "⚠ BOSS BUG INCOMING ⚠", Theme.BUG)
			else
				waveLabel.Text = `WAVE {view.Bug.Wave} / {waveCount}`
				Juice.Banner(root, `WAVE {view.Bug.Wave}`, Theme.MOOD)
			end
			Juice.Pop(waveLabel, 0.4)
			return
		end
	end
end

local function fieldPoint(x: number, y: number): Vector2
	return Vector2.new(x * field.AbsoluteSize.X, y * field.AbsoluteSize.Y)
end

local function liveTargets(elapsed: number): { BugView }
	local list: { BugView } = {}
	for _, view in bugs do
		if view.State == "Pending" and not view.HiddenAt and elapsed >= view.Bug.SpawnAt + 0.3 then
			table.insert(list, view)
		end
	end
	return list
end

-- A bullet flying at (vx, vy) field units per second (vy up), tilted along its path.
local function spawnBullet(x: number, y: number, vx: number, vy: number, turn: number, color: Color3, weapon: string?)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = if weapon == "Missile" then UDim2.fromOffset(6, 14) else UDim2.fromOffset(4, 16)
	frame.Rotation = math.deg(math.atan2(vx, vy))
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.ZIndex = 3
	frame.Parent = field
	table.insert(bullets, { Frame = frame, X = x, Y = y, VX = vx, VY = vy, Turn = turn, Weapon = weapon })
end

local function fire()
	spawnBullet(shipX, SHIP_Y - 0.05, 0, BULLET_SPEED, if homing then HOMING_TURN else 0, if homing then Theme.MOOD else Theme.TYPED, nil)
	Sfx.Play("Shot")
	Juice.Pop(ship, 0.08)
end

-- weapon: nil for the ship's own shots (Act 1 sends exactly what it always did).
local function onBulletHit(view: BugView, weapon: string?)
	if view.Bug.Kind == "Boss" then
		Juice.Shake(view.Label, nil)
		Sfx.Play("Splat", 1.5)
	else
		-- Hide at once for snappy feel; the splat and cheer land when the server confirms the kill.
		view.HiddenAt = os.clock()
		view.Label.Visible = false
	end
	RemoteManager.FireServer(RemoteNames.BattleSquash, view.Bug.Id, weapon)
end

-- Backend's beam: a full-height column flash that hits up to BEAM_MAX_HITS live bugs within BEAM_HALF_WIDTH of x.
local function fireBeam(x: number, elapsed: number)
	local beam = Instance.new("Frame")
	beam.AnchorPoint = Vector2.new(0.5, 0)
	beam.Position = UDim2.fromScale(x, 0)
	beam.Size = UDim2.new(BEAM_HALF_WIDTH * 2, 0, WING_Y, 0)
	beam.BackgroundColor3 = Theme.ACCENT
	beam.BackgroundTransparency = 0.15
	beam.BorderSizePixel = 0
	beam.ZIndex = 3
	beam.Parent = field
	local fade = TweenService:Create(beam, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 2, WING_Y, 0),
		BackgroundTransparency = 1,
	})
	fade.Completed:Once(function()
		beam:Destroy()
	end)
	fade:Play()
	Sfx.Play("BossHit", 1.6)

	local hits = 0
	for _, view in liveTargets(elapsed) do
		local bx, by = BattleState.BugPosition(view.Bug, elapsed)
		if math.abs(bx - x) <= BEAM_HALF_WIDTH and by < WING_Y then
			Juice.Spark(field, UDim2.fromScale(bx, by), Theme.ACCENT)
			onBulletHit(view, "Beam")
			hits += 1
			if hits >= BEAM_MAX_HITS then
				break
			end
		end
	end
end

local function wingFire(wing: Wingman, x: number, elapsed: number)
	Juice.Pop(wing.Label, 0.15)
	if wing.Weapon == "Spread" then
		for _, degrees in { -SPREAD_DEGREES, 0, SPREAD_DEGREES } do
			local angle = math.rad(degrees)
			spawnBullet(x, WING_Y - 0.04, BULLET_SPEED * math.sin(angle), BULLET_SPEED * math.cos(angle), 0, Theme.TYPED, "Spread")
		end
		Sfx.Play("Shot", 1.25)
	elseif wing.Weapon == "Missile" then
		spawnBullet(x, WING_Y - 0.04, 0, BULLET_SPEED * 0.8, MISSILE_TURN, LAG_COLOR, "Missile")
		Sfx.Play("Shot", 0.75)
	elseif wing.Weapon == "Beam" then
		fireBeam(x, elapsed)
	end
end

-- Boss volleys fly their shared straight paths. Bullets fired after the boss died never existed.
local function stepBossBullets(elapsed: number)
	local volleyFired = false
	for _, view in bossBullets do
		local def = view.Def
		local x, y = BattleState.BulletPosition(def, volleySpeed, elapsed)
		local died = bossDiedAt
		local hidden = view.Done
			or elapsed < def.FiredAt
			or (died ~= nil and def.FiredAt > died)
			or y > 1.05
			or x < -0.05
			or x > 1.05
		if not hidden and y >= SHIP_Y and math.abs(x - shipX) <= volleyHitRadius then
			view.Done = true -- it reached the ship: the server judges it, the hit flash follows its mood drop
			hidden = true
		end
		view.Frame.Visible = not hidden
		if not hidden then
			view.Frame.Position = UDim2.fromScale(x, y)
			if not view.Shown then
				view.Shown = true
				volleyFired = true
				Juice.PopIn(view.Frame)
			end
		end
	end
	if volleyFired then
		Sfx.Play("Shot", 0.55)
	end
end

local function stepSquad(elapsed: number)
	local now = os.clock()
	if now >= nextShipSendAt then
		nextShipSendAt = now + SHIP_SEND_INTERVAL
		RemoteManager.FireServer(RemoteNames.BattleShip, shipX)
	end
	if hasWingShield then
		local ready = elapsed >= wingShieldReadyAt
		shieldStroke.Transparency = if ready then 0 else 0.75
		shieldBubble.BackgroundTransparency = if ready then 0.8 else 0.96
	end
	for _, wing in wingmen do
		local x = math.clamp(shipX + wing.Offset, 0.02, 0.98)
		wing.Label.Position = UDim2.fromScale(x, WING_Y)
		if wing.Weapon and elapsed >= wing.NextAt then
			wing.NextAt = elapsed + wing.Interval
			wingFire(wing, x, elapsed)
		end
	end
	stepBossBullets(elapsed)
end

local function step(deltaTime: number)
	local elapsed = serverElapsed()
	announceWave(elapsed)

	-- Ship: keys or stick slide it; a drag or mouse hold pulls it toward the pointer.
	local axis = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.Left) or UserInputService:IsKeyDown(Enum.KeyCode.A) then
		axis -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.Right) or UserInputService:IsKeyDown(Enum.KeyCode.D) then
		axis += 1
	end
	-- A lag spike on the ship (server SlowUntil) halves its speed and tints it.
	local speedScale = if squadOn and elapsed < slowUntil then SLOW_SPEED_SCALE else 1
	if axis ~= 0 then
		dragTarget = nil
		shipX += axis * SHIP_KEY_SPEED * speedScale * deltaTime
	elseif dragTarget then
		local target = dragTarget :: number
		local maxMove = SHIP_DRAG_SPEED * speedScale * deltaTime
		shipX += math.clamp(target - shipX, -maxMove, maxMove)
	end
	shipX = math.clamp(shipX, 0.04, 0.96)
	ship.Position = UDim2.fromScale(shipX, SHIP_Y)
	ship.Rotation = axis * 8
	ship.BackgroundTransparency = if speedScale < 1 then 0.45 else 1

	-- Auto-fire at the loadout's rate.
	if elapsed >= nextShotAt then
		nextShotAt = elapsed + fireInterval
		fire()
	end

	-- Bugs: fly their shared paths; divers glow red as they come down.
	for _, view in bugs do
		local bug = view.Bug
		if view.HiddenAt and os.clock() - (view.HiddenAt :: number) > PREDICTION_TIMEOUT and view.State == "Pending" then
			view.HiddenAt = nil -- the server didn't accept that hit: bring the bug back
		end
		local visible = view.State == "Pending" and not view.HiddenAt and elapsed >= bug.SpawnAt
		view.Label.Visible = visible
		if visible then
			if not view.Shown then
				view.Shown = true
				Juice.PopIn(view.Label)
			end
			local x, y = BattleState.BugPosition(bug, elapsed)
			view.Label.Position = UDim2.fromScale(x, y)
			local diving = elapsed >= bug.DiveAt
			local flash = diving and math.sin(elapsed * 14) > 0
			if bug.Kind ~= "Boss" then
				view.Label.Rotation = if diving then math.sin(elapsed * 18) * 15 else math.sin(elapsed * 4 + bug.Id) * 6
			end
			if bug.Kind == "Minion" then
				view.Label.TextColor3 = if flash then Theme.BUG else Color3.new(1, 1, 1)
			elseif bug.Kind == "Crash" then
				-- the error window flashes red as it dives
				view.Label.BackgroundColor3 = if flash then Theme.BUG else Theme.PANEL
				view.Label.TextColor3 = if flash then Color3.new(1, 1, 1) else Theme.BUG
			elseif bug.Kind == "Lag" then
				-- glitch flicker
				view.Label.TextTransparency = if diving and math.sin(elapsed * 31 + bug.Id) > 0.5 then 0.6 else 0
			end
		end
	end

	if squadOn then
		stepSquad(elapsed)
	end

	-- Bullets: fly up, optionally steer toward the nearest bug, and hit what they touch.
	local targets = liveTargets(elapsed)
	local index = 1
	while index <= #bullets do
		local bullet = bullets[index]
		bullet.Y -= bullet.VY * deltaTime
		bullet.X += bullet.VX * deltaTime
		if bullet.Turn > 0 and #targets > 0 then
			local best, bestDistance = nil, math.huge
			for _, view in targets do
				local x, y = BattleState.BugPosition(view.Bug, elapsed)
				if y < bullet.Y then
					local distance = math.abs(x - bullet.X) + (bullet.Y - y) * 0.3
					if distance < bestDistance then
						best, bestDistance = x, distance
					end
				end
			end
			if best then
				bullet.X += math.clamp(best - bullet.X, -bullet.Turn * deltaTime, bullet.Turn * deltaTime)
			end
		end
		bullet.Frame.Position = UDim2.fromScale(bullet.X, bullet.Y)

		local hit: BugView? = nil
		local point = fieldPoint(bullet.X, bullet.Y)
		for _, view in targets do
			local x, y = BattleState.BugPosition(view.Bug, elapsed)
			local delta = point - fieldPoint(x, y)
			local box = if view.Bug.Kind == "Boss" then BOSS_HIT_PX else Vector2.new(MINION_HIT_PX, MINION_HIT_PX)
			if math.abs(delta.X) <= box.X and math.abs(delta.Y) <= box.Y then
				hit = view
				break
			end
		end

		if hit or bullet.Y < -0.05 or bullet.X < -0.05 or bullet.X > 1.05 then
			bullet.Frame:Destroy()
			table.remove(bullets, index)
			if hit then
				onBulletHit(hit, bullet.Weapon)
				if hit.Bug.Kind ~= "Boss" then
					targets = liveTargets(elapsed)
				end
			end
		else
			index += 1
		end
	end
end

local function makeBug(info: any): BugView
	local bug: BattleState.Bug = {
		Id = tonumber(info.Id) or 0,
		Kind = if info.Kind == "Boss"
			then "Boss"
			elseif info.Kind == "Crash" then "Crash"
			elseif info.Kind == "Lag" then "Lag"
			elseif info.Kind == "Shard" then "Shard"
			else "Minion",
		Wave = tonumber(info.Wave) or 1,
		Side = tonumber(info.Side) or 1,
		SpawnAt = tonumber(info.SpawnAt) or 0,
		EntryTime = tonumber(info.EntryTime) or 1,
		SpawnX = tonumber(info.SpawnX) or 0.5,
		FormX = tonumber(info.FormX) or 0.5,
		FormY = tonumber(info.FormY) or 0.2,
		DiveAt = tonumber(info.DiveAt) or 0,
		DiveX = tonumber(info.DiveX) or 0.5,
		ReachAt = tonumber(info.ReachAt) or 0,
		Hp = tonumber(info.Hp) or 1,
		State = "Pending",
	}
	local isBoss = bug.Kind == "Boss"
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = if isBoss then UDim2.fromOffset(150, 70) else UDim2.fromOffset(36, 36)
	label.Font = Theme.FONT
	label.TextSize = if isBoss then 54 else 30
	label.Text = if isBoss then "👾" else (if bug.Id % 3 == 0 then "🪲" else "🐛")
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Visible = false
	label.ZIndex = if isBoss then 4 else 2
	if bug.Kind == "Crash" then
		-- a crash report: a little red "!" error window
		label.Text = "!"
		label.Font = Enum.Font.GothamBlack
		label.TextSize = 22
		label.TextColor3 = Theme.BUG
		label.Size = UDim2.fromOffset(34, 28)
		label.BackgroundColor3 = Theme.PANEL
		label.BackgroundTransparency = 0.1
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = label
		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.BUG
		stroke.Thickness = 2
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = label
		local titleBar = Instance.new("Frame")
		titleBar.Size = UDim2.new(1, 0, 0, 5)
		titleBar.BackgroundColor3 = Theme.BUG
		titleBar.BorderSizePixel = 0
		titleBar.Parent = label
	elseif bug.Kind == "Lag" then
		-- a lag spike: a purple spike pointing at the ship
		label.Text = "▼"
		label.TextSize = 32
		label.TextColor3 = LAG_COLOR
		label.TextStrokeColor3 = Theme.ACCENT
		label.TextStrokeTransparency = 0.3
	elseif bug.Kind == "Shard" then
		-- half of a split crash report
		label.Text = "◆"
		label.TextSize = 16
		label.TextColor3 = Theme.BUG
		label.Size = UDim2.fromOffset(22, 22)
	end
	label.Parent = field

	local hpFill: Frame? = nil
	if isBoss then
		local back = Instance.new("Frame")
		back.AnchorPoint = Vector2.new(0.5, 0)
		back.Position = UDim2.new(0.5, 0, 1, 2)
		back.Size = UDim2.fromOffset(130, 8)
		back.BackgroundColor3 = Theme.PANEL
		back.BorderSizePixel = 0
		back.Parent = label
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = Theme.BUG
		fill.BorderSizePixel = 0
		fill.Parent = back
		hpFill = fill
		local name = Theme.Text(label, tostring(info.BossName or "MEMORY LEAK"), 13, Theme.BUG)
		name.AutomaticSize = Enum.AutomaticSize.None
		name.AnchorPoint = Vector2.new(0.5, 1)
		name.Position = UDim2.new(0.5, 0, 0, 0)
		name.Size = UDim2.fromOffset(260, 16)
		name.TextXAlignment = Enum.TextXAlignment.Center
	end

	return { Bug = bug, Label = label, HpFill = hpFill, MaxHp = bug.Hp, State = "Pending", Shown = false, HiddenAt = nil }
end

local function showLoadout(loadout: any)
	local shield = tonumber(loadout.Shield) or 0
	fireInterval = math.max(tonumber(loadout.FireInterval) or 0.32, 0.1)
	homing = loadout.Homing == true
	local parts = {
		`🛡 Shield {shield}`,
		string.format("🔥 Fire %.2fs", fireInterval),
		`⏪ Rollback {if loadout.Rollback then "✓" else "✗"}`,
		`🎯 Homing {if homing then "✓" else "✗"}`,
	}
	loadoutLabel.Text = "LOADOUT  " .. table.concat(parts, "   ")
	Juice.Pop(loadoutLabel, 0.3)
	lastShield = shield
	shieldLabel.Text = if shield > 0 then `🛡x{shield}` else ""
end

-- Act 2: wingmen in their slots, the Database shield bubble, and the boss's volley bullets.
local function setupSquad(squad: any, bulletInfos: any)
	local rules = squad.Rules
	volleySpeed = tonumber(rules.BulletSpeed) or 0.35
	volleyHitRadius = tonumber(rules.HitRadius) or 0.035
	local roles = if type(squad.Wingmen) == "table" then squad.Wingmen else {}
	local weapons = if type(rules.Weapons) == "table" then rules.Weapons else {}
	for index, role in roles do
		local offset = WING_OFFSETS[index]
		if type(role) ~= "string" or not offset then
			continue
		end
		if role == rules.ShieldRole then
			hasWingShield = true
		end
		local weapon: string? = nil
		local interval = 1
		for name, def in weapons do
			if type(def) == "table" and def.Role == role then
				weapon = tostring(name)
				interval = math.max(tonumber(def.Interval) or 1, 0.1)
			end
		end
		local label = Theme.Text(field, "▲", 22, ROLE_COLORS[role] or Theme.TEXT)
		label.AutomaticSize = Enum.AutomaticSize.None
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Size = UDim2.fromOffset(24, 24)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextStrokeTransparency = 0.5
		label.ZIndex = 5
		label.Position = UDim2.fromScale(math.clamp(shipX + offset, 0.02, 0.98), WING_Y)
		Juice.PopIn(label)
		-- the first volley waits one interval, matching the server's shot budget
		table.insert(wingmen, { Label = label, Offset = offset, Weapon = weapon, Interval = interval, NextAt = interval })
	end
	shieldBubble.Visible = hasWingShield

	if type(bulletInfos) ~= "table" then
		return
	end
	for _, bulletInfo in bulletInfos do
		if type(bulletInfo) ~= "table" then
			continue
		end
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Size = UDim2.fromOffset(12, 12)
		frame.BackgroundColor3 = Theme.BUG
		frame.BorderSizePixel = 0
		frame.Visible = false
		frame.ZIndex = 4
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = frame
		local glow = Instance.new("UIStroke")
		glow.Color = Theme.MOOD
		glow.Thickness = 2
		glow.Parent = frame
		frame.Parent = field
		table.insert(bossBullets, {
			Def = {
				Id = tonumber(bulletInfo.Id) or 0,
				FiredAt = tonumber(bulletInfo.FiredAt) or 0,
				OriginX = tonumber(bulletInfo.OriginX) or 0.5,
				OriginY = tonumber(bulletInfo.OriginY) or 0,
				DirX = tonumber(bulletInfo.DirX) or 0,
				DirY = tonumber(bulletInfo.DirY) or 1,
				State = "Live",
			},
			Frame = frame,
			Shown = false,
			Done = false,
		})
	end
end

local function onStarted(info: any)
	if type(info) ~= "table" or type(info.Bugs) ~= "table" then
		return
	end
	clearBattle()
	maxProgress = 0
	slowUntil = 0
	bossDiedAt = nil
	wingShieldReadyAt = 0
	lastBulletHits = 0
	nextShipSendAt = 0
	serverStart = tonumber(info.ServerStart) or Workspace:GetServerTimeNow()
	waveCount = tonumber(info.WaveCount) or 2
	announcedWave = 0
	clientName.Text = tostring(info.ClientName)
	lastMoodBand = ""
	faceToken += 1
	lastSquashLine = 0
	rollbackShown = false
	for _, child in bubbleStack:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	lastMood = tonumber(info.Mood) or 70
	setMood(lastMood)
	clientSay("Okay, show me what you've got!", true)
	comboLabel.Text = "x0"
	lastCombo = 0
	waveLabel.Text = "GET READY"
	progressFill.Size = UDim2.fromScale(0, 1)
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	instructionLabel.Text = if touch then INSTRUCTION_TOUCH else INSTRUCTION_KEYBOARD
	showLoadout(if type(info.Loadout) == "table" then info.Loadout else {})

	for _, bugInfo in info.Bugs do
		if type(bugInfo) == "table" then
			bugInfo.BossName = info.BossName
			table.insert(bugs, makeBug(bugInfo))
		end
	end
	shipX = 0.5
	nextShotAt = 0
	local squad = info.Squad
	if type(squad) == "table" and type(squad.Rules) == "table" then
		squadOn = true
		instructionLabel.Text ..= INSTRUCTION_SQUAD
		setupSquad(squad, info.Bullets)
	end

	-- Drag (touch) or hold the mouse to pull the ship toward the pointer; the thumbstick works like keys.
	local function pointerTarget(position: Vector3)
		local left = field.AbsolutePosition.X
		dragTarget = math.clamp((position.X - left) / math.max(field.AbsoluteSize.X, 1), 0, 1)
	end
	table.insert(inputConnections, UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			pointerTarget(input.Position)
		end
	end))
	table.insert(inputConnections, UserInputService.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			pointerTarget(input.Position)
		elseif input.UserInputType == Enum.UserInputType.MouseMovement and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
			pointerTarget(input.Position)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick1 and math.abs(input.Position.X) > 0.2 then
			dragTarget = math.clamp(shipX + input.Position.X * 0.15, 0, 1)
		end
	end))

	renderConnection = RunService.RenderStepped:Connect(step)
	Music.Play("Battle", 0.8)
	gui.Enabled = true
end

local function celebrateCombo(combo: number)
	-- The multiplier grows and heats up the longer the streak runs.
	Juice.Pop(comboLabel, 0.25 + math.min(combo, 20) * 0.02)
	comboLabel.TextColor3 = if combo >= 10 then Theme.TYPED elseif combo >= 5 then Theme.MOOD else Theme.ACCENT
	local callout = COMBO_CALLOUTS[combo]
	if callout then
		if combo >= 5 then
			cheerFrom("Combo")
		end
		Sfx.Play("ComboCallout")
		Juice.Banner(root, callout, if combo >= 10 then Theme.TYPED else Theme.ACCENT, if combo >= 10 then 54 else 46)
		for _ = 1, 6 do
			Juice.Spark(comboLabel, UDim2.fromScale(math.random(), 0.5), Theme.ACCENT)
		end
	end
end

local function onBugSquashed(view: BugView)
	local now = os.clock()
	if now - lastSquashLine >= SQUASH_LINE_COOLDOWN then
		lastSquashLine = now
		cheerFrom("Squash")
	end
	Sfx.Play("Splat")
	local x, y = BattleState.BugPosition(view.Bug, serverElapsed())
	local at = UDim2.fromScale(x, y)
	Juice.Splat(field, at)
	if math.random() < PRAISE_CHANCE then
		Juice.FloatText(field, at + UDim2.fromOffset(0, -30), PRAISE[math.random(1, #PRAISE)], Theme.TYPED)
	end
end

local function onBossHit(view: BugView, newHp: number)
	view.Bug.Hp = newHp
	local fill = view.HpFill
	if fill then
		TweenService:Create(fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(newHp / math.max(view.MaxHp, 1), 1) }):Play()
	end
	-- Not every bullet needs a cheer: speak on every few hits.
	if (view.MaxHp - newHp) % 4 == 1 then
		cheerFrom("BossHit")
	end
	Sfx.Play("BossHit")
	Juice.FloatText(field, view.Label.Position + UDim2.fromOffset(math.random(-40, 40), -50), "CRACK!", Theme.MOOD)
	for _ = 1, 3 do
		Juice.Spark(field, view.Label.Position, Theme.MOOD)
	end
end

-- Act 2 moments: a lag spike slowing the ship, the Database shield eating a hit, boss bullets landing.
local function onSquadUpdate(snapshot: any, moodDropped: boolean)
	local shipAt = UDim2.fromScale(shipX, SHIP_Y - 0.1)
	local slow = tonumber(snapshot.SlowUntil) or 0
	if slow > slowUntil and slow > serverElapsed() then
		Sfx.Play("KeyWrong")
		Juice.FloatText(field, shipAt, "LAG!", LAG_COLOR)
		Juice.Shake(ship, nil)
	end
	slowUntil = slow

	local shieldAt = tonumber(snapshot.WingShieldReadyAt) or 0
	if shieldAt > wingShieldReadyAt then
		Sfx.Play("PromptClean")
		Juice.FloatText(field, shipAt + UDim2.fromOffset(0, -24), "SHIELD!", Theme.TYPED)
		Juice.Pop(shieldBubble, 0.5)
	end
	wingShieldReadyAt = shieldAt

	local died = tonumber(snapshot.BossDiedAt)
	if died then
		bossDiedAt = died
	end

	local hits = tonumber(snapshot.BulletHits) or 0
	if hits > lastBulletHits and moodDropped then
		Sfx.Play("BugGotThrough")
		Juice.Shake(root, rootFlash)
		Juice.Pop(ship, 0.5)
		Juice.FloatText(field, shipAt, "HIT!", Theme.BUG)
	end
	lastBulletHits = hits
end

local function onUpdate(snapshot: any)
	if type(snapshot) ~= "table" or not renderConnection then
		return
	end
	-- Shards born from a crash report kill arrive with the update that confirms the kill.
	if type(snapshot.Spawned) == "table" then
		for _, bugInfo in snapshot.Spawned do
			if type(bugInfo) == "table" then
				table.insert(bugs, makeBug(bugInfo))
			end
		end
	end
	local mood = tonumber(snapshot.Mood) or 0
	local moodDropped = mood < lastMood
	lastMood = mood
	setMood(mood)
	maxProgress = math.max(maxProgress, math.clamp(tonumber(snapshot.Progress) or 0, 0, 1))
	progressFill.Size = UDim2.fromScale(maxProgress, 1)
	if squadOn then
		onSquadUpdate(snapshot, moodDropped)
	end

	local combo = tonumber(snapshot.Combo) or 0
	comboLabel.Text = `x{combo}`
	if combo > lastCombo then
		celebrateCombo(combo)
	elseif combo == 0 and lastCombo > 0 then
		comboLabel.TextColor3 = Theme.ACCENT
		Juice.Shake(comboLabel, nil)
	end
	lastCombo = combo

	-- Loadout moments: the shield eating a hit, and the one-time rollback save.
	local shield = tonumber(snapshot.Shield) or 0
	if shield < lastShield then
		Sfx.Play("PromptClean")
		Juice.FloatText(field, UDim2.fromScale(shipX, SHIP_Y - 0.1), "SHIELD!", Theme.TYPED)
		Juice.Pop(ship, 0.5)
	end
	lastShield = shield
	shieldLabel.Text = if shield > 0 then `🛡x{shield}` else ""
	if snapshot.RollbackUsed == true and not rollbackShown then
		rollbackShown = true
		Sfx.Play("ComboCallout")
		Juice.Banner(root, "⏪ ROLLBACK! Mood restored", Theme.MOOD, 40)
	end

	local bossHp = tonumber(snapshot.BossHp)
	for _, view in bugs do
		if view.Bug.Kind == "Boss" and bossHp and bossHp < view.Bug.Hp and bossHp > 0 then
			onBossHit(view, bossHp)
		end
	end

	if type(snapshot.BugStates) ~= "table" then
		return
	end
	for _, view in bugs do
		local state = snapshot.BugStates[view.Bug.Id]
		if type(state) ~= "string" or view.State ~= "Pending" or state == "Pending" then
			continue
		end
		if state == "Squashed" then
			if view.Bug.Kind == "Boss" then
				-- Peak moment: the boss breaks.
				view.Bug.Hp = 0
				local at = view.Label.Position
				Juice.Splat(field, at)
				Juice.Splat(field, at + UDim2.fromOffset(60, 0))
				Juice.Splat(field, at + UDim2.fromOffset(-60, 0))
				Juice.Banner(root, "BOSS DOWN!", Theme.TYPED, 58)
				cheerFrom("BossDown")
				rootFlash.BackgroundColor3 = Theme.TYPED
				rootFlash.BackgroundTransparency = 0.6
				Sfx.Play("BossDown")
				Sfx.Play("BossHit")
				task.delay(0.15, function()
					rootFlash.BackgroundTransparency = 1
				end)
			else
				onBugSquashed(view)
			end
		elseif state == "Hit" and (view.Bug.Kind ~= "Lag" or moodDropped) then
			-- Contact: a bug got through. Shake the whole screen and flash it red.
			-- (A lag spike that slowed the ship instead already showed LAG!.)
			Sfx.Play("BugGotThrough")
			Juice.Shake(root, rootFlash)
			Juice.FloatText(moodFill, UDim2.fromScale(0.5, -1.5), "OUCH", Theme.BUG)
		end
		view.State = state
		view.Label.Visible = false
	end
end

local function onEnded(result: any, payout: any, grade: any)
	clearBattle()
	Music.Stop(2)
	local shipped = type(result) == "table" and result.Status == "Shipped"
	if shipped then
		Sfx.Play("Shipped")
		Juice.Banner(root, "SHIPPED!", Theme.TYPED, 64)
		for _ = 1, 16 do
			Juice.Spark(root, UDim2.fromScale(math.random(), math.random() * 0.6 + 0.2), Theme.TYPED)
		end
	else
		Juice.Banner(root, "LAUNCH FAILED", Theme.BUG, 56)
	end

	local stats = if type(result) == "table" then result else {}
	task.delay(RESULTS_DELAY, function()
		if not renderConnection then
			gui.Enabled = false
		end
		ResultsScreen.Show({
			Shipped = shipped,
			Payout = tonumber(payout) or 0,
			Successes = tonumber(stats.Successes) or 0,
			Mistakes = tonumber(stats.Mistakes) or 0,
			MaxCombo = tonumber(stats.MaxCombo) or 0,
			Grade = if type(grade) == "string" then grade else "C",
		})
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

	root = Theme.Panel(gui, UDim2.fromScale(0.9, 0.82), UDim2.fromScale(0.5, 0.5))
	root.AnchorPoint = Vector2.new(0.5, 0.5)

	rootFlash = Instance.new("Frame")
	rootFlash.Size = UDim2.fromScale(1, 1)
	rootFlash.BackgroundTransparency = 1
	rootFlash.BorderSizePixel = 0
	rootFlash.ZIndex = 8
	rootFlash.Parent = root

	Sfx.Preload()
	Music.Preload()

	-- Left: the client on a live call.
	local left = Instance.new("Frame")
	left.BackgroundTransparency = 1
	left.Size = UDim2.fromScale(0.26, 1)
	left.Parent = root
	Theme.List(left, 8)
	face = Theme.Text(left, "😐", 48)
	face.LayoutOrder = 1
	clientName = Theme.Text(left, "", 16)
	clientName.LayoutOrder = 2
	Theme.Text(left, "ON CALL · LIVE DEMO", 12, Theme.MUTED).LayoutOrder = 3
	bubbleStack = Instance.new("Frame")
	bubbleStack.BackgroundTransparency = 1
	bubbleStack.Size = UDim2.new(1, 0, 0, 0)
	bubbleStack.AutomaticSize = Enum.AutomaticSize.Y
	bubbleStack.LayoutOrder = 7
	bubbleStack.Parent = left
	Theme.List(bubbleStack, 6)
	Theme.Text(left, "CLIENT MOOD", 12, Theme.MUTED).LayoutOrder = 5
	moodFill = bar(left, Theme.MOOD, 6)

	-- Centre: instruction, wave, ship progress, loadout, combo and the playfield.
	local centre = Instance.new("Frame")
	centre.BackgroundTransparency = 1
	centre.Position = UDim2.fromScale(0.28, 0)
	centre.Size = UDim2.fromScale(0.72, 1)
	centre.Parent = root

	local top = Instance.new("Frame")
	top.BackgroundTransparency = 1
	top.Size = UDim2.new(1, 0, 0, 104)
	top.Parent = centre
	Theme.List(top, 4)
	instructionLabel = Theme.Text(top, INSTRUCTION_KEYBOARD, 14, Theme.MOOD)
	instructionLabel.LayoutOrder = 0
	waveLabel = Theme.Text(top, "GET READY", 16, Theme.ACCENT)
	waveLabel.LayoutOrder = 1
	Theme.Text(top, "SHIP PROGRESS", 12, Theme.MUTED).LayoutOrder = 2
	progressFill = bar(top, Theme.TYPED, 3)
	loadoutLabel = Theme.Text(top, "", 13, Theme.TYPED)
	loadoutLabel.LayoutOrder = 4

	comboLabel = Theme.Text(centre, "x0", 40, Theme.ACCENT)
	comboLabel.Font = Enum.Font.GothamBlack
	comboLabel.AnchorPoint = Vector2.new(1, 0)
	comboLabel.Position = UDim2.new(1, 0, 0, 104)
	comboLabel.Size = UDim2.fromOffset(160, 44)
	comboLabel.AutomaticSize = Enum.AutomaticSize.None
	comboLabel.TextXAlignment = Enum.TextXAlignment.Right

	-- Playfield: bugs fly here; YOUR CODE runs along the bottom edge and the ship guards it.
	field = Instance.new("Frame")
	field.BackgroundColor3 = Theme.BACKGROUND
	field.BackgroundTransparency = 0.4
	field.ClipsDescendants = true
	field.Position = UDim2.fromOffset(0, 150)
	field.Size = UDim2.new(1, 0, 1, -150)
	field.Parent = centre
	local fieldCorner = Instance.new("UICorner")
	fieldCorner.CornerRadius = UDim.new(0, 8)
	fieldCorner.Parent = field

	local codeLine = Instance.new("Frame")
	codeLine.AnchorPoint = Vector2.new(0, 1)
	codeLine.Position = UDim2.fromScale(0, 1)
	codeLine.Size = UDim2.new(1, 0, 0, 4)
	codeLine.BackgroundColor3 = Theme.ACCENT
	codeLine.BackgroundTransparency = 0.3
	codeLine.BorderSizePixel = 0
	codeLine.Parent = field
	local codeLabel = Theme.Text(field, "▲ YOUR CODE ▲", 12, Theme.ACCENT)
	codeLabel.AnchorPoint = Vector2.new(0.5, 1)
	codeLabel.Position = UDim2.new(0.5, 0, 1, -6)
	codeLabel.Size = UDim2.fromOffset(140, 16)
	codeLabel.AutomaticSize = Enum.AutomaticSize.None
	codeLabel.TextXAlignment = Enum.TextXAlignment.Center

	ship = Theme.Text(field, "🚀", 34)
	ship.AutomaticSize = Enum.AutomaticSize.None
	ship.AnchorPoint = Vector2.new(0.5, 0.5)
	ship.Size = UDim2.fromOffset(40, 40)
	ship.TextXAlignment = Enum.TextXAlignment.Center
	ship.ZIndex = 5
	ship.Position = UDim2.fromScale(0.5, SHIP_Y)
	ship.BackgroundColor3 = LAG_COLOR -- shown only while a lag spike slows the ship
	local shipCorner = Instance.new("UICorner")
	shipCorner.CornerRadius = UDim.new(0.5, 0)
	shipCorner.Parent = ship
	-- Act 2 Database wingman: a bubble around the ship, bright when ready, dim while recharging.
	shieldBubble = Instance.new("Frame")
	shieldBubble.AnchorPoint = Vector2.new(0.5, 0.5)
	shieldBubble.Position = UDim2.fromScale(0.5, 0.5)
	shieldBubble.Size = UDim2.fromOffset(60, 60)
	shieldBubble.BackgroundColor3 = Theme.TYPED
	shieldBubble.BackgroundTransparency = 0.8
	shieldBubble.Visible = false
	shieldBubble.ZIndex = 4
	shieldBubble.Parent = ship
	local bubbleCorner = Instance.new("UICorner")
	bubbleCorner.CornerRadius = UDim.new(0.5, 0)
	bubbleCorner.Parent = shieldBubble
	shieldStroke = Instance.new("UIStroke")
	shieldStroke.Color = Theme.TYPED
	shieldStroke.Thickness = 2
	shieldStroke.Parent = shieldBubble
	shieldLabel = Theme.Text(ship, "", 13, Theme.TYPED)
	shieldLabel.AutomaticSize = Enum.AutomaticSize.None
	shieldLabel.AnchorPoint = Vector2.new(0.5, 0)
	shieldLabel.Position = UDim2.new(0.5, 0, 1, -2)
	shieldLabel.Size = UDim2.fromOffset(60, 16)
	shieldLabel.TextXAlignment = Enum.TextXAlignment.Center

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function BattleController.Start()
	RemoteManager.GetRemote(RemoteNames.BattleStarted).OnClientEvent:Connect(onStarted)
	RemoteManager.GetRemote(RemoteNames.BattleUpdate).OnClientEvent:Connect(onUpdate)
	RemoteManager.GetRemote(RemoteNames.BattleEnded).OnClientEvent:Connect(onEnded)
end

return BattleController
