-- KARMA UI design tokens and small construction helpers.
-- The theme is asset-free so every surface can be synced through Rojo.

local Theme = {}

Theme.Version = "RITUAL-01"

Theme.Colors = {
	Ink = Color3.fromRGB(6, 7, 9),
	Backdrop = Color3.fromRGB(9, 10, 12),
	Surface = Color3.fromRGB(15, 17, 20),
	SurfaceRaised = Color3.fromRGB(22, 25, 29),
	SurfaceHover = Color3.fromRGB(31, 34, 39),
	Line = Color3.fromRGB(92, 89, 82),
	LineSoft = Color3.fromRGB(59, 59, 57),
	Ivory = Color3.fromRGB(239, 233, 218),
	Text = Color3.fromRGB(220, 217, 208),
	Muted = Color3.fromRGB(151, 151, 145),
	Faint = Color3.fromRGB(103, 104, 101),
	Brass = Color3.fromRGB(177, 142, 78),
	BrassBright = Color3.fromRGB(224, 187, 106),
	BrassDark = Color3.fromRGB(93, 73, 42),
	Crimson = Color3.fromRGB(132, 34, 40),
	Danger = Color3.fromRGB(205, 65, 65),
	Success = Color3.fromRGB(91, 153, 114),
	Paper = Color3.fromRGB(224, 210, 181),
	PaperLight = Color3.fromRGB(239, 228, 204),
	PaperShadow = Color3.fromRGB(153, 132, 96),
	PaperInk = Color3.fromRGB(57, 45, 35),
	Map = Color3.fromRGB(18, 27, 29),
	MapGrid = Color3.fromRGB(86, 109, 104),
}

Theme.Fonts = {
	Display = Enum.Font.GothamBold,
	Heading = Enum.Font.GothamMedium,
	Body = Enum.Font.Gotham,
	BodyStrong = Enum.Font.GothamMedium,
	Document = Enum.Font.SourceSans,
}

Theme.Radius = {
	Small = 6,
	Medium = 10,
	Large = 16,
	Pill = 999,
}

Theme.Motion = {
	Fast = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Standard = TweenInfo.new(0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	Exit = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
}

function Theme.addCorner(parent: Instance, radius: number?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or Theme.Radius.Medium)
	corner.Parent = parent
	return corner
end

function Theme.addStroke(parent: Instance, color: Color3?, transparency: number?, thickness: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Outline"
	stroke.Color = color or Theme.Colors.Line
	stroke.Transparency = if transparency == nil then 0.35 else transparency
	stroke.Thickness = thickness or 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function Theme.addGradient(parent: Instance, topColor: Color3?, bottomColor: Color3?, rotation: number?)
	local gradient = Instance.new("UIGradient")
	gradient.Name = "SurfaceGradient"
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, topColor or Theme.Colors.SurfaceRaised),
		ColorSequenceKeypoint.new(1, bottomColor or Theme.Colors.Surface),
	})
	gradient.Rotation = rotation or 90
	gradient.Parent = parent
	return gradient
end

function Theme.styleButton(button: TextButton, variant: string?, radius: number?)
	local colors = Theme.Colors
	local selectedVariant = variant or "Secondary"

	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Font = Theme.Fonts.BodyStrong

	if selectedVariant == "Primary" then
		button.BackgroundColor3 = colors.Brass
		button.TextColor3 = colors.Ink
	elseif selectedVariant == "Danger" then
		button.BackgroundColor3 = colors.Crimson
		button.TextColor3 = colors.Ivory
	elseif selectedVariant == "Ghost" then
		button.BackgroundColor3 = colors.SurfaceRaised
		button.BackgroundTransparency = 0.35
		button.TextColor3 = colors.Text
	else
		button.BackgroundColor3 = colors.SurfaceRaised
		button.TextColor3 = colors.Ivory
	end

	Theme.addCorner(button, radius or Theme.Radius.Medium)
	return Theme.addStroke(button, selectedVariant == "Primary" and colors.BrassBright or colors.Line, 0.45)
end

function Theme.addKeyline(parent: Instance, position: UDim2?, size: UDim2?, color: Color3?)
	local line = Instance.new("Frame")
	line.Name = "Keyline"
	line.Position = position or UDim2.new()
	line.Size = size or UDim2.new(1, 0, 0, 1)
	line.BackgroundColor3 = color or Theme.Colors.Brass
	line.BackgroundTransparency = 0.35
	line.BorderSizePixel = 0
	line.Parent = parent
	return line
end

return Theme
