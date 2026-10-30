--!strict
-- Shared typing field for bursts and battles.
-- Keyboard: a hidden TextBox driving one animated label per letter. Touch/gamepad: tap the prompt's words in order.
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
	OnPartial: ((partial: string) -> ())?,
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

function TypingInput.DetectMode(): Mode
	if usingGamepad() or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) then
		return "Touch"
	end
	return "Keyboard"
end

local LETTER_SIZE = 24
local LINE_GAP = 6

type Letter = {
	Char: string,
	Label: TextLabel,
	Home: UDim2,
}

-- One TextLabel per character so each letter can hop, pop and shake on its own.
local function buildLetters(container: Frame, prompt: string): { Letter }
	local glyph = TextService:GetTextSize("a", LETTER_SIZE, Theme.FONT, Vector2.new(math.huge, math.huge))
	-- shortcut: a frame not laid out yet reports ~0 width, so fall back to 600px; re-wrap on AbsoluteSize change if panels get resizable
	local width = container.AbsoluteSize.X
	if width < glyph.X * 10 then
		width = 600
	end
	local columns = math.max(1, math.floor(width / glyph.X))
	local letters: { Letter } = {}
	local column, row = 0, 0

	-- Word wrap: a word that won't fit on the current line moves to the next one.
	for word, space in string.gmatch(prompt, "(%S+)(%s*)") do
		if column > 0 and column + #word > columns then
			column, row = 0, row + 1
		end
		for char in string.gmatch((word :: string) .. (space :: string), ".") do
			local home = UDim2.fromOffset(column * glyph.X, row * (glyph.Y + LINE_GAP))
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromOffset(glyph.X, glyph.Y)
			label.Position = home
			label.Font = Theme.FONT
			label.TextSize = LETTER_SIZE
			label.Text = char
			label.TextColor3 = Theme.TODO
			label:SetAttribute("JuiceHome", home)
			label.Parent = container
			table.insert(letters, { Char = char, Label = label, Home = home })
			column += 1
		end
	end

	container.Size = UDim2.new(1, 0, 0, (row + 1) * (glyph.Y + LINE_GAP))
	return letters
end

