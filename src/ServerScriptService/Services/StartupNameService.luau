--!strict
-- Naming the startup: cheap prechecks, then Roblox's text filter, then the save and the office sign.
-- Every name is shown to other players on the sign, so it is always filtered for broadcast.
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

local StartupNameService = {}

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

function StartupNameService.Init() end

function StartupNameService.Start()
	RemoteManager.Listen(RemoteNames.SetStartupName, onSetName, 2, 3)
	PlotService.OnPromptTriggered("StartupSign", onStartupSign)
end

return StartupNameService
