local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local Localization = require(Shared:WaitForChild("Localization"))
local ObjectiveShared = require(Shared:WaitForChild("ObjectiveShared"))
local RemoteGateway = require(Core:WaitForChild("RemoteGateway"))
local Theme = require(Shared:WaitForChild("UITheme"))

local ObjectiveController = {
	Name = "ObjectiveController",
	Priority = 40,
	remote = nil,
	screenGui = nil,
	cardList = nil,
	cardsById = {},
	lastObjectives = {},
}

local UI = {
	MinWidth = 270,
	MaxWidth = 350,
	TopPadding = 28,
	RightPadding = 26,
	CardSpacing = 9,
}

local function resolveText(text: string, key: string?, params)
	if typeof(key) == "string" and key ~= "" then
		return Localization.translate(key, params)
	end

	if typeof(text) == "string" then
		return text
	end

	return ""
end

function ObjectiveController:createGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ObjectiveGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 35
	screenGui.Enabled = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(1, 0)
	root.Position = UDim2.new(1, -UI.RightPadding, 0, UI.TopPadding)
	root.Size = UDim2.new(0.28, 0, 1, -UI.TopPadding * 2)
	root.BackgroundTransparency = 1
	root.Parent = screenGui

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(UI.MinWidth, 0)
	sizeConstraint.MaxSize = Vector2.new(UI.MaxWidth, 10000)
	sizeConstraint.Parent = root

	local list = Instance.new("Frame")
	list.Name = "CardList"
	list.AnchorPoint = Vector2.new(1, 0)
	list.Position = UDim2.new(1, 0, 0, 0)
	list.Size = UDim2.new(1, 0, 0, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.BackgroundTransparency = 1
	list.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, UI.CardSpacing)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	self.screenGui = screenGui
	self.cardList = list
end

function ObjectiveController:createCard(objective)
	local colors = Theme.Colors

	local card = Instance.new("CanvasGroup")
	card.Name = objective.Id
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Size = UDim2.new(1, 0, 0, 0)
	card.BackgroundTransparency = 1
	card.BorderSizePixel = 0
	card.GroupTransparency = 1
	card.Parent = self.cardList

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Position = UDim2.new(0, 0, 0, 12)
	accent.Size = UDim2.new(0, 3, 1, -24)
	accent.BackgroundColor3 = objective.AccentColor
	accent.BorderSizePixel = 0
	accent.ZIndex = 3
	accent.Parent = card
	Theme.addCorner(accent, 3)

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Position = UDim2.fromOffset(18, 12)
	body.Size = UDim2.new(1, -34, 0, 0)
	body.BackgroundTransparency = 1
	body.Parent = card

	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.Padding = UDim.new(0, 4)
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Parent = body

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.LayoutOrder = 1
	statusLabel.AutomaticSize = Enum.AutomaticSize.Y
	statusLabel.Size = UDim2.new(1, 0, 0, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Theme.Fonts.Display
	statusLabel.Text = "ACTIVE OBJECTIVE"
	statusLabel.TextColor3 = colors.Brass
	statusLabel.TextSize = 9
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextYAlignment = Enum.TextYAlignment.Top
	statusLabel.Parent = body

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.LayoutOrder = 2
	titleLabel.AutomaticSize = Enum.AutomaticSize.Y
	titleLabel.Size = UDim2.new(1, 0, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Theme.Fonts.Heading
	titleLabel.TextSize = 17
	titleLabel.TextColor3 = colors.Ivory
	titleLabel.TextWrapped = true
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextYAlignment = Enum.TextYAlignment.Top
	titleLabel.Parent = body

	local descriptionLabel = Instance.new("TextLabel")
	descriptionLabel.Name = "Description"
	descriptionLabel.LayoutOrder = 3
	descriptionLabel.AutomaticSize = Enum.AutomaticSize.Y
	descriptionLabel.Size = UDim2.new(1, 0, 0, 0)
	descriptionLabel.BackgroundTransparency = 1
	descriptionLabel.Font = Theme.Fonts.Body
	descriptionLabel.TextSize = 12
	descriptionLabel.LineHeight = 1.12
	descriptionLabel.TextColor3 = colors.Muted
	descriptionLabel.TextWrapped = true
	descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
	descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
	descriptionLabel.Parent = body

	local bottomSpacer = Instance.new("Frame")
	bottomSpacer.Name = "BottomSpacer"
	bottomSpacer.LayoutOrder = 4
	bottomSpacer.Size = UDim2.new(1, 0, 0, 8)
	bottomSpacer.BackgroundTransparency = 1
	bottomSpacer.Parent = body

	self.cardsById[objective.Id] = {
		Card = card,
		Accent = accent,
		Title = titleLabel,
		Description = descriptionLabel,
	}

	TweenService:Create(card, Theme.Motion.Standard, { GroupTransparency = 0 }):Play()
	return self.cardsById[objective.Id]
end

function ObjectiveController:destroyMissingCards(activeIds)
	for objectiveId, record in pairs(self.cardsById) do
		if activeIds[objectiveId] ~= true then
			record.Card:Destroy()
			self.cardsById[objectiveId] = nil
		end
	end
end

function ObjectiveController:renderObjectives(objectives)
	if not self.cardList then
		return
	end

	self.lastObjectives = objectives

	local activeIds = {}
	for _, objective in ipairs(objectives) do
		activeIds[objective.Id] = true

		local record = self.cardsById[objective.Id] or self:createCard(objective)
		record.Card.LayoutOrder = objective.Priority * 1000 + objective.Order
		record.Accent.BackgroundColor3 = objective.AccentColor
		record.Title.Text = resolveText(objective.Title, objective.TitleKey, objective.TitleParams)
		record.Description.Text = resolveText(objective.Description, objective.DescriptionKey, objective.DescriptionParams)
		record.Description.Visible = record.Description.Text ~= ""
	end

	self:destroyMissingCards(activeIds)
	self.screenGui.Enabled = next(activeIds) ~= nil
end

function ObjectiveController:Init()
	self.remote = RemoteGateway.waitForRemote("GameRemotes", "ObjectiveEvent", "RemoteEvent", 15)
	self:createGui()
end

function ObjectiveController:Start()
	if not self.remote then
		warn("[ObjectiveController] ObjectiveEvent was not created")
		return
	end

	self.remote.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" or payload.Type ~= "Snapshot" then
			return
		end

		local objectives = {}
		if typeof(payload.Objectives) == "table" then
			for _, rawObjective in ipairs(payload.Objectives) do
				local objective = ObjectiveShared.normalizeObjective(rawObjective)
				if objective and objective.Visible ~= false then
					table.insert(objectives, objective)
				end
			end
		end

		table.sort(objectives, function(left, right)
			if left.Priority ~= right.Priority then
				return left.Priority < right.Priority
			end

			if left.Order ~= right.Order then
				return left.Order < right.Order
			end

			return left.Id < right.Id
		end)

		self:renderObjectives(objectives)
	end)

	Localization.subscribeToLanguageChanged(function()
		self:renderObjectives(self.lastObjectives)
	end)
end

return ObjectiveController
