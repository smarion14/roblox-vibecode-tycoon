--!strict
-- Act 3 incidents (spec §6): one Incidents.State per Act 3 player, ticked every 0.5 s on Workspace:GetServerTimeNow()
-- (the client reads the same clock, so Deadline is a shared timestamp). Answering at the matching IncidentDesk plays
-- that incident's minigame; the server holds the round, stamps Firewall taps, judges and resolves. Not saved: a rejoin
-- starts a fresh schedule. Other services ask IsLocked / RefuseLocked / TakeEliteWave; this module requires none of them.
--
-- Remotes:
--   IncidentState({ Kind, Deadline, LockedStation, Room } | nil)   Room: the desk's room title, e.g. "Security Desk"
--   IncidentStart(kind, roundData)
--     Breach (Firewall): { Packets = { { Id, Red, Lane, ArriveAt } }, TravelSeconds = 3.5 }
--       A packet appears TravelSeconds before ArriveAt and reaches the core at ArriveAt (seconds after IncidentStart).
--     Vulnerability (Triage): { Reports = { { Id, Text } }, TimeLimit }
--     Naysayer (ClapBack): { Posts = { { Post, Replies } }, TimeLimit }
--   IncidentAction(inputs)
--     Firewall: one call per tap, inputs = the packet Id. The server stamps At = server clock - round start and drops
--       taps on packets not yet on screen (At < ArriveAt - TravelSeconds); at most packet count + 5 taps are kept.
--       The round ends on its own one second after the last packet's ArriveAt.
--     Triage: one call, inputs = { [reportId]: "Critical" | "Minor" | "NotABug" }
--     ClapBack: one call, inputs = { [postIndex]: replyIndex }
--   IncidentResult(grade, repDelta, newRep)
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClapBack = require(Shared:WaitForChild("ClapBack"))
local Firewall = require(Shared:WaitForChild("Firewall"))
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Incidents = require(Shared:WaitForChild("Incidents"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local Reputation = require(Shared:WaitForChild("Reputation"))
local Story = require(Shared:WaitForChild("Story"))
local StoryText = require(Shared:WaitForChild("StoryText"))
local Triage = require(Shared:WaitForChild("Triage"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local StartupDataModule = require(ServerScriptService:WaitForChild("Components"):WaitForChild("StartupDataModule"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))
local ProgressService = require(script.Parent:WaitForChild("ProgressService"))

type Response = {
	StartedAt: number,
	EndsAt: number,
	Firewall: Firewall.Round?,
	Triage: Triage.Round?,
	ClapBack: ClapBack.Round?,
	Taps: { Firewall.Tap },
	Finished: boolean,
}
type PlayerState = { Incidents: Incidents.State, Response: Response? }

local CONFIG = GameConfig.INCIDENTS
local TICK_SECONDS = 0.5
local WATCH_SECONDS = 0.2
local ACTION_RATE_LIMIT = 15
local FIREWALL_TRAVEL_SECONDS = 3.5
local FIREWALL_EXTRA_TAPS = 5
local FIREWALL_END_SLACK = 1
local ROUND_LEAD_IN = 2
local TRIAGE_SECONDS_PER_REPORT = 2.5
local CLAPBACK_SECONDS_PER_POST = 6
local LATENCY_GRACE = 1
local MAX_ANSWERS = 32
local TRIAGE_ANSWERS: { [string]: boolean } = { Critical = true, Minor = true, NotABug = true }

local IncidentService = {}

local states: { [Player]: PlayerState } = {}
local rng = Random.new()

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function nextNumber(): number
	return rng:NextNumber()
end

local function isFreePlay(save: StartupDataModule.PlayerSave): boolean
	return save.StoryFlags.FinaleSeen == true
end

local function notice(player: Player, text: string)
	RemoteManager.FireClient(RemoteNames.Notice, player, text)
end

-- No incident starts during a minigame, battle or owed cutscene.
local function isBusy(player: Player, save: StartupDataModule.PlayerSave): boolean
	local story = { Act = save.Act, SeenIntro = save.SeenIntro, RentPaid = save.RentPaid, Flags = save.StoryFlags }
	return StartupDataModule.GetActivity(player) ~= "Idle" or Story.NextBeat(story) ~= nil
end

local function taggedInUnit(player: Player, tag: string): { BasePart }
	local found: { BasePart } = {}
	local unit = PlotService.GetUnitModel(player)
	if unit then
		for _, instance in CollectionService:GetTagged(tag) do
			if instance:IsA("BasePart") and instance:IsDescendantOf(unit) then
				table.insert(found, instance)
			end
		end
	end
	return found
end

local function roomTitle(player: Player, kind: string): string
	for _, desk in taggedInUnit(player, "IncidentDesk") do
		local prompt = desk:FindFirstChildOfClass("ProximityPrompt")
		if desk:GetAttribute("Kind") == kind and prompt then
			return prompt.ObjectText
		end
	end
	return kind
end

-- The client spins lights with Active set; the PointLight is the glow itself.
local function setLights(player: Player, kind: string?)
	for _, light in taggedInUnit(player, "IncidentLight") do
		local on = kind ~= nil and light:GetAttribute("Kind") == kind
		light:SetAttribute("Active", on)
		local glow = light:FindFirstChildOfClass("PointLight")
		if glow then
			glow.Enabled = on
		end
	end
end

local function sendState(player: Player, ps: PlayerState)
	local active = ps.Incidents.Active
	if active then
		RemoteManager.FireClient(RemoteNames.IncidentState, player, {
			Kind = active.Kind,
			Deadline = active.Deadline,
			LockedStation = active.LockedStation,
			Room = roomTitle(player, active.Kind),
		})
		setLights(player, active.Kind)
	else
		RemoteManager.FireClient(RemoteNames.IncidentState, player, nil)
		setLights(player, nil)
	end
end

local function applyReputation(player: Player, delta: number)
	if delta ~= 0 then
		StartupDataModule.Update(player, function(current)
			current.Reputation = Reputation.Apply(current.Reputation, delta)
		end)
	end
end

local function ignoredNotice(player: Player, kind: string?, station: string?, repDelta: number)
	if kind == "Breach" then
		local name = if station then GameConfig.STATION_NAMES[station] else "a station"
		notice(player, `Breach ignored: the {name} is locked for {CONFIG.LockSeconds}s. Reputation {repDelta}.`)
	elseif kind == "Vulnerability" then
		notice(player, `Vulnerability report ignored: your next deploy faces an extra elite wave. Reputation {repDelta}.`)
	else
		notice(player, "Naysayer storm ignored: your reputation is draining.")
	end
end

local function tickPlayer(player: Player)
	local save = StartupDataModule.GetSnapshot(player)
	if not save or save.Act < 3 then
		return
	end
	local freePlay = isFreePlay(save)
	local ps = states[player]
	if not ps then
		ps = { Incidents = Incidents.New(now(), nextNumber, freePlay, CONFIG), Response = nil }
		states[player] = ps
	end
	if ps.Response then
		return -- the incident being answered can neither expire nor be replaced mid-minigame
	end
	local before = ps.Incidents.Active
	local events = Incidents.Tick(ps.Incidents, now(), isBusy(player, save), nextNumber, freePlay, save.Hires, CONFIG, GameConfig.COMPONENTS)
	local repDelta = 0
	local changed = false
	for _, event in events do
		repDelta += event.RepDelta or 0
		if event.Type ~= "Drain" then
			changed = true
		end
		if event.Type == "Ignored" then
			ignoredNotice(player, event.Kind, before and before.LockedStation, event.RepDelta or 0)
		elseif event.Type == "AutoCleared" then
			notice(player, "Your Security Engineer contained the breach.")
		end
	end
	applyReputation(player, repDelta)
	if changed then
		sendState(player, ps)
	end
end

local function finish(player: Player, ps: PlayerState, response: Response, answers: { [number]: any })
	if response.Finished or ps.Response ~= response or states[player] ~= ps then
		return
	end
	response.Finished = true
	ps.Response = nil

	local grade: string
	if response.Firewall then
		local result = Firewall.Judge(response.Firewall, response.Taps)
		grade = Firewall.Grade(result.Correct, result.Total)
	elseif response.Triage then
		local result = Triage.Judge(response.Triage, answers)
		grade = Triage.Grade(result.Correct, result.Total)
	else
		local result = ClapBack.Judge(response.ClapBack :: ClapBack.Round, answers)
		grade = ClapBack.Grade(result.Correct, result.Total)
	end

	local save = StartupDataModule.GetSnapshot(player)
	local repDelta = Incidents.Resolve(ps.Incidents, now(), grade, nextNumber, save ~= nil and isFreePlay(save), CONFIG)
	local newRep = if save then save.Reputation else 0
	StartupDataModule.Update(player, function(current)
		current.Reputation = Reputation.Apply(current.Reputation, repDelta)
		current.StoryFlags.IncidentHandled = true
		newRep = current.Reputation
	end)
	StartupDataModule.SetActivity(player, "Idle")
	RemoteManager.FireClient(RemoteNames.IncidentResult, player, grade, repDelta, newRep)
	sendState(player, ps)
	ProgressService.CheckMilestones(player)
end

local function onDesk(player: Player, desk: BasePart)
	local kind = desk:GetAttribute("Kind")
	local save = StartupDataModule.GetSnapshot(player)
	local ps = states[player]
	if type(kind) ~= "string" or not save or save.Act < 3 or not ps or ps.Response then
		return
	end
	if StartupDataModule.GetActivity(player) ~= "Idle" then
		return
	end
	local active = ps.Incidents.Active
	if not active or active.Kind ~= kind then
		notice(player, "All quiet here. Nothing to respond to.")
		return
	end

	local startedAt = now()
	local response: Response = {
		StartedAt = startedAt,
		EndsAt = 0,
		Firewall = nil,
		Triage = nil,
		ClapBack = nil,
		Taps = {},
		Finished = false,
	}
	local roundData: { [string]: any }
	if kind == "Breach" then
		local round = Firewall.New(nextNumber)
		local lastArrival = 0
		for _, packet in round.Packets do
			lastArrival = math.max(lastArrival, packet.ArriveAt)
		end
		response.Firewall = round
		response.EndsAt = startedAt + lastArrival + FIREWALL_END_SLACK
		roundData = { Packets = round.Packets, TravelSeconds = FIREWALL_TRAVEL_SECONDS }
	elseif kind == "Vulnerability" then
		local round = Triage.New(nextNumber, { Short = save.Hires.QAManager == true, Bank = StoryText.TRIAGE_REPORTS })
		local reports = {}
		for _, report in round.Reports do
			table.insert(reports, { Id = report.Id, Text = report.Text }) -- never the answer
		end
		local timeLimit = ROUND_LEAD_IN + #reports * TRIAGE_SECONDS_PER_REPORT
		response.Triage = round
		response.EndsAt = startedAt + timeLimit + LATENCY_GRACE
		roundData = { Reports = reports, TimeLimit = timeLimit }
	else
		local round = ClapBack.New(nextNumber, { Short = save.Hires.PRLead == true, Bank = StoryText.CLAPBACK_POSTS })
		local posts = {}
		for _, post in round.Posts do
			table.insert(posts, { Post = post.Post, Replies = post.Replies }) -- never the best index
		end
		local timeLimit = ROUND_LEAD_IN + #posts * CLAPBACK_SECONDS_PER_POST
		response.ClapBack = round
		response.EndsAt = startedAt + timeLimit + LATENCY_GRACE
		roundData = { Posts = posts, TimeLimit = timeLimit }
	end

	ps.Response = response
	StartupDataModule.SetActivity(player, "Burst")
	RemoteManager.FireClient(RemoteNames.IncidentStart, player, kind, roundData)
	task.spawn(function()
		while not response.Finished and ps.Response == response do
			task.wait(WATCH_SECONDS)
			if now() > response.EndsAt then
				finish(player, ps, response, {}) -- Firewall's natural end; a timed-out answer sheet counts as blank
			end
		end
	end)
end

-- Client answer maps arrive with number or string keys; keep at most MAX_ANSWERS well-formed entries.
local function cleanAnswers(inputs: any, isValid: (value: any) -> boolean): { [number]: any }
	local clean: { [number]: any } = {}
	if type(inputs) ~= "table" then
		return clean
	end
	local seen = 0
	for key, value in inputs do
		seen += 1
		if seen > MAX_ANSWERS then
			break
		end
		local index = tonumber(key)
		if index and index % 1 == 0 and isValid(value) then
			clean[index] = value
		end
	end
	return clean
end

local function isTriageAnswer(value: any): boolean
	return type(value) == "string" and TRIAGE_ANSWERS[value] == true
end

local function isReplyIndex(value: any): boolean
	return type(value) == "number" and value % 1 == 0
end

local function onAction(player: Player, inputs: any)
	local ps = states[player]
	local response = ps and ps.Response
	if not ps or not response or response.Finished then
		return
	end
	local round = response.Firewall
	if round then
		local packet = if type(inputs) == "number" then round.Packets[inputs] else nil
		if not packet or #response.Taps >= #round.Packets + FIREWALL_EXTRA_TAPS then
			return
		end
		local at = now() - response.StartedAt
		if at < packet.ArriveAt - FIREWALL_TRAVEL_SECONDS then
			return -- the packet isn't on screen yet
		end
		table.insert(response.Taps, { Id = packet.Id, At = at })
	elseif response.Triage then
		finish(player, ps, response, cleanAnswers(inputs, isTriageAnswer))
	else
		finish(player, ps, response, cleanAnswers(inputs, isReplyIndex))
	end
end

function IncidentService.IsLocked(player: Player, station: string): boolean
	local ps = states[player]
	return ps ~= nil and Incidents.IsLocked(ps.Incidents, station, now())
end

-- Station prompts call this first: true, with a notice, while a breach has the station locked.
function IncidentService.RefuseLocked(player: Player, station: string): boolean
	local ps = states[player]
	if not ps or not Incidents.IsLocked(ps.Incidents, station, now()) then
		return false
	end
	local left = math.ceil(ps.Incidents.Locks[station] - now())
	notice(player, `Station locked by a breach — {left}s left`)
	return true
end

-- Pending elite half-waves for the next deploy battle (0, 1 or 2), consumed by the call.
function IncidentService.TakeEliteWave(player: Player): number
	local ps = states[player]
	if not ps then
		return 0
	end
	local halves = math.min(ps.Incidents.EliteWaves, 2)
	Incidents.TakeEliteWave(ps.Incidents)
	return halves
end

function IncidentService.Init() end

function IncidentService.Start()
	PlotService.OnPromptTriggered("IncidentDesk", onDesk)
	RemoteManager.Listen(RemoteNames.IncidentAction, onAction, ACTION_RATE_LIMIT, 1)
	-- Leaving drops the incident and any round in progress; the activity lock dies with the session.
	Players.PlayerRemoving:Connect(function(player: Player)
		local ps = states[player]
		local response = ps and ps.Response
		if response then
			response.Finished = true
		end
		states[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(function()
					tickPlayer(player)
				end)
				if not ok then
					warn(`IncidentService: tick failed: {err}`)
				end
			end
		end
	end)
end

return IncidentService
