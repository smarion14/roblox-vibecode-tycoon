--!strict
-- Act 2 employees: each hired role gets an NPC at its office desk, wearing one of the owner's friends' avatars
-- (random colors when there are no friends to borrow). Act 1 never shows them; the homelab has no desks.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local StartupDataModule = require(ServerScriptService:WaitForChild("Components"):WaitForChild("StartupDataModule"))
local PlotService = require(script.Parent:WaitForChild("PlotService"))

-- Roblox's default R15 sit, used until DeskType is published.
local SIT_ANIMATION_ID = 2506281703
local MAX_FRIENDS = 4

local EmployeeService = {}

local friendCache: { [Player]: { number } } = {}
local rng = Random.new()

local function friendIds(player: Player): { number }
	local cached = friendCache[player]
	if cached then
		return cached
	end
	local ids: { number } = {}
	pcall(function()
		local pages = Players:GetFriendsAsync(player.UserId)
		while #ids < MAX_FRIENDS do
			for _, friend in pages:GetCurrentPage() do
				table.insert(ids, friend.Id)
				if #ids >= MAX_FRIENDS then
					break
				end
			end
			if pages.IsFinished or #ids >= MAX_FRIENDS then
				break
			end
			pages:AdvanceToNextPageAsync()
		end
	end)
	friendCache[player] = ids
	return ids
end

local function randomLook(): HumanoidDescription
	local description = Instance.new("HumanoidDescription")
	local skin = Color3.fromHSV(rng:NextNumber(0.03, 0.1), rng:NextNumber(0.2, 0.6), rng:NextNumber(0.35, 0.95))
	local shirt = Color3.fromHSV(rng:NextNumber(), rng:NextNumber(0.4, 0.8), rng:NextNumber(0.4, 0.9))
	local pants = Color3.fromHSV(rng:NextNumber(), rng:NextNumber(0.1, 0.5), rng:NextNumber(0.15, 0.5))
	description.HeadColor = skin
	description.LeftArmColor = skin
	description.RightArmColor = skin
	description.TorsoColor = shirt
	description.LeftLegColor = pants
	description.RightLegColor = pants
	return description
end

local function lookFor(player: Player, slot: number): HumanoidDescription
	local friendId = friendIds(player)[slot]
	if friendId then
		local ok, description = pcall(function(): HumanoidDescription
			return Players:GetHumanoidDescriptionFromUserId(friendId)
		end)
		if ok and description then
			return description
		end
	end
	return randomLook()
end

local function buildModel(description: HumanoidDescription): Model?
	local ok, model = pcall(function(): Model
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	return if ok then model else nil
end

local function spawnEmployee(player: Player, desk: BasePart, seat: Seat, role: string, slot: number)
	-- A friend's outfit can fail to build (missing or moderated assets); fall back to a plain random look.
	local model = buildModel(lookFor(player, slot)) or buildModel(randomLook())
	if not model or not desk.Parent then
		return
	end
	model.Name = `Employee_{role}`
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	local head = model:FindFirstChild("Head")
	if head then
		local tag = Instance.new("BillboardGui")
		tag.Size = UDim2.fromOffset(160, 28)
		tag.StudsOffset = Vector3.new(0, 2, 0)
		tag.MaxDistance = 40
		tag.Parent = head
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(125, 252, 208)
		label.TextStrokeTransparency = 0.3
		label.Font = Enum.Font.Code
		label.TextScaled = true
		label.Text = GameConfig.HIRES[role].Name
		label.Parent = tag
	end
	model:PivotTo(seat.CFrame * CFrame.new(0, 3, 0))
	model.Parent = desk
	if humanoid then
		seat.Disabled = false
		seat:Sit(humanoid)
		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
		local id = GameConfig.ANIMATIONS.DeskType
		local animation = Instance.new("Animation")
		animation.AnimationId = `rbxassetid://{if id ~= 0 then id else SIT_ANIMATION_ID}`
		local track = animator:LoadAnimation(animation)
		track.Looped = true
		track:Play()
	end
end

-- Shows each hired role at its desk and the "NOW HIRING" note on the rest. Safe to call repeatedly.
function EmployeeService.Refresh(player: Player)
	local save = StartupDataModule.GetSnapshot(player)
	local unit = PlotService.GetUnitModel(player)
	if not save or not unit or save.Act < 2 then
		return
	end
	for _, desk in CollectionService:GetTagged("EmployeeDesk") do
		local role = desk:GetAttribute("Role")
		if not desk:IsA("BasePart") or type(role) ~= "string" or not desk:IsDescendantOf(unit) then
			continue
		end
		local hired = save.Hires[role] == true
		local note = desk:FindFirstChild("HiringNote")
		if note and note:IsA("SurfaceGui") then
			note.Enabled = not hired
		end
		local existing = desk:FindFirstChild(`Employee_{role}`)
		if not hired then
			if existing then
				existing:Destroy()
			end
		elseif not existing and not desk:GetAttribute("Spawning") then
			local seat = desk:FindFirstChild("EmployeeSeat")
			local slot = table.find(GameConfig.COMPONENTS, role) or 1
			if seat and seat:IsA("Seat") then
				-- Spawning yields on web calls; the flag stops an overlapping refresh from adding a second NPC.
				desk:SetAttribute("Spawning", true)
				task.spawn(function()
					local ok, err = pcall(function()
						spawnEmployee(player, desk, seat, role, slot)
					end)
					if not ok then
						warn(`EmployeeService: {role} failed to spawn: {err}`)
					end
					desk:SetAttribute("Spawning", nil)
				end)
			end
		end
	end
end

function EmployeeService.Init() end

function EmployeeService.Start()
	PlotService.OnUnitBuilt(EmployeeService.Refresh)
	Players.PlayerRemoving:Connect(function(player: Player)
		friendCache[player] = nil
	end)
end

return EmployeeService
