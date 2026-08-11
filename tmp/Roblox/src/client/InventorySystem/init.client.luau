local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

print("[InventorySystem] Boot")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local SystemHub = require(Core:WaitForChild("SystemHub"))

if not SystemHub.begin("InventorySystem", script) then
	return
end

local InventoryShared = Shared:WaitForChild("InventoryShared")
local Config = require(InventoryShared:WaitForChild("Config"))
local GridUtils = require(InventoryShared:WaitForChild("GridUtils"))
local Theme = require(Shared:WaitForChild("UITheme"))

local InventoryClient = {
	state = {
		isOpen = false,
		inventory = nil,
		draggingItemId = nil,
		dragRotated = nil,
		dragHover = nil,
		dragAnchor = nil,
		dragGrabOffset = nil,
		isConnected = false,
		pointerPosition = nil,
		pendingHandDragItemId = nil,
		pendingHandDragStart = nil,
		layoutMode = "Default",
	},
	ui = {},
	remotes = {
		stateRemote = nil,
		requestMoveRemote = nil,
		requestRotateRemote = nil,
		requestEquipRemote = nil,
		getStateRemote = nil,
	},
}

local LOBBY_PLACE_ID = 99041403537198

if game.PlaceId == LOBBY_PLACE_ID then
	SystemHub.ready("InventorySystem", script)
	return
end

local function isPointInside(frame: GuiObject, point: Vector2)
	local position = frame.AbsolutePosition
	local size = frame.AbsoluteSize

	return point.X >= position.X
		and point.X <= (position.X + size.X)
		and point.Y >= position.Y
		and point.Y <= (position.Y + size.Y)
end

local function vector2FromInputPosition(position: Vector3)
	return Vector2.new(position.X, position.Y)
end

function InventoryClient:disableDefaultBackpack()
	local function apply()
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
	end

	apply()

	task.spawn(function()
		for _ = 1, 60 do
			if not (self.ui.screenGui and self.ui.screenGui.Parent) then
				return
			end

			apply()
			task.wait(0.1)
		end

		while self.ui.screenGui and self.ui.screenGui.Parent do
			apply()
			task.wait(2)
		end
	end)

	player.CharacterAdded:Connect(function()
		task.defer(apply)
	end)
end

function InventoryClient:getToolbarWidth()
	return Config.UI.HandSlotSize + Config.UI.ToolbarGap + Config.UI.ToggleButtonWidth
end

function InventoryClient:getCellOffset(cellIndex: number)
	local size = Config.UI.CellSize
	local padding = Config.UI.CellPadding
	return (cellIndex - 1) * (size + padding)
end

function InventoryClient:getInventory()
	return self.state.inventory
end

function InventoryClient:isNoteUiOpen()
	local noteGui = playerGui:FindFirstChild("NoteScreenGui")
	return noteGui ~= nil and noteGui:IsA("ScreenGui") and noteGui.Enabled
end

function InventoryClient:getLayoutMode()
	if self:isNoteUiOpen() then
		return "Overlay"
	end

	return "Default"
end

function InventoryClient:updateHudLayout()
	if not self.ui.toolbar or not self.ui.panel then
		return
	end

	local screenPadding = Config.UI.ScreenPadding or 18
	local panelSpacing = Config.UI.PanelSpacing
	local layoutMode = self:getLayoutMode()
	self.state.layoutMode = layoutMode

	local camera = workspace.CurrentCamera
	if camera and self.ui.panelScale and self.ui.toolbarScale then
		local viewport = camera.ViewportSize
		local responsiveScale = math.clamp(math.min((viewport.X - 28) / 360, viewport.Y / 700), 0.72, 1)
		self.ui.panelScale.Scale = responsiveScale
		self.ui.toolbarScale.Scale = responsiveScale
	end

	if layoutMode == "Overlay" then
		self.ui.toolbar.AnchorPoint = Vector2.new(1, 0)
		self.ui.toolbar.Position = UDim2.new(1, -screenPadding, 0, screenPadding)
		self.ui.panel.AnchorPoint = Vector2.new(1, 0)
		self.ui.panel.Position = UDim2.new(
			1,
			-screenPadding,
			0,
			screenPadding + Config.UI.ToolbarHeight + panelSpacing
		)
		return
	end

	self.ui.toolbar.AnchorPoint = Vector2.new(0.5, 1)
	self.ui.toolbar.Position = UDim2.new(0.5, 0, 1, -Config.UI.BottomMargin)
	self.ui.panel.AnchorPoint = Vector2.new(0, 1)
	self.ui.panel.Position = UDim2.new(
		0.5,
		math.floor(self:getToolbarWidth() / 2) + panelSpacing,
		1,
		-Config.UI.BottomMargin
	)
end

function InventoryClient:isReady()
	return self.state.isConnected
		and self.remotes.stateRemote ~= nil
		and self.remotes.requestMoveRemote ~= nil
		and self.remotes.requestRotateRemote ~= nil
		and self.remotes.requestEquipRemote ~= nil
		and self.remotes.getStateRemote ~= nil
