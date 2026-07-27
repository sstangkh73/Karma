local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Localization = require(Shared:WaitForChild("Localization"))
local PhoneConfig = require(Shared:WaitForChild("PhoneConfig"))
local NoteJournal = require(Shared:WaitForChild("NoteJournal"))
local NoteReader = require(Shared:WaitForChild("NoteReader"))

local UI_CONFIG = PhoneConfig.UI
local MAP_CONFIG = PhoneConfig.Map
local APPS = PhoneConfig.Apps

local PhoneController = {
	Name = "PhoneController",
	Priority = 60,
}

local player = Players.LocalPlayer

local state = {
	isOpen = false,
	hasOpenedPhone = false,
	activeAppId = nil,
	lastAppId = nil,
	lastMapRefresh = 0,
	lastMarkerScan = 0,
	cachedMarkers = {},
	mapZoom = 1,
	mapCenterPosition = nil,
	isPanningMap = false,
	isPinchingMap = false,
	panStartPosition = nil,
	panStartCenter = nil,
	pinchLastScale = nil,
	diarySelectedNoteId = nil,
	diaryPageIndex = 0,
}

local ui = {}

local function t(key: string, params)
	return Localization.translate(key, params)
end

local function createCorner(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function createStroke(parent: Instance, color: Color3, transparency: number?, thickness: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = transparency or 0
	stroke.Thickness = thickness or 1
	stroke.Parent = parent
	return stroke
end

local function isScreenPointInside(guiObject: GuiObject?, point: Vector2): boolean
	if not guiObject then
		return false
	end

	local position = guiObject.AbsolutePosition
	local size = guiObject.AbsoluteSize
	return point.X >= position.X
		and point.X <= position.X + size.X
		and point.Y >= position.Y
		and point.Y <= position.Y + size.Y
end

local function getCharacterRoot(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	return nil
end

local function getMarkerName(instance: Instance): string
	local explicitName = instance:GetAttribute("PhoneMapName")
	if typeof(explicitName) == "string" and explicitName ~= "" then
		return explicitName
	end

	local mapName = instance:GetAttribute("MapName")
	if typeof(mapName) == "string" and mapName ~= "" then
		return mapName
	end

	return instance.Name
end

local function getMarkerColor(instance: Instance): Color3
	local color = instance:GetAttribute("PhoneMapColor")
	if typeof(color) == "Color3" then
		return color
	end

	return Color3.fromRGB(255, 213, 94)
end

local function isMapMarker(instance: Instance): boolean
	if CollectionService:HasTag(instance, MAP_CONFIG.MarkerTagName) then
		return true
	end

	if instance:GetAttribute("PhoneMapPoint") == true or instance:GetAttribute("MapMarker") == true then
		return true
	end

	return false
end

local function getMarkerWorldPosition(instance: Instance): Vector3?
	if instance:IsA("BasePart") then
		return instance.Position
	end

	if instance:IsA("Model") then
		return instance:GetPivot().Position
	end

	if instance:IsA("Attachment") then
		return instance.WorldPosition
	end

	return nil
end

local function collectMapMarkers()
	local markers = {}

	for _, instance in ipairs(CollectionService:GetTagged(MAP_CONFIG.MarkerTagName)) do
		local position = getMarkerWorldPosition(instance)
		if position then
			table.insert(markers, {
				Name = getMarkerName(instance),
				Position = position,
				Color = getMarkerColor(instance),
			})
		end
	end

	for _, instance in ipairs(Workspace:GetDescendants()) do
		if isMapMarker(instance) and not CollectionService:HasTag(instance, MAP_CONFIG.MarkerTagName) then
			local position = getMarkerWorldPosition(instance)
			if position then
				table.insert(markers, {
					Name = getMarkerName(instance),
					Position = position,
					Color = getMarkerColor(instance),
				})
			end
		end
	end

	return markers
end

local function getCachedMapMarkers(forceRefresh: boolean?)
	local now = os.clock()
	if forceRefresh or now - state.lastMarkerScan >= MAP_CONFIG.MarkerScanInterval then
		state.lastMarkerScan = now
		state.cachedMarkers = collectMapMarkers()
	end

	return state.cachedMarkers
end

local function clearMarkerLayer()
	for _, child in ipairs(ui.markerLayer:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function getMapCenter(rootPosition: Vector3): Vector3
	if typeof(state.mapCenterPosition) ~= "Vector3" then
		state.mapCenterPosition = rootPosition
	end

	return state.mapCenterPosition
end

local function setMapCenterFromPixelDelta(pixelDelta: Vector2, mapSize: Vector2)
	if typeof(state.panStartCenter) ~= "Vector3" then
		return
	end

	local studsPerPixel = (MAP_CONFIG.StudsAcross / state.mapZoom) / math.max(1, mapSize.X)
	state.mapCenterPosition = state.panStartCenter + Vector3.new(
		-pixelDelta.X * studsPerPixel,
		0,
		-pixelDelta.Y * studsPerPixel
	)
end

local function getMapStudsPerPixel(mapSize: Vector2): number
	return (MAP_CONFIG.StudsAcross / state.mapZoom) / math.max(1, mapSize.X)
end

local function worldToMapOffset(worldPosition: Vector3, centerPosition: Vector3, mapSize: Vector2)
	local studsPerPixel = getMapStudsPerPixel(mapSize)
	local relative = worldPosition - centerPosition
	return Vector2.new(relative.X / studsPerPixel, relative.Z / studsPerPixel)
end

local function hasMapImage(): boolean
	return typeof(MAP_CONFIG.ImageId) == "string" and MAP_CONFIG.ImageId ~= ""
end

local function updateMapBackground(centerPosition: Vector3, mapSize: Vector2)
	local shouldUseImage = hasMapImage()

	if ui.mapImage then
		ui.mapImage.Visible = shouldUseImage

		if shouldUseImage then
			local imageSizeStuds = MAP_CONFIG.ImageSizeStuds
			if typeof(imageSizeStuds) ~= "Vector2" then
				imageSizeStuds = Vector2.new(MAP_CONFIG.StudsAcross, MAP_CONFIG.StudsAcross)
			end

			local imageCenter = MAP_CONFIG.ImageCenter
			if typeof(imageCenter) ~= "Vector3" then
				imageCenter = Vector3.zero
			end

			local studsPerPixel = getMapStudsPerPixel(mapSize)
			local imageOffset = worldToMapOffset(imageCenter, centerPosition, mapSize)

			ui.mapImage.Image = MAP_CONFIG.ImageId
			ui.mapImage.ImageTransparency = MAP_CONFIG.ImageTransparency or 0
			ui.mapImage.Size = UDim2.fromOffset(imageSizeStuds.X / studsPerPixel, imageSizeStuds.Y / studsPerPixel)
			ui.mapImage.Position = UDim2.fromOffset((mapSize.X / 2) + imageOffset.X, (mapSize.Y / 2) + imageOffset.Y)
		end
	end

	if ui.grid then
		ui.grid.Visible = not shouldUseImage or MAP_CONFIG.ShowGridOverImage == true
	end
end

local function createMarker(marker, offset: Vector2, mapSize: Vector2)
	local pin = Instance.new("Frame")
	pin.Name = "PlacePin"
	pin.AnchorPoint = Vector2.new(0.5, 1)
	pin.Size = UDim2.fromOffset(92, 42)
	pin.Position = UDim2.fromOffset((mapSize.X / 2) + offset.X, (mapSize.Y / 2) + offset.Y)
	pin.BackgroundTransparency = 1
	pin.ZIndex = 25
	pin.Parent = ui.markerLayer

	local stem = Instance.new("Frame")
	stem.Name = "Stem"
	stem.AnchorPoint = Vector2.new(0.5, 1)
	stem.Position = UDim2.new(0.5, 0, 1, 0)
	stem.Size = UDim2.fromOffset(3, 16)
	stem.BackgroundColor3 = marker.Color
	stem.BorderSizePixel = 0
	stem.ZIndex = 25
	stem.Parent = pin
	createCorner(stem, 3)

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 1)
	dot.Size = UDim2.fromOffset(14, 14)
	dot.Position = UDim2.new(0.5, 0, 1, -12)
	dot.BackgroundColor3 = marker.Color
	dot.BorderSizePixel = 0
	dot.ZIndex = 26
	dot.Parent = pin
	createCorner(dot, 14)
	createStroke(dot, Color3.fromRGB(18, 21, 28), 0, 2)

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 0)
	label.Size = UDim2.fromOffset(92, 20)
	label.BackgroundColor3 = Color3.fromRGB(16, 19, 25)
	label.BackgroundTransparency = 0.06
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.Text = marker.Name
	label.TextColor3 = Color3.fromRGB(245, 247, 252)
	label.TextSize = 11
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.ZIndex = 27
	label.Parent = pin
	createCorner(label, 7)
	createStroke(label, marker.Color, 0.2)
end

local function updateZoomLabel()
	if ui.zoomLabel then
		ui.zoomLabel.Text = string.format("%.1fx", state.mapZoom)
	end
end

local function setMapZoom(nextZoom: number)
	state.mapZoom = math.clamp(nextZoom, MAP_CONFIG.MinZoom, MAP_CONFIG.MaxZoom)
	updateZoomLabel()
end

local function updateMap()
	if not ui.mapCanvas or not ui.mapCanvas.Visible then
		return
	end

	local root = getCharacterRoot()
	if not root then
		ui.locationLabel.Text = "Waiting for character..."
		return
	end

	local mapSize = ui.mapCanvas.AbsoluteSize
	if mapSize.X <= 0 or mapSize.Y <= 0 then
		return
	end

	clearMarkerLayer()

	local rootPosition = root.Position
	local centerPosition = getMapCenter(rootPosition)
	ui.locationLabel.Text = string.format("X %.0f  Z %.0f  Zoom %.1fx", rootPosition.X, rootPosition.Z, state.mapZoom)
	updateZoomLabel()
	updateMapBackground(centerPosition, mapSize)

	local halfWidth = mapSize.X / 2
	local halfHeight = mapSize.Y / 2

	local playerOffset = worldToMapOffset(rootPosition, centerPosition, mapSize)
	ui.playerDot.Visible = math.abs(playerOffset.X) <= halfWidth and math.abs(playerOffset.Y) <= halfHeight
	if ui.playerDot.Visible then
		ui.playerDot.Position = UDim2.fromOffset(halfWidth + playerOffset.X, halfHeight + playerOffset.Y)
	end

	for _, marker in ipairs(getCachedMapMarkers(false)) do
		local offset = worldToMapOffset(marker.Position, centerPosition, mapSize)
		if math.abs(offset.X) <= halfWidth and math.abs(offset.Y) <= halfHeight then
			createMarker(marker, offset, mapSize)
		end
	end
end

local function formatDiaryMeta(entry)
	local timesLabel = if entry.readCount == 1
		then t("phone.diary.meta.single_read", { count = tostring(entry.readCount) })
		else t("phone.diary.meta.multi_read", { count = tostring(entry.readCount) })
	return string.format("%s  |  %s", timesLabel, os.date("%d/%m %H:%M", entry.lastReadAt))
end

local function getDiaryEntries()
	return NoteJournal.getEntries()
end

local function getDiaryEntryIndex(entries, noteId: string?): number?
	if typeof(noteId) ~= "string" or noteId == "" then
		return nil
	end

	for index, entry in ipairs(entries) do
		if entry.id == noteId then
			return index
		end
	end

	return nil
end

local function getDiaryPageIndexForEntry(entryIndex: number): number
	return math.max(1, entryIndex)
end

local function setDiaryPage(pageUi, entry, entryIndex: number?)
	local hasEntry = entry ~= nil
	pageUi.Frame.BackgroundColor3 = if hasEntry then Color3.fromRGB(248, 239, 222) else Color3.fromRGB(235, 227, 214)
	pageUi.Stroke.Color = if hasEntry then Color3.fromRGB(168, 104, 54) else Color3.fromRGB(168, 145, 118)
	pageUi.Stroke.Transparency = if hasEntry then 0.2 else 0.48
	pageUi.Highlight.BackgroundTransparency = if hasEntry then 0.84 else 0.95
	pageUi.Highlight.Visible = hasEntry
	pageUi.Badge.Text = if hasEntry and entryIndex
		then t("phone.diary.badge.note", { index = string.format("%02d", entryIndex) })
		else t("phone.diary.badge.blank")
	pageUi.Title.Text = if hasEntry and entry.title ~= ""
		then entry.title
		else if hasEntry then t("phone.diary.page.untitled") else t("phone.diary.page.blank")
	pageUi.Meta.Text = if hasEntry then formatDiaryMeta(entry) else t("phone.diary.page.fill_blank")
	pageUi.Body.Text = if hasEntry and entry.typedText ~= ""
		then entry.typedText
		else if hasEntry then t("phone.diary.page.no_typed_text") else t("phone.diary.page.next_recovered")
	pageUi.ReadFullButton.Visible = hasEntry
	pageUi.BodyScroll.CanvasPosition = Vector2.zero
end

function PhoneController:refreshDiaryList()
	if not ui.diaryTabStrip or not ui.diaryPage or not ui.diaryEmptyState then
		return
	end

	for _, child in ipairs(ui.diaryTabStrip:GetChildren()) do
		if child:IsA("GuiButton") or (child:IsA("Frame") and child.Name == "DiaryBookmark") then
			child:Destroy()
		end
	end

	local entries = getDiaryEntries()
	local entryCount = #entries

	ui.diaryEmptyState.Text = t("phone.diary.empty_state")
	ui.diaryEmptyState.Visible = entryCount == 0
	ui.diaryBook.Visible = true
	ui.diaryNavigation.Visible = entryCount > 0
	ui.diaryTabStrip.Visible = entryCount > 0

	if entryCount == 0 then
		state.diarySelectedNoteId = nil
		state.diaryPageIndex = 0
		ui.diaryPageCounter.Text = "0 / 0"
		setDiaryPage(ui.diaryPage, nil, nil)
		return
	end

	local selectedIndex = getDiaryEntryIndex(entries, state.diarySelectedNoteId)
	if not selectedIndex then
		selectedIndex = 1
		state.diarySelectedNoteId = entries[selectedIndex].id
	end

	state.diaryPageIndex = math.clamp(getDiaryPageIndexForEntry(selectedIndex), 1, entryCount)
	local currentEntry = entries[state.diaryPageIndex]

	ui.diaryPageCounter.Text = string.format("%d / %d", state.diaryPageIndex, entryCount)
	setDiaryPage(ui.diaryPage, currentEntry, state.diaryPageIndex)

	ui.diaryPrevButton.BackgroundTransparency = if state.diaryPageIndex <= 1 then 0.45 else 0.08
	ui.diaryNextButton.BackgroundTransparency = if state.diaryPageIndex >= entryCount then 0.45 else 0.08

	for index, entry in ipairs(entries) do
		local tab = Instance.new("TextButton")
		tab.Name = "DiaryBookmark"
		tab.Size = UDim2.fromOffset(78, if index % 2 == 0 then 30 else 26)
		tab.BackgroundColor3 = if entry.id == state.diarySelectedNoteId
			then Color3.fromRGB(169, 103, 56)
			else Color3.fromRGB(132, 91, 58)
		tab.BorderSizePixel = 0
		tab.AutoButtonColor = false
		tab.LayoutOrder = index
		tab.Text = entry.title ~= "" and entry.title or t("phone.diary.tab.note", { index = string.format("%02d", index) })
		tab.TextColor3 = Color3.fromRGB(250, 241, 225)
		tab.TextSize = 10
		tab.Font = Enum.Font.GothamBold
		tab.TextTruncate = Enum.TextTruncate.AtEnd
		tab.TextXAlignment = Enum.TextXAlignment.Left
		tab.TextYAlignment = Enum.TextYAlignment.Center
		tab.ZIndex = 23
		tab.Parent = ui.diaryTabStrip
		createCorner(tab, 9)

		local tabPadding = Instance.new("UIPadding")
		tabPadding.PaddingLeft = UDim.new(0, 10)
		tabPadding.PaddingRight = UDim.new(0, 8)
		tabPadding.Parent = tab

		local stitch = Instance.new("Frame")
		stitch.Name = "Stitch"
		stitch.Size = UDim2.new(1, -18, 0, 2)
		stitch.Position = UDim2.new(0, 9, 1, -7)
		stitch.BackgroundColor3 = Color3.fromRGB(243, 221, 197)
		stitch.BackgroundTransparency = 0.32
		stitch.BorderSizePixel = 0
		stitch.ZIndex = 24
		stitch.Parent = tab
		createCorner(stitch, 2)

		tab.Activated:Connect(function()
			self:openDiaryEntry(entry.id)
		end)
	end
end

function PhoneController:showDiaryList()
	local entries = getDiaryEntries()
	if #entries > 0 then
		if not getDiaryEntryIndex(entries, state.diarySelectedNoteId) then
			state.diarySelectedNoteId = entries[1].id
		end

		local selectedIndex = getDiaryEntryIndex(entries, state.diarySelectedNoteId) or 1
		state.diaryPageIndex = getDiaryPageIndexForEntry(selectedIndex)
	else
		state.diarySelectedNoteId = nil
		state.diaryPageIndex = 0
	end

	self:refreshDiaryList()
end

function PhoneController:openDiaryEntry(noteId: string)
	local entries = getDiaryEntries()
	local entryIndex = getDiaryEntryIndex(entries, noteId)
	if not entryIndex then
		self:showDiaryList()
		return
	end

	state.diarySelectedNoteId = noteId
	state.diaryPageIndex = getDiaryPageIndexForEntry(entryIndex)
	self:refreshDiaryList()
end

function PhoneController:stepDiaryPage(direction: number)
	local entries = getDiaryEntries()
	if #entries == 0 then
		self:refreshDiaryList()
		return
	end

	local currentIndex = if state.diaryPageIndex > 0 then state.diaryPageIndex else 1
	state.diaryPageIndex = math.clamp(currentIndex + direction, 1, #entries)

	local nextEntry = entries[state.diaryPageIndex]
	if nextEntry then
		state.diarySelectedNoteId = nextEntry.id
	end

	self:refreshDiaryList()
end

function PhoneController:openDiaryFullNote()
	local noteId = state.diarySelectedNoteId
	if typeof(noteId) ~= "string" or noteId == "" then
		return
	end

	self:setOpen(false)
	task.defer(function()
		NoteReader.requestOpen(noteId)
	end)
end

function PhoneController:setOpen(shouldOpen: boolean)
	if state.isOpen == shouldOpen then
		return
	end

	state.isOpen = shouldOpen
	ui.screenGui.Enabled = true

	if shouldOpen then
		getCachedMapMarkers(true)
		local root = getCharacterRoot()
		if root and typeof(state.mapCenterPosition) ~= "Vector3" then
			state.mapCenterPosition = root.Position
		end

		if state.hasOpenedPhone and state.lastAppId then
			self:openApp(state.lastAppId)
		else
			self:showHome()
			state.hasOpenedPhone = true
		end

		ui.phone.Position = UDim2.new(1, -28, 1, 24)
		ui.phone.GroupTransparency = 1
		TweenService:Create(ui.phone, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(1, -28, 1, -28),
			GroupTransparency = 0,
		}):Play()
		updateMap()
	else
		local tween = TweenService:Create(ui.phone, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(1, -28, 1, 24),
			GroupTransparency = 1,
		})
		tween.Completed:Once(function()
			if not state.isOpen then
				ui.screenGui.Enabled = false
			end
		end)
		tween:Play()
	end
end

function PhoneController:toggle()
	self:setOpen(not state.isOpen)
end

function PhoneController:openApp(appId: string)
	state.activeAppId = appId
	state.lastAppId = appId
	ui.homePage.Visible = false
	ui.appPage.Visible = true
	ui.mapCanvas.Visible = appId == "Map"
	ui.locationLabel.Visible = appId == "Map"
	ui.diaryContainer.Visible = appId == "Diary"
	ui.appTitle.Text = appId

	if appId == "Diary" then
		self:showDiaryList()
	else
		state.diarySelectedNoteId = nil
		state.diaryPageIndex = 0
	end

	updateMap()
end

function PhoneController:showHome()
	state.activeAppId = nil
	ui.homePage.Visible = true
	ui.appPage.Visible = false
end

function PhoneController:centerMapOnPlayer()
	local root = getCharacterRoot()
	if root then
		state.mapCenterPosition = root.Position
		updateMap()
	end
end

function PhoneController:handleBack()
	if not state.isOpen then
		return Enum.ContextActionResult.Pass
	end

	if ui.appPage.Visible then
		self:showHome()
	else
		self:setOpen(false)
	end

	return Enum.ContextActionResult.Sink
end

function PhoneController:createAppButton(appInfo, index: number)
	local button = Instance.new("TextButton")
	button.Name = appInfo.Id .. "Button"
	button.Size = UDim2.fromOffset(58, 70)
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.Text = ""
	button.LayoutOrder = index
	button.ZIndex = 20
	button.Parent = ui.appGrid

	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	icon.Size = UDim2.fromOffset(50, 50)
	icon.Position = UDim2.fromOffset(4, 0)
	icon.BackgroundColor3 = appInfo.Accent
	icon.BorderSizePixel = 0
	icon.ZIndex = 21
	icon.Parent = button
	createCorner(icon, 12)

	if appInfo.Id == "Diary" then
		local spine = Instance.new("Frame")
		spine.Name = "Spine"
		spine.Size = UDim2.new(0, 8, 1, 0)
		spine.BackgroundColor3 = Color3.fromRGB(126, 76, 41)
		spine.BorderSizePixel = 0
		spine.ZIndex = 22
		spine.Parent = icon
		createCorner(spine, 10)

		local page = Instance.new("Frame")
		page.Name = "Page"
		page.Size = UDim2.new(1, -14, 1, -12)
		page.Position = UDim2.fromOffset(10, 6)
		page.BackgroundColor3 = Color3.fromRGB(247, 238, 220)
		page.BorderSizePixel = 0
		page.ZIndex = 22
		page.Parent = icon
		createCorner(page, 9)

		for lineIndex = 1, 3 do
			local line = Instance.new("Frame")
			line.Name = "Line"
			line.Size = UDim2.new(1, -10, 0, 2)
			line.Position = UDim2.new(0, 5, 0, 9 + ((lineIndex - 1) * 10))
			line.BackgroundColor3 = Color3.fromRGB(199, 178, 148)
			line.BackgroundTransparency = 0.15
			line.BorderSizePixel = 0
			line.ZIndex = 23
			line.Parent = page
			createCorner(line, 2)
		end

		local bookmark = Instance.new("Frame")
		bookmark.Name = "Bookmark"
		bookmark.AnchorPoint = Vector2.new(1, 0)
		bookmark.Position = UDim2.new(1, -4, 0, 0)
		bookmark.Size = UDim2.fromOffset(9, 16)
		bookmark.BackgroundColor3 = Color3.fromRGB(190, 54, 54)
		bookmark.BorderSizePixel = 0
		bookmark.ZIndex = 24
		bookmark.Parent = icon
		createCorner(bookmark, 4)
	else
		local iconText = Instance.new("TextLabel")
		iconText.Name = "IconText"
		iconText.Size = UDim2.fromScale(1, 1)
		iconText.BackgroundTransparency = 1
		iconText.Font = Enum.Font.GothamBold
		iconText.Text = appInfo.Icon
		iconText.TextColor3 = Color3.fromRGB(255, 255, 255)
		iconText.TextSize = 13
		iconText.ZIndex = 22
		iconText.Parent = icon
	end

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Position = UDim2.fromOffset(0, 53)
	label.Size = UDim2.fromOffset(58, 16)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.Text = appInfo.Name
	label.TextColor3 = Color3.fromRGB(236, 240, 247)
	label.TextSize = 11
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.ZIndex = 21
	label.Parent = button

	button.Activated:Connect(function()
		self:openApp(appInfo.Id)
	end)
end

function PhoneController:createMapUi()
	local mapCanvas = Instance.new("Frame")
	mapCanvas.Name = "MapCanvas"
	mapCanvas.Position = UDim2.fromOffset(14, 52)
	mapCanvas.Size = UDim2.new(1, -28, 1, -110)
	mapCanvas.BackgroundColor3 = Color3.fromRGB(26, 35, 42)
	mapCanvas.BorderSizePixel = 0
	mapCanvas.ClipsDescendants = true
	mapCanvas.Active = true
	mapCanvas.ZIndex = 18
	mapCanvas.Parent = ui.appPage
	createCorner(mapCanvas, 14)
	createStroke(mapCanvas, Color3.fromRGB(86, 105, 116), 0.25)

	local mapImage = Instance.new("ImageLabel")
	mapImage.Name = "MapImage"
	mapImage.AnchorPoint = Vector2.new(0.5, 0.5)
	mapImage.Position = UDim2.fromScale(0.5, 0.5)
	mapImage.Size = UDim2.fromScale(1, 1)
	mapImage.BackgroundTransparency = 1
	mapImage.BorderSizePixel = 0
	mapImage.ScaleType = Enum.ScaleType.Stretch
	mapImage.Visible = false
	mapImage.ZIndex = 19
	mapImage.Parent = mapCanvas

	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.Size = UDim2.fromScale(1, 1)
	grid.BackgroundColor3 = Color3.fromRGB(31, 43, 50)
	grid.BackgroundTransparency = 0.18
	grid.BorderSizePixel = 0
	grid.ZIndex = 19
	grid.Parent = mapCanvas

	for i = 1, 5 do
		local vertical = Instance.new("Frame")
		vertical.Name = "GridVertical"
		vertical.AnchorPoint = Vector2.new(0.5, 0)
		vertical.Position = UDim2.new(i / 6, 0, 0, 0)
		vertical.Size = UDim2.new(0, 1, 1, 0)
		vertical.BackgroundColor3 = Color3.fromRGB(82, 105, 114)
		vertical.BackgroundTransparency = 0.72
		vertical.BorderSizePixel = 0
		vertical.ZIndex = 20
		vertical.Parent = mapCanvas

		local horizontal = Instance.new("Frame")
		horizontal.Name = "GridHorizontal"
		horizontal.AnchorPoint = Vector2.new(0, 0.5)
		horizontal.Position = UDim2.new(0, 0, i / 6, 0)
		horizontal.Size = UDim2.new(1, 0, 0, 1)
		horizontal.BackgroundColor3 = Color3.fromRGB(82, 105, 114)
		horizontal.BackgroundTransparency = 0.72
		horizontal.BorderSizePixel = 0
		horizontal.ZIndex = 20
		horizontal.Parent = mapCanvas
	end

	local markerLayer = Instance.new("Frame")
	markerLayer.Name = "MarkerLayer"
	markerLayer.Size = UDim2.fromScale(1, 1)
	markerLayer.BackgroundTransparency = 1
	markerLayer.ZIndex = 22
	markerLayer.Parent = mapCanvas

	local playerDot = Instance.new("Frame")
	playerDot.Name = "PlayerDot"
	playerDot.AnchorPoint = Vector2.new(0.5, 0.5)
	playerDot.Position = UDim2.fromScale(0.5, 0.5)
	playerDot.Size = UDim2.fromOffset(18, 18)
	playerDot.BackgroundColor3 = Color3.fromRGB(245, 248, 255)
	playerDot.BorderSizePixel = 0
	playerDot.ZIndex = 30
	playerDot.Parent = mapCanvas
	createCorner(playerDot, 18)
	createStroke(playerDot, Color3.fromRGB(64, 142, 255), 0, 3)

	local playerDotInner = Instance.new("Frame")
	playerDotInner.Name = "Inner"
	playerDotInner.AnchorPoint = Vector2.new(0.5, 0.5)
	playerDotInner.Position = UDim2.fromScale(0.5, 0.5)
	playerDotInner.Size = UDim2.fromOffset(6, 6)
	playerDotInner.BackgroundColor3 = Color3.fromRGB(64, 142, 255)
	playerDotInner.BorderSizePixel = 0
	playerDotInner.ZIndex = 31
	playerDotInner.Parent = playerDot
	createCorner(playerDotInner, 6)

	local locationLabel = Instance.new("TextLabel")
	locationLabel.Name = "LocationLabel"
	locationLabel.Position = UDim2.new(0, 14, 1, -48)
	locationLabel.Size = UDim2.new(1, -28, 0, 30)
	locationLabel.BackgroundColor3 = Color3.fromRGB(19, 23, 29)
	locationLabel.BackgroundTransparency = 0.08
	locationLabel.BorderSizePixel = 0
	locationLabel.Font = Enum.Font.GothamMedium
	locationLabel.Text = "Waiting for character..."
	locationLabel.TextColor3 = Color3.fromRGB(225, 230, 238)
	locationLabel.TextSize = 12
	locationLabel.TextXAlignment = Enum.TextXAlignment.Center
	locationLabel.ZIndex = 24
	locationLabel.Parent = ui.appPage
	createCorner(locationLabel, 10)

	ui.mapCanvas = mapCanvas
	ui.mapImage = mapImage
	ui.grid = grid
	ui.markerLayer = markerLayer
	ui.playerDot = playerDot
	ui.locationLabel = locationLabel

	mapCanvas.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton2 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		if state.isPinchingMap then
			return
		end

		local inputPosition = Vector2.new(input.Position.X, input.Position.Y)
		local root = getCharacterRoot()
		if not root then
			return
		end

		state.isPanningMap = true
		state.panStartPosition = inputPosition
		state.panStartCenter = getMapCenter(root.Position)
	end)

	mapCanvas.InputChanged:Connect(function(input)
		if not state.isPanningMap then
			return
		end

		if state.isPinchingMap then
			return
		end

		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		if typeof(state.panStartPosition) ~= "Vector2" then
			return
		end

		local currentPosition = Vector2.new(input.Position.X, input.Position.Y)
		setMapCenterFromPixelDelta(currentPosition - state.panStartPosition, mapCanvas.AbsoluteSize)
		updateMap()
	end)

	mapCanvas.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.Touch then
			state.isPanningMap = false
			state.panStartPosition = nil
			state.panStartCenter = nil
		end
	end)
