--!strict
-- Act 3 deploy battle screen: a bullet hell (BulletHell.luau). The server sends a seed and the battle options; this
-- screen rebuilds the same schedule with BulletHell.New(0, ...) and draws it on the shared server clock, so no bullet
-- list is ever sent. BattleUpdate is the truth for lives, grazes, combo, boss HP and kills; each kill carries its
-- server time, so BulletHell.Fired hides exactly the bullets the server stopped judging.
-- The field is square, so the simulation's 0-1 units match on both axes and the tiny hitbox is a true circle.
-- Ship: WASD / arrows / stick, or drag anywhere (on touch the ship rides above the finger). Focus (Shift, the left
-- trigger or the on-screen button) slows it to 40% and shows the hitbox. The ship streams its position at 10 Hz.
-- Acts 1-2 stay on BattleController.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BulletHell = require(Shared:WaitForChild("BulletHell"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Juice = require(UI:WaitForChild("Juice"))
local Music = require(UI:WaitForChild("Music"))
local ResultsScreen = require(UI:WaitForChild("ResultsScreen"))
local Sfx = require(UI:WaitForChild("Sfx"))
local Theme = require(UI:WaitForChild("Theme"))

type EnemyView = {
	Enemy: BulletHell.Enemy, -- the local battle's copy; KilledAt / ActiveFrom / Hp mirror the server's
	Label: TextLabel,
	Shown: boolean,
	HiddenAt: number?, -- a local shot hit it: hidden until the server confirms the kill, or back after a timeout
	X: number, -- this frame's position and whether shots can hit it
	Y: number,
	Targetable: boolean,
}
-- VY: field heights per second upward. Turn: field widths per second it can steer toward an enemy (0 = straight).
type Shot = { Frame: Frame, X: number, Y: number, VX: number, VY: number, Turn: number, Weapon: BulletHell.Weapon }
type Wingman = { Label: TextLabel, Offset: Vector2, Weapon: BulletHell.Weapon?, Interval: number, NextAt: number }
type Slot = { Frame: Frame, Stroke: UIStroke, Look: number } -- Look: 0 unset, 1 popcorn shot, 2 boss shot
type BossLook = { Kind: BulletHell.BossKind, Name: string, Glyph: string, Color: Color3, Size: number, Fill: number }

local CFG = GameConfig.BULLET_HELL
local POOL_SIZE = 400
local SHIP_MIN_X, SHIP_MAX_X = 0.04, 0.96 -- BulletHell's ship x bounds (not exported); y bounds come from CFG
local FOCUS_SCALE = 0.4
local TOUCH_OFFSET_PX = 70 -- the ship rides this far above the finger so the thumb never hides it
local STICK_DEADZONE = 0.2
local SHIP_SEND_INTERVAL = 0.1
local HIT_STOP_SECONDS = 0.08
local RESULTS_DELAY = 1.1
local SHOT_SPEED = 1.6
local HOMING_TURN = 0.9
local MISSILE_TURN = 2.4
local SPREAD_DEGREES = 15
local BEAM_HALF_WIDTH = 0.03
local BEAM_MAX_HITS = 4
local PREDICTION_TIMEOUT = 0.8
local GRAZE_FULL = 40 -- grazes past this no longer raise the score (BulletHell.Score)
local HUD_WIDTH = 150
-- Wingman slots, filled in hire order (the server sends GameConfig.COMPONENTS order), offsets from the ship.
local WING_OFFSETS = { Vector2.new(-0.07, 0.03), Vector2.new(0.07, 0.03), Vector2.new(-0.13, 0.06), Vector2.new(0.13, 0.06) }
local HIT_RADIUS: { [string]: number } = { Popcorn = 0.035, Child = 0.05, Boss = 0.08 } -- for local shot hits
local POPCORN_COLOR = Theme.MOOD
local POPCORN_SIZE = 0.016
local MISSILE_COLOR = Color3.fromHex("b06cff")
local BOSS_LOOKS: { [string]: BossLook } = {
	Hacker = { Kind = "Hacker", Name = "THE HACKER", Glyph = "💀", Color = Color3.fromHex("39ff88"), Size = 0.016, Fill = 0 },
	Naysayer = { Kind = "Naysayer", Name = "THE NAYSAYER", Glyph = "😡", Color = Color3.fromHex("ff6ad5"), Size = 0.026, Fill = 0.55 },
	Swarm = { Kind = "Swarm", Name = "THE SWARM", Glyph = "🦠", Color = Color3.fromHex("ff3b4e"), Size = 0.018, Fill = 0 },
}
local ROLE_COLORS: { [string]: Color3 } = {
	FrontendUnits = Theme.TYPED,
	BackendEndpoints = Theme.ACCENT,
	DatabaseTables = Theme.MOOD,
	PromptTokens = MISSILE_COLOR,
}
local HINT_KEYBOARD = "WASD / arrows to fly. Hold SHIFT to focus. Your squad fires on its own."
local HINT_TOUCH = "Drag anywhere to fly. Tap FOCUS for precision. Your squad fires on its own."
local HINT_GAMEPAD = "Stick to fly. Hold the left trigger to focus. Your squad fires on its own."

local BulletHellController = {}

local gui: ScreenGui
local stage: Frame
local field: Frame
local flash: Frame
local ship: TextLabel
local hitbox: Frame
local clientLabel: TextLabel
local heartsLabel: TextLabel
local grazeFill: Frame
local grazeLabel: TextLabel
local comboLabel: TextLabel
local phaseLabel: TextLabel
local loadoutLabel: TextLabel
local hintLabel: TextLabel
local focusButton: TextButton
local bossBar: Frame
local bossFill: Frame
local bossName: TextLabel

local pool: { Slot } = {}
local poolUsed = 0
local battle: BulletHell.Battle? = nil
local look: BossLook = BOSS_LOOKS.Hacker
local enemyViews: { EnemyView } = {} -- by enemy id (= index)
local shots: { Shot } = {}
local wingmen: { Wingman } = {}
local connections: { RBXScriptConnection } = {}
local serverStart = 0
local drawCursor = 1 -- bullets before this index are gone
local shipX, shipY = 0.5, 0.85
local stick = Vector2.zero
local dragTouch: InputObject? = nil
local mouseDrag = false
local dragTarget: Vector2? = nil
local focusToggle = false
local fireInterval = 0.32
local homing = false
local nextShotAt = 0
local nextSendAt = 0
local hitStopUntil = 0
local announcedPhase = 0
local bossMaxHp = 1
local childMaxHp = 1
local bossDownAt: number? = nil
local invulnUntil = 0
local lastLives = 0
local maxLives = 0
local lastGrazes = 0
local lastCombo = 0
local lastShieldPhase = 0
local savedTouchControls: boolean? = nil

local function serverElapsed(): number
	return Workspace:GetServerTimeNow() - serverStart
end

local function focused(): boolean
	return focusToggle
		or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonL2)
end

local function shipAt(dy: number): UDim2
	return UDim2.fromScale(shipX, shipY + dy)
end

local function refreshHearts()
	heartsLabel.Text = string.rep("♥", math.max(lastLives, 0)) .. string.rep("♡", math.max(maxLives - lastLives, 0))
end

local function refreshFocusButton()
	focusButton.Text = if focusToggle then "FOCUS ON" else "FOCUS"
	focusButton.BackgroundColor3 = if focusToggle then Theme.ACCENT else Theme.PANEL
end

local function refreshHint()
	local preferred = UserInputService.PreferredInput
	hintLabel.Text = if preferred == Enum.PreferredInput.Touch
		then HINT_TOUCH
		elseif preferred == Enum.PreferredInput.Gamepad then HINT_GAMEPAD
		else HINT_KEYBOARD
	focusButton.Visible = preferred == Enum.PreferredInput.Touch
end

local function refreshBossBar()
	local b = battle
	if not b then
		return
	end
	local boss, children = 0, 0
	for _, enemy in b.Enemies do
		if enemy.Kind == "Boss" then
			boss += math.max(enemy.Hp, 0)
		elseif enemy.Kind == "Child" then
			children += math.max(enemy.Hp, 0)
		end
	end
	local ratio = if b.SplitAt then children / childMaxHp else boss / bossMaxHp
	TweenService:Create(bossFill, TweenInfo.new(0.12), { Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1) }):Play()
