local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

print("[InventoryService] Boot")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local SystemHub = require(Core:WaitForChild("SystemHub"))

if not SystemHub.begin("InventoryService", script) then
	return
end

local InventoryShared = Shared:WaitForChild("InventoryShared")
local Config = require(InventoryShared:WaitForChild("Config"))
local GridUtils = require(InventoryShared:WaitForChild("GridUtils"))
local ItemDefinitions = require(InventoryShared:WaitForChild("ItemDefinitions"))
local ObjectiveData = require(Shared:WaitForChild("ObjectiveData"))

local remotesFolder = ReplicatedStorage:FindFirstChild(Config.RemotesFolderName)
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = Config.RemotesFolderName
	remotesFolder.Parent = ReplicatedStorage
end

local stateRemote = remotesFolder:FindFirstChild("State")
if not stateRemote then
	stateRemote = Instance.new("RemoteEvent")
	stateRemote.Name = "State"
	stateRemote.Parent = remotesFolder
end

local requestMoveRemote = remotesFolder:FindFirstChild("RequestMoveItem")
if not requestMoveRemote then
	requestMoveRemote = Instance.new("RemoteFunction")
	requestMoveRemote.Name = "RequestMoveItem"
	requestMoveRemote.Parent = remotesFolder
end

local requestRotateRemote = remotesFolder:FindFirstChild("RequestRotateItem")
if not requestRotateRemote then
	requestRotateRemote = Instance.new("RemoteFunction")
	requestRotateRemote.Name = "RequestRotateItem"
	requestRotateRemote.Parent = remotesFolder
end

local requestEquipRemote = remotesFolder:FindFirstChild("RequestEquipHandItem")
if not requestEquipRemote then
	requestEquipRemote = Instance.new("RemoteFunction")
	requestEquipRemote.Name = "RequestEquipHandItem"
	requestEquipRemote.Parent = remotesFolder
end

local getStateRemote = remotesFolder:FindFirstChild("GetState")
if not getStateRemote then
	getStateRemote = Instance.new("RemoteFunction")
	getStateRemote.Name = "GetState"
	getStateRemote.Parent = remotesFolder
end

local serverApiFolder = ServerStorage:FindFirstChild("InventoryServerApi")
if not serverApiFolder then
	serverApiFolder = Instance.new("Folder")
	serverApiFolder.Name = "InventoryServerApi"
	serverApiFolder.Parent = ServerStorage
end

local removeItemByDefinitionBindable = serverApiFolder:FindFirstChild("RemoveItemByDefinitionId")
if not removeItemByDefinitionBindable then
	removeItemByDefinitionBindable = Instance.new("BindableFunction")
	removeItemByDefinitionBindable.Name = "RemoveItemByDefinitionId"
	removeItemByDefinitionBindable.Parent = serverApiFolder
end

local placeQuestItemBindable = serverApiFolder:FindFirstChild("PlaceQuestItemByDefinitionId")
if not placeQuestItemBindable then
	placeQuestItemBindable = Instance.new("BindableFunction")
	placeQuestItemBindable.Name = "PlaceQuestItemByDefinitionId"
	placeQuestItemBindable.Parent = serverApiFolder
end

local pickupWorldToolBindable = serverApiFolder:FindFirstChild("PickupWorldTool")
if not pickupWorldToolBindable then
	pickupWorldToolBindable = Instance.new("BindableFunction")
	pickupWorldToolBindable.Name = "PickupWorldTool"
	pickupWorldToolBindable.Parent = serverApiFolder
end

local storedItemFolder = ServerStorage:FindFirstChild("InventoryStoredItems")
if not storedItemFolder then
	storedItemFolder = Instance.new("Folder")
	storedItemFolder.Name = "InventoryStoredItems"
	storedItemFolder.Parent = ServerStorage
end

local InventoryService = {}
InventoryService.playerStates = {}
InventoryService.worldToolConnections = {}
InventoryService.storedItemInstances = {}

local function getObjectiveUpsertBindable()
	local objectiveApiFolder = ServerStorage:FindFirstChild("ObjectiveServerApi")
	if not objectiveApiFolder then
		return nil
	end

	local upsertObjective = objectiveApiFolder:FindFirstChild("UpsertObjective")
	if upsertObjective and upsertObjective:IsA("BindableFunction") then
		return upsertObjective
	end

	return nil
end

local function getObjectiveRemoveBindable()
	local objectiveApiFolder = ServerStorage:FindFirstChild("ObjectiveServerApi")
	if not objectiveApiFolder then
		return nil
	end

	local removeObjective = objectiveApiFolder:FindFirstChild("RemoveObjective")
	if removeObjective and removeObjective:IsA("BindableFunction") then
		return removeObjective
	end

	return nil
