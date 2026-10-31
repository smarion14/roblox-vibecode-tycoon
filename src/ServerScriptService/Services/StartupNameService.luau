--!strict
-- Naming the startup: cheap prechecks, then Roblox's text filter, then the save and the office sign.
-- Every name is shown to other players on the sign, so it is always filtered for broadcast.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local Story = require(Shared:WaitForChild("Story"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local StartupDataModule = require(ServerScriptService:WaitForChild("Components"):WaitForChild("StartupDataModule"))
local WorldBuilder = require(ServerScriptService:WaitForChild("World"):WaitForChild("WorldBuilder"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))

local FILTER_FAILED = "Couldn't check that name. Try again."
local FILTERED_OUT = "Try a different name"
local REPLAY_PROMPT = "ReplayEndingPrompt"

local StartupNameService = {}

local replayHandler: ((player: Player) -> ())? = nil

local function reply(player: Player, ok: boolean, text: string)
	RemoteManager.FireClient(RemoteNames.NameResult, player, ok, text)
end

local function onSetName(player: Player, raw: any)
	if type(raw) ~= "string" or #raw > GameConfig.MAX_REMOTE_STRING then
		return
	end
	local save = StartupDataModule.GetSnapshot(player)
	if not save or save.Act < 2 then
		return
	end
	local clean, reason = Story.PrecheckName(raw)
	if not clean then
		reply(player, false, reason or FILTERED_OUT)
		return
	end
	local ok, filtered = pcall(function(): string
		return TextService:FilterStringAsync(clean, player.UserId):GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		reply(player, false, FILTER_FAILED)
		return
	end
	-- A fully censored name comes back as all '#'.
	if not string.find(filtered, "[^#%s]") then
		reply(player, false, FILTERED_OUT)
		return
	end
	StartupDataModule.Update(player, function(current)
		current.StartupName = filtered
	end)
	local unit = PlotService.GetUnitModel(player)
	if unit then
		WorldBuilder.SetSignText(unit, filtered)
	end
	reply(player, true, filtered)
end

local function onStartupSign(player: Player)
	local save = StartupDataModule.GetSnapshot(player)
	if save and save.Act >= 2 then
		RemoteManager.FireClient(RemoteNames.OpenUI, player, "Rename", save.StartupName or "")
	end
end

-- Once the game is complete the startup sign gets a second prompt, on its own key (prompts default to one per key)
-- and offset below Rename, that replays the finale through ProgressService.
function StartupNameService.RefreshReplayPrompt(player: Player)
	local unit = PlotService.GetUnitModel(player)
	local save = StartupDataModule.GetSnapshot(player)
	if not unit or not save then
		return
	end
	for _, sign in CollectionService:GetTagged("StartupSign") do
		if not sign:IsDescendantOf(unit) then
			continue
		end
		local existing = sign:FindFirstChild(REPLAY_PROMPT)
		if save.StoryFlags.GameComplete and not existing then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = REPLAY_PROMPT
			prompt.ActionText = "Replay ending"
			prompt.ObjectText = "Startup Sign"
			prompt.KeyboardKeyCode = Enum.KeyCode.F
			prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
			prompt.UIOffset = Vector2.new(0, 72)
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 10
			prompt.RequiresLineOfSight = false
			prompt.Triggered:Connect(function(who: Player)
				if replayHandler and PlotService.IsOwnPrompt(who, prompt) then
					replayHandler(who)
				end
			end)
			prompt.Parent = sign
		elseif not save.StoryFlags.GameComplete and existing then
			existing:Destroy()
		end
	end
end

function StartupNameService.OnReplayEnding(handler: (player: Player) -> ())
	replayHandler = handler
end

function StartupNameService.Init() end

function StartupNameService.Start()
	RemoteManager.Listen(RemoteNames.SetStartupName, onSetName, 2, 3)
	PlotService.OnPromptTriggered("StartupSign", onStartupSign)
	PlotService.OnUnitBuilt(StartupNameService.RefreshReplayPrompt)
end

return StartupNameService
