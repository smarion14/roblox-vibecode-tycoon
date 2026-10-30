--!strict
-- Assigns each player a unit on the megablock floor and routes world interactions to their owner only.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local StartupDataModule = require(ServerScriptService:WaitForChild("Components"):WaitForChild("StartupDataModule"))
local WorldBuilder = require(ServerScriptService:WaitForChild("World"):WaitForChild("WorldBuilder"))

local SPAWN_HEIGHT = 3
local SERVER_FULL_MESSAGE = "Server is full."
local UNTITLED_NAME = "UNTITLED STARTUP"

local PlotService = {}

local units: { Model }? = nil
local ownerOf: { [number]: Player } = {}
local unitOf: { [Player]: number } = {}
local builtCallbacks: { (player: Player) -> () } = {}

local function ensureWorld(): { Model }
	if not units then
		units = WorldBuilder.BuildFloor()
	end
	return units :: { Model }
end

local function unitIndexOf(instance: Instance): number?
	local current: Instance? = instance
	while current do
		local index = current:GetAttribute("Unit")
		if type(index) == "number" then
			return index
		end
		current = current.Parent
	end
	return nil
end

local function spawnPointFor(index: number): CFrame?
	for _, spawnPad in CollectionService:GetTagged("UnitSpawn") do
		if spawnPad:IsA("BasePart") and unitIndexOf(spawnPad) == index then
			return spawnPad.CFrame
		end
	end
	return nil
end

local function onCharacterAdded(player: Player, character: Model)
	local index = unitOf[player]
	local spawnPoint = if index then spawnPointFor(index) else nil
	if spawnPoint then
		character:PivotTo(spawnPoint + Vector3.new(0, SPAWN_HEIGHT, 0))
	end
end

-- Act 1 shows no name; from Act 2 the office sign shows the startup's name (or a placeholder until it's named).
local function signTextFor(act: number, startupName: string?): string
	if act < 2 then
		return ""
	end
	return startupName or UNTITLED_NAME
end

local function onPlayerAdded(player: Player)
	for index = 1, #ensureWorld() do
		if not ownerOf[index] then
			ownerOf[index] = player
			unitOf[player] = index
			player:SetAttribute("Unit", index)
			player.CharacterAdded:Connect(function(character: Model)
				onCharacterAdded(player, character)
			end)
			if player.Character then
				onCharacterAdded(player, player.Character)
			end
			return
		end
	end
	player:Kick(SERVER_FULL_MESSAGE)
end

local function onPlayerRemoving(player: Player)
	local index = unitOf[player]
	if index then
		ownerOf[index] = nil
		unitOf[player] = nil
		player:SetAttribute("Unit", nil)
		-- The next owner starts from an empty Act 1 homelab until their save says otherwise.
		local unit = ensureWorld()[index]
		WorldBuilder.BuildContents(unit, 1)
		WorldBuilder.SetSignText(unit, "")
	end
end

-- Builds the owner's saved act once their data has loaded.
local function onPlayerLoaded(player: Player)
	local save = StartupDataModule.GetSnapshot(player)
	if save and unitOf[player] then
		PlotService.RebuildUnit(player, save.Act)
	end
end

function PlotService.GetUnitIndex(player: Player): number?
	return unitOf[player]
end

function PlotService.GetUnitModel(player: Player): Model?
	local index = unitOf[player]
	return if index then ensureWorld()[index] else nil
end

-- Swaps the player's unit contents to an act's layout and refreshes the sign. Prompts rebind on their own.
function PlotService.RebuildUnit(player: Player, act: number)
	local unit = PlotService.GetUnitModel(player)
	if not unit then
		return
	end
	WorldBuilder.BuildContents(unit, act)
	local save = StartupDataModule.GetSnapshot(player)
	WorldBuilder.SetSignText(unit, signTextFor(act, if save then save.StartupName else nil))
	for _, callback in builtCallbacks do
		task.spawn(callback, player)
	end
end

-- Runs after a player's unit contents are rebuilt, so per-player prompt labels can be reapplied.
function PlotService.OnUnitBuilt(callback: (player: Player) -> ())
	table.insert(builtCallbacks, callback)
end

function PlotService.IsOwnPrompt(player: Player, prompt: ProximityPrompt): boolean
	local index = unitIndexOf(prompt)
	return index ~= nil and unitOf[player] == index
end

-- Server-side Triggered: Roblox checks the player's distance, so this is a trusted physical interaction.
-- Binds current and future tagged parts, since unit contents are rebuilt per owner and per act. A destroyed
-- part takes its prompt's connection with it.
function PlotService.OnPromptTriggered(tag: string, handler: (player: Player, part: BasePart) -> ())
	ensureWorld()
	local function bind(tagged: Instance)
		local prompt = tagged:FindFirstChildOfClass("ProximityPrompt")
		if not prompt or not tagged:IsA("BasePart") then
			return
		end
		prompt.Triggered:Connect(function(player: Player)
			if PlotService.IsOwnPrompt(player, prompt) then
				handler(player, tagged)
			end
		end)
	end
	for _, tagged in CollectionService:GetTagged(tag) do
		bind(tagged)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(bind)
end

function PlotService.Init()
	ensureWorld()
end

function PlotService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	StartupDataModule.OnPlayerLoaded(onPlayerLoaded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return PlotService