end

function InventoryClient:getItemState(itemId: string)
	local inventory = self:getInventory()
	if not inventory then
		return nil
	end

	return inventory.Items[itemId]
end

function InventoryClient:getHandItemState()
	local inventory = self:getInventory()
	if not inventory or not inventory.HandItemId then
		return nil
	end

	return inventory.Items[inventory.HandItemId]
end

function InventoryClient:getItemDefinition(itemState)
	local inventory = self:getInventory()
	if not inventory then
		return nil
	end

	return inventory.ItemDefinitions[itemState.DefinitionId]
end

function InventoryClient:getFootprint(itemState, forceRotated: boolean?)
	local definition = self:getItemDefinition(itemState)
	if not definition then
		return 1, 1
	end

	local rotated = itemState.Rotated
	if forceRotated ~= nil then
		rotated = forceRotated
	end

	return GridUtils.getFootprint(definition, rotated)
end

function InventoryClient:getDragAnchor()
	return self.state.dragAnchor or Vector2.new(1, 1)
end

function InventoryClient:getDragGrabOffset()
	return self.state.dragGrabOffset or Vector2.zero
end

function InventoryClient:getPointerPosition()
	return self.state.pointerPosition or UserInputService:GetMouseLocation()
end

function InventoryClient:setPointerPosition(position: Vector2?)
	if position then
		self.state.pointerPosition = position
	end
end

function InventoryClient:clearPendingHandDrag()
	self.state.pendingHandDragItemId = nil
	self.state.pendingHandDragStart = nil
end

function InventoryClient:beginPendingHandDrag(position: Vector2)
	local handItem = self:getHandItemState()
	if not self.state.isOpen or not handItem then
		return
	end

	self.state.pendingHandDragItemId = handItem.ItemId
	self.state.pendingHandDragStart = position
	self:setPointerPosition(position)
end

function InventoryClient:maybeStartPendingHandDrag(position: Vector2)
	local itemId = self.state.pendingHandDragItemId
	local startPosition = self.state.pendingHandDragStart
	if not itemId or not startPosition or self.state.draggingItemId then
		return
	end

	if (position - startPosition).Magnitude < (Config.UI.DragStartThreshold or 10) then
		return
	end

	self:clearPendingHandDrag()
	self:startDragging(itemId, startPosition, "Hand")
end

function InventoryClient:getDragDataForItem(itemId: string, mousePosition: Vector2?, source: string?)
	if not mousePosition then
		return Vector2.new(1, 1), Vector2.zero
	end

	local itemState = self:getItemState(itemId)
	if not itemState then
		return Vector2.new(1, 1), Vector2.zero
	end

	local width, height = self:getFootprint(itemState)
	local step = Config.UI.CellSize + Config.UI.CellPadding
	local dragWidth = (width * Config.UI.CellSize) + ((width - 1) * Config.UI.CellPadding)
	local dragHeight = (height * Config.UI.CellSize) + ((height - 1) * Config.UI.CellPadding)
	local frame
	if source == "Inventory" then
		frame = self.ui.itemFrames[itemId]
	elseif source == "Hand" then
		frame = self.ui.handSlotButton
	else
		return Vector2.new(1, 1), Vector2.zero
	end

	if not frame then
		return Vector2.new(1, 1), Vector2.zero
	end

	local frameSize = frame.AbsoluteSize
	local relative = Vector2.new(
		math.clamp(mousePosition.X - frame.AbsolutePosition.X, 0, frameSize.X),
		math.clamp(mousePosition.Y - frame.AbsolutePosition.Y, 0, frameSize.Y)
	)

	if source == "Hand" then
		local normalizedX = frameSize.X > 0 and (relative.X / frameSize.X) or 0.5
		local normalizedY = frameSize.Y > 0 and (relative.Y / frameSize.Y) or 0.5
		local anchorX = math.clamp(math.floor(normalizedX * width) + 1, 1, width)
		local anchorY = math.clamp(math.floor(normalizedY * height) + 1, 1, height)

		return Vector2.new(anchorX, anchorY), Vector2.new(
			math.clamp(normalizedX * dragWidth, 0, dragWidth),
			math.clamp(normalizedY * dragHeight, 0, dragHeight)
		)
	end

	local anchorX = math.clamp(math.floor(relative.X / step) + 1, 1, width)
	local anchorY = math.clamp(math.floor(relative.Y / step) + 1, 1, height)

	return Vector2.new(anchorX, anchorY), relative
end

function InventoryClient:createRoundedStroke(parent: Instance, color: Color3, transparency: number?)
	Theme.addCorner(parent, Theme.Radius.Medium)
	Theme.addStroke(parent, color, transparency)
end

