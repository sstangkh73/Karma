local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local DialogueData = require(Shared:WaitForChild("DialogueData"))
local RemoteGateway = require(Core:WaitForChild("RemoteGateway"))

local DialogueController = {
	Name = "DialogueController",
	Priority = 65,
	remote = nil,
	gui = nil,
	queue = {},
	queuedIds = {},
	activeSequenceId = nil,
	generation = 0,
	isTyping = false,
	advanceRequested = false,
	lastInputAt = 0,
}

local settings = DialogueData.getSettings()
local uiSettings = settings.SubtitleUI or {}

local function configuredNumber(name: string, fallback: number)
	local value = uiSettings[name]
	return if typeof(value) == "number" then value else fallback
end

local function configuredColor(name: string, fallback: Color3)
	local value = uiSettings[name]
	if typeof(value) == "table"
		and typeof(value[1]) == "number"
		and typeof(value[2]) == "number"
		and typeof(value[3]) == "number" then
		return Color3.fromRGB(value[1], value[2], value[3])
	end
	return fallback
end

local function makeText(parent: Instance, name: string, size: UDim2, position: UDim2, textSize: number)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = Color3.fromRGB(244, 244, 244)
	label.TextSize = textSize
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Parent = parent
	return label
end

local function createCinematicLine(parent: Instance, name: string, positionY: number, lineColor: Color3)
	local container = Instance.new("Frame")
	container.Name = name
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(0.5, positionY)
	container.Size = UDim2.new(1, 0, 0, 18)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ZIndex = 2
	container.Parent = parent

	local layers = {
		{ Name = "WideGlow", Height = 16, Transparency = 0.88 },
		{ Name = "NearGlow", Height = 6, Transparency = 0.66 },
		{ Name = "Core", Height = 2, Transparency = 0.12 },
	}

	for _, layer in ipairs(layers) do
		local line = Instance.new("Frame")
		line.Name = layer.Name
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Position = UDim2.fromScale(0.5, 0.5)
		line.Size = UDim2.new(1, 0, 0, layer.Height)
		line.BackgroundColor3 = lineColor
		line.BackgroundTransparency = layer.Transparency
		line.BorderSizePixel = 0
		line.ZIndex = 2
		line.Parent = container

		local gradient = Instance.new("UIGradient")
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.08, 0.92),
			NumberSequenceKeypoint.new(0.28, 0.32),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.72, 0.32),
			NumberSequenceKeypoint.new(0.92, 0.92),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = line
	end

	return container
end