end

function PhoneController:createDiaryUi()
	local diaryContainer = Instance.new("Frame")
	diaryContainer.Name = "DiaryContainer"
	diaryContainer.Position = UDim2.fromOffset(10, 48)
	diaryContainer.Size = UDim2.new(1, -20, 1, -58)
	diaryContainer.BackgroundTransparency = 1
	diaryContainer.BorderSizePixel = 0
	diaryContainer.Visible = false
	diaryContainer.ZIndex = 18
	diaryContainer.Parent = ui.appPage
	local bookmarkBar = Instance.new("ScrollingFrame")
	bookmarkBar.Name = "DiaryTabStrip"
	bookmarkBar.Position = UDim2.fromOffset(0, 0)
	bookmarkBar.Size = UDim2.new(1, 0, 0, 36)
	bookmarkBar.BackgroundTransparency = 1
	bookmarkBar.BorderSizePixel = 0
	bookmarkBar.CanvasSize = UDim2.new()
	bookmarkBar.AutomaticCanvasSize = Enum.AutomaticSize.X
	bookmarkBar.ScrollBarThickness = 0
	bookmarkBar.ScrollingDirection = Enum.ScrollingDirection.X
	bookmarkBar.ZIndex = 21
	bookmarkBar.Parent = diaryContainer

	local bookmarkPadding = Instance.new("UIPadding")
	bookmarkPadding.PaddingLeft = UDim.new(0, 8)
	bookmarkPadding.PaddingRight = UDim.new(0, 8)
	bookmarkPadding.Parent = bookmarkBar

	local bookmarkLayout = Instance.new("UIListLayout")
	bookmarkLayout.FillDirection = Enum.FillDirection.Horizontal
	bookmarkLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	bookmarkLayout.Padding = UDim.new(0, 6)
	bookmarkLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bookmarkLayout.Parent = bookmarkBar

	local bookShadow = Instance.new("Frame")
	bookShadow.Name = "BookShadow"
	bookShadow.Position = UDim2.fromOffset(4, 34)
	bookShadow.Size = UDim2.new(1, -8, 1, -48)
	bookShadow.BackgroundColor3 = Color3.fromRGB(36, 21, 13)
	bookShadow.BackgroundTransparency = 0.38
	bookShadow.BorderSizePixel = 0
	bookShadow.ZIndex = 18
	bookShadow.Parent = diaryContainer
	createCorner(bookShadow, 20)

	local diaryBook = Instance.new("Frame")
	diaryBook.Name = "DiaryBook"
	diaryBook.Position = UDim2.fromOffset(0, 28)
	diaryBook.Size = UDim2.new(1, 0, 1, -44)
	diaryBook.BackgroundColor3 = Color3.fromRGB(98, 68, 43)
	diaryBook.BorderSizePixel = 0
	diaryBook.ZIndex = 19
	diaryBook.Parent = diaryContainer
	createCorner(diaryBook, 20)
	createStroke(diaryBook, Color3.fromRGB(206, 183, 148), 0.45)

	local bookTop = Instance.new("Frame")
	bookTop.Name = "BookTop"
	bookTop.Size = UDim2.new(1, -12, 0, 18)
	bookTop.Position = UDim2.fromOffset(6, 6)
	bookTop.BackgroundColor3 = Color3.fromRGB(123, 89, 59)
	bookTop.BorderSizePixel = 0
	bookTop.ZIndex = 20
	bookTop.Parent = diaryBook
	createCorner(bookTop, 12)

	local navigation = Instance.new("Frame")
	navigation.Name = "DiaryNavigation"
	navigation.Position = UDim2.new(0, 14, 0, 10)
	navigation.Size = UDim2.new(1, -28, 0, 30)
	navigation.BackgroundTransparency = 1
	navigation.ZIndex = 22
	navigation.Parent = diaryBook

	local prevButton = Instance.new("TextButton")
	prevButton.Name = "PrevButton"
	prevButton.Size = UDim2.fromOffset(30, 24)
	prevButton.Position = UDim2.fromOffset(0, 0)
	prevButton.BackgroundColor3 = Color3.fromRGB(136, 97, 63)
	prevButton.BorderSizePixel = 0
	prevButton.AutoButtonColor = false
	prevButton.Font = Enum.Font.GothamBold
	prevButton.Text = "<"
	prevButton.TextColor3 = Color3.fromRGB(248, 236, 218)
	prevButton.TextSize = 14
	prevButton.ZIndex = 23
	prevButton.Parent = navigation
	createCorner(prevButton, 9)

	local spreadCounter = Instance.new("TextLabel")
	spreadCounter.Name = "SpreadCounter"
	spreadCounter.AnchorPoint = Vector2.new(0.5, 0)
	spreadCounter.Position = UDim2.new(0.5, 0, 0, 1)
	spreadCounter.Size = UDim2.fromOffset(82, 22)
	spreadCounter.BackgroundTransparency = 1
	spreadCounter.Font = Enum.Font.GothamBold
	spreadCounter.Text = "0 / 0"
	spreadCounter.TextColor3 = Color3.fromRGB(239, 225, 204)
	spreadCounter.TextSize = 12
	spreadCounter.ZIndex = 23
	spreadCounter.Parent = navigation

	local nextButton = Instance.new("TextButton")
	nextButton.Name = "NextButton"
	nextButton.AnchorPoint = Vector2.new(1, 0)
	nextButton.Position = UDim2.new(1, 0, 0, 0)
	nextButton.Size = UDim2.fromOffset(30, 24)
	nextButton.BackgroundColor3 = Color3.fromRGB(136, 97, 63)
	nextButton.BorderSizePixel = 0
	nextButton.AutoButtonColor = false
	nextButton.Font = Enum.Font.GothamBold
	nextButton.Text = ">"
	nextButton.TextColor3 = Color3.fromRGB(248, 236, 218)
	nextButton.TextSize = 14
	nextButton.ZIndex = 23
	nextButton.Parent = navigation
	createCorner(nextButton, 9)

	local pageFrame = Instance.new("Frame")
	pageFrame.Name = "DiaryPage"
	pageFrame.Position = UDim2.fromOffset(12, 44)
	pageFrame.Size = UDim2.new(1, -24, 1, -58)
	pageFrame.BackgroundColor3 = Color3.fromRGB(248, 239, 222)
	pageFrame.BorderSizePixel = 0
	pageFrame.ZIndex = 22
	pageFrame.Parent = diaryBook
	createCorner(pageFrame, 16)

	local pageStroke = createStroke(pageFrame, Color3.fromRGB(168, 145, 118), 0.45)

	local highlight = Instance.new("Frame")
	highlight.Name = "Highlight"
	highlight.Size = UDim2.new(1, -14, 1, -14)
	highlight.Position = UDim2.fromOffset(7, 7)
	highlight.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	highlight.BackgroundTransparency = 0.9
	highlight.BorderSizePixel = 0
	highlight.ZIndex = 22
	highlight.Parent = pageFrame
	createCorner(highlight, 13)

	local topFold = Instance.new("Frame")
	topFold.Name = "TopFold"
	topFold.Size = UDim2.new(1, -18, 0, 12)
	topFold.Position = UDim2.fromOffset(9, 8)
	topFold.BackgroundColor3 = Color3.fromRGB(231, 214, 188)
	topFold.BackgroundTransparency = 0.32
	topFold.BorderSizePixel = 0
	topFold.ZIndex = 23
	topFold.Parent = pageFrame
	createCorner(topFold, 8)

	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.Position = UDim2.fromOffset(16, 14)
	badge.Size = UDim2.new(1, -32, 0, 16)
	badge.BackgroundTransparency = 1
	badge.Font = Enum.Font.GothamBold
	badge.Text = ""
	badge.TextColor3 = Color3.fromRGB(153, 107, 68)
	badge.TextSize = 9
	badge.TextXAlignment = Enum.TextXAlignment.Left
	badge.ZIndex = 24
	badge.Parent = pageFrame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(16, 32)
	title.Size = UDim2.new(1, -32, 0, 34)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = ""
	title.TextColor3 = Color3.fromRGB(76, 52, 35)
	title.TextSize = 15
	title.TextWrapped = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Top
	title.ZIndex = 24
	title.Parent = pageFrame

	local meta = Instance.new("TextLabel")
	meta.Name = "Meta"
	meta.Position = UDim2.fromOffset(16, 68)
	meta.Size = UDim2.new(1, -132, 0, 14)
	meta.BackgroundTransparency = 1
	meta.Font = Enum.Font.GothamMedium
	meta.Text = ""
	meta.TextColor3 = Color3.fromRGB(144, 111, 80)
	meta.TextSize = 9
	meta.TextXAlignment = Enum.TextXAlignment.Left
	meta.ZIndex = 24
	meta.Parent = pageFrame

	local readFullButton = Instance.new("TextButton")
	readFullButton.Name = "ReadFullButton"
	readFullButton.AnchorPoint = Vector2.new(1, 0)
	readFullButton.Position = UDim2.new(1, -16, 0, 62)
	readFullButton.Size = UDim2.fromOffset(98, 24)
	readFullButton.BackgroundColor3 = Color3.fromRGB(154, 102, 59)
	readFullButton.BorderSizePixel = 0
	readFullButton.AutoButtonColor = true
	readFullButton.Font = Enum.Font.GothamBold
	readFullButton.Text = "Read Full"
	readFullButton.TextColor3 = Color3.fromRGB(251, 241, 224)
	readFullButton.TextSize = 11
	readFullButton.Visible = false
	readFullButton.ZIndex = 24
	readFullButton.Parent = pageFrame
	createCorner(readFullButton, 10)

	for lineIndex = 1, 10 do
		local line = Instance.new("Frame")
		line.Name = "RuleLine"
		line.Size = UDim2.new(1, -28, 0, 1)
		line.Position = UDim2.new(0, 14, 0, 108 + ((lineIndex - 1) * 18))
		line.BackgroundColor3 = Color3.fromRGB(201, 189, 168)
		line.BackgroundTransparency = 0.35
		line.BorderSizePixel = 0
		line.ZIndex = 22
		line.Parent = pageFrame
	end

	local bodyScroll = Instance.new("ScrollingFrame")
	bodyScroll.Name = "BodyScroll"
	bodyScroll.Position = UDim2.fromOffset(14, 96)
	bodyScroll.Size = UDim2.new(1, -28, 1, -110)
	bodyScroll.BackgroundTransparency = 1
	bodyScroll.BorderSizePixel = 0
	bodyScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	bodyScroll.CanvasSize = UDim2.new()
	bodyScroll.ScrollBarThickness = 3
	bodyScroll.ScrollBarImageColor3 = Color3.fromRGB(155, 124, 94)
	bodyScroll.ZIndex = 24
	bodyScroll.Parent = pageFrame

	local bodyPadding = Instance.new("UIPadding")
	bodyPadding.PaddingBottom = UDim.new(0, 12)
	bodyPadding.Parent = bodyScroll

	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.SourceSans
	body.Text = ""
	body.TextColor3 = Color3.fromRGB(88, 67, 50)
	body.TextSize = 20
	body.LineHeight = 1.16
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.ZIndex = 25
	body.Parent = bodyScroll

	local diaryEmptyState = Instance.new("TextLabel")
	diaryEmptyState.Name = "DiaryEmptyState"
	diaryEmptyState.AnchorPoint = Vector2.new(0.5, 0.5)
	diaryEmptyState.Position = UDim2.fromScale(0.5, 0.54)
	diaryEmptyState.Size = UDim2.new(1, -44, 0, 80)
	diaryEmptyState.BackgroundTransparency = 1
	diaryEmptyState.Font = Enum.Font.GothamMedium
	diaryEmptyState.Text = t("phone.diary.empty_state")
	diaryEmptyState.TextColor3 = Color3.fromRGB(218, 201, 182)
	diaryEmptyState.TextSize = 13
	diaryEmptyState.TextWrapped = true
	diaryEmptyState.ZIndex = 24
	diaryEmptyState.Parent = diaryBook

	prevButton.Activated:Connect(function()
		self:stepDiaryPage(-1)
	end)

	nextButton.Activated:Connect(function()
		self:stepDiaryPage(1)
	end)

	readFullButton.Activated:Connect(function()
		self:openDiaryFullNote()
	end)

	ui.diaryContainer = diaryContainer
	ui.diaryBook = diaryBook
	ui.diaryNavigation = navigation
	ui.diaryPrevButton = prevButton
	ui.diaryNextButton = nextButton
	ui.diaryPageCounter = spreadCounter
	ui.diaryTabStrip = bookmarkBar
	ui.diaryPage = {
		Frame = pageFrame,
		Stroke = pageStroke,
		Highlight = highlight,
		Badge = badge,
		Title = title,
		Meta = meta,
		ReadFullButton = readFullButton,
		BodyScroll = bodyScroll,
		Body = body,
	}
	ui.diaryEmptyState = diaryEmptyState