function InventoryClient:createUi()
	local colors = Theme.Colors

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "InventoryGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = Config.UI.DisplayOrder or 900
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = screenGui

	local toolbar = Instance.new("Frame")
	toolbar.Name = "Toolbar"
	toolbar.AnchorPoint = Vector2.new(0.5, 1)
	toolbar.Position = UDim2.new(0.5, 0, 1, -Config.UI.BottomMargin)
	toolbar.Size = UDim2.fromOffset(self:getToolbarWidth(), Config.UI.ToolbarHeight)
	toolbar.BackgroundTransparency = 1
	toolbar.Active = true
	toolbar.Parent = root

	local toolbarScale = Instance.new("UIScale")
	toolbarScale.Name = "ResponsiveScale"
	toolbarScale.Parent = toolbar

	local handSlotButton = Instance.new("TextButton")
	handSlotButton.Name = "HandSlot"
	handSlotButton.Size = UDim2.fromOffset(Config.UI.HandSlotSize, Config.UI.HandSlotSize)
	handSlotButton.Position = UDim2.fromOffset(0, 0)
	handSlotButton.BackgroundColor3 = colors.Surface
	handSlotButton.AutoButtonColor = false
	handSlotButton.Font = Theme.Fonts.BodyStrong
	handSlotButton.TextColor3 = colors.Ivory
	handSlotButton.TextSize = 12
	handSlotButton.TextWrapped = true
	handSlotButton.Text = "01  /  HAND\nEMPTY"
	handSlotButton.ZIndex = 20
	handSlotButton.Parent = toolbar
	self:createRoundedStroke(handSlotButton, colors.Line, 0.3)

	local toggleButton = Instance.new("TextButton")
	toggleButton.Name = "ToggleBag"
	toggleButton.Size = UDim2.fromOffset(Config.UI.ToggleButtonWidth, Config.UI.ToolbarHeight)
	toggleButton.Position = UDim2.fromOffset(Config.UI.HandSlotSize + Config.UI.ToolbarGap, 0)
	toggleButton.BackgroundColor3 = colors.Surface
	toggleButton.AutoButtonColor = false
	toggleButton.Font = Theme.Fonts.BodyStrong
	toggleButton.TextColor3 = colors.Ivory
	toggleButton.TextSize = 12
	toggleButton.TextWrapped = true
	toggleButton.Text = "I  /  INVENTORY\nOPEN FIELD KIT"
	toggleButton.ZIndex = 20
	toggleButton.Parent = toolbar
	self:createRoundedStroke(toggleButton, colors.Brass, 0.38)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0.5, math.floor(self:getToolbarWidth() / 2) + Config.UI.PanelSpacing, 1, -Config.UI.BottomMargin)
	panel.Size = UDim2.fromOffset(320, 180)
	panel.BackgroundColor3 = colors.Surface
	panel.BackgroundTransparency = 0.06
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Active = true
	panel.ZIndex = 10
	panel.Parent = root
	self:createRoundedStroke(panel, colors.Line, 0.28)
	Theme.addGradient(panel, colors.SurfaceRaised, colors.Backdrop)

	local panelScale = Instance.new("UIScale")
	panelScale.Name = "ResponsiveScale"
	panelScale.Parent = panel

	local eyebrow = Instance.new("TextLabel")
	eyebrow.Name = "Eyebrow"
	eyebrow.Position = UDim2.fromOffset(Config.UI.PanelPadding, 12)
	eyebrow.Size = UDim2.new(1, -(Config.UI.PanelPadding * 2), 0, 12)
	eyebrow.BackgroundTransparency = 1
	eyebrow.Font = Theme.Fonts.Display
	eyebrow.Text = "FIELD INVENTORY  //  EVIDENCE KIT"
	eyebrow.TextColor3 = colors.Brass
	eyebrow.TextSize = 9
	eyebrow.TextXAlignment = Enum.TextXAlignment.Left
	eyebrow.ZIndex = 11
	eyebrow.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(Config.UI.PanelPadding, 29)
	title.Size = UDim2.new(1, -(Config.UI.PanelPadding * 2), 0, 24)
	title.BackgroundTransparency = 1
	title.Font = Theme.Fonts.Heading
	title.Text = "Recovered Items"
	title.TextColor3 = colors.Ivory
	title.TextSize = 17
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 11
	title.Parent = panel

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Position = UDim2.fromOffset(Config.UI.PanelPadding, 53)
	subtitle.Size = UDim2.new(1, -(Config.UI.PanelPadding * 2), 0, 30)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Theme.Fonts.Body
	subtitle.Text = "DRAG TO REARRANGE   /   R ROTATE   /   1 EQUIP"
	subtitle.TextColor3 = colors.Muted
	subtitle.TextSize = 9
	subtitle.TextWrapped = true
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.ZIndex = 11
	subtitle.Parent = panel

	local gridFrame = Instance.new("Frame")
	gridFrame.Name = "Grid"
	gridFrame.BackgroundTransparency = 1
	gridFrame.Position = UDim2.fromOffset(Config.UI.PanelPadding, 90)
	gridFrame.Size = UDim2.fromOffset(0, 0)
	gridFrame.Active = true
	gridFrame.ZIndex = 11
	gridFrame.Parent = panel

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.Position = UDim2.fromOffset(Config.UI.PanelPadding, 92)
	statusLabel.Size = UDim2.new(1, -(Config.UI.PanelPadding * 2), 0, 28)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Theme.Fonts.Body
	statusLabel.Text = "Synchronizing field inventory..."
	statusLabel.TextColor3 = colors.Muted
	statusLabel.TextSize = 12
	statusLabel.TextWrapped = true
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.ZIndex = 11
	statusLabel.Parent = panel

	local dragLayer = Instance.new("Frame")
	dragLayer.Name = "DragLayer"
	dragLayer.Size = UDim2.fromScale(1, 1)
	dragLayer.BackgroundTransparency = 1
	dragLayer.Active = false
	dragLayer.ZIndex = 30
	dragLayer.Parent = screenGui

	local placementFrame = Instance.new("Frame")
	placementFrame.Name = "PlacementFrame"
	placementFrame.BackgroundColor3 = colors.Success
	placementFrame.BackgroundTransparency = 0.35
	placementFrame.BorderSizePixel = 0
	placementFrame.Visible = false
	placementFrame.ZIndex = 12
	placementFrame.Parent = gridFrame

	self:createRoundedStroke(placementFrame, colors.Ivory, 0.62)

	self.ui.screenGui = screenGui
	self.ui.root = root
	self.ui.toolbar = toolbar
	self.ui.toolbarScale = toolbarScale
	self.ui.handSlotButton = handSlotButton
	self.ui.toggleButton = toggleButton
	self.ui.panel = panel
	self.ui.panelScale = panelScale
	self.ui.title = title
	self.ui.subtitle = subtitle
	self.ui.gridFrame = gridFrame
	self.ui.statusLabel = statusLabel
	self.ui.dragLayer = dragLayer
	self.ui.placementFrame = placementFrame
	self.ui.cellFrames = {}
	self.ui.itemFrames = {}
	self.ui.dragFrame = nil
	self:updateHudLayout()

	toggleButton.Activated:Connect(function()
		self:toggle()
	end)

	handSlotButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self:beginPendingHandDrag(vector2FromInputPosition(input.Position))
		end
	end)

	handSlotButton.Activated:Connect(function()
		self:clearPendingHandDrag()

		if self:getHandItemState() then
			self:equipHandSlot()
		end
	end)