end

local function invokeObjectiveCallback(callbackName: string?, player: Player, payload)
	if typeof(callbackName) ~= "string" or callbackName == "" then
		return
	end

	local callbacksFolder = ServerStorage:FindFirstChild("ObjectiveCallbacks")
	if not callbacksFolder or not callbacksFolder:IsA("Folder") then
		return
	end

	local callback = callbacksFolder:FindFirstChild(callbackName)
	if callback and callback:IsA("BindableEvent") then
		callback:Fire(player, payload)
	elseif callback and callback:IsA("BindableFunction") then
		callback:Invoke(player, payload)
	end
end

local function applyPickupObjectiveAction(player: Player, definitionId: string, action)
	if typeof(action) ~= "table" or typeof(action.ObjectiveId) ~= "string" or action.ObjectiveId == "" then
		return
	end

	local payload = {
		ObjectiveId = action.ObjectiveId,
		Kind = action.Kind,
		PickupDefinitionId = definitionId,
	}

	if action.Kind == "Complete" then
		local removeObjective = getObjectiveRemoveBindable()
		if not removeObjective then
			return
		end

		local ok, didRemove = pcall(function()
			return removeObjective:Invoke(player, action.ObjectiveId)
		end)
		if ok and didRemove ~= false then
			invokeObjectiveCallback(action.CallbackName, player, payload)
		end
		return
	end

	local upsertObjective = getObjectiveUpsertBindable()
	if not upsertObjective then
		return
	end

	local ok, didUpsert = pcall(function()
		return upsertObjective:Invoke(player, {
			Id = action.ObjectiveId,
		})
	end)
	if ok and didUpsert ~= false then
		invokeObjectiveCallback(action.CallbackName, player, payload)
	end
end

local function applyPlaceObjectiveAction(player: Player, definitionId: string, action, placedInstance, zoneInstance)
	if typeof(action) ~= "table" or typeof(action.ObjectiveId) ~= "string" or action.ObjectiveId == "" then
		return
	end

	local payload = {
		ObjectiveId = action.ObjectiveId,
		Kind = action.Kind,
		PlacedDefinitionId = definitionId,
		PlacedInstance = placedInstance,
		ZoneInstance = zoneInstance,
	}

	if action.Kind == "Complete" then
		local removeObjective = getObjectiveRemoveBindable()
		if not removeObjective then
			return
		end

		local ok, didRemove = pcall(function()
			return removeObjective:Invoke(player, action.ObjectiveId)
		end)
		if ok and didRemove ~= false then
			invokeObjectiveCallback(action.CallbackName, player, payload)
		end
		return
	end

	local upsertObjective = getObjectiveUpsertBindable()
	if not upsertObjective then
		return
	end

	local ok, didUpsert = pcall(function()
		return upsertObjective:Invoke(player, {
			Id = action.ObjectiveId,
		})
	end)
	if ok and didUpsert ~= false then
		invokeObjectiveCallback(action.CallbackName, player, payload)
	end
end

local function getQuestPlacePoint(zoneInstance)
	if typeof(zoneInstance) ~= "Instance" then
		return nil, nil
	end

	local tagName = ObjectiveData.getPlacePointTagName()
	local attributeName = ObjectiveData.getPlacePointIdAttributeName()
	local current = zoneInstance

	while current and current ~= Workspace do
		if CollectionService:HasTag(current, tagName) then
			local placePointId = current:GetAttribute(attributeName)
			if typeof(placePointId) == "string" and placePointId ~= "" then
				return placePointId, current
			end
		end

		current = current.Parent
	end

	return nil, nil
end

local function shallowCopy(source)
	local clone = {}
	for key, value in source do
		clone[key] = value
	end
	return clone
end

local STARTER_ITEMS = {
	{
		DefinitionId = "Flashlight",
		Location = "Hand",
		Rotated = false,
		Data = {
			Durability = 100,
		},
	},
}

function InventoryService:getDefinition(itemState)
	return ItemDefinitions[itemState.DefinitionId]
end

function InventoryService:getDefinitionById(definitionId: string)
	return ItemDefinitions[definitionId]
end

function InventoryService:getResolvedRotation(definition, rotated: boolean?, fallback: boolean)
	local resolved = fallback

	if rotated ~= nil then
		resolved = rotated == true
	end

	if not definition.Rotatable then
		resolved = false
	end

	return resolved
end

function InventoryService:rebuildOccupancy(playerState)
	playerState.Occupancy = GridUtils.buildOccupancyFromItems(playerState.Items, ItemDefinitions)
	return playerState.Occupancy
end

