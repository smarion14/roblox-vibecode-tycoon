--!strict
-- Laptop shop: gear (changes the typing minigame) and hires (pre-fill C units, Act 2 only). Prices, ownership and
-- act checked here.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local StartupDataModule = require(ServerScriptService:WaitForChild("Components"):WaitForChild("StartupDataModule"))
local EmployeeService = require(script.Parent:WaitForChild("EmployeeService"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))
local ProgressService = require(script.Parent:WaitForChild("ProgressService"))

local NO_OFFICE_MESSAGE = "Hire people once you have an office."

type ShopItem = {
	Id: string,
	Kind: "Gear" | "Hire",
	Name: string,
	Price: number,
	Owned: boolean,
}

local ShopService = {}

local function catalogFor(save: StartupDataModule.PlayerSave): { ShopItem }
	local items: { ShopItem } = {}
	for id, def in GameConfig.GEAR do
		table.insert(items, { Id = id, Kind = "Gear", Name = def.Name, Price = def.Price, Owned = save.Gear[id] == true })
	end
	-- Hires only appear once there's an office to put them in.
	if save.Act >= 2 then
		for id, def in GameConfig.HIRES do
			table.insert(items, { Id = id, Kind = "Hire", Name = def.Name, Price = def.Price, Owned = save.Hires[id] == true })
		end
	end
	table.sort(items, function(a: ShopItem, b: ShopItem): boolean
		return a.Price < b.Price or (a.Price == b.Price and a.Id < b.Id)
	end)
	return items
end

local function openShop(player: Player)
	local save = StartupDataModule.GetSnapshot(player)
	if save then
		RemoteManager.FireClient(RemoteNames.OpenUI, player, "Shop", catalogFor(save))
	end
end

local function onPurchase(player: Player, itemId: any)
	if type(itemId) ~= "string" or #itemId > GameConfig.MAX_REMOTE_STRING then
		return
	end
	local save = StartupDataModule.GetSnapshot(player)
	if not save then
		return
	end

	local gear = GameConfig.GEAR[itemId]
	local hire = GameConfig.HIRES[itemId]
	local def = gear or hire
	if not def then
		return
	end

	if hire and save.Act < 2 then
		RemoteManager.FireClient(RemoteNames.Notice, player, NO_OFFICE_MESSAGE)
		return
	end

	local owned = if gear then save.Gear[itemId] == true else save.Hires[itemId] == true
	if owned then
		RemoteManager.FireClient(RemoteNames.Notice, player, `You already have the {def.Name}.`)
		return
	end
	if save.Cash < def.Price then
		RemoteManager.FireClient(RemoteNames.Notice, player, `Not enough cash. {def.Name} costs ${def.Price}.`)
		return
	end

	StartupDataModule.Update(player, function(current)
		current.Cash -= def.Price
		if gear then
			current.Gear[itemId] = true
		else
			current.Hires[itemId] = true
		end
	end)
	RemoteManager.FireClient(RemoteNames.Notice, player, `Bought: {def.Name}`)
	if hire then
		EmployeeService.Refresh(player)
		ProgressService.CheckMilestones(player)
	end
	openShop(player)
end

function ShopService.Init() end

function ShopService.Start()
	PlotService.OnPromptTriggered("ShopComputer", openShop)
	RemoteManager.Listen(RemoteNames.Purchase, onPurchase)
end

return ShopService
