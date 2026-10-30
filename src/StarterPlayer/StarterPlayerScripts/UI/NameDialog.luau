--!strict
-- "Name your startup" dialog: a text box and Confirm. The server prechecks and filters the name and answers with
-- NameResult; a rejection shakes the box and shows why, a success closes it with a pop.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemoteNames = require(Shared:WaitForChild("RemoteNames"))
local RemoteManager = require(ReplicatedStorage:WaitForChild("Network"):WaitForChild("RemoteManager"))
local Juice = require(script.Parent:WaitForChild("Juice"))
local Sfx = require(script.Parent:WaitForChild("Sfx"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local NameDialog = {}

local gui: ScreenGui? = nil
local window: Frame
local input: TextBox
local reasonLabel: TextLabel
local confirm: TextButton
local cancel: TextButton
local open = false
local waiting = false
local submitToken = 0

local function build(): ScreenGui
	local screen = Theme.Screen("NameDialog", 25)
	screen.IgnoreGuiInset = true
	screen.Enabled = false

	window = Theme.Panel(screen, UDim2.fromOffset(420, 0), UDim2.fromScale(0.5, 0.5))
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.AutomaticSize = Enum.AutomaticSize.Y
	Theme.List(window, 10)
	Theme.Text(window, "NAME YOUR STARTUP", 14, Theme.ACCENT).LayoutOrder = 1

	input = Instance.new("TextBox")
	input.LayoutOrder = 2
	input.Size = UDim2.new(1, 0, 0, 44)
	input.BackgroundColor3 = Theme.PANEL
	input.TextColor3 = Theme.TYPED
	input.PlaceholderText = "e.g. Night Shift Labs"
	input.PlaceholderColor3 = Theme.TODO
	input.Font = Theme.FONT
	input.TextSize = 22
	input.ClearTextOnFocus = false
	input.Parent = window
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = input

	reasonLabel = Theme.Text(window, "", 14, Theme.BUG)
	reasonLabel.LayoutOrder = 3

	confirm = Theme.Button(window, "Confirm", 18)
	confirm.LayoutOrder = 4
	cancel = Theme.Button(window, "Cancel", 14)
	cancel.LayoutOrder = 5

	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return screen
end

local function submit()
	if waiting or not open then
		return
	end
	waiting = true
	reasonLabel.Text = "Checking..."
	RemoteManager.FireServer(RemoteNames.SetStartupName, input.Text)
	-- The server drops requests past its rate limit without replying, so don't wait forever.
	submitToken += 1
	local token = submitToken
	task.delay(4, function()
		if waiting and submitToken == token then
			waiting = false
			reasonLabel.Text = "No answer. Try again."
		end
	end)
end

-- Closes the dialog without a name (cutscene skipped, or Cancel).
function NameDialog.Close()
	open = false
end

-- Shows the dialog and yields until the server accepts a name (true) or the dialog is closed (false).
function NameDialog.Prompt(defaultText: string, cancellable: boolean?): boolean
	local screen = gui or build()
	if not gui then
		gui = screen
		confirm.Activated:Connect(submit)
		input.FocusLost:Connect(function(enterPressed: boolean)
			if enterPressed then
				submit()
			end
		end)
		cancel.Activated:Connect(NameDialog.Close)
	end
	if open then
		return false
	end

	open = true
	waiting = false
	input.Text = defaultText
	reasonLabel.Text = ""
	cancel.Visible = cancellable == true
	Juice.OpenWindow(screen, window)

	local accepted = false
	local connection = RemoteManager.GetRemote(RemoteNames.NameResult).OnClientEvent:Connect(function(ok: any, text: any)
		waiting = false
		if ok == true then
			accepted = true
			open = false
			Sfx.Play("PromptClean")
		else
			reasonLabel.Text = if type(text) == "string" then text else "Try a different name"
			Sfx.Play("KeyWrong")
			Juice.Shake(window)
		end
	end)
	while open do
		task.wait()
	end
	connection:Disconnect()
	Juice.CloseWindow(screen, window)
	return accepted
end

return NameDialog