function InventoryService:findItemByDefinitionId(playerState, definitionId: string)
	for _, itemState in playerState.Items do
		if itemState.DefinitionId == definitionId then
			return itemState
		end
	end

	return nil
end

function InventoryService:countItemsByDefinitionId(playerState, definitionId: string)
	local count = 0

	for _, itemState in playerState.Items do
		if itemState.DefinitionId == definitionId then
			count += 1
		end
	end

	return count
end

function InventoryService:countGlobalItemsByDefinitionId(definitionId: string)
	local count = 0

	for _, playerState in self.playerStates do
		count += self:countItemsByDefinitionId(playerState, definitionId)
	end

	return count
end

function InventoryService:getMaxOwned(definition)
	if typeof(definition.MaxOwned) == "number" and definition.MaxOwned > 0 then
		return math.floor(definition.MaxOwned)
	end

	return nil
end

function InventoryService:getMaxGlobalOwned(definition)
	if typeof(definition.MaxGlobalOwned) == "number" and definition.MaxGlobalOwned > 0 then
		return math.floor(definition.MaxGlobalOwned)
	end

	return nil
end

function InventoryService:canOwnAdditional(playerState, definitionId: string)
	local definition = self:getDefinitionById(definitionId)
	if not definition then
		return false, "Unknown item definition"
	end

	local maxOwned = self:getMaxOwned(definition)
	if maxOwned ~= nil and self:countItemsByDefinitionId(playerState, definitionId) >= maxOwned then
		return false, "Already own maximum amount"
	end

	local maxGlobalOwned = self:getMaxGlobalOwned(definition)
	if maxGlobalOwned ~= nil and self:countGlobalItemsByDefinitionId(definitionId) >= maxGlobalOwned then
		return false, "Already owned by another player"
	end

	return true, nil
end

function InventoryService:findFirstOpenSlot(playerState, definitionId: string, rotated: boolean?)
	local definition = self:getDefinitionById(definitionId)
	if not definition then
		return nil, nil
	end

	local width, height = GridUtils.getFootprint(definition, rotated)
	for gridY = 1, playerState.Rows - height + 1 do
		for gridX = 1, playerState.Columns - width + 1 do
			if GridUtils.canPlaceItem(
				playerState.Occupancy,
				playerState.Columns,
				playerState.Rows,
				gridX,
				gridY,
				width,
				height
			) then
				return gridX, gridY
			end
		end
	end

	return nil, nil
end

function InventoryService:createItemState(
	playerState,
	definitionId: string,
	gridX: number?,
	gridY: number?,
	rotated: boolean?,
	extraData,
	location: string?
)
	local definition = ItemDefinitions[definitionId]
	assert(definition, string.format("Unknown item definition '%s'", definitionId))

	playerState.NextItemSerial += 1
	local itemId = string.format("%d-%d", playerState.Player.UserId, playerState.NextItemSerial)
	local itemLocation = location == "Hand" and "Hand" or "Inventory"

	local itemState = {
		ItemId = itemId,
		DefinitionId = definition.Id,
		Location = itemLocation,
		GridX = gridX,
		GridY = gridY,
		Rotated = self:getResolvedRotation(definition, rotated, false),
		Data = shallowCopy(extraData or {}),
	}

	playerState.Items[itemId] = itemState

	if itemLocation == "Hand" then
		playerState.HandItemId = itemId
	end

	return itemState
end

function InventoryService:addInventoryItem(playerState, definitionId: string, rotated: boolean?, extraData)
	local definition = self:getDefinitionById(definitionId)
	if not definition then
		return false, "Unknown item definition"
	end

	local canOwnAdditional, denyReason = self:canOwnAdditional(playerState, definitionId)
	if not canOwnAdditional then
		return false, denyReason
	end

	local gridX, gridY = self:findFirstOpenSlot(playerState, definitionId, rotated)
	if gridX == nil or gridY == nil then
		return false, "Inventory full"
	end

	local itemState = self:createItemState(playerState, definitionId, gridX, gridY, rotated, extraData, "Inventory")
	self:rebuildOccupancy(playerState)
	self:pushState(playerState.Player)

	return true, itemState
end

function InventoryService:serializeState(playerState)
	local items = {}

	for itemId, itemState in playerState.Items do
		local definition = self:getDefinition(itemState)
		if definition then
			local width, height = GridUtils.getFootprint(definition, itemState.Rotated)
			items[itemId] = {
				ItemId = itemState.ItemId,
				DefinitionId = itemState.DefinitionId,
				Name = definition.Name,
				Type = definition.Type,
				Rotatable = definition.Rotatable,
				Rotated = itemState.Rotated,
				Location = itemState.Location,
				GridX = itemState.GridX,
				GridY = itemState.GridY,
				Width = width,
				Height = height,
				BaseWidth = definition.Width,
				BaseHeight = definition.Height,
				Data = shallowCopy(itemState.Data),
			}
		end
	end

	return {
		Grid = {
			Columns = playerState.Columns,
			Rows = playerState.Rows,
		},
		HandItemId = playerState.HandItemId,
		Items = items,
		ItemDefinitions = ItemDefinitions,
	}