function DialogueController:createGui()
	local existing = playerGui:FindFirstChild("DialogueScreenGui")
	if existing then
		existing:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DialogueScreenGui"
	screenGui.DisplayOrder = 80
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, configuredNumber("PositionY", 0.54))
	panel.Size = UDim2.fromScale(
		configuredNumber("WidthScale", 0.92),
		configuredNumber("HeightScale", 0.20)
	)
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.Parent = screenGui

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(
		configuredNumber("MinWidth", 320),
		configuredNumber("MinHeight", 136)
	)
	sizeConstraint.MaxSize = Vector2.new(
		configuredNumber("MaxWidth", 1700),
		configuredNumber("MaxHeight", 210)
	)
	sizeConstraint.Parent = panel

	local lineColor = configuredColor("LineColor", Color3.fromRGB(245, 245, 245))
	createCinematicLine(panel, "TopLine", 0.08, lineColor)
	createCinematicLine(panel, "BottomLine", 0.92, lineColor)

	local speaker = makeText(panel, "Speaker", UDim2.new(1, -120, 0, 24), UDim2.new(0, 60, 0, 30), 16)
	speaker.Font = Enum.Font.GothamBold
	speaker.TextColor3 = configuredColor("TextColor", Color3.fromRGB(246, 246, 246))
	speaker.TextXAlignment = Enum.TextXAlignment.Center
	speaker.TextYAlignment = Enum.TextYAlignment.Center
	speaker.Visible = uiSettings.ShowSpeaker == true
	speaker.ZIndex = 3

	local body = makeText(panel, "Body", UDim2.new(1, -100, 0.58, 0), UDim2.new(0, 50, 0.21, 0), 34)
	body.Font = Enum.Font.GothamMedium
	body.TextColor3 = configuredColor("TextColor", Color3.fromRGB(246, 246, 246))
	body.TextScaled = true
	body.TextXAlignment = Enum.TextXAlignment.Center
	body.TextYAlignment = Enum.TextYAlignment.Center
	body.ZIndex = 3

	local textSizeConstraint = Instance.new("UITextSizeConstraint")
	textSizeConstraint.MinTextSize = configuredNumber("MinTextSize", 22)
	textSizeConstraint.MaxTextSize = configuredNumber("MaxTextSize", 38)
	textSizeConstraint.Parent = body

	local bodyStroke = Instance.new("UIStroke")
	bodyStroke.Name = "TextShadow"
	bodyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	bodyStroke.Color = Color3.fromRGB(0, 0, 0)
	bodyStroke.Thickness = 2
	bodyStroke.Transparency = 0.42
	bodyStroke.Parent = body

	local hint = makeText(panel, "Hint", UDim2.new(1, -100, 0, 20), UDim2.new(0, 50, 1, -28), 12)
	hint.Text = "E / Space"
	hint.TextColor3 = Color3.fromRGB(170, 170, 170)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.TextYAlignment = Enum.TextYAlignment.Center
	hint.Visible = uiSettings.ShowHint == true
	hint.ZIndex = 3

	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(1, 0)
	skip.Position = UDim2.new(1, -16, 0, 28)
	skip.Size = UDim2.fromOffset(78, 30)
	skip.BackgroundColor3 = Color3.fromRGB(35, 38, 44)
	skip.BackgroundTransparency = 0.55
	skip.BorderSizePixel = 0
	skip.Font = Enum.Font.GothamMedium
	skip.Text = "ข้าม"
	skip.TextColor3 = Color3.fromRGB(210, 210, 210)
	skip.TextSize = 14
	skip.Visible = uiSettings.ShowSkipButton == true
	skip.ZIndex = 4
	skip.Parent = panel
	local skipCorner = Instance.new("UICorner")
	skipCorner.CornerRadius = UDim.new(0, 7)
	skipCorner.Parent = skip

	local advance = Instance.new("TextButton")
	advance.Name = "Advance"
	advance.Size = UDim2.fromScale(1, 1)
	advance.BackgroundTransparency = 1
	advance.Text = ""
	advance.ZIndex = 2
	advance.Parent = panel

	self.gui = {
		ScreenGui = screenGui,
		Panel = panel,
		Speaker = speaker,
		Body = body,
		Hint = hint,
		Skip = skip,
		Advance = advance,
	}

	advance.Activated:Connect(function()
		self:requestAdvance()
	end)
	skip.Activated:Connect(function()
		self:cancelActive("Skipped")
	end)
end

function DialogueController:isBlockingUiOpen()
	local noteGui = playerGui:FindFirstChild("NoteScreenGui")
	return noteGui and noteGui:IsA("ScreenGui") and noteGui.Enabled
end

function DialogueController:requestAdvance()
	local cooldown = settings.InputCooldown or 0.12
	local now = os.clock()
	if now - self.lastInputAt < cooldown or not self.activeSequenceId then
		return
	end
	self.lastInputAt = now

	if self.isTyping then
		self.isTyping = false
		self.gui.Body.MaxVisibleGraphemes = -1
	else
		self.advanceRequested = true
	end
end

function DialogueController:cancelActive(result: string?)
	if not self.activeSequenceId then
		return
	end

	local sequenceId = self.activeSequenceId
	self.generation += 1
	self.isTyping = false
	self.advanceRequested = true
	self.activeSequenceId = nil
	self.gui.ScreenGui.Enabled = false

	if self.remote then
		self.remote:FireServer({
			Type = "Finished",
			SequenceId = sequenceId,
			Result = result or "Cancelled",
		})
	end

	task.defer(function()
		self:playNext()
	end)
end

function DialogueController:typeLine(text: string, generation: number, characterDelay: number?)
	self.gui.Body.Text = text
	self.gui.Body.MaxVisibleGraphemes = 0
	self.isTyping = true

	local graphemeCount = utf8.len(text) or #text
	local delayPerCharacter = characterDelay or settings.CharacterDelay or 0.025
	for index = 1, graphemeCount do
		if generation ~= self.generation or not self.isTyping then
			break
		end
		self.gui.Body.MaxVisibleGraphemes = index
		task.wait(delayPerCharacter)
	end

	if generation == self.generation then
		self.gui.Body.MaxVisibleGraphemes = -1
		self.isTyping = false
	end