end

-- Clears the field; the bullet pool stays for the next battle.
local function teardown()
	battle = nil
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, view in enemyViews do
		view.Label:Destroy()
	end
	table.clear(enemyViews)
	for _, shot in shots do
		shot.Frame:Destroy()
	end
	table.clear(shots)
	for _, wing in wingmen do
		wing.Label:Destroy()
	end
	table.clear(wingmen)
	for _, slot in pool do
		slot.Frame.Visible = false
		slot.Look = 0
	end
	poolUsed = 0
	bossBar.Visible = false
	hitbox.Visible = false
	ship.Visible = false
	focusToggle = false
	refreshFocusButton()
	dragTouch = nil
	mouseDrag = false
	dragTarget = nil
	stick = Vector2.zero
	if savedTouchControls ~= nil then
		GuiService.TouchControlsEnabled = savedTouchControls
		savedTouchControls = nil
	end
end

-- Ship movement mirrors the server's limits: never faster than ShipSpeed (Euclidean, so diagonals get no bonus),
-- inside the same box. The server stamps each sample on its own clock and clamps anything faster.
local function moveShip(dt: number)
	local axis = Vector2.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		axis -= Vector2.xAxis
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		axis += Vector2.xAxis
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
		axis -= Vector2.yAxis
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
		axis += Vector2.yAxis
	end
	if axis.Magnitude == 0 and stick.Magnitude > STICK_DEADZONE then
		axis = Vector2.new(stick.X, -stick.Y)
	end
	local isFocused = focused()
	local maxMove = CFG.ShipSpeed * (if isFocused then FOCUS_SCALE else 1) * dt
	local move = Vector2.zero
	if axis.Magnitude > 0 then
		dragTarget = nil
		move = (if axis.Magnitude > 1 then axis.Unit else axis) * maxMove
	elseif dragTarget then
		local delta = (dragTarget :: Vector2) - Vector2.new(shipX, shipY)
		move = if delta.Magnitude > maxMove then delta.Unit * maxMove else delta
	end
	shipX = math.clamp(shipX + move.X, SHIP_MIN_X, SHIP_MAX_X)
	shipY = math.clamp(shipY + move.Y, CFG.ShipMinY, CFG.ShipMaxY)
	ship.Position = shipAt(0)
	ship.Rotation = math.clamp(move.X / math.max(maxMove, 1e-6), -1, 1) * 10
	hitbox.Position = ship.Position
	hitbox.Visible = isFocused
