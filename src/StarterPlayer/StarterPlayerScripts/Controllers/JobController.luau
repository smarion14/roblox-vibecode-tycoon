--!strict
-- Phone job list. The server decides which clients are offered and validates the pick.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local JobController = {}

local gui: ScreenGui
local list: Frame

local function close()
	gui.Enabled = false
end

local function open(clients: any)
	if type(clients) ~= "table" then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	Theme.Text(list, "INCOMING JOBS", 18, Theme.ACCENT).LayoutOrder = 0
	for index, client in clients do
		if type(client) ~= "table" or type(client.Id) ~= "string" then
			continue
		end
		local button = Theme.Button(list, `{client.Name}  ·  pays x{client.TierMultiplier}`, 16)
		button.LayoutOrder = index
		button.Activated:Connect(function()
			RemoteManager.FireServer(RemoteNames.AcceptJob, client.Id)
			close()
		end)
	end
	local cancel = Theme.Button(list, "Close", 14)
	cancel.LayoutOrder = 1000
	cancel.Activated:Connect(close)

	gui.Enabled = true
end

function JobController.Init()
	gui = Theme.Screen("Jobs", 5)
	gui.Enabled = false
	list = Theme.Panel(gui, UDim2.fromOffset(380, 0), UDim2.fromScale(0.5, 0.3))
	list.AnchorPoint = Vector2.new(0.5, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	Theme.List(list, 8)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function JobController.Start()
	RemoteManager.GetRemote(RemoteNames.OpenUI).OnClientEvent:Connect(function(kind: any, payload: any)
		if kind == "Jobs" then
			open(payload)
		end
	end)
end

return JobController