end

function InventoryClient:updatePanelLayout()
	local inventory = self:getInventory()
	if not inventory then
		self.ui.statusLabel.Visible = true
		return
	end

	local columns = inventory.Grid.Columns
	local rows = inventory.Grid.Rows
	local cellSize = Config.UI.CellSize
	local padding = Config.UI.CellPadding
	local panelPadding = Config.UI.PanelPadding

	local gridWidth = (columns * cellSize) + ((columns - 1) * padding)
	local gridHeight = (rows * cellSize) + ((rows - 1) * padding)
	local panelWidth = gridWidth + (panelPadding * 2)
	local panelHeight = gridHeight + panelPadding + 92

	self.ui.gridFrame.Position = UDim2.fromOffset(panelPadding, panelHeight - panelPadding - gridHeight)
	self.ui.gridFrame.Size = UDim2.fromOffset(gridWidth, gridHeight)
	self.ui.panel.Size = UDim2.fromOffset(panelWidth, panelHeight)
	self.ui.statusLabel.Visible = false
	self.ui.placementFrame.Visible = false
	self:updateHudLayout()
end

function InventoryClient:clearGrid()
	for _, frame in self.ui.cellFrames do
		frame:Destroy()
	end
	self.ui.cellFrames = {}

	for _, frame in self.ui.itemFrames do
		frame:Destroy()
	end
	self.ui.itemFrames = {}
end

function InventoryClient:createGrid()
	self:clearGrid()
	self:updatePanelLayout()

	local inventory = self:getInventory()
	if not inventory then
		return
	end

	for row = 1, inventory.Grid.Rows do
		for column = 1, inventory.Grid.Columns do
			local cell = Instance.new("Frame")
			cell.Name = string.format("Cell_%d_%d", column, row)
			cell.Size = UDim2.fromOffset(Config.UI.CellSize, Config.UI.CellSize)
			cell.Position = UDim2.fromOffset(self:getCellOffset(column), self:getCellOffset(row))
			cell.BackgroundColor3 = Theme.Colors.SurfaceHover
			cell.BackgroundTransparency = 0.34
			cell.BorderSizePixel = 0
			cell.Active = true
			cell.ZIndex = 11
			cell.Parent = self.ui.gridFrame

			Theme.addCorner(cell, Theme.Radius.Small)
			Theme.addStroke(cell, Theme.Colors.LineSoft, 0.68)

			self.ui.cellFrames[string.format("%d:%d", column, row)] = cell
		end
	end
end

function InventoryClient:resetPlacementPreview()
	self.ui.placementFrame.Visible = false

	local handStroke = self.ui.handSlotButton:FindFirstChildOfClass("UIStroke")
	if handStroke then
		handStroke.Color = Theme.Colors.Line
		handStroke.Transparency = 0.3
		handStroke.Thickness = 1
	end
end