end

function InventoryService:syncPlayerAttributes(playerState)
	local handItemId = playerState.HandItemId
	local handItem = handItemId and playerState.Items[handItemId] or nil

	playerState.Player:SetAttribute("HeldItemId", handItemId)
	playerState.Player:SetAttribute("HeldDefinitionId", handItem and handItem.DefinitionId or nil)
end

function InventoryService:pushState(player)
	local playerState = self.playerStates[player]
	if not playerState then
		return
	end

	self:syncPlayerAttributes(playerState)
	stateRemote:FireClient(player, self:serializeState(playerState))
end

function InventoryService:unequipPlayerTools(player)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:UnequipTools()
	end
end

function InventoryService:getPlayerToolByDefinitionId(player, definitionId: string)
	local character = player.Character
	if character then
		local tool = character:FindFirstChild(definitionId)
		if tool and tool:IsA("Tool") then
			return tool
		end
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		local tool = backpack:FindFirstChild(definitionId)
		if tool and tool:IsA("Tool") then
			return tool
		end
	end

	return nil
end

function InventoryService:destroyPlayerToolsByDefinitionId(player, definitionId: string)
	local character = player.Character
	if character then
		for _, child in character:GetChildren() do
			if child:IsA("Tool") and child.Name == definitionId then
				child:Destroy()
			end
		end
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in backpack:GetChildren() do
			if child:IsA("Tool") and child.Name == definitionId then
				child:Destroy()
			end
		end
	end
end

function InventoryService:storeItemInstance(itemState, instance)
	if not itemState or not instance or not instance:IsA("Tool") then
		return nil
	end

	local existing = self.storedItemInstances[itemState.ItemId]
	if existing and existing ~= instance then
		existing:Destroy()
	end

	self:disconnectWorldTool(instance)

	instance:SetAttribute("InventoryItemId", itemState.ItemId)
	instance.Parent = storedItemFolder
	self.storedItemInstances[itemState.ItemId] = instance

	return instance
end

function InventoryService:getStoredItemInstance(itemId: string)
	local storedInstance = self.storedItemInstances[itemId]
	if storedInstance and storedInstance.Parent then
		return storedInstance
	end

	for _, child in storedItemFolder:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("InventoryItemId") == itemId then
			self.storedItemInstances[itemId] = child
			return child
		end
	end

	return nil
end

function InventoryService:takeStoredItemInstance(itemId: string)
	local instance = self:getStoredItemInstance(itemId)
	self.storedItemInstances[itemId] = nil
	return instance
end

function InventoryService:destroyStoredItemInstance(itemId: string)
	local instance = self:takeStoredItemInstance(itemId)
	if instance then
		instance:Destroy()
	end
end

function InventoryService:getItemTemplate(definitionId: string)
	local serverTemplates = ServerStorage:FindFirstChild("InventoryItemTemplates")
	local serverTemplate = serverTemplates and serverTemplates:FindFirstChild(definitionId)
	if serverTemplate and serverTemplate:IsA("Tool") then
		return serverTemplate
	end

	local directServerTemplate = ServerStorage:FindFirstChild(definitionId)
	if directServerTemplate and directServerTemplate:IsA("Tool") and directServerTemplate.Parent ~= storedItemFolder then
		return directServerTemplate
	end

	local replicatedTemplates = ReplicatedStorage:FindFirstChild("InventoryItemTemplates")
	local replicatedTemplate = replicatedTemplates and replicatedTemplates:FindFirstChild(definitionId)
	if replicatedTemplate and replicatedTemplate:IsA("Tool") then
		return replicatedTemplate
	end

	return nil
end

function InventoryService:createPlacedItemInstance(itemState)
	local storedTool = self:takeStoredItemInstance(itemState.ItemId)
	if storedTool then
		return storedTool
	end

	local template = self:getItemTemplate(itemState.DefinitionId)
	if template then
		local clone = template:Clone()
		clone:SetAttribute("InventoryItemId", itemState.ItemId)
		return clone
	end

	return nil
end

