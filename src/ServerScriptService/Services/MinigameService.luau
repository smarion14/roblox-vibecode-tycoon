--!strict
-- Station minigames other than typing: Patch Panel (Server Rack), RAID Rebuild (Database Console) and
-- Training Run (AI Model Rig). The server generates every puzzle, keeps the authoritative state, times
-- everything on its own clock and grades the result. Clients only render and send raw actions.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local PatchPanel = require(Shared:WaitForChild("PatchPanel"))
local RaidRebuild = require(Shared:WaitForChild("RaidRebuild"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local TrainingRun = require(Shared:WaitForChild("TrainingRun"))
local TypingJudge = require(Shared:WaitForChild("TypingJudge"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local StartupDataModule = require(ServerScriptService:WaitForChild("Components"):WaitForChild("StartupDataModule"))
local AssemblyService = require(script.Parent:WaitForChild("AssemblyService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))

type Session = {
	Kind: string,
	Component: string,
	StartedAt: number,
	Finished: boolean,
	-- Patch Panel
	Puzzle: PatchPanel.Puzzle?,
	Rotations: { number },
	-- RAID Rebuild
	Sequence: { number },
	Round: number,
	AwaitingInput: boolean,
	FlashEndsAt: number,
	InputDeadline: number,
	CorrectTotal: number,
	RequiredTotal: number,
	RoundsCleared: number,
	-- Training Run
	Epochs: { TrainingRun.Epoch },
	EpochIndex: number,
	EpochSentAt: number,
	EpochOpen: boolean,
	HitSum: number,
	Hits: number,
}

local WATCH_SECONDS = 0.1
local ACTION_RATE_LIMIT = 20
local PATCH_GRACE = 0.5
local RAID_LEAD_IN = 0.7 -- pause before the first flash so the player is looking
local NEXT_STEP_DELAY = 0.9 -- breathing room between rounds / epochs for the feedback to land
local MAX_RAID_INPUTS = 20

local LABELS: { [string]: { Progress: string, Score: string } } = {
	PatchPanel = { Progress = "Cable laid", Score = "Score" },
	RaidRebuild = { Progress = "Rounds cleared", Score = "Recall" },
	TrainingRun = { Progress = "Epochs hit", Score = "Precision" },
}

local MinigameService = {}

local sessions: { [Player]: Session } = {}
local rng = Random.new()

local function nextNumber(): number
	return rng:NextNumber()
end

local function send(player: Player, event: string, payload: any)
	RemoteManager.FireClient(RemoteNames.MinigameUpdate, player, event, payload)
end

local function finish(player: Player, session: Session, accuracy: number, completed: number, total: number, allDone: boolean)
	if session.Finished or sessions[player] ~= session then
		return
	end
	session.Finished = true
	sessions[player] = nil

	local score = math.clamp(accuracy, 0, 1)
	local grade: TypingJudge.Grade = TypingJudge.GradeFor(score, allDone)
	local outcome, replaced = AssemblyService.BuildPart(player, session.Component, grade)
	StartupDataModule.SetActivity(player, "Idle")
	local labels = LABELS[session.Kind]
	RemoteManager.FireClient(
		RemoteNames.BurstFinished,
		player,
		grade,
		score,
		session.Component,
		completed,
		total,
		labels.Progress,
		labels.Score,
		outcome,
		replaced
	)
end

-- Patch Panel --------------------------------------------------------------

local function finishPatch(player: Player, session: Session)
	local puzzle = session.Puzzle :: PatchPanel.Puzzle
	local config = GameConfig.MINIGAMES.PatchPanel
	local trace = PatchPanel.Trace(puzzle, session.Rotations)
	local elapsed = os.clock() - session.StartedAt
	local score = PatchPanel.Score(trace.Solved, elapsed, config.TimeLimit, trace.Connected, puzzle.PathLength)
	finish(player, session, score, math.min(trace.Connected, puzzle.PathLength), puzzle.PathLength, trace.Solved)
end

local function startPatch(player: Player, session: Session)
	local config = GameConfig.MINIGAMES.PatchPanel
	local puzzle = PatchPanel.Generate(config.Cols, config.Rows, nextNumber)
	session.Puzzle = puzzle
	session.Rotations = table.clone(puzzle.Start)
	local shapes: { string } = {}
	for _, tile in puzzle.Tiles do
		table.insert(shapes, tile.Shape)
	end
	RemoteManager.FireClient(RemoteNames.MinigameStart, player, "PatchPanel", {
		Cols = puzzle.Cols,
		Rows = puzzle.Rows,
		StartRow = puzzle.StartRow,
		EndRow = puzzle.EndRow,
		Shapes = shapes,
		Rotations = session.Rotations,
		TimeLimit = config.TimeLimit,
	})
end

local function onPatchRotate(player: Player, session: Session, tileIndex: any)
	local puzzle = session.Puzzle
	if not puzzle or type(tileIndex) ~= "number" or tileIndex % 1 ~= 0 or not puzzle.Tiles[tileIndex] then
		return
	end
	session.Rotations[tileIndex] = (session.Rotations[tileIndex] + 1) % 4
	local trace = PatchPanel.Trace(puzzle, session.Rotations)
	send(player, "Rotated", { Index = tileIndex, Rotation = session.Rotations[tileIndex], Solved = trace.Solved })
	if trace.Solved then
		finishPatch(player, session)
	end
end

-- RAID Rebuild -------------------------------------------------------------

local function raidRoundLength(round: number): number
	return GameConfig.MINIGAMES.RaidRebuild.StartLength + round - 1
end

local function finishRaid(player: Player, session: Session)
	local config = GameConfig.MINIGAMES.RaidRebuild
	finish(
		player,
		session,
		session.CorrectTotal / math.max(session.RequiredTotal, 1),
		session.RoundsCleared,
		config.Rounds,
		session.RoundsCleared == config.Rounds
	)
end

local function flashRound(player: Player, session: Session, round: number)
	local config = GameConfig.MINIGAMES.RaidRebuild
	local length = raidRoundLength(round)
	session.Round = round
	session.AwaitingInput = true
	session.FlashEndsAt = os.clock() + RAID_LEAD_IN + length * config.StepSeconds
	session.InputDeadline = session.FlashEndsAt + length * config.InputSecondsPerStep + config.InputGrace
	send(player, "Flash", {
		Round = round,
		Steps = table.move(session.Sequence, 1, length, 1, {}),
		StepSeconds = config.StepSeconds,
		LeadIn = RAID_LEAD_IN,
		InputSeconds = session.InputDeadline - session.FlashEndsAt,
	})
end

local function startRaid(player: Player, session: Session)
	local config = GameConfig.MINIGAMES.RaidRebuild
	session.Sequence = RaidRebuild.Generate(config.Bays, raidRoundLength(config.Rounds), nextNumber)
	session.RequiredTotal = 0
	for round = 1, config.Rounds do
		session.RequiredTotal += raidRoundLength(round)
	end
	RemoteManager.FireClient(RemoteNames.MinigameStart, player, "RaidRebuild", { Bays = config.Bays, Rounds = config.Rounds })
	flashRound(player, session, 1)
end

local function onRaidRound(player: Player, session: Session, inputs: any)
	if not session.AwaitingInput or type(inputs) ~= "table" or #inputs > MAX_RAID_INPUTS then
		return
	end
	local config = GameConfig.MINIGAMES.RaidRebuild
	session.AwaitingInput = false
	local length = raidRoundLength(session.Round)
	local result = RaidRebuild.JudgeRound(session.Sequence, length, inputs)
	if not RaidRebuild.IsPlausible(session.FlashEndsAt, os.clock(), #inputs, config.MinSecondsPerInput) then
		result = { Correct = 0, Perfect = false } -- answered before the flash finished or faster than humanly possible
	end
	session.CorrectTotal += result.Correct
	send(player, "RoundResult", { Round = session.Round, Correct = result.Correct, Perfect = result.Perfect })

	if not result.Perfect then
		finishRaid(player, session)
		return
	end
	session.RoundsCleared += 1
	if session.Round >= config.Rounds then
		finishRaid(player, session)
		return
	end
	local nextRound = session.Round + 1
	task.delay(NEXT_STEP_DELAY, function()
		if not session.Finished and sessions[player] == session then
			flashRound(player, session, nextRound)
		end
	end)
end

-- Training Run -------------------------------------------------------------

local function finishTraining(player: Player, session: Session)
	local count = #session.Epochs
	finish(player, session, session.HitSum / math.max(count, 1), session.Hits, count, session.HitSum >= count)
end

local function openEpoch(player: Player, session: Session, index: number)
	local config = GameConfig.MINIGAMES.TrainingRun
	local epoch = session.Epochs[index]
	session.EpochIndex = index
	session.EpochOpen = true
	session.EpochSentAt = os.clock()
	send(player, "Epoch", {
		Index = index,
		Speed = epoch.Speed,
		Phase = epoch.Phase,
		ZoneCenter = epoch.ZoneCenter,
		ZoneWidth = epoch.ZoneWidth,
		Seconds = config.EpochSeconds,
	})
end

local function resolveEpoch(player: Player, session: Session, hit: TrainingRun.Hit, needle: number?)
	session.EpochOpen = false
	session.HitSum += TrainingRun.Value(hit)
	if hit ~= "Miss" then
		session.Hits += 1
	end
	send(player, "EpochResult", { Index = session.EpochIndex, Hit = hit, Needle = needle })
	if session.EpochIndex >= #session.Epochs then
		task.delay(0.4, function()
			finishTraining(player, session)
		end)
		return
	end
	local nextIndex = session.EpochIndex + 1
	task.delay(NEXT_STEP_DELAY, function()
		if not session.Finished and sessions[player] == session then
			openEpoch(player, session, nextIndex)
		end
	end)
end

local function startTraining(player: Player, session: Session)
	local config = GameConfig.MINIGAMES.TrainingRun
	for _, epochConfig in config.Epochs do
		table.insert(session.Epochs, {
			Speed = epochConfig.Speed,
			Phase = rng:NextNumber() * 2 * math.pi,
			ZoneCenter = 0.2 + rng:NextNumber() * 0.6,
			ZoneWidth = epochConfig.ZoneWidth,
		})
	end
	RemoteManager.FireClient(RemoteNames.MinigameStart, player, "TrainingRun", { EpochCount = #session.Epochs })
	openEpoch(player, session, 1)
end

local function onTrainingPress(player: Player, session: Session, offset: any)
	if not session.EpochOpen or type(offset) ~= "number" or offset ~= offset then
		return
	end
	local config = GameConfig.MINIGAMES.TrainingRun
	local epoch = session.Epochs[session.EpochIndex]
	local serverElapsed = os.clock() - session.EpochSentAt
	if not TrainingRun.IsPlausibleOffset(offset, serverElapsed, config.MaxLag, config.Lead) then
		resolveEpoch(player, session, "Miss", nil)
		return
	end
	resolveEpoch(player, session, TrainingRun.JudgePress(epoch, offset), TrainingRun.NeedleAt(epoch, offset))
end

-- Shared -------------------------------------------------------------------

local function watch(player: Player, session: Session)
	while not session.Finished and sessions[player] == session do
		task.wait(WATCH_SECONDS)
		local now = os.clock()
		if session.Kind == "PatchPanel" then
			if now > session.StartedAt + GameConfig.MINIGAMES.PatchPanel.TimeLimit + PATCH_GRACE then
				finishPatch(player, session)
			end
		elseif session.Kind == "RaidRebuild" then
			if session.AwaitingInput and now > session.InputDeadline then
				onRaidRound(player, session, {}) -- ran out of time: counts as a wrong answer
			end
		elseif session.Kind == "TrainingRun" then
			if session.EpochOpen and now - session.EpochSentAt > GameConfig.MINIGAMES.TrainingRun.EpochSeconds then
				resolveEpoch(player, session, "Miss", nil)
			end
		end
	end
end

local function onStation(player: Player, part: BasePart)
	local component = part:GetAttribute("Component")
	if type(component) ~= "string" then
		return
	end
	local kind = GameConfig.STATION_MINIGAMES[component]
	if kind == nil or kind == "Typing" then
		return -- typing stations belong to BurstService
	end
	if not StartupDataModule.GetSnapshot(player) or StartupDataModule.GetActivity(player) ~= "Idle" then
		return
	end
	if not AssemblyService.GetActiveJob(player) then
		RemoteManager.FireClient(RemoteNames.Notice, player, "Pick up a job on your phone first.")
		return
	end

	local session: Session = {
		Kind = kind,
		Component = component,
		StartedAt = os.clock(),
		Finished = false,
		Puzzle = nil,
		Rotations = {},
		Sequence = {},
		Round = 0,
		AwaitingInput = false,
		FlashEndsAt = 0,
		InputDeadline = 0,
		CorrectTotal = 0,
		RequiredTotal = 0,
		RoundsCleared = 0,
		Epochs = {},
		EpochIndex = 0,
		EpochSentAt = 0,
		EpochOpen = false,
		HitSum = 0,
		Hits = 0,
	}
	sessions[player] = session
	StartupDataModule.SetActivity(player, "Burst")

	if kind == "PatchPanel" then
		startPatch(player, session)
	elseif kind == "RaidRebuild" then
		startRaid(player, session)
	else
		startTraining(player, session)
	end
	task.spawn(watch, player, session)
end

local function onAction(player: Player, action: any, data: any)
	local session = sessions[player]
	if not session or session.Finished or type(action) ~= "string" then
		return
	end
	if action == "Rotate" and session.Kind == "PatchPanel" then
		onPatchRotate(player, session, data)
	elseif action == "Round" and session.Kind == "RaidRebuild" then
		onRaidRound(player, session, data)
	elseif action == "Press" and session.Kind == "TrainingRun" then
		onTrainingPress(player, session, data)
	end
end

function MinigameService.Init() end

function MinigameService.Start()
	PlotService.OnPromptTriggered("Station", onStation)
	RemoteManager.Listen(RemoteNames.MinigameAction, onAction, ACTION_RATE_LIMIT, 1)
	-- Leaving mid-game discards it: nothing is added and the activity lock dies with the session.
	Players.PlayerRemoving:Connect(function(player: Player)
		local session = sessions[player]
		if session then
			session.Finished = true
			sessions[player] = nil
		end
	end)
end

return MinigameService