function InventoryClient:updatePlacementPreview(itemState, hover)
	self:resetPlacementPreview()

	if not hover then
		return
	end

	if hover.Target == "Hand" then
		local handStroke = self.ui.handSlotButton:FindFirstChildOfClass("UIStroke")
		if handStroke then
			handStroke.Color = hover.CanPlace and Theme.Colors.Success or Theme.Colors.Danger
			handStroke.Transparency = 0
			handStroke.Thickness = 2
		end
		return
	end

	local inventory = self:getInventory()
	if not inventory then
		return
	end

	local width, height = self:getFootprint(itemState, self.state.dragRotated)
	local maxGridX = math.max(1, inventory.Grid.Columns - width + 1)
	local maxGridY = math.max(1, inventory.Grid.Rows - height + 1)
	local displayGridX = math.clamp(hover.GridX, 1, maxGridX)
	local displayGridY = math.clamp(hover.GridY, 1, maxGridY)

	self.ui.placementFrame.Size = UDim2.fromOffset(
		(width * Config.UI.CellSize) + ((width - 1) * Config.UI.CellPadding),
		(height * Config.UI.CellSize) + ((height - 1) * Config.UI.CellPadding)
	)
	self.ui.placementFrame.Position = UDim2.fromOffset(
		self:getCellOffset(displayGridX),
		self:getCellOffset(displayGridY)
	)
	self.ui.placementFrame.BackgroundColor3 = hover.CanPlace and Theme.Colors.Success or Theme.Colors.Danger
	self.ui.placementFrame.Visible = true
end

function InventoryClient:createInventoryItemFrame(itemId: string, itemState)
	local button = Instance.new("TextButton")
	button.Name = itemId
	button.AutoButtonColor = false
	button.Font = Theme.Fonts.BodyStrong
	button.TextColor3 = Theme.Colors.Ivory
	button.TextSize = 12
	button.TextWrapped = true
	button.BackgroundColor3 = Theme.Colors.BrassDark
	button.BorderSizePixel = 0
	button.ZIndex = 14
	button.Parent = self.ui.gridFrame

	self:createRoundedStroke(button, Theme.Colors.Brass, 0.38)

	button.InputBegan:Connect(function(input)
		if not self.state.isOpen then
			return
		end

		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		self:startDragging(itemId, vector2FromInputPosition(input.Position), "Inventory")
	end)

	self.ui.itemFrames[itemId] = button
	return button
end

function InventoryClient:createDragFrame(itemState)
	local frame = Instance.new("TextLabel")
	frame.Name = "DragPreview"
	frame.BackgroundColor3 = Theme.Colors.Success
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Text = itemState.Name
	frame.TextWrapped = true
	frame.Font = Theme.Fonts.BodyStrong
	frame.TextSize = 13
	frame.TextColor3 = Theme.Colors.Ivory
	frame.ZIndex = 35
	frame.Parent = self.ui.dragLayer

	self:createRoundedStroke(frame, Theme.Colors.Ivory, 0.48)

	return frame
end

function InventoryClient:updateInventoryItemFrame(button: TextButton, itemState, drawGridX: number?, drawGridY: number?, drawRotated: boolean?)
	local width, height = self:getFootprint(itemState, drawRotated)
	local gridX = drawGridX or itemState.GridX
	local gridY = drawGridY or itemState.GridY

	button.Size = UDim2.fromOffset(
		(width * Config.UI.CellSize) + ((width - 1) * Config.UI.CellPadding),
		(height * Config.UI.CellSize) + ((height - 1) * Config.UI.CellPadding)
	)
	button.Position = UDim2.fromOffset(self:getCellOffset(gridX), self:getCellOffset(gridY))
	button.Text = itemState.Name
end

function InventoryClient:refreshToolbar()
	local inventory = self:getInventory()
	local handItem = self:getHandItemState()
	local handButton = self.ui.handSlotButton

	if handItem and handItem.ItemId ~= self.state.draggingItemId then
		handButton.Text = string.upper(handItem.Name)
		handButton.BackgroundColor3 = Theme.Colors.BrassDark
	else
		handButton.Text = "01  /  HAND\nEMPTY"
		handButton.BackgroundColor3 = Theme.Colors.Surface
	end

	local itemCount = 0
	if inventory then
		for _, itemState in inventory.Items do
			if itemState.Location == "Inventory" then
				itemCount += 1
			end
		end
	end

	self.ui.toggleButton.Text = string.format("I  /  INVENTORY\n%02d RECOVERED", itemCount)
	if not self:isReady() then
		self.ui.toggleButton.Text = "I  /  INVENTORY\nSYNCHRONIZING"
	end

	self.ui.panel.Visible = self.state.isOpen
end

function InventoryClient:refreshInventoryItems()
	local inventory = self:getInventory()
	if not inventory then
		return
	end

	for itemId, itemState in inventory.Items do
		if itemState.Location == "Inventory" then
			local button = self.ui.itemFrames[itemId]
			if not button then
				button = self:createInventoryItemFrame(itemId, itemState)
			end

			button.Visible = itemId ~= self.state.draggingItemId
			self:updateInventoryItemFrame(button, itemState)
		end
	end

	for itemId, button in self.ui.itemFrames do
		local itemState = inventory.Items[itemId]
		if itemState == nil or itemState.Location ~= "Inventory" then
			button:Destroy()
			self.ui.itemFrames[itemId] = nil
		end
	end