end

local function announce(b: BulletHell.Battle, t: number)
	local index = 0
	for i, phase in b.Phases do
		if t >= phase.StartsAt then
			index = i
		end
	end
	if index <= announcedPhase then
		return
	end
	announcedPhase = index
	local phase = b.Phases[index]
	Sfx.Play("Banner")
	if phase.Kind == "Boss" then
		phaseLabel.Text = look.Name
		Music.Play("Boss", 1.5)
		Juice.Banner(stage, `⚠ {look.Name} ⚠`, look.Color, 48)
		bossBar.Visible = true
		Juice.PopIn(bossBar)
	elseif phase.Kind == "Elite" then
		phaseLabel.Text = "ELITE WAVE"
		Juice.Banner(stage, "⚠ ELITE WAVE ⚠", Theme.BUG)
	else
		phaseLabel.Text = `WAVE {index} / {CFG.WaveCount}`
		Juice.Banner(stage, `WAVE {index}`, Theme.MOOD)
	end
	Juice.Pop(phaseLabel, 0.4)
end

local function drawEnemies(t: number)
	for _, view in enemyViews do
		local enemy = view.Enemy
		if view.HiddenAt and os.clock() - (view.HiddenAt :: number) > PREDICTION_TIMEOUT and not enemy.KilledAt then
			view.HiddenAt = nil -- the server didn't take that hit: bring it back
		end
		local activeFrom = enemy.ActiveFrom
		local alive = activeFrom ~= nil and t >= activeFrom and enemy.KilledAt == nil and t <= enemy.LeaveAt + 1
		local x, y = 0, -1
		if alive then
			x, y = BulletHell.EnemyPosition(enemy, t)
		end
		local visible = alive and not view.HiddenAt and y > -0.08
		view.Label.Visible = visible
		view.X, view.Y = x, y
		-- what the server accepts: on screen for VisibleDelay, not gone, and (a boss) inside the field
		view.Targetable = visible
			and t >= (activeFrom or math.huge) + CFG.VisibleDelay
			and t <= enemy.LeaveAt + CFG.LatencyGrace
			and y >= 0
		if visible then
			view.Label.Position = UDim2.fromScale(x, y)
			if enemy.Kind == "Popcorn" then
				view.Label.Rotation = math.sin(t * 5 + enemy.Id) * 10
			end
			if not view.Shown then
				view.Shown = true
				Juice.PopIn(view.Label)
			end
		end
	end
end

-- Pooled bullet frames: each frame takes the next live bullet (fired by a live, active owner and still in the field).
local function setLook(slot: Slot, kind: number)
	slot.Look = kind
	local size = if kind == 2 then look.Size else POPCORN_SIZE
	local color = if kind == 2 then look.Color else POPCORN_COLOR
	slot.Frame.Size = UDim2.fromScale(size, size)
	slot.Frame.BackgroundColor3 = if kind == 2 and look.Fill > 0 then color else Color3.new(1, 1, 1)
	slot.Frame.BackgroundTransparency = if kind == 2 then look.Fill else 0
	slot.Stroke.Color = color
end

local function drawBullets(b: BulletHell.Battle, t: number)
	local bullets = b.Bullets
	while bullets[drawCursor] and bullets[drawCursor].GoneAt < t do
		drawCursor += 1
	end
	local used = 0
	local down = bossDownAt
	if down == nil or t < down then -- boss down clears the screen
		for i = drawCursor, #bullets do
			local bullet = bullets[i]
			if bullet.FiredAt > t or used >= POOL_SIZE then
				break
			end
			if bullet.GoneAt >= t and BulletHell.Fired(b, bullet) then
				used += 1
				local slot = pool[used]
				local owner = b.Enemies[bullet.Owner]
				local kind = if owner and owner.Kind ~= "Popcorn" then 2 else 1
				if slot.Look ~= kind then
					setLook(slot, kind)
				end
				local x, y = BulletHell.BulletPosition(bullet, t)
				slot.Frame.Position = UDim2.fromScale(x, y)
				slot.Frame.Visible = true
			end
		end
	end
	for i = used + 1, poolUsed do
		pool[i].Frame.Visible = false
	end
	poolUsed = used
end

local function claim(view: EnemyView, weapon: BulletHell.Weapon)
	if view.Enemy.Kind == "Popcorn" then
		view.HiddenAt = os.clock() -- hide at once; the splat lands when the server confirms
		view.Label.Visible = false
		view.Targetable = false
	else
		Juice.Pop(view.Label, 0.12)
	end
	RemoteManager.FireServer(RemoteNames.BattleSquash, view.Enemy.Id, weapon)
end

