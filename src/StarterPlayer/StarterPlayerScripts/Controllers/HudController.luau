--!strict
-- Always-on HUD: cash, valuation, rent goal, the active job's recipe progress, and notice toasts.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local NOTICE_SECONDS = 3

local HudController = {}

local cashLabel: TextLabel
local valuationLabel: TextLabel
local rentFill: Frame
local rentLabel: TextLabel
local jobLabel: TextLabel
local recipeLabel: TextLabel
local noticeLabel: TextLabel
local noticeToken = 0

local function countUnits(grades: any): number
	if type(grades) ~= "table" then
		return 0
	end
	return (grades.S or 0) + (grades.A or 0) + (grades.B or 0) + (grades.C or 0)
end

local function onStateSync(view: any)
	if type(view) ~= "table" then
		return
	end
	local cash = tonumber(view.Cash) or 0
	cashLabel.Text = `CASH  ${cash}`
	valuationLabel.Text = string.format("VALUATION  x%.2f", tonumber(view.Valuation) or 1)

	if view.RentPaid then
		rentLabel.Text = "RENT  PAID"
		rentFill.Size = UDim2.fromScale(1, 1)
	else
		rentLabel.Text = `RENT  ${cash} / ${GameConfig.RENT_GOAL}`
		rentFill.Size = UDim2.fromScale(math.clamp(cash / GameConfig.RENT_GOAL, 0, 1), 1)
	end

	local job: GameConfig.ClientDef? = nil
	for _, client in GameConfig.CLIENTS do
		if client.Id == view.ActiveJobId then
			job = client
		end
	end
	if not job then
		jobLabel.Text = "NO JOB  check your phone"
		recipeLabel.Text = ""
		return
	end

	jobLabel.Text = `JOB  {job.Name}`
	local recipe = GameConfig.RECIPES[job.Project]
	local lines: { string } = {}
	for _, component in GameConfig.COMPONENTS do
		local have = countUnits(view.Inventory and view.Inventory[component])
		local need = recipe[component] or 0
		local mark = if have >= need then "+" else "-"
		table.insert(lines, `{mark} {GameConfig.STATION_NAMES[component]}  {have}/{need}`)
	end
	recipeLabel.Text = table.concat(lines, "\n")
end

local function showNotice(text: any)
	if type(text) ~= "string" then
		return
	end
	noticeToken += 1
	local token = noticeToken
	noticeLabel.Text = text
	noticeLabel.Visible = true
	task.delay(NOTICE_SECONDS, function()
		if noticeToken == token then
			noticeLabel.Visible = false
		end
	end)
end

function HudController.Init()
	local gui = Theme.Screen("Hud", 1)

	local panel = Theme.Panel(gui, UDim2.fromOffset(280, 0), UDim2.fromOffset(12, 12))
	panel.AutomaticSize = Enum.AutomaticSize.Y
	Theme.List(panel, 4)

	cashLabel = Theme.Text(panel, "CASH  $0", 18, Theme.TYPED)
	valuationLabel = Theme.Text(panel, "VALUATION  x1.00", 14, Theme.MUTED)
	rentLabel = Theme.Text(panel, "RENT", 14, Theme.MOOD)

	local rentBar = Instance.new("Frame")
	rentBar.Size = UDim2.new(1, 0, 0, 8)
	rentBar.BackgroundColor3 = Theme.PANEL
	rentBar.BorderSizePixel = 0
	rentBar.Parent = panel
	rentFill = Instance.new("Frame")
	rentFill.Size = UDim2.fromScale(0, 1)
	rentFill.BackgroundColor3 = Theme.MOOD
	rentFill.BorderSizePixel = 0
	rentFill.Parent = rentBar

	jobLabel = Theme.Text(panel, "", 14, Theme.ACCENT)
	recipeLabel = Theme.Text(panel, "", 13)

	noticeLabel = Theme.Text(gui, "", 18, Theme.TEXT)
	noticeLabel.AnchorPoint = Vector2.new(0.5, 1)
	noticeLabel.Position = UDim2.new(0.5, 0, 1, -120)
	noticeLabel.Size = UDim2.fromOffset(520, 30)
	noticeLabel.TextXAlignment = Enum.TextXAlignment.Center
	noticeLabel.BackgroundTransparency = 0.2
	noticeLabel.BackgroundColor3 = Theme.BACKGROUND
	noticeLabel.Visible = false

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function HudController.Start()
	RemoteManager.GetRemote(RemoteNames.StateSync).OnClientEvent:Connect(onStateSync)
	RemoteManager.GetRemote(RemoteNames.Notice).OnClientEvent:Connect(showNotice)
end

return HudController