end

function InventoryClient:buildLocalOccupancy(excludedItemId: string?)
	local occupancy = {}
	local inventory = self:getInventory()
	if not inventory then
		return occupancy
	end

	for itemId, itemState in inventory.Items do
		if itemId ~= excludedItemId and itemState.Location == "Inventory" then
			GridUtils.writeItemToGrid(occupancy, itemId, itemState.GridX, itemState.GridY, itemState.Width, itemState.Height)
		end
	end

	return occupancy
end

function InventoryClient:getHoveredGridPosition(mousePosition: Vector2)
	local gridFrame = self.ui.gridFrame
	local origin = gridFrame.AbsolutePosition
	local relative = mousePosition - origin
	local step = Config.UI.CellSize + Config.UI.CellPadding

	local gridX = math.floor(relative.X / step) + 1
	local gridY = math.floor(relative.Y / step) + 1
	return gridX, gridY
end

function InventoryClient:getPlacementGridPosition(mousePosition: Vector2)
	local rawGridX, rawGridY = self:getHoveredGridPosition(mousePosition)
	local anchor = self:getDragAnchor()

	return rawGridX - math.floor(anchor.X) + 1, rawGridY - math.floor(anchor.Y) + 1
end

function InventoryClient:canMoveToHand(itemState)
	local inventory = self:getInventory()
	local definition = self:getItemDefinition(itemState)
	if not inventory or not definition then
		return false
	end

	if definition.Type ~= "Tool" then
		return false
	end

	return inventory.HandItemId == nil or inventory.HandItemId == itemState.ItemId
end

function InventoryClient:getDragHover(mousePosition: Vector2)
	local itemState = self:getItemState(self.state.draggingItemId)
	local inventory = self:getInventory()
	if not itemState or not inventory then
		return nil
	end

	if isPointInside(self.ui.handSlotButton, mousePosition) then
		return {
			Target = "Hand",
			CanPlace = self:canMoveToHand(itemState),
		}
	end

	if not self.state.isOpen or not isPointInside(self.ui.gridFrame, mousePosition) then
		return nil
	end

	local gridX, gridY = self:getPlacementGridPosition(mousePosition)
	local width, height = self:getFootprint(itemState, self.state.dragRotated)
	local occupancy = self:buildLocalOccupancy(itemState.ItemId)
	local maxGridX = math.max(1, inventory.Grid.Columns - width + 1)
	local maxGridY = math.max(1, inventory.Grid.Rows - height + 1)
	local clampedGridX = math.clamp(gridX, 1, maxGridX)
	local clampedGridY = math.clamp(gridY, 1, maxGridY)

	return {
		Target = "Inventory",
		GridX = clampedGridX,
		GridY = clampedGridY,
		CanPlace = GridUtils.canPlaceItem(
			occupancy,
			inventory.Grid.Columns,
			inventory.Grid.Rows,
			clampedGridX,
			clampedGridY,
			width,
			height
		),
	}
end

function InventoryClient:destroyDragFrame()
	if self.ui.dragFrame then
		self.ui.dragFrame:Destroy()
		self.ui.dragFrame = nil
	end

	self:resetPlacementPreview()
end

function InventoryClient:updateDragPreview()
	local itemState = self:getItemState(self.state.draggingItemId)
	if not itemState then
		self:destroyDragFrame()
		return
	end

	local pointerPosition = self:getPointerPosition()
	if not self.ui.dragFrame then
		self.ui.dragFrame = self:createDragFrame(itemState)
	end

	local dragFrame = self.ui.dragFrame
	local width, height = self:getFootprint(itemState, self.state.dragRotated)
	local dragWidth = (width * Config.UI.CellSize) + ((width - 1) * Config.UI.CellPadding)
	local dragHeight = (height * Config.UI.CellSize) + ((height - 1) * Config.UI.CellPadding)
	local grabOffset = self:getDragGrabOffset()

	dragFrame.Size = UDim2.fromOffset(dragWidth, dragHeight)
	self.state.dragHover = self:getDragHover(pointerPosition)
	self:updatePlacementPreview(itemState, self.state.dragHover)

	if self.state.dragHover and self.state.dragHover.Target == "Inventory" then
		dragFrame.Visible = false
	elseif self.state.dragHover and self.state.dragHover.Target == "Hand" then
		dragFrame.Visible = true
		local handPosition = self.ui.handSlotButton.AbsolutePosition
		local handSize = self.ui.handSlotButton.AbsoluteSize
		dragFrame.Position = UDim2.fromOffset(
			handPosition.X + math.floor((handSize.X - dragWidth) / 2),
			handPosition.Y + math.floor((handSize.Y - dragHeight) / 2)
		)
	else
		dragFrame.Visible = true
		dragFrame.Position = UDim2.fromOffset(pointerPosition.X - grabOffset.X, pointerPosition.Y - grabOffset.Y)
	end

	dragFrame.Text = itemState.Name
	dragFrame.BackgroundColor3 = (self.state.dragHover and self.state.dragHover.CanPlace)
			and Theme.Colors.Success
		or Theme.Colors.Danger