local function spawnShot(x: number, y: number, vx: number, vy: number, turn: number, color: Color3, weapon: BulletHell.Weapon)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = if weapon == "Missile" then UDim2.fromOffset(6, 14) else UDim2.fromOffset(4, 14)
	frame.Rotation = math.deg(math.atan2(vx, vy))
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = 0.25 -- your shots stay quieter than the bullets you dodge
	frame.BorderSizePixel = 0
	frame.Position = UDim2.fromScale(x, y)
	frame.ZIndex = 3
	frame.Parent = field
	table.insert(shots, { Frame = frame, X = x, Y = y, VX = vx, VY = vy, Turn = turn, Weapon = weapon })
end

-- Backend's beam: a column flash up from the wingman that hits up to BEAM_MAX_HITS enemies within reach of x.
local function fireBeam(x: number, y: number)
	local beam = Instance.new("Frame")
	beam.AnchorPoint = Vector2.new(0.5, 1)
	beam.Position = UDim2.fromScale(x, y)
	beam.Size = UDim2.fromScale(BEAM_HALF_WIDTH * 2, y)
	beam.BackgroundColor3 = Theme.ACCENT
	beam.BackgroundTransparency = 0.3
	beam.BorderSizePixel = 0
	beam.ZIndex = 3
	beam.Parent = field
	local fade = TweenService:Create(beam, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 2, y, 0),
		BackgroundTransparency = 1,
	})
	fade.Completed:Once(function()
		beam:Destroy()
	end)
	fade:Play()
	Sfx.Play("BossHit", 1.6)
	local hits = 0
	for _, view in enemyViews do
		if view.Targetable and view.Y < y and math.abs(view.X - x) <= BEAM_HALF_WIDTH + HIT_RADIUS[view.Enemy.Kind] then
			Juice.Spark(field, UDim2.fromScale(view.X, view.Y), Theme.ACCENT)
			claim(view, "Beam")
			hits += 1
			if hits >= BEAM_MAX_HITS then
				break
			end
		end
	end
end

local function stepWeapons(t: number)
	if t >= nextShotAt then
		nextShotAt = t + fireInterval
		spawnShot(shipX, shipY - 0.04, 0, SHOT_SPEED, if homing then HOMING_TURN else 0, if homing then Theme.MOOD else Theme.TYPED, "Ship")
		Sfx.Play("Shot")
	end
	for _, wing in wingmen do
		local x = math.clamp(shipX + wing.Offset.X, 0.02, 0.98)
		local y = math.clamp(shipY + wing.Offset.Y, 0.02, 0.98)
		wing.Label.Position = UDim2.fromScale(x, y)
		if wing.Weapon and t >= wing.NextAt then
			wing.NextAt = t + wing.Interval
			Juice.Pop(wing.Label, 0.15)
			if wing.Weapon == "Spread" then
				for _, degrees in { -SPREAD_DEGREES, 0, SPREAD_DEGREES } do
					local angle = math.rad(degrees)
					spawnShot(x, y - 0.03, SHOT_SPEED * math.sin(angle), SHOT_SPEED * math.cos(angle), 0, Theme.TYPED, "Spread")
				end
				Sfx.Play("Shot", 1.25)
			elseif wing.Weapon == "Missile" then
				spawnShot(x, y - 0.03, 0, SHOT_SPEED * 0.8, MISSILE_TURN, MISSILE_COLOR, "Missile")
				Sfx.Play("Shot", 0.75)
			else
				fireBeam(x, y)
			end
		end
	end
end

local function stepShots(dt: number)
	local index = 1
	while index <= #shots do
		local shot = shots[index]
		shot.Y -= shot.VY * dt
		shot.X += shot.VX * dt
		if shot.Turn > 0 then
			local best, bestDistance = nil, math.huge
			for _, view in enemyViews do
				if view.Targetable and view.Y < shot.Y then
					local distance = math.abs(view.X - shot.X) + (shot.Y - view.Y) * 0.3
					if distance < bestDistance then
						best, bestDistance = view.X, distance
					end
				end
			end
			if best then
				shot.X += math.clamp(best - shot.X, -shot.Turn * dt, shot.Turn * dt)
			end
		end
		local hit: EnemyView? = nil
		for _, view in enemyViews do
			local radius = HIT_RADIUS[view.Enemy.Kind]
			if view.Targetable and (view.X - shot.X) ^ 2 + (view.Y - shot.Y) ^ 2 <= radius * radius then
				hit = view
				break
			end
		end
		if hit or shot.Y < -0.05 or shot.X < -0.05 or shot.X > 1.05 then
			shot.Frame:Destroy()
			table.remove(shots, index)
			if hit then
				claim(hit, shot.Weapon)
			end
		else
			shot.Frame.Position = UDim2.fromScale(shot.X, shot.Y)
			index += 1
		end
	end
end

local function step(dt: number)
	local b = battle
	if not b or os.clock() < hitStopUntil then
		return -- hit-stop: the whole field freezes for a beat
	end
	local t = serverElapsed()
	moveShip(dt)
	if t >= nextSendAt then
		nextSendAt = math.max(nextSendAt + SHIP_SEND_INTERVAL, t) -- fixed 10 Hz, no catch-up burst after a hitch
		RemoteManager.FireServer(RemoteNames.BattleShip, shipX, shipY)
	end
	announce(b, t)
	drawEnemies(t)
	stepWeapons(t)
	stepShots(dt)
	drawBullets(b, t)
	ship.TextTransparency = if t < invulnUntil and math.floor(t * 12) % 2 == 0 then 0.75 else 0
