--!strict
-- Always-on HUD: cash, valuation, Act 3 reputation, rent goal, the active job's recipe progress, and notice toasts.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("GameConfig"))
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local Reputation = require(Shared:WaitForChild("Reputation"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local UI = script.Parent.Parent:WaitForChild("UI")
local ClientState = require(UI:WaitForChild("ClientState"))
local Juice = require(UI:WaitForChild("Juice"))
local Theme = require(UI:WaitForChild("Theme"))

local NOTICE_SECONDS = 3

local HudController = {}

local cashLabel: TextLabel
local valuationLabel: TextLabel
local repLabel: TextLabel
local rentFill: Frame
local rentLabel: TextLabel
local jobLabel: TextLabel
local recipeLabel: TextLabel
local noticeLabel: TextLabel
local noticeToken = 0
local shownCash: number? = nil
local shownJob: string? = nil
local shownUnits: { [string]: number } = {}
local cashToken = 0

local function countUnits(grades: any): number
	if type(grades) ~= "table" then
		return 0
	end
	return (grades.S or 0) + (grades.A or 0) + (grades.B or 0) + (grades.C or 0)
end

-- 12400 -> "12,400"
local function commas(amount: number): string
	local text = tostring(math.floor(amount))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^(-?),", "%1"))
end

local function onStateSync(view: any)
	if type(view) ~= "table" then
		return
	end
	local cash = tonumber(view.Cash) or 0
	local valuationText = string.format("VALUATION  x%.2f", tonumber(view.Valuation) or 1)

	-- Cash rolls to the new value and flashes amber for income, red for spending.
	local previous = shownCash
	shownCash = cash
	if previous == nil or previous == cash then
		cashLabel.Text = `CASH  ${cash}`
	else
		cashToken += 1
		local token = cashToken
		local from = previous
		local gained = cash > from
		cashLabel.TextColor3 = if gained then Theme.MOOD else Theme.BUG
		Juice.Pop(cashLabel, if gained then 0.35 else 0.2)
		local started = os.clock()
		task.spawn(function()
			while cashToken == token do
				local t = math.clamp((os.clock() - started) / 0.8, 0, 1)
				local eased = 1 - (1 - t) ^ 3
				cashLabel.Text = `CASH  ${math.floor(from + (cash - from) * eased + 0.5)}`
				if t >= 1 then
					break
				end
				task.wait()
			end
			if cashToken == token then
				TweenService:Create(cashLabel, TweenInfo.new(0.4), { TextColor3 = Theme.TYPED }):Play()
			end
		end)
	end
	if valuationLabel.Text ~= valuationText then
		local first = previous == nil
		valuationLabel.Text = valuationText
		if not first then
			Juice.Pop(valuationLabel, 0.3)
		end
	end

	local act = tonumber(view.Act) or 1
	repLabel.Visible = act >= 3
	if act >= 3 then
		local rep = tonumber(view.Reputation) or GameConfig.ACT3.StartReputation
		local mult = Reputation.Multiplier(rep, GameConfig.ACT3.MinMultiplier, GameConfig.ACT3.MaxMultiplier)
		local repText = string.format("REP %d · x%.2f", math.floor(rep + 0.5), mult)
		if repLabel.Text ~= repText then
			local first = repLabel.Text == ""
			repLabel.Text = repText
			if not first then
				Juice.Pop(repLabel, 0.3)
			end
		end

		-- Act 3: a running total of deploy payouts toward the goal; after the end it keeps counting.
		local earned = tonumber(view.Act3Earned) or 0
		local flags = view.StoryFlags
		if type(flags) == "table" and flags.GameComplete then
			rentLabel.Text = `LIFETIME EARNINGS  ${commas(earned)}`
			rentFill.Size = UDim2.fromScale(1, 1)
		else
			rentLabel.Text = `GOAL  ${commas(earned)} / ${commas(GameConfig.ACT3.Goal)}`
			rentFill.Size = UDim2.fromScale(math.clamp(earned / GameConfig.ACT3.Goal, 0, 1), 1)
		end
	elseif act >= 2 then
		-- Act 2: the same row tracks the valuation goal from where the act started.
		local valuation = tonumber(view.Valuation) or 1
		local goal = tonumber(view.ActGoal) or 1
		local start = goal - GameConfig.ACT2.ValuationStep
		rentLabel.Text = string.format("GOAL  valuation x%.2f / x%.2f", valuation, goal)
		rentFill.Size = UDim2.fromScale(math.clamp((valuation - start) / (goal - start), 0, 1), 1)
	elseif view.RentPaid then
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
	local jobId = if job then job.Id else nil
	if jobId ~= shownJob then
		shownJob = jobId
		Juice.Pop(jobLabel, 0.35)
		table.clear(shownUnits)
	end
	if not job then
		jobLabel.Text = "NO JOB  check your phone"
		recipeLabel.Text = ""
		return
	end

	jobLabel.Text = `JOB  {job.Name}`
	local recipe = GameConfig.RECIPES[job.Project]
	local lines: { string } = {}
	local grew = false
	for _, component in GameConfig.COMPONENTS do
		local have = countUnits(view.Inventory and view.Inventory[component])
		local before = shownUnits[component]
		if before ~= nil and have > before then
			grew = true
		end
		shownUnits[component] = have
		local need = recipe[component] or 0
		-- Cap the count at what the job needs: extra builds still stack into the payout, but "3/2" reads as a bug.
		local mark = if have >= need then "✓" else "-"
		table.insert(lines, `{mark} {GameConfig.STATION_NAMES[component]}  {math.min(have, need)}/{need}`)
	end
	recipeLabel.Text = table.concat(lines, "\n")
	if grew then
		Juice.Pop(recipeLabel, 0.12)
	end
end

local function showNotice(text: any)
	if type(text) ~= "string" then
		return
	end
	noticeToken += 1
	local token = noticeToken
	noticeLabel.Text = text
	Juice.SlideIn(noticeLabel, UDim2.fromOffset(0, 40))
	task.delay(NOTICE_SECONDS, function()
		if noticeToken == token then
			Juice.SlideOut(noticeLabel, UDim2.fromOffset(0, 40))
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
	repLabel = Theme.Text(panel, "", 14, Theme.ACCENT)
	repLabel.Visible = false
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
	ClientState.OnChanged(onStateSync)
	RemoteManager.GetRemote(RemoteNames.Notice).OnClientEvent:Connect(showNotice)
end

return HudController