function InventoryService:removeItemState(playerState, itemState, options)
	if not playerState or not itemState then
		return false, "Missing item state"
	end

	options = options or {}

	if itemState.Location == "Inventory" and itemState.GridX ~= nil and itemState.GridY ~= nil then
		GridUtils.clearItemFromGrid(playerState.Occupancy, itemState.ItemId)
	elseif playerState.HandItemId == itemState.ItemId then
		self:unequipPlayerTools(playerState.Player)
		playerState.HandItemId = nil
	end

	self:destroyPlayerToolsByDefinitionId(playerState.Player, itemState.DefinitionId)
	if not options.PreserveStoredInstance then
		self:destroyStoredItemInstance(itemState.ItemId)
	end
	playerState.Items[itemState.ItemId] = nil
	self:rebuildOccupancy(playerState)
	self:pushState(playerState.Player)

	return true, "Removed"
end

function InventoryService:removeItemByDefinitionId(player, definitionId: string)
	local playerState = self.playerStates[player]
	if not playerState then
		return false, "Missing inventory state"
	end

	local itemState = self:findItemByDefinitionId(playerState, definitionId)
	if not itemState then
		return false, "Item not owned"
	end

	return self:removeItemState(playerState, itemState)
end

function InventoryService:placeQuestItemByDefinitionId(player, definitionId: string, zoneInstance, placementOffset)
	local playerState = self.playerStates[player]
	if not playerState then
		return false, "Missing inventory state"
	end

	local itemState = self:findItemByDefinitionId(playerState, definitionId)
	if not itemState then
		return false, "Item not owned"
	end

	local definition = self:getDefinition(itemState)
	if not definition then
		return false, "Missing definition"
	end

	if definition.Type ~= "Quest" then
		return false, "Item is not a quest item"
	end

	local storedTool = self:createPlacedItemInstance(itemState)
	if not storedTool then
		return false, "No stored item instance or template"
	end

	local didRemove, removeReason = self:removeItemState(playerState, itemState, {
		PreserveStoredInstance = true,
	})
	if not didRemove then
		self.storedItemInstances[itemState.ItemId] = storedTool
		storedTool.Parent = storedItemFolder
		return false, removeReason
	end

	local handle = storedTool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		storedTool:Destroy()
		return false, "Stored item is missing a valid Handle"
	end

	storedTool:SetAttribute("InventoryItemId", nil)
	storedTool:SetAttribute("InventoryPickupLocked", nil)
	storedTool.Parent = Workspace

	local baseCFrame = nil
	if typeof(zoneInstance) == "Instance" then
		if zoneInstance:IsA("BasePart") then
			baseCFrame = zoneInstance.CFrame
		elseif zoneInstance:IsA("Model") and zoneInstance.PrimaryPart then
			baseCFrame = zoneInstance.PrimaryPart.CFrame
		end
	end

	local offset = typeof(placementOffset) == "CFrame" and placementOffset or CFrame.new(0, 2, 0)
	if baseCFrame ~= nil then
		handle.CFrame = baseCFrame * offset
	end

	local canPickupAfterPlace = definition.AllowPickupAfterPlace ~= false

	handle.Anchored = true
	handle.CanCollide = false

	local pickupPrompt = handle:FindFirstChildWhichIsA("ProximityPrompt")
	if pickupPrompt then
		pickupPrompt.Enabled = canPickupAfterPlace
	end

	storedTool:SetAttribute("DisableInventoryPickup", not canPickupAfterPlace)

	if canPickupAfterPlace then
		self:connectWorldTool(storedTool)
	else
		self:disconnectWorldTool(storedTool)
	end

	local placePointId, placePointInstance = getQuestPlacePoint(zoneInstance)
	if placePointId then
		for _, action in ipairs(ObjectiveData.getPlacePointActions(placePointId, definition.Id)) do
			applyPlaceObjectiveAction(player, definition.Id, action, storedTool, placePointInstance)
		end
	end

	for _, action in ipairs(ObjectiveData.getPlaceActions(definition.Id)) do
		applyPlaceObjectiveAction(player, definition.Id, action, storedTool, zoneInstance)
	end

	return true, storedTool
end

function InventoryService:syncContainerItem(playerState, instance)
	if not instance or not instance:IsA("Tool") then
		return false, "Not a tool"
	end

	local definition = self:getDefinitionById(instance.Name)
	if not definition then
		return false, "No matching definition"
	end

	if instance:GetAttribute("InventoryItemId") then
		return true, "Already linked"
	end

	local canOwnAdditional, denyReason = self:canOwnAdditional(playerState, definition.Id)
	if not canOwnAdditional then
		local existingItem = self:findItemByDefinitionId(playerState, definition.Id)
		if existingItem and definition.Type == "Tool" then
			instance:SetAttribute("InventoryItemId", existingItem.ItemId)
			return true, "Linked to existing tool item"
		end

		instance:SetAttribute("InventoryBlockedReason", denyReason)
		instance:Destroy()
		return false, denyReason
	end

	local didAdd, result = self:addInventoryItem(playerState, definition.Id, false, {
		ImportedFromWorld = true,
	})
	if not didAdd then
		warn(string.format("[InventoryService] Failed to import '%s' for %s: %s", definition.Id, playerState.Player.Name, tostring(result)))
		return false, tostring(result)
	end

	local itemState = result
	instance:SetAttribute("InventoryItemId", itemState.ItemId)

	if definition.Type ~= "Tool" then
		self:storeItemInstance(itemState, instance)
	end

	return true, itemState.ItemId
