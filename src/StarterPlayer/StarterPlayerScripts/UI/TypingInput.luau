--!strict
-- Shared typing field for bursts and battles.
-- Keyboard: a hidden TextBox with live per-character colouring. Touch/gamepad: tap the prompt's words in order.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Theme = require(script.Parent:WaitForChild("Theme"))

export type Mode = "Keyboard" | "Touch"

export type TypingField = {
	SetPrompt: (self: TypingField, text: string) -> (),
	Clear: (self: TypingField) -> (),
	Destroy: (self: TypingField) -> (),
	OnSubmit: ((text: string) -> ())?,
	OnWord: ((word: string) -> boolean)?,
}

local CLICK_SOUND = "rbxasset://sounds/clickfast.wav"

local TypingInput = {}

local function usingGamepad(): boolean
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

-- Blank input is never sent, and anything longer than the server accepts is cut to fit.
local function prepare(text: string): string?
	if string.match(text, "^%s*$") then
		return nil
	end
	return string.sub(text, 1, GameConfig.MAX_REMOTE_STRING)
end

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

function TypingInput.DetectMode(): Mode
	if usingGamepad() or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) then
		return "Touch"
	end
	return "Keyboard"
end

-- Colours the prompt by what has been typed so far: correct, wrong, current, remaining.
local function renderPrompt(prompt: string, typed: string): string
	local parts: { string } = {}
	for i = 1, #prompt do
		local char = string.sub(prompt, i, i)
		local shown = if char == " " then " " else char
		if i <= #typed then
			local color = if string.sub(typed, i, i) == char then Theme.TYPED else Theme.BUG
			table.insert(parts, `<font color="{hex(color)}">{shown}</font>`)
		elseif i == #typed + 1 then
			table.insert(parts, `<u><font color="#ffffff">{shown}</font></u>`)
		else
			table.insert(parts, `<font color="{hex(Theme.TODO)}">{shown}</font>`)
		end
	end
	return table.concat(parts)
end

local function createKeyboard(parent: GuiObject): TypingField
	local field: TypingField
	local prompt = ""
	local active = true
	local editing = false
	local submitted = false

	local label = Theme.Text(parent, "", 22)
	label.RichText = true
	label.Size = UDim2.new(1, 0, 0, 60)

	local box = Instance.new("TextBox")
	box.Size = UDim2.fromScale(1, 1)
	box.BackgroundTransparency = 1
	box.TextTransparency = 1
	box.ClearTextOnFocus = false
	box.TextEditable = true
	box.Text = ""
	box.Parent = label

	local click = Instance.new("Sound")
	click.SoundId = CLICK_SOUND
	click.Volume = 0.4
	click.Parent = label

	-- One submit per prompt: an Enter right after an auto-submit must not send the next prompt's answer.
	local function submit()
		local text = prepare(box.Text)
		if prompt == "" or submitted or not text then
			return
		end
		submitted = true
		local onSubmit = field.OnSubmit
		if onSubmit then
			onSubmit(text)
		end
	end

	box:GetPropertyChangedSignal("Text"):Connect(function()
		if editing then
			return
		end
		local typed = string.lower(box.Text)
		click:Play()

		-- A finished word may be a bug's name; if the battle eats it, remove it from the buffer.
		local word = string.match(typed, "(%S+) $")
		local onWord = field.OnWord
		if word and onWord and onWord(word) then
			editing = true
			box.Text = string.sub(typed, 1, #typed - #word - 1)
			editing = false
			typed = box.Text
		end

		label.Text = renderPrompt(prompt, typed)
		if prompt ~= "" and typed == prompt then
			submit()
		end
	end)

	box.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			submit()
		end
		if active then
			task.defer(function()
				if active then
					box:CaptureFocus()
				end
			end)
		end
	end)

	field = {
		SetPrompt = function(self: TypingField, text: string)
			prompt = text
			submitted = false
			editing = true
			box.Text = ""
			editing = false
			label.Text = renderPrompt(prompt, "")
			box:CaptureFocus()
		end,
		Clear = function(self: TypingField)
			submitted = false
			editing = true
			box.Text = ""
			editing = false
			label.Text = renderPrompt(prompt, "")
		end,
		Destroy = function(self: TypingField)
			active = false
			label:Destroy()
		end,
		OnSubmit = nil,
		OnWord = nil,
	}
	return field
end

local function createTouch(parent: GuiObject): TypingField
	local field: TypingField
	local buffer: { string } = {}
	local wordCount = 0

	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 150)
	holder.Parent = parent

	local typedLabel = Theme.Text(holder, "", 18, Theme.TYPED)
	typedLabel.Size = UDim2.new(1, 0, 0, 40)

	local chips = Instance.new("Frame")
	chips.BackgroundTransparency = 1
	chips.Position = UDim2.fromOffset(0, 44)
	chips.Size = UDim2.new(1, 0, 1, -44)
	chips.Parent = holder

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(110, 36)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = chips

	local rng = Random.new()

	-- Gamepad players move a selection cursor over the chips; keep it on the next untapped one.
	local function selectNextChip()
		if not usingGamepad() then
			return
		end
		for _, child in chips:GetChildren() do
			if child:IsA("TextButton") and child.Active then
				GuiService.SelectedObject = child
				return
			end
		end
	end

	local function clearChips()
		for _, child in chips:GetChildren() do
			if child:IsA("GuiButton") then
				child:Destroy()
			end
		end
	end

	local function setPrompt(text: string)
		clearChips()
		table.clear(buffer)
		typedLabel.Text = ""
		local words = string.split(text, " ")
		wordCount = #words
		for _, word in words do
			local chip = Theme.Button(chips, word, 16)
			chip.LayoutOrder = rng:NextInteger(1, 1000)
			chip.Activated:Connect(function()
				if not chip.Active then
					return
				end
				chip.Active = false
				chip.TextTransparency = 0.6
				table.insert(buffer, word)
				typedLabel.Text = table.concat(buffer, " ")
				selectNextChip()
				if #buffer >= wordCount then
					local onSubmit = field.OnSubmit
					local text = prepare(table.concat(buffer, " "))
					if onSubmit and text then
						onSubmit(text)
					end
				end
			end)
		end
		task.defer(selectNextChip)
	end

	field = {
		SetPrompt = function(self: TypingField, text: string)
			setPrompt(text)
		end,
		Clear = function(self: TypingField)
			table.clear(buffer)
			typedLabel.Text = ""
			for _, child in chips:GetChildren() do
				if child:IsA("TextButton") then
					child.Active = true
					child.TextTransparency = 0
				end
			end
		end,
		Destroy = function(self: TypingField)
			holder:Destroy()
		end,
		OnSubmit = nil,
		OnWord = nil,
	}
	return field
end

function TypingInput.Create(parent: GuiObject, mode: Mode): TypingField
	if mode == "Touch" then
		return createTouch(parent)
	end
	return createKeyboard(parent)
end

return TypingInput
