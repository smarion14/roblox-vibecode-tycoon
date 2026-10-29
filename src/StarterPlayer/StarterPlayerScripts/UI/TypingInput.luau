--!strict
-- Shared typing field for bursts and battles.
-- Keyboard: a hidden TextBox with live per-character colouring. Touch/gamepad: tap the prompt's words in order.
local UserInputService = game:GetService("UserInputService")

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

local function hex(color: Color3): string
	return "#" .. color:ToHex()
end

function TypingInput.DetectMode(): Mode
	local lastInput = UserInputService:GetLastInputType()
	local usingGamepad = lastInput.Name:sub(1, 7) == "Gamepad"
	if usingGamepad or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) then
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

	local function submit()
		if prompt == "" then
			return
		end
		local text = box.Text
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
		if prompt ~= "" and #typed >= #prompt then
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
			editing = true
			box.Text = ""
			editing = false
			label.Text = renderPrompt(prompt, "")
			box:CaptureFocus()
		end,
		Clear = function(self: TypingField)
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
				if #buffer >= wordCount then
					local onSubmit = field.OnSubmit
					if onSubmit then
						onSubmit(table.concat(buffer, " "))
					end
				end
			end)
		end
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