end

local function enemyLabel(enemy: BulletHell.Enemy): TextLabel
	local label = Theme.Text(field, "", 26)
	label.AutomaticSize = Enum.AutomaticSize.None
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Visible = false
	if enemy.Kind == "Boss" then
		label.Text = look.Glyph
		label.TextSize = 56
		label.Size = UDim2.fromOffset(80, 70)
		label.ZIndex = 3
	elseif enemy.Kind == "Child" then
		label.Text = look.Glyph
		label.TextSize = 34
		label.Size = UDim2.fromOffset(44, 44)
		label.ZIndex = 3
	else
		label.Text = "👾"
		label.Size = UDim2.fromOffset(32, 32)
		label.ZIndex = 2
	end
	return label
end

local function weaponFor(role: string): (BulletHell.Weapon?, number)
	local weapons = CFG.Weapons
	if weapons.Spread.Role == role then
		return "Spread", weapons.Spread.Interval
	elseif weapons.Beam.Role == role then
		return "Beam", weapons.Beam.Interval
	elseif weapons.Missile.Role == role then
		return "Missile", weapons.Missile.Interval
	end
	return nil, 1
end

local function bindInput()
	-- Touch: the first finger down (not on a button) steers; the ship rides above it. Mouse: hold to pull the ship.
	local function setTarget(position: Vector3, offsetPx: number)
		local origin, size = field.AbsolutePosition, field.AbsoluteSize
		dragTarget = Vector2.new(
			(position.X - origin.X) / math.max(size.X, 1),
			(position.Y - offsetPx - origin.Y) / math.max(size.Y, 1)
		)
	end
	table.insert(connections, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch and not dragTouch then
			dragTouch = input
			setTarget(input.Position, TOUCH_OFFSET_PX)
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouseDrag = true
			setTarget(input.Position, 0)
		end
	end))
	table.insert(connections, UserInputService.InputChanged:Connect(function(input: InputObject)
		if input == dragTouch then
			setTarget(input.Position, TOUCH_OFFSET_PX)
		elseif input.UserInputType == Enum.UserInputType.MouseMovement and mouseDrag then
			setTarget(input.Position, 0)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
			stick = Vector2.new(input.Position.X, input.Position.Y)
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input: InputObject)
		if input == dragTouch then
			dragTouch = nil
			dragTarget = nil
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 and mouseDrag then
			mouseDrag = false
			dragTarget = nil
		elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
			stick = Vector2.zero
		end
	end))
	table.insert(connections, UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(refreshHint))
end

local function onStarted(info: any)
	if type(info) ~= "table" or info.Mode ~= "BulletHell" then
		return -- Acts 1-2: BattleController
	end
	local bossLook = BOSS_LOOKS[info.Boss]
	local seed = tonumber(info.Seed)
	local loadout = info.Loadout
	if not bossLook or not seed or type(loadout) ~= "table" then
		return
	end
	teardown()
	look = bossLook
	local roles: { string } = {}
	if type(info.Wingmen) == "table" then
		for _, role in info.Wingmen do
			if type(role) == "string" then
				table.insert(roles, role)
			end
		end
	end
	-- Must match the server's options exactly: boss and child HP scale with the wingmen.
	local options: BulletHell.Options = {
		Boss = bossLook.Kind,
		EliteHalfWaves = tonumber(info.EliteHalfWaves) or 0,
		Loadout = {
			Shield = loadout.Shield == true,
			ExtraLife = loadout.ExtraLife == true,
			Homing = loadout.Homing == true,
			FireInterval = tonumber(loadout.FireInterval) or 0.32,
		},
		Wingmen = roles,
	}
	local b = BulletHell.New(0, seed, options, CFG)
	battle = b
	serverStart = tonumber(info.ServerStart) or Workspace:GetServerTimeNow()

	local start = b.ShipSamples[1]
	shipX, shipY = start.X, start.Y
	fireInterval = math.max(options.Loadout.FireInterval, 0.1)
	homing = options.Loadout.Homing
	nextShotAt, nextSendAt, hitStopUntil = 0, 0, 0
	drawCursor = 1
	announcedPhase = 0
	bossDownAt = nil
	invulnUntil = 0
	lastLives, maxLives = b.Lives, b.MaxLives
	lastGrazes, lastCombo, lastShieldPhase = 0, 0, 0

	bossMaxHp, childMaxHp = 1, 0
	for _, enemy in b.Enemies do
		if enemy.Kind == "Boss" then
			bossMaxHp = math.max(enemy.Hp, 1)
		elseif enemy.Kind == "Child" then
			childMaxHp += enemy.Hp
		end
		enemyViews[enemy.Id] = {
			Enemy = enemy,
			Label = enemyLabel(enemy),
			Shown = false,
			HiddenAt = nil,
			X = 0,
			Y = -1,
			Targetable = false,
		}
	end
	childMaxHp = math.max(childMaxHp, 1)

	for index, role in roles do
		local offset = WING_OFFSETS[index]
		if not offset then
			continue
		end
		local weapon: BulletHell.Weapon?, interval: number = weaponFor(role)
		local label = Theme.Text(field, "▲", 20, ROLE_COLORS[role] or Theme.TEXT)
		label.AutomaticSize = Enum.AutomaticSize.None
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Size = UDim2.fromOffset(22, 22)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextStrokeTransparency = 0.5
		label.ZIndex = 5
		Juice.PopIn(label)
		-- the first volley waits one interval, matching the server's claim budget
		table.insert(wingmen, { Label = label, Offset = offset, Weapon = weapon, Interval = math.max(interval, 0.1), NextAt = interval })
	end

	clientLabel.Text = tostring(info.ClientName or "")
	bossName.Text = look.Name
	bossFill.BackgroundColor3 = look.Color
	bossFill.Size = UDim2.fromScale(1, 1)
	refreshHearts()
	grazeFill.Size = UDim2.fromScale(0, 1)
	grazeLabel.Text = "0"
	comboLabel.Text = "x0"
	comboLabel.TextColor3 = Theme.ACCENT
	phaseLabel.Text = "GET READY"
	local parts = {
		`🛡 Shield {if options.Loadout.Shield then "✓" else "✗"}`,
		string.format("🔥 Fire %.2fs", fireInterval),
		`⏪ Extra life {if options.Loadout.ExtraLife then "✓" else "✗"}`,
		`🎯 Homing {if homing then "✓" else "✗"}`,
	}
	loadoutLabel.Text = table.concat(parts, "\n")
	refreshHint()
	ship.Position = shipAt(0)
	ship.Visible = true

	if savedTouchControls == nil then
		savedTouchControls = GuiService.TouchControlsEnabled
		GuiService.TouchControlsEnabled = false -- drag anywhere: no thumbstick or jump button in the way
	end
	bindInput()
	table.insert(connections, RunService.RenderStepped:Connect(step))
	Music.Play("Battle", 0.8)
	gui.Enabled = true
