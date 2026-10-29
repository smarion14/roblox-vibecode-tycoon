--!strict
-- Laptop shop list. Only sends the item id; the server checks price, cash and ownership.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local ShopController = {}

local gui: ScreenGui
local list: Frame

local function close()
	gui.Enabled = false
end

local function open(items: any)
	if type(items) ~= "table" then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	Theme.Text(list, "LAPTOP · GEAR & HIRES", 18, Theme.ACCENT).LayoutOrder = 0
	for index, item in items do
		if type(item) ~= "table" or type(item.Id) ~= "string" then
			continue
		end
		local label = if item.Owned
			then `{item.Name}  ·  owned`
			else `{item.Name}  ·  ${item.Price}  ({string.lower(tostring(item.Kind))})`
		local button = Theme.Button(list, label, 15)
		button.LayoutOrder = index
		if item.Owned then
			button.TextTransparency = 0.5
		else
			button.Activated:Connect(function()
				RemoteManager.FireServer(RemoteNames.Purchase, item.Id)
			end)
		end
	end
	local cancel = Theme.Button(list, "Close", 14)
	cancel.LayoutOrder = 1000
	cancel.Activated:Connect(close)

	gui.Enabled = true
end

function ShopController.Init()
	gui = Theme.Screen("Shop", 5)
	gui.Enabled = false
	list = Theme.Panel(gui, UDim2.fromOffset(420, 0), UDim2.fromScale(0.5, 0.2))
	list.AnchorPoint = Vector2.new(0.5, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	Theme.List(list, 8)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function ShopController.Start()
	RemoteManager.GetRemote(RemoteNames.OpenUI).OnClientEvent:Connect(function(kind: any, payload: any)
		if kind == "Shop" then
			open(payload)
		end
	end)
end

return ShopController