end

function InventoryClient:startDragging(itemId: string, mousePosition: Vector2?, source: string?)
	local itemState = self:getItemState(itemId)
	if not itemState then
		return
	end

	self.state.draggingItemId = itemId
	self.state.dragRotated = itemState.Rotated
	self.state.dragAnchor, self.state.dragGrabOffset = self:getDragDataForItem(itemId, mousePosition, source)
	self.state.dragHover = nil
	self:refreshToolbar()
	self:refreshInventoryItems()
	self:updateDragPreview()
end

function InventoryClient:finishDrag()
	self.state.draggingItemId = nil
	self.state.dragRotated = nil
	self.state.dragHover = nil
	self.state.dragAnchor = nil
	self.state.dragGrabOffset = nil
	self:clearPendingHandDrag()
	self:destroyDragFrame()
	self:refreshToolbar()
	self:refreshInventoryItems()
end

function InventoryClient:commitDrag()
	local itemId = self.state.draggingItemId
	local hover = self.state.dragHover
	if not itemId or not hover or not hover.CanPlace then
		self:finishDrag()
		return
	end

	local payload
	if hover.Target == "Hand" then
		payload = {
			ItemId = itemId,
			Target = "Hand",
			Rotated = self.state.dragRotated == true,
		}
	else
		payload = {
			ItemId = itemId,
			Target = "Inventory",
			GridX = hover.GridX,
			GridY = hover.GridY,
			Rotated = self.state.dragRotated == true,
		}
	end

	self:finishDrag()
	if self.remotes.requestMoveRemote then
		self.remotes.requestMoveRemote:InvokeServer(payload)
	end
end

function InventoryClient:toggle()
	self.state.isOpen = not self.state.isOpen
	self.ui.panel.Visible = self.state.isOpen

	if not self.state.isOpen and self.state.draggingItemId then
		self:finishDrag()
	end

	self:refreshToolbar()
end

function InventoryClient:pulseHandSlot()
	local stroke = self.ui.handSlotButton:FindFirstChildOfClass("UIStroke")
	if not stroke then
		return
	end

	stroke.Color = Theme.Colors.BrassBright
	stroke.Thickness = 2
	task.delay(0.18, function()
		if stroke.Parent then
			stroke.Color = Theme.Colors.Line
			stroke.Thickness = 1
		end
	end)
end

function InventoryClient:equipHandSlot()
	if self.remotes.requestEquipRemote then
		self.remotes.requestEquipRemote:InvokeServer()
		self:pulseHandSlot()
	end
end

function InventoryClient:rotateDraggedItem()
	local itemState = self:getItemState(self.state.draggingItemId)
	if not itemState or not itemState.Rotatable then
		return
	end

	local currentRotated = self.state.dragRotated == true
	local currentWidth, currentHeight = self:getFootprint(itemState, currentRotated)
	local nextRotated = not currentRotated
	local nextWidth, nextHeight = self:getFootprint(itemState, nextRotated)
	local anchor = self:getDragAnchor()
	local currentGrabOffset = self:getDragGrabOffset()
	local currentPixelWidth = (currentWidth * Config.UI.CellSize) + ((currentWidth - 1) * Config.UI.CellPadding)
	local nextPixelWidth = (nextWidth * Config.UI.CellSize) + ((nextWidth - 1) * Config.UI.CellPadding)
	local nextPixelHeight = (nextHeight * Config.UI.CellSize) + ((nextHeight - 1) * Config.UI.CellPadding)

	self.state.dragRotated = nextRotated
	self.state.dragAnchor = Vector2.new(
		math.clamp(anchor.Y, 1, nextWidth),
		math.clamp(currentWidth - anchor.X + 1, 1, nextHeight)
	)
	self.state.dragGrabOffset = Vector2.new(
		math.clamp(currentGrabOffset.Y, 0, nextPixelWidth),
		math.clamp(currentPixelWidth - currentGrabOffset.X, 0, nextPixelHeight)
	)
	self:updateDragPreview()
end

function InventoryClient:handleQuickSlotInput()
	if self.state.draggingItemId then
		local itemState = self:getItemState(self.state.draggingItemId)
		if itemState and self:canMoveToHand(itemState) and self.remotes.requestMoveRemote then
			local didMove = self.remotes.requestMoveRemote:InvokeServer({
				ItemId = itemState.ItemId,
				Target = "Hand",
				Rotated = self.state.dragRotated == true,
			})
			self:finishDrag()
			if didMove then
				self:equipHandSlot()
			end
		else
			self:finishDrag()
		end
		return
	end

	local handItem = self:getHandItemState()
	if handItem then
		self:equipHandSlot()
		return
	end

	if not self.state.isOpen then
		return
	end

	local hoveredItemId = self:getHoveredItemId(self:getPointerPosition())
	local hoveredItem = hoveredItemId and self:getItemState(hoveredItemId) or nil
	if hoveredItem and self:canMoveToHand(hoveredItem) and self.remotes.requestMoveRemote then
		local didMove = self.remotes.requestMoveRemote:InvokeServer({
			ItemId = hoveredItem.ItemId,
			Target = "Hand",
			Rotated = hoveredItem.Rotated,
		})
		if didMove then
			self:equipHandSlot()
		end
	end
