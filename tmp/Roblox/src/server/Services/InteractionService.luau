local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local RemoteGateway = require(Core:WaitForChild("RemoteGateway"))
local NoteData = require(Shared:WaitForChild("NoteData"))

local InventoryShared = Shared:FindFirstChild("InventoryShared")
local ItemDefinitions = if InventoryShared then require(InventoryShared:WaitForChild("ItemDefinitions")) else {}

local CONFIG = {
	RemotesFolderName = "GameRemotes",
	EventName = "InteractionEvent",
	TagName = "Interactable",
	DefaultDistance = 10,
	DistanceBuffer = 4,
	RateLimitWindow = 0.25,
}

local InteractionService = {
	Name = "InteractionService",
	Priority = 30,
	eventRemote = nil,
	handlers = {},
	tracked = {},
	rateLimit = nil,
}

local function getAttribute(instance: Instance, name: string, fallback)
	local value = instance:GetAttribute(name)
	if value == nil then
		return fallback
	end

	return value
end

local function getNumberAttribute(instance: Instance, name: string, fallback: number)
	local value = instance:GetAttribute(name)
	if typeof(value) == "number" then
		return value
	end

	return fallback
end

local function getBooleanAttribute(instance: Instance, name: string, fallback: boolean)
	local value = instance:GetAttribute(name)
	if typeof(value) == "boolean" then
		return value
	end

	return fallback
end

local function isPlayerCharacterDescendant(instance: Instance): boolean
	local current = instance
	while current and current ~= Workspace do
		if current:IsA("Model") and Players:GetPlayerFromCharacter(current) then
			return true
		end

		current = current.Parent
	end

	return false
end

local function getTool(instance: Instance?): Tool?
	if not instance then
		return nil
	end

	if isPlayerCharacterDescendant(instance) then
		return nil
	end

	if instance:IsA("Tool") then
		return instance
	end

	local ancestor = instance:FindFirstAncestorOfClass("Tool")
	if ancestor and ancestor:IsDescendantOf(Workspace) and not isPlayerCharacterDescendant(ancestor) then
		return ancestor
	end

	return nil
end

