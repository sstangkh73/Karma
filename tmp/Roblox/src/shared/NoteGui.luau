-- NoteGui: สร้าง ScreenGui สำหรับระบบอ่านโน้ต 2 ชั้น
-- ชั้น 1: รูปภาพลายมือ (ImageLabel) บนกระดาษ
-- ชั้น 2: พื้นหลังมืดโปร่งแสง + ข้อความสีขาว (แบบเกม horror)

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Localization = require(script.Parent:WaitForChild("Localization"))

local NoteGui = {}

function NoteGui.create()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- ScreenGui หลัก
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "NoteScreenGui"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 10
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	-- ========================================
	-- พื้นหลังมืดสำหรับชั้น 1 (Overlay สำหรับกระดาษ)
	-- ========================================
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.Position = UDim2.new(0, 0, 0, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 1
	overlay.Parent = screenGui

	-- ========================================
	-- ชั้นที่ 1: กรอบกระดาษ + รูปลายมือ
	-- ========================================
	local noteFrame = Instance.new("Frame")
	noteFrame.Name = "NoteFrame"
	noteFrame.Size = UDim2.new(0, 500, 0, 650)
	noteFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	noteFrame.Position = UDim2.fromScale(0.5, 0.5)
	noteFrame.BackgroundColor3 = Color3.fromRGB(245, 235, 210)
	noteFrame.BorderSizePixel = 0
	noteFrame.ZIndex = 2
	noteFrame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = noteFrame

	local imageViewport = Instance.new("Frame")
	imageViewport.Name = "ImageViewport"
	imageViewport.Size = UDim2.new(1, -28, 1, -70)
	imageViewport.Position = UDim2.fromOffset(14, 14)
	imageViewport.BackgroundColor3 = Color3.fromRGB(24, 22, 19)
	imageViewport.BackgroundTransparency = 0.08
	imageViewport.BorderSizePixel = 0
	imageViewport.ClipsDescendants = true
	imageViewport.Active = true
	imageViewport.ZIndex = 3
	imageViewport.Parent = noteFrame

	-- รูปโน้ตอยู่ใน viewport เพื่อรองรับการซูมและลาก
	local handwritingLayer = Instance.new("ImageLabel")
	handwritingLayer.Name = "HandwritingLayer"
	handwritingLayer.Size = UDim2.fromScale(1, 1)
	handwritingLayer.AnchorPoint = Vector2.new(0.5, 0.5)
	handwritingLayer.Position = UDim2.fromScale(0.5, 0.5)
	handwritingLayer.BackgroundTransparency = 1
	handwritingLayer.ScaleType = Enum.ScaleType.Fit
	handwritingLayer.ZIndex = 4
	handwritingLayer.Image = ""
	handwritingLayer.Parent = imageViewport

	-- ปุ่มสลับไปชั้น 2 (อยู่ในกรอบกระดาษ)
	local toggleButton = Instance.new("TextButton")
	toggleButton.Name = "ToggleButton"
	toggleButton.Size = UDim2.new(0, 200, 0, 40)
	toggleButton.Position = UDim2.new(0.5, -100, 1, -55)
	toggleButton.BackgroundColor3 = Color3.fromRGB(139, 119, 80)
	toggleButton.BorderSizePixel = 0
	toggleButton.Font = Enum.Font.GothamBold
	toggleButton.TextSize = 16
	toggleButton.TextColor3 = Color3.new(1, 1, 1)
	toggleButton.Text = ""
	toggleButton.ZIndex = 5
	toggleButton.Visible = false
	toggleButton.Parent = noteFrame

	local toggleCorner = Instance.new("UICorner")
	toggleCorner.CornerRadius = UDim.new(0, 6)
	toggleCorner.Parent = toggleButton

	local zoomControls = Instance.new("Frame")
	zoomControls.Name = "ZoomControls"
	zoomControls.Size = UDim2.fromOffset(184, 40)
	zoomControls.AnchorPoint = Vector2.new(0.5, 1)
	zoomControls.Position = UDim2.new(0.5, 0, 1, -10)
	zoomControls.BackgroundColor3 = Color3.fromRGB(35, 31, 26)
	zoomControls.BackgroundTransparency = 0.08
	zoomControls.BorderSizePixel = 0
	zoomControls.ZIndex = 5
	zoomControls.Parent = noteFrame

	local zoomCorner = Instance.new("UICorner")
	zoomCorner.CornerRadius = UDim.new(0, 6)
	zoomCorner.Parent = zoomControls

	local function createZoomButton(name: string, text: string, x: number, width: number)
		local button = Instance.new("TextButton")
		button.Name = name
		button.Size = UDim2.fromOffset(width, 32)
		button.Position = UDim2.fromOffset(x, 4)
		button.BackgroundColor3 = Color3.fromRGB(69, 62, 51)
		button.BorderSizePixel = 0
		button.Font = Enum.Font.GothamBold
		button.TextSize = 16
		button.TextColor3 = Color3.fromRGB(245, 240, 225)
		button.Text = text
		button.ZIndex = 6
		button.Parent = zoomControls

		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 5)
		buttonCorner.Parent = button

		return button
	end

	local zoomOutButton = createZoomButton("ZoomOutButton", "-", 4, 40)
	local zoomResetButton = createZoomButton("ZoomResetButton", "100%", 48, 88)
	local zoomInButton = createZoomButton("ZoomInButton", "+", 140, 40)

	-- ปุ่มปิด (ชั้น 1)
	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.new(0, 36, 0, 36)
	closeButton.Position = UDim2.new(1, -42, 0, 6)
	closeButton.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
	closeButton.BorderSizePixel = 0
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 20
	closeButton.TextColor3 = Color3.new(1, 1, 1)
	closeButton.Text = "X"
	closeButton.ZIndex = 5
	closeButton.Parent = noteFrame

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 18)
	closeCorner.Parent = closeButton

	-- ========================================
	-- ชั้นที่ 2: พื้นหลังมืดโปร่งแสง + ข้อความขาว
	-- (แบบในรูปตัวอย่าง - เห็นฉากเกมด้านหลัง)
	-- ========================================
	local textOverlay = Instance.new("Frame")
	textOverlay.Name = "TextOverlay"
	textOverlay.Size = UDim2.new(1, 0, 1, 0)
	textOverlay.Position = UDim2.new(0, 0, 0, 0)
	textOverlay.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
	textOverlay.BackgroundTransparency = 0.25 -- มืดแต่ยังเห็นฉากด้านหลังเล็กน้อย
	textOverlay.BorderSizePixel = 0
	textOverlay.ZIndex = 10
	textOverlay.Visible = false
	textOverlay.Parent = screenGui

	-- ชื่อโน้ต (Title) ด้านบน
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(0.8, 0, 0, 50)
	titleLabel.Position = UDim2.new(0.1, 0, 0.05, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 32
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.ZIndex = 11
	titleLabel.Text = ""
	titleLabel.Parent = textOverlay

	-- เส้นคั่นใต้ Title
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Size = UDim2.new(0.6, 0, 0, 2)
	divider.Position = UDim2.new(0.2, 0, 0.05, 55)
	divider.BackgroundColor3 = Color3.fromRGB(180, 180, 180)
	divider.BackgroundTransparency = 0.5
	divider.BorderSizePixel = 0
	divider.ZIndex = 11
	divider.Parent = textOverlay

	-- ScrollingFrame สำหรับข้อความยาว
	local textLayer = Instance.new("ScrollingFrame")
	textLayer.Name = "TextLayer"
	textLayer.Size = UDim2.new(0.75, 0, 0.7, 0)
	textLayer.Position = UDim2.new(0.125, 0, 0.14, 0)
	textLayer.BackgroundTransparency = 1
	textLayer.BorderSizePixel = 0
	textLayer.ScrollBarThickness = 4
	textLayer.ScrollBarImageColor3 = Color3.fromRGB(150, 150, 150)
	textLayer.ScrollBarImageTransparency = 0.3
	textLayer.CanvasSize = UDim2.new(0, 0, 0, 0)
	textLayer.AutomaticCanvasSize = Enum.AutomaticSize.Y
	textLayer.ZIndex = 11
	textLayer.Parent = textOverlay

	-- ข้อความหลัก
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "NoteText"
	textLabel.Size = UDim2.new(1, 0, 0, 0)
	textLabel.AutomaticSize = Enum.AutomaticSize.Y
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.SourceSans
	textLabel.TextSize = 24
	textLabel.TextColor3 = Color3.fromRGB(220, 220, 220) -- ข้อความสีขาวนวล
	textLabel.TextWrapped = true
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextYAlignment = Enum.TextYAlignment.Top
	textLabel.LineHeight = 1.4
	textLabel.RichText = true
	textLabel.ZIndex = 12
	textLabel.Text = ""
	textLabel.Parent = textLayer

	-- แถบด้านล่าง: ปุ่มควบคุม
	local bottomBar = Instance.new("Frame")
	bottomBar.Name = "BottomBar"
	bottomBar.Size = UDim2.new(1, 0, 0, 60)
	bottomBar.Position = UDim2.new(0, 0, 1, -60)
	bottomBar.BackgroundTransparency = 1
	bottomBar.ZIndex = 11
	bottomBar.Parent = textOverlay

	-- ปุ่มกลับไปดูลายมือ
	local backButton = Instance.new("TextButton")
	backButton.Name = "BackButton"
	backButton.Size = UDim2.new(0, 160, 0, 36)
	backButton.Position = UDim2.new(0.5, -170, 0.5, -18)
	backButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
	backButton.BackgroundTransparency = 0.3
	backButton.BorderSizePixel = 0
	backButton.Font = Enum.Font.GothamBold
	backButton.TextSize = 14
	backButton.TextColor3 = Color3.fromRGB(200, 200, 200)
	backButton.Text = ""
	backButton.ZIndex = 12
	backButton.Visible = false
	backButton.Parent = bottomBar

	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(0, 6)
	backCorner.Parent = backButton

	-- ปุ่มปิด (ชั้น 2)
	local closeButton2 = Instance.new("TextButton")
	closeButton2.Name = "CloseButton2"
	closeButton2.Size = UDim2.new(0, 160, 0, 36)
	closeButton2.Position = UDim2.new(0.5, -80, 0.5, -18)
	closeButton2.BackgroundColor3 = Color3.fromRGB(160, 50, 50)
	closeButton2.BackgroundTransparency = 0.3
	closeButton2.BorderSizePixel = 0
	closeButton2.Font = Enum.Font.GothamBold
	closeButton2.TextSize = 14
	closeButton2.TextColor3 = Color3.fromRGB(220, 220, 220)
	closeButton2.Text = ""
	closeButton2.ZIndex = 12
	closeButton2.Parent = bottomBar

	local closeCorner2 = Instance.new("UICorner")
	closeCorner2.CornerRadius = UDim.new(0, 6)
	closeCorner2.Parent = closeButton2

	-- คำแนะนำด้านล่าง (เหมือน WASD / Q ออก)
	local hintLabel = Instance.new("TextLabel")
	hintLabel.Name = "HintLabel"
	hintLabel.Size = UDim2.new(1, 0, 0, 30)
	hintLabel.Position = UDim2.new(0, 0, 1, -30)
	hintLabel.BackgroundTransparency = 1
	hintLabel.Font = Enum.Font.Gotham
	hintLabel.TextSize = 14
	hintLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
	hintLabel.TextTransparency = 0.3
	hintLabel.Text = ""
	hintLabel.ZIndex = 12
	hintLabel.Parent = textOverlay

	local function applyLocalizedText()
		toggleButton.Text = Localization.translate("note.ui.read_text")
		backButton.Text = Localization.translate("note.ui.view_handwriting")
		closeButton2.Text = Localization.translate("note.ui.close")
		hintLabel.Text = Localization.translate("note.ui.hint")
	end

	applyLocalizedText()
	Localization.subscribeToLanguageChanged(applyLocalizedText)

	return {
		ScreenGui = screenGui,
		-- ชั้น 1
		Overlay = overlay,
		NoteFrame = noteFrame,
		ImageViewport = imageViewport,
		HandwritingLayer = handwritingLayer,
		ToggleButton = toggleButton,
		CloseButton = closeButton,
		ZoomControls = zoomControls,
		ZoomOutButton = zoomOutButton,
		ZoomResetButton = zoomResetButton,
		ZoomInButton = zoomInButton,
		-- ชั้น 2
		TextOverlay = textOverlay,
		TitleLabel = titleLabel,
		TextLayer = textLayer,
		TextLabel = textLabel,
		BackButton = backButton,
		CloseButton2 = closeButton2,
		HintLabel = hintLabel,
	}
end

return NoteGui
