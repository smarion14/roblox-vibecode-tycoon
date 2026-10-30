--!strict
-- Office decorating (Act 2+): buys, moves and sells decor in the decorate zone, and builds the saved layout into
-- unit.Contents.Decor whenever the office is built. Every placement is checked here with Decor.CanPlace, the same
-- rules the client preview uses; prices and refunds come from GameConfig only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local Decor = require(Shared:WaitForChild("Decor"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local DecorModels = require(ReplicatedStorage:WaitForChild("World"):WaitForChild("DecorModels"))
local StartupDataModule = require(ServerScriptService:WaitForChild("Components"):WaitForChild("StartupDataModule"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))

local MAX_CALLS = 6
local WINDOW_SECONDS = 1
-- Cells and rotations are small whole numbers; anything this big (or NaN/inf) is a forged request.
local MAX_WHOLE = 10000

local BAD_REQUEST = "That didn't work."
local NOT_HERE = "Decorate from inside your own office."
local NO_ITEM = "That item isn't in your office."

local DecorService = {}

local function reply(player: Player, ok: boolean, reason: string?)
	RemoteManager.FireClient(RemoteNames.DecorResult, player, ok, reason)
end

local function isWhole(value: any): boolean
	return type(value) == "number" and value == math.floor(value) and math.abs(value) <= MAX_WHOLE
end

-- The save, if this player may decorate right now: Act 2+, idle, and standing inside their own unit.
local function decoratingSave(player: Player): StartupDataModule.PlayerSave?
	local save = StartupDataModule.GetSnapshot(player)
	if not save or save.Act < 2 or StartupDataModule.GetActivity(player) ~= "Idle" then
		return nil
	end
	local unit = PlotService.GetUnitModel(player)
	local floor = if unit then unit:FindFirstChild("Floor") else nil
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not floor or not floor:IsA("BasePart") or not root or not root:IsA("BasePart") then
		return nil
	end
	local offset = floor.CFrame:PointToObjectSpace(root.Position)
	if math.abs(offset.X) > floor.Size.X / 2 or math.abs(offset.Z) > floor.Size.Z / 2 then
		return nil
	end
	return save
end

-- Sanitize only checks structure, so a saved layout is re-validated in order; entries that no longer fit (outside
-- the zone, overlapping, a second copy of a perk) are dropped.
local function validLayout(placed: { Decor.Placement }): { Decor.Placement }
	local kept: { Decor.Placement } = {}
	for _, entry in placed do
		if Decor.CanPlace(kept, GameConfig.DECOR, GameConfig.DECOR_ZONE, entry) then
			table.insert(kept, entry)
		end
	end
	return kept
end

local function cellCFrame(origin: CFrame, entry: Decor.Placement): CFrame?
	local def = GameConfig.DECOR[entry.Id]
	if not def then
		return nil
	end
	local w, d = Decor.Footprint(def, entry.R)
	return DecorModels.CellCFrame(origin, entry.X, entry.Z, w, d, entry.R)
end

-- Each model carries its save index as DecorIndex, for decorate mode.
local function addModel(folder: Folder, origin: CFrame, entry: Decor.Placement, index: number)
	local at = cellCFrame(origin, entry)
	if not at then
		return
	end
	local model = DecorModels.Build(entry.Id)
	model:PivotTo(at)
	model:SetAttribute("DecorIndex", index)
	model.Parent = folder
end

-- The built Decor folder and the unit origin, when both exist.
local function builtDecor(player: Player): (Folder?, CFrame?)
	local unit = PlotService.GetUnitModel(player)
	local contents = if unit then unit:FindFirstChild("Contents") else nil
	local folder = if contents then contents:FindFirstChild("Decor") else nil
	local origin = if unit then unit:GetAttribute("OriginCFrame") else nil
	if folder and folder:IsA("Folder") and typeof(origin) == "CFrame" then
		return folder, origin
	end
	return nil, nil
end

local function modelAt(folder: Folder, index: number): Model?
	for _, child in folder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("DecorIndex") == index then
			return child
		end
	end
	return nil
end

-- Rebuilds unit.Contents.Decor from the save. Only on load and office builds (and as a fallback if the folder is
-- missing): changes touch one model each, so spamming free moves can't churn hundreds of replicated parts.
local function buildDecor(player: Player)
	local unit = PlotService.GetUnitModel(player)
	local save = StartupDataModule.GetSnapshot(player)
	local contents = if unit then unit:FindFirstChild("Contents") else nil
	if not unit or not save or not contents then
		return
	end
	local old = contents:FindFirstChild("Decor")
	if old then
		old:Destroy()
	end
	local origin = unit:GetAttribute("OriginCFrame")
	if save.Act < 2 or typeof(origin) ~= "CFrame" then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Decor"
	for index, entry in save.Decor do
		addModel(folder, origin, entry, index)
	end
	folder.Parent = contents
end

local function onUnitBuilt(player: Player)
	local save = StartupDataModule.GetSnapshot(player)
	if not save then
		return
	end
	local kept = validLayout(save.Decor)
	if #kept ~= #save.Decor then
		StartupDataModule.Update(player, function(current)
			current.Decor = kept
		end)
	end
	buildDecor(player)
end

local function onPlace(player: Player, id: any, x: any, z: any, r: any)
	if type(id) ~= "string" or #id > GameConfig.MAX_REMOTE_STRING or not isWhole(x) or not isWhole(z) or not isWhole(r) then
		reply(player, false, BAD_REQUEST)
		return
	end
	local save = decoratingSave(player)
	if not save then
		reply(player, false, NOT_HERE)
		return
	end
	local def = GameConfig.DECOR[id]
	if not def then
		reply(player, false, BAD_REQUEST)
		return
	end
	local item: Decor.Placement = { Id = id, X = x, Z = z, R = r }
	local ok, reason = Decor.CanPlace(save.Decor, GameConfig.DECOR, GameConfig.DECOR_ZONE, item)
	if not ok then
		reply(player, false, reason)
		return
	end
	if save.Cash < def.Price then
		reply(player, false, `Not enough cash. {def.Name} costs ${def.Price}.`)
		return
	end
	StartupDataModule.Update(player, function(current)
		current.Cash -= def.Price
		table.insert(current.Decor, item)
	end)
	local folder, origin = builtDecor(player)
	if folder and origin then
		addModel(folder, origin, item, #save.Decor + 1)
	else
		buildDecor(player)
	end
	reply(player, true, nil)
end

local function onMove(player: Player, index: any, x: any, z: any, r: any)
	if not isWhole(index) or not isWhole(x) or not isWhole(z) or not isWhole(r) then
		reply(player, false, BAD_REQUEST)
		return
	end
	local save = decoratingSave(player)
	if not save then
		reply(player, false, NOT_HERE)
		return
	end
	local entry = save.Decor[index]
	if not entry then
		reply(player, false, NO_ITEM)
		return
	end
	local item: Decor.Placement = { Id = entry.Id, X = x, Z = z, R = r }
	local ok, reason = Decor.CanPlace(save.Decor, GameConfig.DECOR, GameConfig.DECOR_ZONE, item, index)
	if not ok then
		reply(player, false, reason)
		return
	end
	StartupDataModule.Update(player, function(current)
		current.Decor[index] = item
	end)
	local folder, origin = builtDecor(player)
	local model = if folder then modelAt(folder, index) else nil
	local at = if origin then cellCFrame(origin, item) else nil
	if model and at then
		model:PivotTo(at)
	else
		buildDecor(player)
	end
	reply(player, true, nil)
end

local function onSell(player: Player, index: any)
	if not isWhole(index) then
		reply(player, false, BAD_REQUEST)
		return
	end
	local save = decoratingSave(player)
	if not save then
		reply(player, false, NOT_HERE)
		return
	end
	local entry = save.Decor[index]
	if not entry then
		reply(player, false, NO_ITEM)
		return
	end
	local def = GameConfig.DECOR[entry.Id]
	local refund = if def then math.floor(def.Price * GameConfig.DECOR_SELL_RATE) else 0
	StartupDataModule.Update(player, function(current)
		table.remove(current.Decor, index)
		current.Cash += refund
	end)
	local folder = builtDecor(player)
	local model = if folder then modelAt(folder, index) else nil
	if folder and model then
		model:Destroy()
		-- Later entries shifted down one in the save; keep their models' indices in step.
		for _, child in folder:GetChildren() do
			local childIndex = child:GetAttribute("DecorIndex")
			if type(childIndex) == "number" and childIndex > index then
				child:SetAttribute("DecorIndex", childIndex - 1)
			end
		end
	else
		buildDecor(player)
	end
	reply(player, true, nil)
end

function DecorService.Init() end

function DecorService.Start()
	PlotService.OnUnitBuilt(onUnitBuilt)
	RemoteManager.Listen(RemoteNames.DecorPlace, onPlace, MAX_CALLS, WINDOW_SECONDS)
	RemoteManager.Listen(RemoteNames.DecorMove, onMove, MAX_CALLS, WINDOW_SECONDS)
	RemoteManager.Listen(RemoteNames.DecorSell, onSell, MAX_CALLS, WINDOW_SECONDS)
end

return DecorService