end

function InventoryService:syncPlayerTools(playerState)
	local player = playerState.Player
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in backpack:GetChildren() do
			self:syncContainerItem(playerState, child)
		end
	end

	local character = player.Character
	if character then
		for _, child in character:GetChildren() do
			self:syncContainerItem(playerState, child)
		end
	end
end

function InventoryService:isWorldTool(tool)
	if not tool or not tool:IsA("Tool") then
		return false
	end

	if tool:GetAttribute("DisableInventoryPickup") == true then
		return false
	end

	if not tool:IsDescendantOf(Workspace) then
		return false
	end

	local parent = tool.Parent
	if parent and Players:GetPlayerFromCharacter(parent) then
		return false
	end

	return self:getDefinitionById(tool.Name) ~= nil
end

function InventoryService:disconnectWorldTool(tool)
	local connections = self.worldToolConnections[tool]
	if not connections then
		return
	end

	for _, connection in connections do
		connection:Disconnect()
	end

	self.worldToolConnections[tool] = nil
end

function InventoryService:pickupWorldTool(player, tool)
	if not self:isWorldTool(tool) then
		return false, "Not a world tool"
	end

	if tool:GetAttribute("InventoryPickupLocked") then
		return false, "Pickup already in progress"
	end

	local definition = self:getDefinitionById(tool.Name)
	if not definition then
		return false, "No matching definition"
	end

	local playerState = self.playerStates[player] or self:createPlayerState(player)
	if not playerState then
		return false, "Missing inventory state"
	end

	local canOwnAdditional, denyReason = self:canOwnAdditional(playerState, definition.Id)
	if not canOwnAdditional then
		return false, denyReason
	end

	tool:SetAttribute("InventoryPickupLocked", true)

	local didAdd, result = self:addInventoryItem(playerState, definition.Id, false, {
		ImportedFromWorld = true,
	})
	if not didAdd then
		tool:SetAttribute("InventoryPickupLocked", nil)
		return false, tostring(result)
	end

	local itemState = result
	tool:SetAttribute("InventoryItemId", itemState.ItemId)

	for _, action in ipairs(ObjectiveData.getPickupActions(definition.Id)) do
		applyPickupObjectiveAction(player, definition.Id, action)
	end

	local objectiveIdOnPickup = tool:GetAttribute("ObjectiveIdOnPickup")
	local upsertObjective = getObjectiveUpsertBindable()
	if typeof(objectiveIdOnPickup) == "string" and objectiveIdOnPickup ~= "" and upsertObjective then
		local ok, didUpsert, result = pcall(function()
			return upsertObjective:Invoke(player, {
				Id = objectiveIdOnPickup,
				Channel = tool:GetAttribute("ObjectiveChannelOnPickup"),
				Order = tool:GetAttribute("ObjectiveOrderOnPickup"),
				Priority = tool:GetAttribute("ObjectivePriorityOnPickup"),
			})
		end)

		if not ok then
			warn(("[InventoryService] Failed to invoke pickup objective for %s: %s"):format(tool:GetFullName(), tostring(didUpsert)))
		elseif didUpsert == false then
			warn(("[InventoryService] Pickup objective rejected for %s: %s"):format(tool:GetFullName(), tostring(result)))
		end
	end

	if definition.Type == "Tool" then
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack then
			tool.Parent = backpack
		end
	else
		self:storeItemInstance(itemState, tool)
	end

	return true, itemState.ItemId
end

function InventoryService:connectWorldTool(tool)
	if not self:isWorldTool(tool) or self.worldToolConnections[tool] then
		return
	end

	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return
	end

	local connections = {}
	connections.Touched = handle.Touched:Connect(function(hit)
		local character = hit and hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if player then
			task.defer(function()
				self:pickupWorldTool(player, tool)
			end)
		end
	end)
	connections.AncestryChanged = tool.AncestryChanged:Connect(function()
		if not tool:IsDescendantOf(Workspace) then
			self:disconnectWorldTool(tool)
		end
	end)

	self.worldToolConnections[tool] = connections
end

