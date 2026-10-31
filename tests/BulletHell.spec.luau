--!strict
local BulletHell = require("../src/ReplicatedStorage/Shared/BulletHell")
local GameConfig = require("../src/ReplicatedStorage/Shared/GameConfig")

local CFG = GameConfig.BULLET_HELL
local START = 100
local EPSILON = 1e-9

local function options(
	shield: boolean?,
	extraLife: boolean?,
	eliteHalfWaves: number?,
	boss: BulletHell.BossKind?,
	wingmen: { string }?
): BulletHell.Options
	return {
		Boss = boss or "Hacker",
		EliteHalfWaves = eliteHalfWaves or 0,
		Loadout = { Shield = shield == true, ExtraLife = extraLife == true, Homing = false, FireInterval = 0.3 },
		Wingmen = wingmen or {},
	}
end

local function newBattle(seed: number, opts: BulletHell.Options?): BulletHell.Battle
	return BulletHell.New(START, seed, opts or options(), CFG)
end

-- A bullet flying straight down at BulletSpeed that is at (x, y) exactly at time crossAt.
local function fallingBullet(id: number, x: number, y: number, crossAt: number): BulletHell.Bullet
	local firedAt = crossAt - 1
	return BulletHell.NewBullet(id, firedAt, x, y - CFG.BulletSpeed, 0, CFG.BulletSpeed, 0)
end

-- A battle with no scheduled bullets except the given ones; the ship sits at its start position unless moved.
local function battleWith(bullets: { BulletHell.Bullet }, opts: BulletHell.Options?): BulletHell.Battle
	local b = newBattle(1, opts)
	b.Bullets = bullets
	return b
end

local function sameBullets(a: { BulletHell.Bullet }, b: { BulletHell.Bullet }): boolean
	if #a ~= #b then
		return false
	end
	for i, bullet in a do
		local other = b[i]
		for key, value in bullet :: any do
			if (other :: any)[key] ~= value then
				return false
			end
		end
	end
	return true
end

local function enemiesOf(b: BulletHell.Battle, kind: BulletHell.EnemyKind): { BulletHell.Enemy }
	local list: { BulletHell.Enemy } = {}
	for _, enemy in b.Enemies do
		if enemy.Kind == kind then
			table.insert(list, enemy)
		end
	end
	return list
end

-- A battle whose enemies are scheduled but whose bullets are cleared, so claims can be tested without the idle ship dying.
local function quietBattle(seed: number, opts: BulletHell.Options?): BulletHell.Battle
	local b = newBattle(seed, opts)
	b.Bullets = {}
	return b
end

-- Claims `count` kills on an enemy with the ship's gun, one every 0.3 s (its fire rate) from `from`; returns the
-- time of the last claim.
local function claimSteadily(b: BulletHell.Battle, enemyId: number, from: number, count: number): number
	local t = from
	for i = 1, count do
		t = from + (i - 1) * 0.3
		assert(BulletHell.Kill(b, enemyId, t, "Ship"), `claim {i} at {t}`)
	end
	return t
end

local tests = {}

tests["rng is deterministic and in [0, 1)"] = function()
	local first, second = BulletHell.Rng(42), BulletHell.Rng(42)
	for _ = 1, 1000 do
		local value = first()
		assert(value == second(), "same seed, same sequence")
		assert(value >= 0 and value < 1, "value in [0, 1)")
	end
	assert(BulletHell.Rng(42)() ~= BulletHell.Rng(43)(), "nearby seeds diverge on the first draw")
end

