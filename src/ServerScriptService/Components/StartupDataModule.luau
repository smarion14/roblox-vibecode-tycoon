--!strict
-- Owns every player's save for the session: loads with a session lock, autosaves, and saves on leave/shutdown.
-- All game state changes go through Update so they are marked dirty and synced to the owning client.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local SaveSchema = require(Shared:WaitForChild("SaveSchema"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))

export type PlayerSave = SaveSchema.PlayerSave
export type Activity = "Idle" | "Burst" | "Battle"

type Session = {
	Save: PlayerSave,
	Dirty: boolean,
	Activity: Activity,
}

local SAVE_CONFIG = GameConfig.SAVE
local LOAD_FAILED_MESSAGE = "Couldn't load your save. Please rejoin."

local StartupDataModule = {}

local sessions: { [Player]: Session } = {}
local loadedCallbacks: { (player: Player) -> () } = {}
local store: DataStore? = nil

local function sortedKeys(map: { [string]: any }): { string }
	local keys: { string } = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local catalog: SaveSchema.SaveCatalog = {
	Components = GameConfig.COMPONENTS,
	GearIds = sortedKeys(GameConfig.GEAR),
	HireIds = sortedKeys(GameConfig.HIRES),
	StartingValuation = GameConfig.STARTING_VALUATION,
}

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value :: any do
		copy[key] = deepCopy(child)
	end
	return copy :: any
end

local function keyFor(player: Player): string
	return SAVE_CONFIG.KeyPrefix .. tostring(player.UserId)
end

local function getStore(): DataStore
	if not store then
		store = DataStoreService:GetDataStore(SAVE_CONFIG.DataStoreName)
	end
	return store :: DataStore
end

local function publicView(save: PlayerSave): { [string]: any }
	local view = deepCopy(save) :: any
	view.LockJobId = nil
	view.LockTime = nil
	return view
end

local function sync(player: Player)
	local session = sessions[player]
	if session then
		RemoteManager.FireClient(RemoteNames.StateSync, player, publicView(session.Save))
	end
end

-- Returns the claimed save, "Conflict" when another live server holds the lock, or "Error" on a DataStore failure.
local function attemptLoad(player: Player): PlayerSave | "Conflict" | "Error"
	local claimed: PlayerSave? = nil
	local ok = pcall(function()
		getStore():UpdateAsync(keyFor(player), function(raw: any): any
			claimed = nil
			local save = if SaveSchema.ResolveLoad(true, raw) == "UseDefault"
				then SaveSchema.Default(catalog)
				else SaveSchema.Sanitize(raw, catalog)
			if not SaveSchema.TryClaimLock(save, game.JobId, os.time(), SAVE_CONFIG.LockStaleAfter) then
				return nil -- cancels the write; another server still owns this save
			end
			claimed = save
			return save
		end)
	end)

	if SaveSchema.ResolveLoad(ok, true) == "Fail" then
		return "Error"
	end
	return claimed or "Conflict"
end

-- Writes the session save. Refuses to overwrite a save another server has since claimed.
local function writeSave(player: Player, release: boolean): boolean
	local session = sessions[player]
	if not session then
		return true
	end

	local snapshot = deepCopy(session.Save)
	snapshot.LockJobId = if release then nil else game.JobId
	snapshot.LockTime = os.time()

	local ok, err = pcall(function()
		getStore():UpdateAsync(keyFor(player), function(raw: any): any
			if type(raw) == "table" and raw.LockJobId ~= nil and raw.LockJobId ~= game.JobId then
				return nil
			end
			return snapshot
		end)
	end)

	if ok then
		session.Dirty = false
	else
		warn(`[StartupDataModule] save failed for {player.UserId}: {err}`)
	end
	return ok
end

local function onPlayerAdded(player: Player)
	for attempt = 1, SAVE_CONFIG.MaxLoadRetries do
		local result = attemptLoad(player)
		if type(result) == "table" then
			if player.Parent == nil then
				-- Left while loading: hand the lock straight back without starting a session.
				sessions[player] = { Save = result, Dirty = false, Activity = "Idle" }
				writeSave(player, true)
				sessions[player] = nil
				return
			end

			sessions[player] = { Save = result, Dirty = false, Activity = "Idle" }
			sync(player)
			for _, callback in loadedCallbacks do
				task.spawn(callback, player)
			end
			return
		end

		if attempt < SAVE_CONFIG.MaxLoadRetries then
			task.wait(2 ^ attempt)
		end
	end

	-- Never play on default data after a failed load: a later save would overwrite the real one.
	player:Kick(LOAD_FAILED_MESSAGE)
end

local function onPlayerRemoving(player: Player)
	if sessions[player] then
		writeSave(player, true)
		sessions[player] = nil
	end
end

function StartupDataModule.GetCatalog(): SaveSchema.SaveCatalog
	return catalog
end

function StartupDataModule.OnPlayerLoaded(callback: (player: Player) -> ())
	table.insert(loadedCallbacks, callback)
	for player in sessions do
		task.spawn(callback, player)
	end
end

function StartupDataModule.IsLoaded(player: Player): boolean
	return sessions[player] ~= nil
end

function StartupDataModule.GetSnapshot(player: Player): PlayerSave?
	local session = sessions[player]
	if not session then
		return nil
	end
	return deepCopy(session.Save)
end

function StartupDataModule.Update(player: Player, mutator: (save: PlayerSave) -> ()): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	mutator(session.Save)
	session.Dirty = true
	sync(player)
	return true
end

function StartupDataModule.GetActivity(player: Player): Activity
	local session = sessions[player]
	return if session then session.Activity else "Idle"
end

function StartupDataModule.SetActivity(player: Player, activity: Activity)
	local session = sessions[player]
	if session then
		session.Activity = activity
	end
end

function StartupDataModule.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Saves every session each interval, dirty or not, so the session lock never goes stale while playing.
	task.spawn(function()
		while true do
			task.wait(SAVE_CONFIG.AutosaveInterval)
			for player in sessions do
				task.spawn(writeSave, player, false)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player in sessions do
			pending += 1
			task.spawn(function()
				writeSave(player, true)
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait()
		end
	end)
end

return StartupDataModule