end

function PhoneController:createHintUi(playerGui: PlayerGui)
	local hintGui = Instance.new("ScreenGui")
	hintGui.Name = "PhoneHintGui"
	hintGui.ResetOnSpawn = false
	hintGui.IgnoreGuiInset = true
	hintGui.DisplayOrder = UI_CONFIG.DisplayOrder - 10
	hintGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	hintGui.Parent = playerGui

	local hintLabel = Instance.new("TextLabel")
	hintLabel.Name = "ShortcutHint"
	hintLabel.AnchorPoint = Vector2.new(1, 1)
	hintLabel.Position = UDim2.new(1, -22, 1, -28)
	hintLabel.Size = UDim2.fromOffset(220, 48)
	hintLabel.BackgroundTransparency = 1
	hintLabel.Font = Enum.Font.GothamMedium
	hintLabel.Text = "V to unlock mouse\nP to open phone"
	hintLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	hintLabel.TextSize = 15
	hintLabel.TextTransparency = 0.04
	hintLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	hintLabel.TextStrokeTransparency = 0.45
	hintLabel.TextXAlignment = Enum.TextXAlignment.Right
	hintLabel.TextYAlignment = Enum.TextYAlignment.Bottom
	hintLabel.ZIndex = 10
	hintLabel.Parent = hintGui

	local hintScale = Instance.new("UIScale")
	hintScale.Name = "ResponsiveScale"
	hintScale.Scale = 1
	hintScale.Parent = hintLabel

	ui.hintGui = hintGui
	ui.hintScale = hintScale
