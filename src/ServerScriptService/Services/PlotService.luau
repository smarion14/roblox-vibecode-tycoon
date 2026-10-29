--!strict
-- Assigns each player a unit on the megablock floor and routes world interactions to their owner only.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local WorldBuilder = require(ServerScriptService:WaitForChild("World"):WaitForChild("WorldBuilder"))

local SPAWN_HEIGHT = 3
local SERVER_FULL_MESSAGE = "Server is full."

local PlotService = {}

local units: { Model }? = nil
local ownerOf: { [number]: Player } = {}
local unitOf: { [Player]: number } = {}

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

local function onPlayerAdded(player: Player)
	for index = 1, #ensureWorld() do
		if not ownerOf[index] then
			ownerOf[index] = player
			unitOf[player] = index
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
	end
end

function PlotService.GetUnitIndex(player: Player): number?
	return unitOf[player]
end

function PlotService.IsOwnPrompt(player: Player, prompt: ProximityPrompt): boolean
	local index = unitIndexOf(prompt)
	return index ~= nil and unitOf[player] == index
end

-- Server-side Triggered: Roblox checks the player's distance, so this is a trusted physical interaction.
function PlotService.OnPromptTriggered(tag: string, handler: (player: Player, part: BasePart) -> ())
	ensureWorld()
	for _, tagged in CollectionService:GetTagged(tag) do
		local prompt = tagged:FindFirstChildOfClass("ProximityPrompt")
		if not prompt or not tagged:IsA("BasePart") then
			continue
		end
		prompt.Triggered:Connect(function(player: Player)
			if PlotService.IsOwnPrompt(player, prompt) then
				handler(player, tagged)
			end
		end)
	end
end

function PlotService.Init()
	ensureWorld()
end

function PlotService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return PlotService
