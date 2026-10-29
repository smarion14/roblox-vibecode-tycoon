--!strict
-- Shared typing field for bursts and battles.
-- Keyboard: a hidden TextBox with live per-character colouring. Touch/gamepad: tap the prompt's words in order.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConfig"))
local Juice = require(script.Parent:WaitForChild("Juice"))
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
local SUCCESS_SOUND = "rbxasset://sounds/electronicpingshort.wav"
local SUCCESS_TEXT = "CLEAN ✓"

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

	local typedLength = 0

	-- The holder sits in the parent's layout; the label inside it is free to shake and scale.
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 60)
	holder.ClipsDescendants = false
	holder.Parent = parent

	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Parent = holder

	local label = Theme.Text(holder, "", 22)
	label.RichText = true
	label.AutomaticSize = Enum.AutomaticSize.None
	label.Size = UDim2.fromScale(1, 1)
	label.TextYAlignment = Enum.TextYAlignment.Top

	-- shortcut: assumes monospace Code font and character wrapping, so sparks drift a little on word-wrapped lines; measure real glyph positions if that reads wrong
	local function charPosition(index: number): UDim2
		local glyph = TextService:GetTextSize("a", label.TextSize, label.Font, Vector2.new(math.huge, math.huge))
		local columns = math.max(1, math.floor(label.AbsoluteSize.X / glyph.X))
		local row = (index - 1) // columns
		local column = (index - 1) % columns
		return UDim2.fromOffset((column + 0.5) * glyph.X, (row + 0.5) * glyph.Y)
	end

	local wrong = Instance.new("Sound")
	wrong.SoundId = CLICK_SOUND
	wrong.PlaybackSpeed = 0.55
	wrong.Volume = 0.6
	wrong.Parent = holder

	local done = Instance.new("Sound")
	done.SoundId = SUCCESS_SOUND
	done.Volume = 0.5
	done.Parent = holder

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

		-- Feedback only for a newly typed character, not for deletes or bug words removed from the buffer.
		if prompt ~= "" and #typed == typedLength + 1 and #typed <= #prompt then
			if string.sub(typed, #typed, #typed) == string.sub(prompt, #typed, #typed) then
				click:Play()
				Juice.Pop(label, 0.03)
				Juice.Spark(holder, charPosition(#typed), Theme.TYPED)
			else
				wrong:Play()
				Juice.Shake(label, flash)
			end
		end
		typedLength = #typed

		if prompt ~= "" and typed == prompt then
			done:Play()
			Juice.Bounce(label, holder, SUCCESS_TEXT)
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
			typedLength = 0
			editing = true
			box.Text = ""
			editing = false
			label.Text = renderPrompt(prompt, "")
			box:CaptureFocus()
		end,
		Clear = function(self: TypingField)
			submitted = false
			typedLength = 0
			editing = true
			box.Text = ""
			editing = false
			label.Text = renderPrompt(prompt, "")
		end,
		Destroy = function(self: TypingField)
			active = false
			holder:Destroy()
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

	local flash = Instance.new("Frame")
	flash.Size = UDim2.new(1, 0, 0, 40)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Parent = holder

	local typedLabel = Theme.Text(holder, "", 18, Theme.TYPED)
	typedLabel.AutomaticSize = Enum.AutomaticSize.None
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
	local expected: { string } = {}

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
		expected = words
		for _, word in words do
			local chip = Theme.Button(chips, word, 16)
			chip.LayoutOrder = rng:NextInteger(1, 1000)
			chip.Activated:Connect(function()
				if not chip.Active then
					return
				end
				chip.Active = false
				chip.TextTransparency = 0.6
				if word == expected[#buffer + 1] then
					Juice.Pop(chip, 0.15)
					Juice.Spark(holder, UDim2.fromScale(math.min(#buffer / math.max(wordCount, 1) + 0.05, 0.95), 0.12), Theme.TYPED)
				else
					Juice.Shake(typedLabel, flash)
				end
				table.insert(buffer, word)
				typedLabel.Text = table.concat(buffer, " ")
				selectNextChip()
				if #buffer >= wordCount then
					if table.concat(buffer, " ") == table.concat(expected, " ") then
						Juice.Bounce(typedLabel, holder, SUCCESS_TEXT)
					end
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
