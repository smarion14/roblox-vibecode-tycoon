--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local REMOTE_FOLDER_NAME = "Remotes"
local DEFAULT_MAX_CALLS = 10
local DEFAULT_WINDOW_SECONDS = 1
local CLIENT_WAIT_TIMEOUT_SECONDS = 10

type RateState = {
	windowStart: number,
	count: number,
}

export type ServerHandler = (player: Player, ...any) -> ()

local RemoteManager = {}

local remoteFolder: Folder? = nil
local rateStates: { [string]: { [Player]: RateState } } = {}

local function getRemoteFolder(): Folder
	if remoteFolder then
		return remoteFolder
	end

	local parent = script.Parent :: Instance
	local folder: Folder
	if RunService:IsServer() then
		local existing = parent:FindFirstChild(REMOTE_FOLDER_NAME)
		if existing then
			folder = existing :: Folder
		else
			folder = Instance.new("Folder")
			folder.Name = REMOTE_FOLDER_NAME
			folder.Parent = parent
		end
	else
		folder = parent:WaitForChild(REMOTE_FOLDER_NAME, CLIENT_WAIT_TIMEOUT_SECONDS) :: Folder
		assert(folder, "RemoteManager: Remotes folder never replicated")
	end

	remoteFolder = folder
	return folder
end

-- Server creates the RemoteEvent on first request; the client waits for it to replicate.
function RemoteManager.GetRemote(name: string): RemoteEvent
	local folder = getRemoteFolder()
	local existing = folder:FindFirstChild(name)
	if existing then
		assert(existing:IsA("RemoteEvent"), `RemoteManager: "{name}" exists but is not a RemoteEvent`)
		return existing
	end

	if RunService:IsServer() then
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		return remote
	end

	local waited = folder:WaitForChild(name, CLIENT_WAIT_TIMEOUT_SECONDS)
	assert(waited and waited:IsA("RemoteEvent"), `RemoteManager: RemoteEvent "{name}" never replicated`)
	return waited
end

-- Server only. Calls over maxCalls inside one windowSeconds window are silently dropped.
function RemoteManager.Listen(
	name: string,
	handler: ServerHandler,
	maxCalls: number?,
	windowSeconds: number?
): RBXScriptConnection
	assert(RunService:IsServer(), "RemoteManager.Listen is server only")

	local limit = maxCalls or DEFAULT_MAX_CALLS
	local window = windowSeconds or DEFAULT_WINDOW_SECONDS
	local playerStates: { [Player]: RateState } = rateStates[name] or {}
	rateStates[name] = playerStates

	return RemoteManager.GetRemote(name).OnServerEvent:Connect(function(player: Player, ...: any)
		local now = os.clock()
		local state = playerStates[player]
		if not state or now - state.windowStart >= window then
			playerStates[player] = { windowStart = now, count = 1 }
		elseif state.count >= limit then
			return
		else
			state.count += 1
		end

		handler(player, ...)
	end)
end

function RemoteManager.FireClient(name: string, player: Player, ...: any)
	assert(RunService:IsServer(), "RemoteManager.FireClient is server only")
	RemoteManager.GetRemote(name):FireClient(player, ...)
end

function RemoteManager.FireAllClients(name: string, ...: any)
	assert(RunService:IsServer(), "RemoteManager.FireAllClients is server only")
	RemoteManager.GetRemote(name):FireAllClients(...)
end

function RemoteManager.FireServer(name: string, ...: any)
	assert(RunService:IsClient(), "RemoteManager.FireServer is client only")
	RemoteManager.GetRemote(name):FireServer(...)
end

if RunService:IsServer() then
	Players.PlayerRemoving:Connect(function(player: Player)
		for _, playerStates in rateStates do
			playerStates[player] = nil
		end
	end)
end

return RemoteManager
