--!strict
-- The one StateSync listener on the client. Roblox hands events queued before anyone listened to the first
-- connection only, so every controller reads the server's public save view through here. Main.client requires
-- this before any controller, so the connection exists as early as possible.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))

export type View = { [string]: any }

local ClientState = {}

local latest: View? = nil
local callbacks: { (View) -> () } = {}

-- The latest view, or nil before the first sync.
function ClientState.Get(): View?
	return latest
end

-- Calls back on every sync, and right away with the latest view if one has arrived.
function ClientState.OnChanged(callback: (View) -> ())
	table.insert(callbacks, callback)
	if latest then
		task.spawn(callback, latest)
	end
end

RemoteManager.GetRemote(RemoteNames.StateSync).OnClientEvent:Connect(function(view: any)
	if type(view) ~= "table" then
		return
	end
	latest = view
	for _, callback in callbacks do
		task.spawn(callback, view) -- one failing listener can't stop the others
	end
end)

return ClientState