function InventoryService:connectPlayerContainers(playerState)
	local player = playerState.Player
	playerState.Connections = playerState.Connections or {}

	local function connectContainer(container)
		if not container then
			return
		end

		table.insert(playerState.Connections, container.ChildAdded:Connect(function(child)
			task.defer(function()
				self:syncContainerItem(playerState, child)
			end)
		end))
	end

	local function connectBackpack(backpack)
		connectContainer(backpack)
		task.defer(function()
			self:syncPlayerTools(playerState)
		end)
	end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		connectBackpack(backpack)
	end

	table.insert(playerState.Connections, player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			connectBackpack(child)
		end
	end))

	table.insert(playerState.Connections, player.CharacterAdded:Connect(function(character)
		connectContainer(character)
		task.defer(function()
			self:syncPlayerTools(playerState)
		end)
	end))

	if player.Character then
		connectContainer(player.Character)
	end

	task.defer(function()
		self:syncPlayerTools(playerState)
	end)
end

function InventoryService:equipHandItem(player)
	local playerState = self.playerStates[player]
	if not playerState then
		return false, "Missing inventory state"
	end

	local handItemId = playerState.HandItemId
	if not handItemId then
		self:unequipPlayerTools(player)
		return false, "Hand slot is empty"
	end

	local itemState = playerState.Items[handItemId]
	if not itemState then
		return false, "Missing hand item"
	end

	local definition = self:getDefinition(itemState)
	if not definition or definition.Type ~= "Tool" then
		return false, "Hand item is not a tool"
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "Missing humanoid"
	end

	local tool = self:getPlayerToolByDefinitionId(player, itemState.DefinitionId)
	if not tool then
		return false, string.format("Tool '%s' not found in Backpack/Character", itemState.DefinitionId)
	end

	if tool.Parent == character then
		humanoid:UnequipTools()
		return true, "Unequipped"
	end

	humanoid:EquipTool(tool)
	return true, "Equipped"
end

function InventoryService:moveItemToInventory(playerState, itemState, gridX: number?, gridY: number?, rotated: boolean?)
	if typeof(gridX) ~= "number" or typeof(gridY) ~= "number" then
		return false, "Invalid position"
	end

	gridX = math.floor(gridX)
	gridY = math.floor(gridY)

	local definition = self:getDefinition(itemState)
	if not definition then
		return false, "Missing definition"
	end

	local nextRotated = self:getResolvedRotation(definition, rotated, itemState.Rotated)
	local previousLocation = itemState.Location
	local previousGridX = itemState.GridX
	local previousGridY = itemState.GridY
	local previousRotated = itemState.Rotated

	if previousLocation == "Inventory" then
		GridUtils.clearItemFromGrid(playerState.Occupancy, itemState.ItemId)
	elseif playerState.HandItemId == itemState.ItemId then
		self:unequipPlayerTools(playerState.Player)
		playerState.HandItemId = nil
	end

	local nextWidth, nextHeight = GridUtils.getFootprint(definition, nextRotated)
	local canPlace = GridUtils.canPlaceItem(
		playerState.Occupancy,
		playerState.Columns,
		playerState.Rows,
		gridX,
		gridY,
		nextWidth,
		nextHeight
	)

	if not canPlace then
		if previousLocation == "Inventory" and previousGridX ~= nil and previousGridY ~= nil then
			local previousWidth, previousHeight = GridUtils.getFootprint(definition, previousRotated)
			GridUtils.writeItemToGrid(
				playerState.Occupancy,
				itemState.ItemId,
				previousGridX,
				previousGridY,
				previousWidth,
				previousHeight
			)
		elseif previousLocation == "Hand" then
			playerState.HandItemId = itemState.ItemId
		end

		return false, "Cannot place item there"
	end

	itemState.Location = "Inventory"
	itemState.GridX = gridX
	itemState.GridY = gridY
	itemState.Rotated = nextRotated

	GridUtils.writeItemToGrid(playerState.Occupancy, itemState.ItemId, gridX, gridY, nextWidth, nextHeight)
	self:pushState(playerState.Player)

	return true, "Moved to inventory"
end

function InventoryService:moveItemToHand(playerState, itemState, rotated: boolean?)
	local definition = self:getDefinition(itemState)
	if not definition then
		return false, "Missing definition"
	end

	if definition.Type ~= "Tool" then
		return false, "Only tools can be held"
	end

	if playerState.HandItemId ~= nil and playerState.HandItemId ~= itemState.ItemId then
		return false, "Hand slot occupied"
	end

	local nextRotated = self:getResolvedRotation(definition, rotated, itemState.Rotated)
	if itemState.Location == "Inventory" then
		GridUtils.clearItemFromGrid(playerState.Occupancy, itemState.ItemId)
	end

	itemState.Location = "Hand"
	itemState.Rotated = nextRotated
	playerState.HandItemId = itemState.ItemId
	self:pushState(playerState.Player)

	return true, "Moved to hand"