end

function InventoryClient:getHoveredItemId(mousePosition: Vector2)
	local handItem = self:getHandItemState()
	if handItem and isPointInside(self.ui.handSlotButton, mousePosition) then
		return handItem.ItemId
	end

	if not self.state.isOpen or not isPointInside(self.ui.gridFrame, mousePosition) then
		return nil
	end

	local gridX, gridY = self:getHoveredGridPosition(mousePosition)
	local inventory = self:getInventory()
	if not inventory then
		return nil
	end

	for itemId, itemState in inventory.Items do
		if itemState.Location == "Inventory"
			and gridX >= itemState.GridX
			and gridX < (itemState.GridX + itemState.Width)
			and gridY >= itemState.GridY
			and gridY < (itemState.GridY + itemState.Height)
		then
			return itemId
		end
	end

	return nil
end

function InventoryClient:onInventoryState(newState)
	self.state.inventory = newState
	self:createGrid()
	self:refreshToolbar()
	self:refreshInventoryItems()
end

function InventoryClient:connectRemotes()
	local ok, errorMessage = pcall(function()
		local remotesFolder = ReplicatedStorage:WaitForChild(Config.RemotesFolderName)
		self.remotes.stateRemote = remotesFolder:WaitForChild("State")
		self.remotes.requestMoveRemote = remotesFolder:WaitForChild("RequestMoveItem")
		self.remotes.requestRotateRemote = remotesFolder:WaitForChild("RequestRotateItem")
		self.remotes.requestEquipRemote = remotesFolder:WaitForChild("RequestEquipHandItem")
		self.remotes.getStateRemote = remotesFolder:WaitForChild("GetState")
		self.state.isConnected = true

		self.remotes.stateRemote.OnClientEvent:Connect(function(newState)
			self:onInventoryState(newState)
		end)

		local initialState = self.remotes.getStateRemote:InvokeServer()
		self:onInventoryState(initialState)
		self:refreshToolbar()
	end)

	if not ok then
		self.state.isConnected = false
		if self.ui.statusLabel then
			self.ui.statusLabel.Text = string.format("Inventory failed to connect: %s", tostring(errorMessage))
		end
		self:refreshToolbar()
	end
end

function InventoryClient:bind()
	ContextActionService:BindActionAtPriority(
		"InventoryToggle",
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
		Config.UI.InputPriority or Enum.ContextActionPriority.High.Value,
		Config.UI.ToggleKey
	)

	ContextActionService:BindActionAtPriority(
		"InventoryQuickSlot",
		function(_, inputState)
			if inputState ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end

			if UserInputService:GetFocusedTextBox() then
				return Enum.ContextActionResult.Pass
			end

			self:handleQuickSlotInput()
			return Enum.ContextActionResult.Sink
		end,
		false,
		Config.UI.InputPriority or Enum.ContextActionPriority.High.Value,
		Config.UI.QuickSlotKey
	)

	ContextActionService:BindActionAtPriority(
		"InventoryRotate",
		function(_, inputState)
			if inputState ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end

			if UserInputService:GetFocusedTextBox() then
				return Enum.ContextActionResult.Pass
			end

			if self.state.draggingItemId then
				self:rotateDraggedItem()
				return Enum.ContextActionResult.Sink
			end

			local hoveredItemId = self:getHoveredItemId(self:getPointerPosition())
			if hoveredItemId and self.remotes.requestRotateRemote then
				self.remotes.requestRotateRemote:InvokeServer(hoveredItemId)
				return Enum.ContextActionResult.Sink
			end

			return Enum.ContextActionResult.Pass
		end,
		false,
		Config.UI.InputPriority or Enum.ContextActionPriority.High.Value,
		Config.UI.RotateKey
	)

	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local pointerPosition = vector2FromInputPosition(input.Position)
			self:setPointerPosition(pointerPosition)
			self:maybeStartPendingHandDrag(pointerPosition)
		end
	end)

	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self:setPointerPosition(vector2FromInputPosition(input.Position))
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self:setPointerPosition(vector2FromInputPosition(input.Position))
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if self.state.draggingItemId then
				self:commitDrag()
			else
				self:clearPendingHandDrag()
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		self:updateHudLayout()

		if self.state.draggingItemId then
			self:updateDragPreview()
		end
	end)
end

function InventoryClient:start()
	self:createUi()
	self:disableDefaultBackpack()
	self:bind()
	self:refreshToolbar()

	task.spawn(function()
		self:connectRemotes()
	end)
end

InventoryClient:start()
SystemHub.ready("InventorySystem", script)
