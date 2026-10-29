--!strict
-- Shared UI palette (from the approved deploy-battle mockup) and two small builders every screen uses.
local Theme = {}

Theme.BACKGROUND = Color3.fromHex("0b0716")
Theme.PANEL = Color3.fromHex("160f27")
Theme.BORDER = Color3.fromHex("3a2560")
Theme.TEXT = Color3.fromHex("e9ddff")
Theme.MUTED = Color3.fromHex("a58bd6")
Theme.TODO = Color3.fromHex("6d5a94")
Theme.TYPED = Color3.fromHex("7dfcd0")
Theme.ACCENT = Color3.fromHex("ff4fd8")
Theme.MOOD = Color3.fromHex("ffb84f")
Theme.BUG = Color3.fromHex("ff5a6e")
Theme.FONT = Enum.Font.Code

function Theme.Panel(parent: Instance, size: UDim2, position: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = Theme.BACKGROUND
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.BORDER
	stroke.Thickness = 1
	stroke.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = frame
	return frame
end

function Theme.Text(parent: Instance, text: string, textSize: number, color: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Theme.FONT
	label.Text = text
	label.TextSize = textSize
	label.TextColor3 = color or Theme.TEXT
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.new(1, 0, 0, textSize + 4)
	label.Parent = parent
	return label
end

function Theme.Button(parent: Instance, text: string, textSize: number): TextButton
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = Theme.PANEL
	button.Font = Theme.FONT
	button.Text = text
	button.TextSize = textSize
	button.TextColor3 = Theme.TEXT
	button.AutoButtonColor = true
	button.Size = UDim2.new(1, 0, 0, textSize + 20)
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.ACCENT
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	return button
end

function Theme.List(parent: Instance, spacing: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, spacing)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	return layout
end

function Theme.Screen(name: string, displayOrder: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = displayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	return gui
end

return Theme
