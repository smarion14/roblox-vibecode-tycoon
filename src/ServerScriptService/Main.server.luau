--!strict
-- Server bootstrap: creates every remote, then Init and Start on each service, then begins loading players.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

type Service = { Init: () -> (), Start: () -> () }

local RemoteNames = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RemoteNames"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local StartupDataModule = require(ServerScriptService:WaitForChild("Components"):WaitForChild("StartupDataModule"))

-- Created up front so clients can wait for them before the server first fires one.
for _, remoteName in RemoteNames :: { [string]: string } do
	RemoteManager.GetRemote(remoteName)
end

local services: { Service } = {}
for _, child in ServerScriptService:WaitForChild("Services"):GetChildren() do
	if child:IsA("ModuleScript") then
		table.insert(services, require(child) :: any)
	end
end

for _, service in services do
	service.Init()
end
for _, service in services do
	service.Start()
end

StartupDataModule.Start()