end

function PhoneController:createUi()
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PhoneGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = UI_CONFIG.DisplayOrder
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	self:createHintUi(playerGui)

	local phone = Instance.new("CanvasGroup")
	phone.Name = "Phone"
	phone.AnchorPoint = Vector2.new(1, 1)
	phone.Position = UDim2.new(1, -28, 1, 24)
	phone.Size = UDim2.fromOffset(286, 504)
	phone.BackgroundColor3 = Color3.fromRGB(9, 11, 15)
	phone.BorderSizePixel = 0
	phone.GroupTransparency = 1
	phone.ZIndex = 10
	phone.Parent = screenGui
	createCorner(phone, 34)
	createStroke(phone, Color3.fromRGB(55, 61, 72), 0.05, 2)

	local scale = Instance.new("UIScale")
	scale.Name = "ResponsiveScale"
	scale.Scale = 1
	scale.Parent = phone

	local screen = Instance.new("Frame")
	screen.Name = "Screen"
	screen.Position = UDim2.fromOffset(13, 13)
	screen.Size = UDim2.new(1, -26, 1, -26)
	screen.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
	screen.BorderSizePixel = 0
	screen.ClipsDescendants = true
	screen.ZIndex = 11
	screen.Parent = phone
	createCorner(screen, 26)

	local statusBar = Instance.new("Frame")
	statusBar.Name = "StatusBar"
	statusBar.Size = UDim2.new(1, 0, 0, 36)
	statusBar.BackgroundTransparency = 1
	statusBar.ZIndex = 14
	statusBar.Parent = screen

	local timeLabel = Instance.new("TextLabel")
	timeLabel.Name = "Time"
	timeLabel.Position = UDim2.fromOffset(18, 8)
	timeLabel.Size = UDim2.fromOffset(74, 20)
	timeLabel.BackgroundTransparency = 1
	timeLabel.Font = Enum.Font.GothamBold
	timeLabel.Text = "PHONE"
	timeLabel.TextColor3 = Color3.fromRGB(238, 242, 248)
	timeLabel.TextSize = 12
	timeLabel.TextXAlignment = Enum.TextXAlignment.Left
	timeLabel.ZIndex = 15
	timeLabel.Parent = statusBar

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -14, 0, 8)
	closeButton.Size = UDim2.fromOffset(28, 22)
	closeButton.BackgroundColor3 = Color3.fromRGB(36, 42, 52)
	closeButton.AutoButtonColor = true
	closeButton.Font = Enum.Font.GothamBold
	closeButton.Text = "X"
	closeButton.TextColor3 = Color3.fromRGB(232, 236, 243)
	closeButton.TextSize = 12
	closeButton.ZIndex = 15
	closeButton.Parent = statusBar
	createCorner(closeButton, 8)

	local homePage = Instance.new("Frame")
	homePage.Name = "HomePage"
	homePage.Position = UDim2.fromOffset(0, 36)
	homePage.Size = UDim2.new(1, 0, 1, -78)
	homePage.BackgroundTransparency = 1
	homePage.ZIndex = 12
	homePage.Parent = screen

	local wallpaper = Instance.new("Frame")
	wallpaper.Name = "Wallpaper"
	wallpaper.Size = UDim2.fromScale(1, 1)
	wallpaper.BackgroundColor3 = Color3.fromRGB(24, 34, 45)
	wallpaper.BorderSizePixel = 0
	wallpaper.ZIndex = 12
	wallpaper.Parent = homePage

	local appGrid = Instance.new("Frame")
	appGrid.Name = "AppGrid"
	appGrid.Position = UDim2.fromOffset(22, 32)
	appGrid.Size = UDim2.new(1, -44, 1, -64)
	appGrid.BackgroundTransparency = 1
	appGrid.ZIndex = 16
	appGrid.Parent = homePage

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(58, 70)
	layout.CellPadding = UDim2.fromOffset(14, 18)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = appGrid

	local appPage = Instance.new("Frame")
	appPage.Name = "AppPage"
	appPage.Position = UDim2.fromOffset(0, 36)
	appPage.Size = UDim2.new(1, 0, 1, -78)
	appPage.BackgroundColor3 = Color3.fromRGB(17, 21, 28)
	appPage.BorderSizePixel = 0
	appPage.Visible = false
	appPage.ZIndex = 16
	appPage.Parent = screen

	local appTitle = Instance.new("TextLabel")
	appTitle.Name = "AppTitle"
	appTitle.Position = UDim2.fromOffset(18, 12)
	appTitle.Size = UDim2.new(1, -36, 0, 24)
	appTitle.BackgroundTransparency = 1
	appTitle.Font = Enum.Font.GothamBold
	appTitle.Text = "Map"
	appTitle.TextColor3 = Color3.fromRGB(239, 243, 249)
	appTitle.TextSize = 18
	appTitle.TextXAlignment = Enum.TextXAlignment.Left
	appTitle.ZIndex = 18
	appTitle.Parent = appPage

	local homeBar = Instance.new("TextButton")
	homeBar.Name = "HomeBar"
	homeBar.AnchorPoint = Vector2.new(0.5, 1)
	homeBar.Position = UDim2.new(0.5, 0, 1, -14)
	homeBar.Size = UDim2.fromOffset(92, 6)
	homeBar.BackgroundColor3 = Color3.fromRGB(221, 226, 235)
	homeBar.AutoButtonColor = false
	homeBar.Text = ""
	homeBar.ZIndex = 30
	homeBar.Parent = screen
	createCorner(homeBar, 6)

	ui.screenGui = screenGui
	ui.phone = phone
	ui.scale = scale
	ui.screen = screen
	ui.homePage = homePage
	ui.appPage = appPage
	ui.appGrid = appGrid
	ui.appTitle = appTitle

	for index, appInfo in ipairs(APPS) do
		self:createAppButton(appInfo, index)
	end

	self:createMapUi()
	self:createDiaryUi()
	self:showHome()

	closeButton.Activated:Connect(function()
		self:setOpen(false)
	end)

	homeBar.Activated:Connect(function()
		self:handleBack()
	end)
