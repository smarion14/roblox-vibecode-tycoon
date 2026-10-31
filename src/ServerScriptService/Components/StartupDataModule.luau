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
	Activity: Activity,
	Released: boolean,
}

local SAVE_CONFIG = GameConfig.SAVE
local LOAD_FAILED_MESSAGE = "Couldn't load your save. Please rejoin."
local RELEASE_ATTEMPTS = 3

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
	-- Interns and Act 3 key hires share save.Hires; both must survive the load sanitizer.
	HireIds = (function(): { string }
		local ids = sortedKeys(GameConfig.HIRES)
		for _, id in sortedKeys(GameConfig.KEY_HIRES) do
			table.insert(ids, id)
		end
		return ids
	end)(),
	ClientIds = (function(): { string }
		local ids: { string } = {}
		for _, client in GameConfig.CLIENTS do
			table.insert(ids, client.Id)
		end
		return ids
	end)(),
	DecorIds = sortedKeys(GameConfig.DECOR),
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

-- Writes a session's save. Refuses to overwrite a save another server has since claimed, and a periodic
-- write that lands after the session was released is cancelled so it can't re-lock the save.
local function writeSave(player: Player, session: Session, release: boolean): boolean
	local snapshot = deepCopy(session.Save)
	snapshot.LockJobId = if release then nil else game.JobId
	snapshot.LockTime = os.time()

	local ok, err = pcall(function()
		getStore():UpdateAsync(keyFor(player), function(raw: any): any
			if not release and session.Released then
				return nil
			end
			if type(raw) == "table" and raw.LockJobId ~= nil and raw.LockJobId ~= game.JobId then
				return nil
			end
			return snapshot
		end)
	end)

	if not ok then
		warn(`[StartupDataModule] save failed for {player.UserId}: {err}`)
	end
	return ok
end

-- Ends a session: removes it first so no autosave can follow, then saves and frees the lock, with retries.
local function releaseSession(player: Player, session: Session)
	session.Released = true
	if sessions[player] == session then
		sessions[player] = nil
	end
	for attempt = 1, RELEASE_ATTEMPTS do
		if writeSave(player, session, true) then
			return
		end
		if attempt < RELEASE_ATTEMPTS then
			task.wait(attempt)
		end
	end
end

local function onPlayerAdded(player: Player)
	for attempt = 1, SAVE_CONFIG.MaxLoadRetries do
		local result = attemptLoad(player)
		if type(result) == "table" then
			if player.Parent == nil then
				-- Left while loading: hand the lock straight back without starting a session.
				releaseSession(player, { Save = result, Activity = "Idle", Released = false })
				return
			end

			sessions[player] = { Save = result, Activity = "Idle", Released = false }
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
	local session = sessions[player]
	if session then
		releaseSession(player, session)
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
	-- Replicated so the client can hold the character still while a minigame or battle has the keyboard.
	player:SetAttribute("Activity", activity)
end

function StartupDataModule.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- Saves every session each interval so the session lock never goes stale while playing.
	task.spawn(function()
		while true do
			task.wait(SAVE_CONFIG.AutosaveInterval)
			for player, session in sessions do
				task.spawn(writeSave, player, session, false)
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player, session in sessions do
			pending += 1
			task.spawn(function()
				releaseSession(player, session)
				pending -= 1
			end)
		end
		while pending > 0 do
			task.wait()
		end
	end)
end

return StartupDataModule