end

local function onKilled(view: EnemyView)
	view.Label.Visible = false
	if not view.Shown or view.Y < -0.05 then
		return
	end
	local at = UDim2.fromScale(view.X, view.Y)
	if view.Enemy.Kind == "Popcorn" then
		Sfx.Play("Splat")
		Juice.Splat(field, at)
	else
		Sfx.Play("BossHit", 0.8)
		Juice.Splat(field, at)
		Juice.Splat(field, at + UDim2.fromOffset(30, 10))
	end
end

local function onBossDown()
	Juice.Banner(stage, "BOSS DOWN!", Theme.TYPED, 58)
	Sfx.Play("BossDown")
	Sfx.Play("BossHit")
	flash.BackgroundColor3 = Theme.TYPED
	flash.BackgroundTransparency = 0.5
	TweenService:Create(flash, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
	Juice.Shake(stage, nil)
	for _ = 1, 12 do
		Juice.Spark(field, UDim2.fromScale(math.random() * 0.8 + 0.1, math.random() * 0.5 + 0.1), look.Color)
	end
end

local function onHit()
	Sfx.Play("BugGotThrough")
	Juice.Shake(stage, flash)
	Juice.Pop(heartsLabel, 0.5)
	Juice.FloatText(field, shipAt(-0.06), "-1 ♥", Theme.BUG)
	hitStopUntil = os.clock() + HIT_STOP_SECONDS
end

local function onUpdate(update: any)
	local b = battle
	if not b or type(update) ~= "table" then
		return
	end
	-- Kills first: each one stops its enemy's bullets from its kill time on (BulletHell.Fired).
	if type(update.Killed) == "table" then
		for _, kill in update.Killed do
			local view = if type(kill) == "table" then enemyViews[tonumber(kill.Id) or 0] else nil
			local at = if type(kill) == "table" then tonumber(kill.At) else nil
			if view and at and not view.Enemy.KilledAt then
				view.Enemy.KilledAt = at
				onKilled(view)
			end
		end
	end
	local splitAt = tonumber(update.SplitAt)
	if splitAt and not b.SplitAt then
		b.SplitAt = splitAt
		for _, enemy in b.Enemies do
			if enemy.Kind == "Child" then
				enemy.ActiveFrom = splitAt -- the dormant children wake up, and their fans start flying
			end
		end
		Sfx.Play("Banner")
		Juice.Banner(stage, "IT SPLIT!", look.Color, 50)
	end
	if type(update.Bosses) == "table" then
		for _, info in update.Bosses do
			local view = if type(info) == "table" then enemyViews[tonumber(info.Id) or 0] else nil
			local hp = if type(info) == "table" then tonumber(info.Hp) else nil
			if view and hp and hp < view.Enemy.Hp then
				view.Enemy.Hp = hp
				if hp > 0 then
					Sfx.Play("BossHit", 1.1 + math.random() * 0.3)
					Juice.Spark(field, UDim2.fromScale(view.X, view.Y), look.Color)
				end
			end
		end
		refreshBossBar()
	end
	local downAt = tonumber(update.BossDownAt)
	if downAt and not bossDownAt then
		bossDownAt = downAt
		b.BossDownAt = downAt
		onBossDown()
	end

	invulnUntil = tonumber(update.InvulnUntil) or invulnUntil
	local lives = tonumber(update.Lives) or lastLives
	if lives < lastLives then
		onHit()
	end
	lastLives = lives
	refreshHearts()

	local shieldPhase = tonumber(update.ShieldUsedPhase) or 0
	if shieldPhase ~= lastShieldPhase and shieldPhase > 0 then
		Sfx.Play("PromptClean")
		Juice.FloatText(field, shipAt(-0.06), "SHIELD!", Theme.TYPED)
		Juice.Pop(ship, 0.6)
	end
	lastShieldPhase = shieldPhase

	local grazes = tonumber(update.Grazes) or lastGrazes
	if grazes > lastGrazes then
		Sfx.Play("ChipTap", 1.6)
		for _ = 1, math.min(grazes - lastGrazes, 6) do
			Juice.Spark(field, shipAt(0), look.Color)
		end
		Juice.Pop(grazeLabel, 0.3)
	end
	lastGrazes = grazes
	grazeLabel.Text = tostring(grazes)
	grazeFill.Size = UDim2.fromScale(math.clamp(grazes / GRAZE_FULL, 0, 1), 1)

	local combo = tonumber(update.Combo) or lastCombo
	comboLabel.Text = `x{combo}`
	if combo > lastCombo then
		Juice.Pop(comboLabel, 0.2 + math.min(combo, 30) * 0.01)
		comboLabel.TextColor3 = if combo >= 20 then Theme.TYPED elseif combo >= 10 then Theme.MOOD else Theme.ACCENT
		if combo % 10 == 0 then
			Sfx.Play("ComboCallout")
			Juice.Banner(stage, `COMBO x{combo}!`, comboLabel.TextColor3, 44)
		end
	elseif combo == 0 and lastCombo > 0 then
		comboLabel.TextColor3 = Theme.ACCENT
		Juice.Pop(comboLabel, -0.3)
	end
	lastCombo = combo
end

local function onEnded(result: any, payout: any, grade: any)
	if not battle then
		return -- Acts 1-2: BattleController
	end
	teardown()
	Music.Stop(2)
	local shipped = type(result) == "table" and result.Status == "Shipped"
	if shipped then
		Sfx.Play("Shipped")
		Juice.Banner(stage, "SHIPPED!", Theme.TYPED, 64)
		for _ = 1, 16 do
			Juice.Spark(stage, UDim2.fromScale(math.random(), math.random() * 0.6 + 0.2), Theme.TYPED)
		end
	else
		Juice.Banner(stage, "LAUNCH FAILED", Theme.BUG, 56)
	end
	local stats = if type(result) == "table" then result else {}
	task.delay(RESULTS_DELAY, function()
		if not battle then
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

local function hudColumn(anchorX: number, positionX: UDim): Frame
	local column = Instance.new("Frame")
	column.BackgroundTransparency = 1
	column.AnchorPoint = Vector2.new(anchorX, 0)
	column.Position = UDim2.new(positionX, UDim.new(0, 0))
	column.Size = UDim2.new(0, HUD_WIDTH, 1, 0)
	column.Parent = stage
	Theme.List(column, 6)
	return column
end

local function meter(parent: Instance, color: Color3, order: number): Frame
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

function BulletHellController.Init()
	gui = Theme.Screen("BulletHell", 6)
	gui.Enabled = false

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Theme.BACKGROUND
	backdrop.BackgroundTransparency = 0.2
	backdrop.BorderSizePixel = 0
	backdrop.Parent = gui

	-- A square stage as tall as the screen allows; the HUD columns hang off its sides.
	stage = Instance.new("Frame")
	stage.BackgroundTransparency = 1
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.5)
	stage.Size = UDim2.fromScale(1, 0.94)
	stage.Parent = gui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = stage

	field = Instance.new("Frame")
	field.Size = UDim2.fromScale(1, 1)
	field.BackgroundColor3 = Theme.BACKGROUND
	field.BorderSizePixel = 0
	field.ClipsDescendants = true
	field.Parent = stage
	local fieldCorner = Instance.new("UICorner")
	fieldCorner.CornerRadius = UDim.new(0, 8)
	fieldCorner.Parent = field
	local fieldStroke = Instance.new("UIStroke")
	fieldStroke.Color = Theme.ACCENT
	fieldStroke.Thickness = 2
	fieldStroke.Parent = field
	-- faint terminal grid
	for i = 1, 9 do
		for _, vertical in { true, false } do
			local line = Instance.new("Frame")
			line.BackgroundColor3 = Theme.BORDER
			line.BackgroundTransparency = 0.6
			line.BorderSizePixel = 0
			line.Position = if vertical then UDim2.fromScale(i / 10, 0) else UDim2.fromScale(0, i / 10)
			line.Size = if vertical then UDim2.new(0, 1, 1, 0) else UDim2.new(1, 0, 0, 1)
			line.Parent = field
		end
	end

	flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 8
	flash.Parent = field

	for _ = 1, POOL_SIZE do
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BorderSizePixel = 0
		frame.Visible = false
		frame.ZIndex = 4
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = frame
		frame.Parent = field
		table.insert(pool, { Frame = frame, Stroke = stroke, Look = 0 })
	end

	ship = Theme.Text(field, "▲", 28, Theme.TYPED)
	ship.AutomaticSize = Enum.AutomaticSize.None
	ship.AnchorPoint = Vector2.new(0.5, 0.5)
	ship.Size = UDim2.fromOffset(30, 30)
	ship.TextXAlignment = Enum.TextXAlignment.Center
	ship.TextStrokeColor3 = Theme.ACCENT
	ship.TextStrokeTransparency = 0.2
	ship.ZIndex = 6
	ship.Visible = false

	-- The real hitbox (HitRadius), drawn while focused; never smaller than a few pixels so it stays readable.
	hitbox = Instance.new("Frame")
	hitbox.AnchorPoint = Vector2.new(0.5, 0.5)
	hitbox.Size = UDim2.fromScale(CFG.HitRadius * 2, CFG.HitRadius * 2)
	hitbox.BackgroundColor3 = Color3.new(1, 1, 1)
	hitbox.BorderSizePixel = 0
	hitbox.Visible = false
	hitbox.ZIndex = 7
	hitbox.Parent = field
	local hitboxCorner = Instance.new("UICorner")
	hitboxCorner.CornerRadius = UDim.new(0.5, 0)
	hitboxCorner.Parent = hitbox
	local hitboxStroke = Instance.new("UIStroke")
	hitboxStroke.Color = Theme.BUG
	hitboxStroke.Thickness = 1.5
	hitboxStroke.Parent = hitbox
	local hitboxMin = Instance.new("UISizeConstraint")
	hitboxMin.MinSize = Vector2.new(6, 6)
	hitboxMin.Parent = hitbox

	bossBar = Instance.new("Frame")
	bossBar.AnchorPoint = Vector2.new(0.5, 0)
	bossBar.Position = UDim2.new(0.5, 0, 0, 22)
	bossBar.Size = UDim2.new(0.8, 0, 0, 10)
	bossBar.BackgroundColor3 = Theme.PANEL
	bossBar.BorderSizePixel = 0
	bossBar.Visible = false
	bossBar.ZIndex = 7
	bossBar.Parent = field
	bossFill = Instance.new("Frame")
	bossFill.Size = UDim2.fromScale(1, 1)
	bossFill.BorderSizePixel = 0
	bossFill.ZIndex = 7
	bossFill.Parent = bossBar
	bossName = Theme.Text(bossBar, "", 13, Theme.TEXT)
	bossName.AutomaticSize = Enum.AutomaticSize.None
	bossName.AnchorPoint = Vector2.new(0, 1)
	bossName.Position = UDim2.new(0, 0, 0, -2)
	bossName.Size = UDim2.new(1, 0, 0, 16)
	bossName.ZIndex = 7

	-- Left: who it's for, lives, graze meter, combo.
	local left = hudColumn(1, UDim.new(0, -10))
	clientLabel = Theme.Text(left, "", 15)
	clientLabel.TextXAlignment = Enum.TextXAlignment.Right
	clientLabel.LayoutOrder = 1
	local livesTitle = Theme.Text(left, "LIVES", 12, Theme.MUTED)
	livesTitle.TextXAlignment = Enum.TextXAlignment.Right
	livesTitle.LayoutOrder = 2
	heartsLabel = Theme.Text(left, "", 26, Theme.BUG)
	heartsLabel.TextXAlignment = Enum.TextXAlignment.Right
	heartsLabel.LayoutOrder = 3
	local grazeTitle = Theme.Text(left, "GRAZE", 12, Theme.MUTED)
	grazeTitle.TextXAlignment = Enum.TextXAlignment.Right
	grazeTitle.LayoutOrder = 4
	grazeFill = meter(left, Theme.TYPED, 5)
	grazeLabel = Theme.Text(left, "0", 18, Theme.TYPED)
	grazeLabel.TextXAlignment = Enum.TextXAlignment.Right
	grazeLabel.LayoutOrder = 6
	comboLabel = Theme.Text(left, "x0", 36, Theme.ACCENT)
	comboLabel.Font = Enum.Font.GothamBlack
	comboLabel.TextXAlignment = Enum.TextXAlignment.Right
	comboLabel.LayoutOrder = 7

	-- Right: phase, loadout, controls, and the touch focus toggle.
	local right = hudColumn(0, UDim.new(1, 10))
	phaseLabel = Theme.Text(right, "GET READY", 16, Theme.ACCENT)
	phaseLabel.LayoutOrder = 1
	loadoutLabel = Theme.Text(right, "", 13, Theme.TYPED)
	loadoutLabel.LayoutOrder = 2
	hintLabel = Theme.Text(right, HINT_KEYBOARD, 12, Theme.MOOD)
	hintLabel.LayoutOrder = 3
	focusButton = Theme.Button(right, "FOCUS", 18)
	focusButton.Size = UDim2.fromOffset(120, 52)
	focusButton.LayoutOrder = 4
	focusButton.Activated:Connect(function()
		focusToggle = not focusToggle
		refreshFocusButton()
	end)

	Sfx.Preload()
	Music.Preload()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function BulletHellController.Start()
	RemoteManager.GetRemote(RemoteNames.BattleStarted).OnClientEvent:Connect(onStarted)
	RemoteManager.GetRemote(RemoteNames.BattleUpdate).OnClientEvent:Connect(onUpdate)
	RemoteManager.GetRemote(RemoteNames.BattleEnded).OnClientEvent:Connect(onEnded)
end

return BulletHellController