local function createKeyboard(parent: GuiObject): TypingField
	local field: TypingField
	local prompt = ""
	local active = true
	local editing = false
	local submitted = false
	local typedLength = 0
	local letters: { Letter } = {}

	-- The holder sits in the parent's layout; letters inside it are free to move.
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 60)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.Parent = parent

	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Parent = holder

	local lettersFrame = Instance.new("Frame")
	lettersFrame.BackgroundTransparency = 1
	lettersFrame.Size = UDim2.new(1, 0, 0, 60)
	lettersFrame.Parent = holder

	local cursor = Instance.new("Frame")
	cursor.BackgroundColor3 = Theme.ACCENT
	cursor.BorderSizePixel = 0
	cursor.Size = UDim2.fromOffset(12, 3)
	cursor.ZIndex = 3
	cursor.Parent = lettersFrame

	local box = Instance.new("TextBox")
	box.Size = UDim2.fromScale(1, 1)
	box.BackgroundTransparency = 1
	box.TextTransparency = 1
	box.ClearTextOnFocus = false
	box.TextEditable = true
	box.Text = ""
	box.ZIndex = 5
	box.Parent = holder

	local click = Instance.new("Sound")
	click.SoundId = CLICK_SOUND
	click.Volume = 0.4
	click.Parent = holder

	local wrong = Instance.new("Sound")
	wrong.SoundId = CLICK_SOUND
	wrong.PlaybackSpeed = 0.55
	wrong.Volume = 0.6
	wrong.Parent = holder

	local done = Instance.new("Sound")
	done.SoundId = SUCCESS_SOUND
	done.Volume = 0.5
	done.Parent = holder

	-- Colours every letter for the typed buffer and slides the cursor under the next one.
	local function paint(typed: string)
		for index, letter in letters do
			local color = Theme.TODO
			if index <= #typed then
				color = if string.sub(typed, index, index) == letter.Char then Theme.TYPED else Theme.BUG
			elseif index == #typed + 1 then
				color = Theme.TEXT
			end
			letter.Label.TextColor3 = color
		end

		local next = letters[#typed + 1]
		cursor.Visible = next ~= nil
		if next then
			Juice.Slide(cursor, next.Home + UDim2.fromOffset(0, next.Label.Size.Y.Offset))
		end
	end

	local function reset()
		submitted = false
		typedLength = 0
		editing = true
		box.Text = ""
		editing = false
		paint("")
	end

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

		paint(typed)
		local onPartial = field.OnPartial
		if onPartial then
			onPartial(string.match(typed, "(%S*)$") or "")
		end

		-- Feedback only for a newly typed character, not for deletes or bug words removed from the buffer.
		local letter = letters[#typed]
		if letter and #typed == typedLength + 1 then
			if string.sub(typed, #typed, #typed) == letter.Char then
				click:Play()
				Juice.Hop(letter.Label)
				Juice.Spark(lettersFrame, letter.Home + UDim2.fromOffset(letter.Label.Size.X.Offset / 2, 0), Theme.TYPED)
			else
				wrong:Play()
				Juice.Shake(letter.Label, flash)
			end
		end
		typedLength = #typed

		if prompt ~= "" and typed == prompt then
			done:Play()
			local labels: { GuiObject } = {}
			for _, each in letters do
				table.insert(labels, each.Label)
			end
			Juice.Wave(labels)
			Juice.Bounce(lettersFrame, holder, SUCCESS_TEXT)
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
			for _, letter in letters do
				letter.Label:Destroy()
			end
			letters = buildLetters(lettersFrame, prompt)
			cursor.Position = if letters[1] then letters[1].Home + UDim2.fromOffset(0, letters[1].Label.Size.Y.Offset) else UDim2.new()
			reset()
			box:CaptureFocus()
		end,
		Clear = function(self: TypingField)
			reset()
		end,
		Destroy = function(self: TypingField)
			active = false
			holder:Destroy()
		end,
		OnSubmit = nil,
		OnWord = nil,
		OnPartial = nil,
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
		OnPartial = nil,
	}
	return field
end

export type WordCatcher = {
	Destroy: (self: WordCatcher) -> (),
	OnWord: ((word: string) -> boolean)?,
	OnPartial: ((partial: string) -> ())?,
}

-- Keyboard input with no prompt: letters pop in as you type; SPACE or ENTER fires the word.
-- OnWord returns true when the word hit something (the buffer clears with a bounce) or false (it shakes red).
function TypingInput.CreateWordCatcher(parent: GuiObject): WordCatcher
	local catcher: WordCatcher
	local active = true
	local editing = false

	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 56)
	holder.Parent = parent

	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Parent = holder

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	row.Parent = holder
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local caret = Theme.Text(row, "▌", 28, Theme.ACCENT)
	caret.AutomaticSize = Enum.AutomaticSize.XY
	caret.Size = UDim2.new()
	caret.LayoutOrder = 100000

	local box = Instance.new("TextBox")
	box.Size = UDim2.fromScale(1, 1)
	box.BackgroundTransparency = 1
	box.TextTransparency = 1
	box.ClearTextOnFocus = false
	box.Text = ""
	box.ZIndex = 5
	box.Parent = holder

	local click = Instance.new("Sound")
	click.SoundId = CLICK_SOUND
	click.Volume = 0.4
	click.Parent = holder
	local wrong = Instance.new("Sound")
	wrong.SoundId = CLICK_SOUND
	wrong.PlaybackSpeed = 0.55
	wrong.Volume = 0.6
	wrong.Parent = holder

	local letters: { TextLabel } = {}

	local function clearLetters()
		for _, letter in letters do
			letter:Destroy()
		end
		table.clear(letters)
	end

	local function setBuffer(text: string)
		editing = true
		box.Text = text
		editing = false
	end

	local function fire(word: string)
		if word == "" then
			return
		end
		local onWord = catcher.OnWord
		if onWord and onWord(word) then
			Juice.Pop(row, 0.2)
		else
			wrong:Play()
			Juice.Shake(row, flash)
		end
		clearLetters()
		setBuffer("")
		local onPartial = catcher.OnPartial
		if onPartial then
			onPartial("")
		end
	end

	box:GetPropertyChangedSignal("Text"):Connect(function()
		if editing then
			return
		end
		local typed = string.lower(box.Text)
		local word = string.match(typed, "^%s*(%S+)%s$")
		if word then
			fire(word)
			return
		end
		typed = string.gsub(typed, "%s", "")
		if #typed > GameConfig.MAX_REMOTE_STRING then
			typed = string.sub(typed, 1, GameConfig.MAX_REMOTE_STRING)
		end

		-- Grow or shrink the letter row to match the buffer; each new letter pops in.
		while #letters > #typed do
			(table.remove(letters) :: TextLabel):Destroy()
		end
		while #letters < #typed do
			local index = #letters + 1
			local letter = Theme.Text(row, string.sub(typed, index, index), 30, Theme.TYPED)
			letter.AutomaticSize = Enum.AutomaticSize.XY
			letter.Size = UDim2.new()
			letter.LayoutOrder = index
			letter.Rotation = math.random(-14, 14)
			table.insert(letters, letter)
			click:Play()
			Juice.Pop(letter, 0.7)
		end

		local onPartial = catcher.OnPartial
		if onPartial then
			onPartial(typed)
		end
	end)

	box.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			fire((string.gsub(string.lower(box.Text), "%s", "")))
		end
		if active then
			task.defer(function()
				if active then
					box:CaptureFocus()
				end
			end)
		end
	end)

	catcher = {
		Destroy = function(self: WordCatcher)
			active = false
			holder:Destroy()
		end,
		OnWord = nil,
		OnPartial = nil,
	}
	box:CaptureFocus()
	return catcher
end

function TypingInput.Create(parent: GuiObject, mode: Mode): TypingField
	if mode == "Touch" then
		return createTouch(parent)
	end
	return createKeyboard(parent)
end

return TypingInput