end

function InventoryService:moveItem(player, payload)
	local playerState = self.playerStates[player]
	if not playerState then
		return false, "Missing inventory state"
	end

	if typeof(payload) ~= "table" then
		return false, "Invalid payload"
	end

	local itemId = tostring(payload.ItemId)
	local itemState = playerState.Items[itemId]
	if not itemState then
		return false, "Unknown item"
	end

	local target = payload.Target == "Hand" and "Hand" or "Inventory"
	if target == "Hand" then
		return self:moveItemToHand(playerState, itemState, payload.Rotated)
	end

	return self:moveItemToInventory(
		playerState,
		itemState,
		tonumber(payload.GridX),
		tonumber(payload.GridY),
		payload.Rotated
	)
end

function InventoryService:rotateItem(player, itemId: string)
	local playerState = self.playerStates[player]
	if not playerState then
		return false, "Missing inventory state"
	end

	local itemState = playerState.Items[itemId]
	if not itemState then
		return false, "Unknown item"
	end

	local definition = self:getDefinition(itemState)
	if not definition or not definition.Rotatable then
		return false, "Item cannot rotate"
	end

	local nextRotated = not itemState.Rotated
	if itemState.Location == "Hand" then
		itemState.Rotated = nextRotated
		self:pushState(player)
		return true, "Rotated"
	end

	return self:moveItemToInventory(playerState, itemState, itemState.GridX, itemState.GridY, nextRotated)
end

function InventoryService:createPlayerState(player)
	if self.playerStates[player] then
		return self.playerStates[player]
	end

	local playerState = {
		Player = player,
		Columns = Config.Grid.Columns,
		Rows = Config.Grid.Rows,
		HandItemId = nil,
		Items = {},
		Occupancy = {},
		NextItemSerial = 0,
		Connections = {},
	}

	self.playerStates[player] = playerState

	for _, starterItem in STARTER_ITEMS do
		if ItemDefinitions[starterItem.DefinitionId] then
			self:createItemState(
				playerState,
				starterItem.DefinitionId,
				starterItem.GridX,
				starterItem.GridY,
				starterItem.Rotated,
				starterItem.Data,
				starterItem.Location
			)
		end
	end

	self:rebuildOccupancy(playerState)
	self:pushState(player)
	self:connectPlayerContainers(playerState)

	return playerState
end

function InventoryService:removePlayerState(player)
	local playerState = self.playerStates[player]
	if playerState and playerState.Connections then
		for _, connection in playerState.Connections do
			connection:Disconnect()
		end
	end

	if playerState then
		for _, itemState in playerState.Items do
			self:destroyStoredItemInstance(itemState.ItemId)
		end
	end

	self.playerStates[player] = nil
end

requestMoveRemote.OnServerInvoke = function(player, payload)
	return InventoryService:moveItem(player, payload)
end

requestRotateRemote.OnServerInvoke = function(player, itemId)
	return InventoryService:rotateItem(player, tostring(itemId))
end

requestEquipRemote.OnServerInvoke = function(player)
	return InventoryService:equipHandItem(player)
end

removeItemByDefinitionBindable.OnInvoke = function(player, definitionId)
	return InventoryService:removeItemByDefinitionId(player, tostring(definitionId))
end

placeQuestItemBindable.OnInvoke = function(player, definitionId, zoneInstance, placementOffset)
	return InventoryService:placeQuestItemByDefinitionId(
		player,
		tostring(definitionId),
		zoneInstance,
		placementOffset
	)
end

pickupWorldToolBindable.OnInvoke = function(player, tool)
	return InventoryService:pickupWorldTool(player, tool)
end

getStateRemote.OnServerInvoke = function(player)
	local playerState = InventoryService.playerStates[player]
	if not playerState then
		playerState = InventoryService:createPlayerState(player)
	end

	return InventoryService:serializeState(playerState)
end

Players.PlayerAdded:Connect(function(player)
	InventoryService:createPlayerState(player)
end)

Players.PlayerRemoving:Connect(function(player)
	InventoryService:removePlayerState(player)
end)

for _, player in Players:GetPlayers() do
	InventoryService:createPlayerState(player)
end

Workspace.DescendantAdded:Connect(function(instance)
	if instance:IsA("Tool") then
		task.defer(function()
			InventoryService:connectWorldTool(instance)
		end)
	end
end)

for _, instance in Workspace:GetDescendants() do
	if instance:IsA("Tool") then
		InventoryService:connectWorldTool(instance)
	end
end

SystemHub.ready("InventoryService", script)