end

function DialogueController:waitForAdvance(line, generation: number)
	self.advanceRequested = false
	local autoAdvanceDelay = line.AutoAdvanceDelay
	if autoAdvanceDelay == nil then
		autoAdvanceDelay = settings.AutoAdvanceDelay or 4.5
	end
	local startedAt = os.clock()

	while generation == self.generation and not self.advanceRequested do
		if typeof(autoAdvanceDelay) == "number" and autoAdvanceDelay >= 0
			and os.clock() - startedAt >= autoAdvanceDelay then
			break
		end
		RunService.Heartbeat:Wait()
	end
end

function DialogueController:finishActive(result: string)
	local sequenceId = self.activeSequenceId
	self.activeSequenceId = nil
	self.gui.ScreenGui.Enabled = false
	self.isTyping = false
	self.advanceRequested = false

	if self.remote and sequenceId then
		self.remote:FireServer({
			Type = "Finished",
			SequenceId = sequenceId,
			Result = result,
		})
	end
end

function DialogueController:runSequence(sequenceId: string)
	while self:isBlockingUiOpen() do
		if self.activeSequenceId ~= sequenceId then
			return
		end
		task.wait(0.1)
	end
	if self.activeSequenceId ~= sequenceId then
		return
	end

	local sequence = DialogueData.getResolvedSequence(sequenceId)
	if not sequence or #(sequence.Lines or {}) == 0 then
		warn(("[DialogueController] Missing lines for %s"):format(sequenceId))
		self:finishActive("Invalid")
		return
	end

	self.generation += 1
	local generation = self.generation
	self.gui.ScreenGui.Enabled = true

	for _, line in ipairs(sequence.Lines) do
		if generation ~= self.generation or self.activeSequenceId ~= sequenceId then
			return
		end

		self.gui.Speaker.Text = line.Speaker or ""
		self.gui.Speaker.Visible = uiSettings.ShowSpeaker == true and self.gui.Speaker.Text ~= ""
		self:typeLine(line.Text or "", generation, line.CharacterDelay)
		if generation ~= self.generation then
			return
		end
		self:waitForAdvance(line, generation)
	end

	if generation == self.generation and self.activeSequenceId == sequenceId then
		self:finishActive("Completed")
		self:playNext()
	end
end

function DialogueController:playNext()
	if self.activeSequenceId or #self.queue == 0 then
		return
	end

	local record = table.remove(self.queue, 1)
	self.queuedIds[record.SequenceId] = nil
	self.activeSequenceId = record.SequenceId
	task.spawn(function()
		self:runSequence(record.SequenceId)
	end)
end

function DialogueController:enqueue(sequenceId: string)
	if sequenceId == self.activeSequenceId or self.queuedIds[sequenceId] then
		return false
	end

	local sequence = DialogueData.getSequence(sequenceId)
	if not sequence then
		warn(("[DialogueController] Unknown sequence %s"):format(sequenceId))
		return false
	end

	local record = {
		SequenceId = sequenceId,
		Priority = if typeof(sequence.Priority) == "number" then sequence.Priority else 0,
	}
	local insertAt = #self.queue + 1
	for index, queued in ipairs(self.queue) do
		if record.Priority > queued.Priority then
			insertAt = index
			break
		end
	end
	table.insert(self.queue, insertAt, record)
	self.queuedIds[sequenceId] = true
	self:playNext()
	return true
end

function DialogueController:Init()
	self:createGui()
	self.remote = RemoteGateway.waitForRemote("GameRemotes", "DialogueEvent", "RemoteEvent", 15)
	if not self.remote then
		error("DialogueEvent was not created")
	end
end

function DialogueController:Start()
	self.remote.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end

		if payload.Type == "Play" and typeof(payload.SequenceId) == "string" then
			self:enqueue(payload.SequenceId)
		elseif payload.Type == "Cancel" then
			table.clear(self.queue)
			table.clear(self.queuedIds)
			self:cancelActive(payload.Reason or "Cancelled")
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not self.activeSequenceId then
			return
		end
		if input.KeyCode == Enum.KeyCode.E
			or input.KeyCode == Enum.KeyCode.Space
			or input.KeyCode == Enum.KeyCode.Return then
			self:requestAdvance()
		elseif input.KeyCode == Enum.KeyCode.Escape then
			self:cancelActive("Skipped")
		end
	end)
end

return DialogueController