tests["same seed, same bullets"] = function()
	local a, b, c = newBattle(42), newBattle(42), newBattle(43)
	assert(#a.Bullets > 100, "the schedule has bullets")
	assert(sameBullets(a.Bullets, b.Bullets), "seed 42 twice gives equal lists")
	assert(not sameBullets(a.Bullets, c.Bullets), "seed 43 differs")
	for i, bullet in a.Bullets do
		assert(bullet.Id == i, "ids are list indices")
		assert(i == 1 or a.Bullets[i - 1].FiredAt <= bullet.FiredAt, "sorted by fire time")
		assert(bullet.GoneAt > bullet.FiredAt, "every bullet has a lifetime")
	end
	for i, enemy in a.Enemies do
		assert(enemy.Id == i, "enemy ids are list indices")
		local x, y = BulletHell.EnemyPosition(enemy, enemy.SpawnAt + 2)
		local x2, y2 = BulletHell.EnemyPosition(b.Enemies[i], enemy.SpawnAt + 2)
		assert(x == x2 and y == y2, "same seed, same enemy paths")
	end
	assert(#enemiesOf(a, "Popcorn") > 20 and #enemiesOf(a, "Boss") == 1, "waves of popcorn, then one boss")
end

tests["curved bullets are analytic and leave the field"] = function()
	local bullet = BulletHell.NewBullet(1, 10, 0.5, 0.2, 0, CFG.BulletSpeed, 1.5)
	local x, y = BulletHell.BulletPosition(bullet, 10)
	assert(x == 0.5 and y == 0.2, "starts at its origin")
	local x1, y1 = BulletHell.BulletPosition(bullet, 10.5)
	local x2, y2 = BulletHell.BulletPosition(bullet, 10.5 + 1e-4)
	local speed = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) / 1e-4
	assert(math.abs(speed - CFG.BulletSpeed) < 1e-3, "curving keeps its speed")
	assert(bullet.GoneAt < math.huge and bullet.GoneAt > 10, "a curved bullet still leaves")
	local gx, gy = BulletHell.BulletPosition(bullet, bullet.GoneAt)
	local edge = -0.1 + 1e-6
	assert(gx <= edge or gx >= 1 - edge or gy <= edge or gy >= 1 - edge, "GoneAt is on or past the field's edge")
end

tests["ship moves are clamped"] = function()
	local b = battleWith({})
	BulletHell.MoveShip(b, 0.5, 0.85, START + 1)
	local before = b.ShipSamples[#b.ShipSamples]
	for _ = 1, 10 do
		BulletHell.MoveShip(b, 1, 0.1, START + 1)
	end
	local after = b.ShipSamples[#b.ShipSamples]
	local burst = math.sqrt((after.X - before.X) ^ 2 + (after.Y - before.Y) ^ 2)
	assert(burst > CFG.ShipSlack - EPSILON, "the burst used its slack")
	assert(burst <= CFG.ShipSlack + EPSILON, "a burst moves at most ShipSlack")
	assert(#b.ShipSamples <= 3, "a burst doesn't grow the sample list")

	-- y stays inside [ShipMinY, ShipMaxY] however far the ship is allowed to fly
	BulletHell.MoveShip(b, 0.5, 0, START + 10)
	local _, top = BulletHell.ShipAt(b, START + 10)
	assert(math.abs(top - CFG.ShipMinY) < EPSILON, "y clamped to ShipMinY")
	BulletHell.MoveShip(b, 0.5, 2, START + 20)
	local _, bottom = BulletHell.ShipAt(b, START + 20)
	assert(math.abs(bottom - CFG.ShipMaxY) < EPSILON, "y clamped to ShipMaxY")

	-- NaN and out-of-order input are ignored
	BulletHell.MoveShip(b, 0 / 0, 0.5, START + 21)
	BulletHell.MoveShip(b, 0.2, 0.5, START + 19)
	local nx, ny = BulletHell.ShipAt(b, START + 30)
	assert(nx == 0.5 and math.abs(ny - CFG.ShipMaxY) < EPSILON, "bad input left the ship alone")

	-- a fast stream stays bounded: samples two apart are >= 0.05 s apart, so a 2 s window keeps at most 81, plus the anchor
	local most = 0
	for i = 1, 2000 do
		BulletHell.MoveShip(b, 0.5, 0.6, START + 30 + i * 0.026)
		most = math.max(most, #b.ShipSamples)
	end
	assert(most > 2 / 0.05 + 2, "samples can be closer than the minimum gap")
	assert(most <= 2 * 2 / 0.05 + 2, "sample list bounded by the window")
end

tests["a move is limited by elapsed time"] = function()
	local b = battleWith({})
	BulletHell.MoveShip(b, 0.5, 0.85, START + 5)
	local before = b.ShipSamples[#b.ShipSamples]
	BulletHell.MoveShip(b, 0.04, 0.35, START + 5.1)
	local after = b.ShipSamples[#b.ShipSamples]
	local moved = math.sqrt((after.X - before.X) ^ 2 + (after.Y - before.Y) ^ 2)
	assert(moved <= CFG.ShipSpeed * 0.1 + CFG.ShipSlack + EPSILON, "at most speed x time + slack")
	assert(moved > CFG.ShipSpeed * 0.1 + CFG.ShipSlack - EPSILON, "and the full allowance is granted")
end

tests["a dodge is judged at the bullet's time"] = function()
	local crossAt = START + 2
	-- held on the path at the crossing time, moved away 0.1 s later: still a hit
	local b = battleWith({ fallingBullet(1, 0.5, 0.8, crossAt) })
	BulletHell.MoveShip(b, 0.5, 0.8, START + 0.5)
	BulletHell.MoveShip(b, 0.5, 0.8, crossAt)
	BulletHell.MoveShip(b, 0.7, 0.8, crossAt + 0.1)
	BulletHell.Tick(b, crossAt + 1)
	assert(b.Lives == CFG.Lives - 1, "late dodge is still a hit")

	-- held away at the crossing time, passing through the point later: no hit
	local c = battleWith({ fallingBullet(1, 0.5, 0.8, crossAt) })
	BulletHell.MoveShip(c, 0.7, 0.8, START + 0.5)
	BulletHell.MoveShip(c, 0.7, 0.8, crossAt + 0.4)
	BulletHell.MoveShip(c, 0.5, 0.8, crossAt + 0.5)
	BulletHell.Tick(c, crossAt + 1)
	assert(c.Lives == CFG.Lives, "ship was away when the bullet crossed")
	assert(c.Grazes == 0, "too far to graze")
end

tests["a full-speed sweep between substeps still hits"] = function()
	-- the ship crosses x = 0.5 at full speed halfway between two 1/30 s grid steps, while the bullet crosses y = 0.8
	local crossAt = START + 2 + 1 / 60
	local function shipX(t: number): number
		return 0.5 + CFG.ShipSpeed * (t - crossAt)
	end
	local b = battleWith({ fallingBullet(1, 0.5, 0.8, crossAt) })
	BulletHell.MoveShip(b, shipX(START + 1.9), 0.8, START + 0.5)
	BulletHell.MoveShip(b, shipX(START + 1.9), 0.8, START + 1.9)
	BulletHell.MoveShip(b, shipX(START + 2.1), 0.8, START + 2.1)
	assert(math.abs(b.ShipSamples[#b.ShipSamples].X - shipX(START + 2.1)) < EPSILON, "the sweep was allowed")
	BulletHell.Tick(b, START + 3)
	assert(b.Lives == CFG.Lives - 1, "swept through the bullet: a hit")
end

tests["judging waits for the latency grace"] = function()
	local b = battleWith({ fallingBullet(1, 0.5, 0.85, START + 2) })
	BulletHell.Tick(b, START + 2 + CFG.LatencyGrace - 0.1)
	assert(b.Lives == CFG.Lives, "not judged yet")
	BulletHell.Tick(b, START + 2 + CFG.LatencyGrace + 0.1)
	assert(b.Lives == CFG.Lives - 1, "judged once the grace passed")
end

tests["graze counts once"] = function()
	local b = battleWith({ fallingBullet(1, 0.53, 0.85, START + 2) })
	for i = 1, 20 do
		BulletHell.Tick(b, START + 1.5 + i * 0.1)
	end
	assert(b.Grazes == 1, "one graze")
	assert(b.Combo == 1 and b.MaxCombo == 1, "graze adds to the combo")
	assert(b.Lives == CFG.Lives, "a graze is not a hit")
end

tests["invulnerability after a hit"] = function()
	local b = battleWith({ fallingBullet(1, 0.5, 0.85, START + 2), fallingBullet(2, 0.5, 0.85, START + 3) })
	BulletHell.Tick(b, START + 5)
	assert(b.Lives == CFG.Lives - 1, "second bullet inside the window is free")
	assert(math.abs(b.InvulnUntil - (START + 2 + CFG.InvulnSeconds)) < 0.05, "invulnerable from the hit")
end

tests["shield absorbs one hit per wave"] = function()
	local b = battleWith({
		fallingBullet(1, 0.5, 0.85, START + 2),
		fallingBullet(2, 0.5, 0.85, START + 4),
		fallingBullet(3, 0.5, 0.85, START + CFG.WaveSeconds + 5),
	}, options(true))
	BulletHell.Tick(b, START + 3)
	assert(b.Lives == CFG.Lives, "first hit absorbed")
	BulletHell.Tick(b, START + 5)
	assert(b.Lives == CFG.Lives - 1, "second hit in the same wave costs a life")
	BulletHell.Tick(b, START + CFG.WaveSeconds + 6)
	assert(b.Lives == CFG.Lives - 1, "the next wave's shield absorbs again")
end

tests["losing all lives fails"] = function()
	local function hits(count: number): { BulletHell.Bullet }
		local list: { BulletHell.Bullet } = {}
		for i = 1, count do
			table.insert(list, fallingBullet(i, 0.5, 0.85, START + 2 * i))
		end
		return list
	end
	local b = battleWith(hits(3))
	BulletHell.Tick(b, START + 10)
	assert(b.Lives == 0 and b.Status == "Failed", "3 hits fail")

	local c = battleWith(hits(4), options(false, true))
	BulletHell.Tick(c, START + 7)
	assert(c.Lives == 1 and c.Status == "Running", "ExtraLife survives 3 hits")
	BulletHell.Tick(c, START + 10)
	assert((c.Status :: BulletHell.BattleStatus) == "Failed", "the 4th hit fails")
end

tests["time up ships, elite waves lengthen the fight"] = function()
	local b = battleWith({})
	local endAt = START + CFG.WaveCount * CFG.WaveSeconds + CFG.BossSeconds
	assert(CFG.Duration == endAt - START, "Duration matches the phases")
	BulletHell.Tick(b, endAt + CFG.LatencyGrace - 0.1)
	assert(b.Status == "Running", "still judging the last moments")
	BulletHell.Tick(b, endAt + CFG.LatencyGrace + 0.1)
	assert((b.Status :: BulletHell.BattleStatus) == "Shipped", "time up with lives left ships")

	local c = battleWith({}, options(false, false, 2))
	BulletHell.Tick(c, endAt + CFG.LatencyGrace + 0.1)
	assert(c.Status == "Running", "an elite wave adds time")
	assert(c.EndsAt == endAt + CFG.EliteWaveSeconds, "one full elite wave")
	local boss = c.Phases[#c.Phases]
	assert(boss.Kind == "Boss" and c.Phases[#c.Phases - 1].Kind == "Elite", "elite wave right before the boss")
end

tests["boss pattern by client"] = function()
	local hacker = newBattle(7, options(false, false, 0, "Hacker"))
	local hackerBoss = enemiesOf(hacker, "Boss")[1]
	local curved = 0
	for _, bullet in hacker.Bullets do
		if bullet.Owner == hackerBoss.Id and bullet.Curve ~= 0 then
			curved += 1
		end
	end
	assert(curved > 100, "the Hacker fires curving streams")

	local naysayer = newBattle(7, options(false, false, 0, "Naysayer"))
	local naysayerBoss = enemiesOf(naysayer, "Boss")[1]
	local rows: { [number]: { number } } = {}
	local rowCount = 0
	for _, bullet in naysayer.Bullets do
		if bullet.Owner == naysayerBoss.Id then
			assert(bullet.VX == 0 and bullet.VY > 0 and bullet.VY < CFG.BulletSpeed, "bubbles fall slowly, straight down")
			if not rows[bullet.FiredAt] then
				rows[bullet.FiredAt] = {}
				rowCount += 1
			end
			table.insert(rows[bullet.FiredAt], bullet.X)
		end
	end
	assert(rowCount >= 10, "the Naysayer rains walls")
	for _, row in rows do
		table.sort(row)
		assert(#row >= 12, "a row is a wall")
		local widest = 0
		for i = 2, #row do
			widest = math.max(widest, row[i] - row[i - 1] - 2 * CFG.HitRadius)
		end
		assert(widest >= 0.12, "every wall has a gap a ship fits through")
	end
end

tests["swarm splits at half health"] = function()
	local b = quietBattle(3, options(false, false, 0, "Swarm"))
	local boss = enemiesOf(b, "Boss")[1]
	local children = enemiesOf(b, "Child")
	assert(#children == 3, "three children, pre-generated")
	local t = boss.SpawnAt + 5
	assert(not BulletHell.Kill(b, children[1].Id, t, "Ship"), "a dormant child can't be hit")
	t = claimSteadily(b, boss.Id, t, CFG.BossHp / 2 - 1)
	assert(b.SplitAt == nil and children[1].ActiveFrom == nil, "no split above half health")
	t += 0.3
	assert(BulletHell.Kill(b, boss.Id, t, "Ship"), "the half-health claim")
	assert(b.SplitAt == t and boss.KilledAt == t, "the big boss splits")
	for _, child in children do
		assert(child.ActiveFrom == t and child.Hp == CFG.SwarmChildHp, "each child spawns at the split")
	end
	assert(b.BossDownAt == nil, "the children are still up")

	local later = t + CFG.VisibleDelay
	for _, child in children do
		later = claimSteadily(b, child.Id, later + 0.3, CFG.SwarmChildHp)
	end
	assert(b.BossDownAt == later, "last child down: boss down")
	BulletHell.Tick(b, later + CFG.LatencyGrace + 0.1)
	assert(b.Status == "Shipped", "boss down ships")
end

tests["claims need the weapon and a live enemy"] = function()
	local b = quietBattle(5)
	local first = b.Enemies[1]
	local t = first.SpawnAt + 1.5
	assert(not BulletHell.Kill(b, first.Id, first.SpawnAt - 0.5, "Ship"), "not on screen yet")
	assert(not BulletHell.Kill(b, first.Id, t, "Spread"), "Spread needs its hire")
	assert(not BulletHell.Kill(b, first.Id, t, "Laser" :: any), "unknown weapon")
	assert(not BulletHell.Kill(b, 9999, t, "Ship"), "no such enemy")
	assert(BulletHell.Kill(b, first.Id, t, "Ship"), "the ship's gun hits")
	assert(first.KilledAt == t and b.Killed == 1 and b.Combo == 1, "kill recorded, combo up")
	assert(not BulletHell.Kill(b, first.Id, t, "Ship"), "already dead")
	local second = b.Enemies[2]
	assert(not BulletHell.Kill(b, second.Id, second.LeaveAt + CFG.LatencyGrace + 0.1, "Ship"), "already left the screen")

	local c = quietBattle(5, options(false, false, 0, nil, { CFG.Weapons.Spread.Role }))
	assert(BulletHell.Kill(c, 1, t, "Spread"), "a hired Spread wingman hits")

end

tests["claims refill at the fire rate and can't be banked"] = function()
	-- after 46 s unused, one instant allows only ShotBudgetSlack + PerShot claims per weapon
	local d = quietBattle(5, options(false, false, 0, nil, { CFG.Weapons.Spread.Role }))
	local boss = enemiesOf(d, "Boss")[1]
	boss.Hp = 10000
	local at = boss.SpawnAt + 6
	local function drain(weapon: BulletHell.Weapon, perShot: number)
		for _ = 1, CFG.ShotBudgetSlack + perShot do
			assert(BulletHell.Kill(d, boss.Id, at, weapon), "inside the bucket")
		end
		assert(not BulletHell.Kill(d, boss.Id, at, weapon), "the bucket is empty")
	end
	drain("Ship", 1)
	drain("Spread", CFG.Weapons.Spread.PerShot)
	assert(not BulletHell.Kill(d, boss.Id, boss.SpawnAt + 3, "Ship"), "a clock going backwards refills nothing")

	-- a steady stream at the fire rate keeps succeeding
	local e = quietBattle(5)
	local eBoss = enemiesOf(e, "Boss")[1]
	eBoss.Hp = 10000
	claimSteadily(e, eBoss.Id, eBoss.SpawnAt + 2, 100)
end

tests["a boss flying in can't be hit yet"] = function()
	local b = quietBattle(5)
	local boss = enemiesOf(b, "Boss")[1]
	local _, y = BulletHell.EnemyPosition(boss, boss.SpawnAt + CFG.VisibleDelay)
	assert(y < 0, "still above the field after VisibleDelay")
	assert(not BulletHell.Kill(b, boss.Id, boss.SpawnAt + CFG.VisibleDelay, "Ship"), "off screen")
	assert(BulletHell.Kill(b, boss.Id, boss.SpawnAt + 0.5, "Ship"), "centre on screen")
end

tests["wingmen toughen the boss"] = function()
	local wingmen = { CFG.Weapons.Spread.Role, CFG.Weapons.Beam.Role }
	local b = newBattle(5, options(false, false, 0, "Swarm", wingmen))
	assert(enemiesOf(b, "Boss")[1].Hp == CFG.BossHp * 2, "two wingmen: x2 boss HP")
	assert(enemiesOf(b, "Child")[1].Hp == CFG.SwarmChildHp * 2, "and x2 child HP")
	assert(enemiesOf(newBattle(5), "Boss")[1].Hp == CFG.BossHp, "no wingmen: base HP")
end

tests["a dead enemy stops firing"] = function()
	local b = quietBattle(11)
	local scheduled = newBattle(11).Bullets
	local enemy = b.Enemies[1]
	local t = enemy.SpawnAt + 2
	local before, after = 0, 0
	for _, bullet in scheduled do
		if bullet.Owner == enemy.Id then
			assert(BulletHell.Fired(b, bullet), "alive: every shot fires")
			if bullet.FiredAt > t then
				after += 1
			else
				before += 1
			end
		end
	end
	assert(before > 0 and after > 0, "the enemy fires before and after the kill time")
	assert(BulletHell.Kill(b, enemy.Id, t, "Ship"), "kill")
	for _, bullet in scheduled do
		if bullet.Owner == enemy.Id then
			assert(BulletHell.Fired(b, bullet) == (bullet.FiredAt <= t), "only shots fired before the kill fly")
		end
	end
end

tests["score formula"] = function()
	local b = newBattle(1)
	b.Killed = 30
	b.Grazes = 20
	b.MaxCombo = 45
	b.Lives = 2
	local expected = 0.6 * 30 / #b.Enemies + 0.4 * (20 / 40) + 0.5 * 1 + 0.5 * 2 / 3
	assert(math.abs(BulletHell.Score(b) - expected) < EPSILON, "score matches the formula")
	local result = BulletHell.Result(b)
	assert(result.Status == "Running" and result.Grazes == 20 and result.MaxCombo == 45, "result fields")
	assert(result.LivesLeft == 2 and math.abs(result.Score - expected) < EPSILON, "result score and lives")

	b.Killed, b.Grazes, b.MaxCombo, b.Lives = #b.Enemies, 400, 400, 3
	assert(math.abs(BulletHell.Score(b) - 2) < EPSILON, "a perfect run scores 2")
	b.Killed, b.Grazes, b.MaxCombo, b.Lives = 0, 0, 0, 0
	assert(BulletHell.Score(b) == 0, "nothing scores 0")
end

tests["elite wave lengthens the fight"] = function()
	local a = newBattle(9)
	local c = newBattle(9, options(false, false, 2))
	local bossA, bossC = enemiesOf(a, "Boss")[1], enemiesOf(c, "Boss")[1]
	assert(bossC.SpawnAt == bossA.SpawnAt + CFG.EliteWaveSeconds, "the boss spawns one elite wave later")
	local elite = c.Phases[#c.Phases - 1]
	local eliteEnemies = 0
	for _, enemy in c.Enemies do
		if enemy.Kind == "Popcorn" and enemy.SpawnAt >= elite.StartsAt and enemy.SpawnAt < bossC.SpawnAt then
			eliteEnemies += 1
		end
	end
	assert(eliteEnemies >= 10, "the elite wave is full of enemies")
	assert(#c.Enemies == #a.Enemies + eliteEnemies, "and only adds enemies")

	local capped = newBattle(9, options(false, false, 4))
	assert(capped.EndsAt == c.EndsAt and #capped.Enemies == #c.Enemies, "EliteHalfWaves = 4 behaves like 2")
end

return tests