end

function PhoneController:updateScale()
	if not ui.scale then
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local viewport = camera.ViewportSize
	local maxWidthScale = (viewport.X - 24) / 286
	local maxHeightScale = (viewport.Y - 24) / 504
	ui.scale.Scale = math.clamp(math.min(maxWidthScale, maxHeightScale, 1), 0.72, 1)

	if ui.hintScale then
		ui.hintScale.Scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.9, 1.3)
	end
end

function PhoneController:bind()
	ContextActionService:BindActionAtPriority(
		"PhoneToggle",
		function(_, inputState)
			if inputState ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end

			if UserInputService:GetFocusedTextBox() then
				return Enum.ContextActionResult.Pass
			end

			self:toggle()
			return Enum.ContextActionResult.Sink
		end,
		false,
		UI_CONFIG.InputPriority,
		UI_CONFIG.ToggleKey
	)

	ContextActionService:BindActionAtPriority(
		"PhoneBack",
		function(_, inputState)
			if inputState ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end

			if UserInputService:GetFocusedTextBox() then
				return Enum.ContextActionResult.Pass
			end

			return self:handleBack()
		end,
		false,
		UI_CONFIG.InputPriority,
		Enum.KeyCode.Escape,
		UI_CONFIG.CloseKey
	)

	UserInputService.TouchPinch:Connect(function(touchPositions, scale, _, inputState)
		if not state.isOpen or not ui.mapCanvas or not ui.mapCanvas.Visible then
			return
		end

		local firstTouch = touchPositions[1]
		if not firstTouch or not isScreenPointInside(ui.mapCanvas, firstTouch) then
			return
		end

		if inputState == Enum.UserInputState.Begin then
			state.isPinchingMap = true
			state.isPanningMap = false
			state.panStartPosition = nil
			state.panStartCenter = nil
			state.pinchLastScale = scale
			return
		end

		if inputState == Enum.UserInputState.Change then
			if not state.isPinchingMap or typeof(state.pinchLastScale) ~= "number" or state.pinchLastScale <= 0 then
				state.pinchLastScale = scale
				return
			end

			local zoomRatio = scale / state.pinchLastScale
			if zoomRatio > 0 then
				setMapZoom(state.mapZoom * zoomRatio)
				updateMap()
			end

			state.pinchLastScale = scale
			return
		end

		state.isPinchingMap = false
		state.pinchLastScale = nil
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseWheel then
			return
		end

		if not state.isOpen or not ui.mapCanvas or not ui.mapCanvas.Visible then
			return
		end

		local wheelDelta = input.Position.Z
		if wheelDelta ~= 0 then
			setMapZoom(state.mapZoom * (if wheelDelta > 0 then 1.15 else 1 / 1.15))
			updateMap()
		end
	end)

	RunService.RenderStepped:Connect(function()
		self:updateScale()

		if state.isOpen then
			local now = os.clock()
			if now - state.lastMapRefresh >= MAP_CONFIG.RefreshInterval then
				state.lastMapRefresh = now
				updateMap()
			end
		end
	end)
end

function PhoneController:Init()
	self:createUi()
end

function PhoneController:Start()
	NoteJournal.subscribe(function()
		self:refreshDiaryList()
	end)

	self:bind()
end

return PhoneController