local function getPromptParent(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("Tool") then
		local handle = instance:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			return handle
		end
	end

	return nil
end

local function getInventoryToolDefinition(instance: Instance)
	local tool = getTool(instance)
	if not tool then
		return nil, nil
	end

	if tool:GetAttribute("DisableInventoryPickup") == true then
		return nil, nil
	end

	return tool, ItemDefinitions[tool.Name]
end

local function getKeyCodeFromAttribute(instance: Instance, attributeName: string, fallback: Enum.KeyCode)
	local rawValue = instance:GetAttribute(attributeName)
	if typeof(rawValue) ~= "string" or rawValue == "" then
		return fallback
	end

	local keyCode = Enum.KeyCode[rawValue]
	return keyCode or fallback
end

function InteractionService:getInteractionType(instance: Instance)
	local explicitType = instance:GetAttribute("InteractionType")
	if typeof(explicitType) == "string" and explicitType ~= "" then
		return explicitType
	end

	if instance:IsA("BasePart") and instance:GetAttribute("NoteId") then
		return "Note"
	end

	local _, definition = getInventoryToolDefinition(instance)
	if definition then
		return "InventoryPickup"
	end

	return nil
end

function InteractionService:getInteractionConfig(instance: Instance)
	local interactionType = self:getInteractionType(instance)
	if not interactionType then
		return nil
	end

	local promptParent = getPromptParent(instance)
	if not promptParent then
		return nil
	end

	local tool, itemDefinition = getInventoryToolDefinition(promptParent)
	local objectText = getAttribute(promptParent, "InteractionObjectText", promptParent.Name)
	local actionText = getAttribute(promptParent, "InteractionActionText", "")
	local objectTextKey = getAttribute(promptParent, "InteractionObjectTextKey", nil)
	local actionTextKey = getAttribute(promptParent, "InteractionActionTextKey", "interaction.prompt.use")

	if interactionType == "Note" then
		objectText = getAttribute(promptParent, "InteractionObjectText", "")
		actionText = getAttribute(promptParent, "InteractionActionText", "")
		objectTextKey = getAttribute(promptParent, "InteractionObjectTextKey", "note.prompt.object")
		actionTextKey = getAttribute(promptParent, "InteractionActionTextKey", "note.prompt.read")
	elseif interactionType == "InventoryPickup" then
		objectText = getAttribute(promptParent, "InteractionObjectText", itemDefinition and itemDefinition.Name or tool.Name)
		actionText = getAttribute(promptParent, "InteractionActionText", "")
		actionTextKey = getAttribute(promptParent, "InteractionActionTextKey", "interaction.prompt.pick_up")
	end

	return {
		Type = interactionType,
		Target = tool or instance,
		PromptParent = promptParent,
		ObjectText = objectText,
		ActionText = actionText,
		ObjectTextKey = objectTextKey,
		ActionTextKey = actionTextKey,
		Distance = getNumberAttribute(promptParent, "InteractionDistance", CONFIG.DefaultDistance),
		HoldDuration = getNumberAttribute(promptParent, "InteractionHoldDuration", 0),
		RequiresLineOfSight = getBooleanAttribute(promptParent, "InteractionRequiresLineOfSight", false),
		KeyboardKeyCode = getKeyCodeFromAttribute(promptParent, "InteractionKeyCode", Enum.KeyCode.E),
		GamepadKeyCode = getKeyCodeFromAttribute(promptParent, "InteractionGamepadKeyCode", Enum.KeyCode.ButtonX),
	}
end

function InteractionService:sendFeedback(player: Player, messageKey: string, messageParams, fallbackMessage: string?)
	if self.eventRemote then
		self.eventRemote:FireClient(player, {
			Type = "Feedback",
			MessageKey = messageKey,
			MessageParams = messageParams,
			Message = fallbackMessage,
		})
	end
end

function InteractionService:isPlayerCloseEnough(player: Player, promptParent: BasePart)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end

	local prompt = promptParent:FindFirstChildOfClass("ProximityPrompt")
	local maxDistance = prompt and prompt.MaxActivationDistance or CONFIG.DefaultDistance
	return (root.Position - promptParent.Position).Magnitude <= maxDistance + CONFIG.DistanceBuffer
end

function InteractionService:handleTriggered(player: Player, promptParent: BasePart, triggerKind: string)
	local record = self.tracked[promptParent]
	if not record then
		return
	end

	local allowed = self.rateLimit(player, promptParent:GetFullName())
	if not allowed then
		return
	end

	if not self:isPlayerCloseEnough(player, promptParent) then
		self:sendFeedback(player, "interaction.feedback.too_far")
		return
	end

	local handler = self.handlers[record.Type]
	if not handler then
		self:sendFeedback(player, "interaction.feedback.no_handler", {
			type = record.Type,
		})
		return
	end

	local ok, didHandle, message = pcall(function()
		return handler(self, player, record.Target, promptParent, triggerKind)
	end)

	if not ok then
		warn(("[InteractionService] %s handler failed: %s"):format(record.Type, tostring(didHandle)))
		self:sendFeedback(player, "interaction.feedback.failed")
	elseif didHandle == false and typeof(message) == "table" and typeof(message.Key) == "string" then
		self:sendFeedback(player, message.Key, message.Params, message.Fallback)
	elseif didHandle == false and typeof(message) == "string" then
		self:sendFeedback(player, "", nil, message)
	end
end

function InteractionService:untrack(promptParent: BasePart)
	local record = self.tracked[promptParent]
	if not record then
		return
	end

	for _, connection in record.Connections do
		connection:Disconnect()
	end

	if record.CreatedPrompt and record.Prompt then
		record.Prompt:Destroy()
	end

	if record.CreatedClickDetector and record.ClickDetector then
		record.ClickDetector:Destroy()
	end

	self.tracked[promptParent] = nil
end

function InteractionService:track(instance: Instance)
	local config = self:getInteractionConfig(instance)
	if not config then
		return
	end

	local promptParent = config.PromptParent
	if self.tracked[promptParent] then
		return
	end

	local prompt = promptParent:FindFirstChildOfClass("ProximityPrompt")
	local createdPrompt = false
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		createdPrompt = true
	end

	prompt.ActionText = config.ActionText
	prompt.ObjectText = config.ObjectText
	prompt:SetAttribute("LocalizationActionKey", config.ActionTextKey)
	prompt:SetAttribute("LocalizationObjectKey", config.ObjectTextKey)
	prompt.KeyboardKeyCode = config.KeyboardKeyCode
	prompt.GamepadKeyCode = config.GamepadKeyCode
	prompt.HoldDuration = config.HoldDuration
	prompt.MaxActivationDistance = config.Distance
	prompt.RequiresLineOfSight = config.RequiresLineOfSight
	prompt.Parent = promptParent

	local clickDetector = promptParent:FindFirstChildOfClass("ClickDetector")
	local createdClickDetector = false
	if not clickDetector then
		clickDetector = Instance.new("ClickDetector")
		createdClickDetector = true
	end

	clickDetector.MaxActivationDistance = config.Distance
	clickDetector.Parent = promptParent

	local connections = {
		prompt.Triggered:Connect(function(player)
			self:handleTriggered(player, promptParent, "Prompt")
		end),
		clickDetector.MouseClick:Connect(function(player)
			self:handleTriggered(player, promptParent, "Click")
		end),
		promptParent.AncestryChanged:Connect(function()
			if not promptParent:IsDescendantOf(Workspace) or isPlayerCharacterDescendant(promptParent) then
				self:untrack(promptParent)
			end
		end),
	}

	self.tracked[promptParent] = {
		Type = config.Type,
		Target = config.Target,
		Prompt = prompt,
		ClickDetector = clickDetector,
		CreatedPrompt = createdPrompt,
		CreatedClickDetector = createdClickDetector,
		Connections = connections,
	}
end

function InteractionService:RegisterHandler(interactionType: string, handler)
	self.handlers[interactionType] = handler
end

function InteractionService:registerDefaultHandlers()
	self:RegisterHandler("Note", function(_, player, target, promptParent)
		local noteId = target:GetAttribute("NoteId") or promptParent:GetAttribute("NoteId")
		if typeof(noteId) ~= "string" or noteId == "" then
			return false, {
				Key = "interaction.feedback.missing_note_id",
			}
		end
		if noteId == "note_5" and Workspace:GetAttribute("TeacherDeskUnlocked") ~= true then
			return false, {
				Message = "ลิ้นชักยังล็อกอยู่",
			}
		end

		if not NoteData.getNoteById(noteId) then
			return false, {
				Key = "interaction.feedback.unknown_note",
			}
		end

		self.eventRemote:FireClient(player, {
			Type = "Note",
			NoteId = noteId,
		})

		return true
	end)

	self:RegisterHandler("InventoryPickup", function(_, player, target)
		local tool = getTool(target)
		if not tool then
			return false, {
				Key = "interaction.feedback.missing_item",
			}
		end

		local apiFolder = ServerStorage:FindFirstChild("InventoryServerApi")
		local pickupWorldTool = apiFolder and apiFolder:FindFirstChild("PickupWorldTool")
		if not pickupWorldTool or not pickupWorldTool:IsA("BindableFunction") then
			return false, {
				Key = "interaction.feedback.inventory_not_ready",
			}
		end

		return pickupWorldTool:Invoke(player, tool)
	end)
end

function InteractionService:scanWorkspace()
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		self:track(descendant)
	end

	for _, tagged in ipairs(CollectionService:GetTagged(CONFIG.TagName)) do
		self:track(tagged)
	end
end

function InteractionService:Init()
	self.eventRemote = RemoteGateway.getOrCreateRemote(CONFIG.RemotesFolderName, CONFIG.EventName, "RemoteEvent")
	self.rateLimit = RemoteGateway.createRateLimiter({
		Window = CONFIG.RateLimitWindow,
	})
	self:registerDefaultHandlers()
end

function InteractionService:Start()
	self:scanWorkspace()

	Workspace.DescendantAdded:Connect(function(instance)
		task.defer(function()
			self:track(instance)
		end)
	end)

	Workspace.DescendantRemoving:Connect(function(instance)
		if instance:IsA("BasePart") then
			self:untrack(instance)
		end
	end)

	CollectionService:GetInstanceAddedSignal(CONFIG.TagName):Connect(function(instance)
		self:track(instance)
	end)

	CollectionService:GetInstanceRemovedSignal(CONFIG.TagName):Connect(function(instance)
		if instance:IsA("BasePart") then
			self:untrack(instance)
		end
	end)
end

return InteractionService
