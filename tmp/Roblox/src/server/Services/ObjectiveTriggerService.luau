local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ObjectiveData = require(Shared:WaitForChild("ObjectiveData"))

local CONFIG = {
	TagName = "ObjectiveTrigger",
	TouchDebounceWindow = 0.35,
	CallbacksFolderName = "ObjectiveCallbacks",
}

local ObjectiveTriggerService = {
	Name = "ObjectiveTriggerService",
	Priority = 26,
	upsertObjective = nil,
	removeObjective = nil,
	tracked = {},
}

local function getStringAttribute(instance: Instance, attributeName: string)
	local value = instance:GetAttribute(attributeName)
	if typeof(value) == "string" and value ~= "" then
		return value
	end

	return nil
end

local function getNumberAttribute(instance: Instance, attributeName: string)
	local value = instance:GetAttribute(attributeName)
	if typeof(value) == "number" then
		return value
	end

	return nil
end

local function getBooleanAttribute(instance: Instance, attributeName: string, fallback: boolean)
	local value = instance:GetAttribute(attributeName)
	if typeof(value) == "boolean" then
		return value
	end

	return fallback
end

local function getPlayerFromHit(hit: BasePart?): Player?
	local current = hit
	while current and current ~= Workspace do
		if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
			local player = Players:GetPlayerFromCharacter(current)
			if player then
				return player
			end
		end

		current = current.Parent
	end

	return nil
end

function ObjectiveTriggerService:untrack(instance: Instance)
	local record = self.tracked[instance]
	if not record then
		return
	end

	for _, connection in ipairs(record.Connections) do
		connection:Disconnect()
	end

	self.tracked[instance] = nil
end

function ObjectiveTriggerService:invokeCallback(callbackName: string?, player: Player, payload)
	if typeof(callbackName) ~= "string" or callbackName == "" then
		return
	end

	local callbacksFolder = ServerStorage:FindFirstChild(CONFIG.CallbacksFolderName)
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

function ObjectiveTriggerService:applyObjectiveAction(action, player: Player, instance: BasePart)
	if typeof(action) ~= "table" or typeof(action.ObjectiveId) ~= "string" or action.ObjectiveId == "" then
		return false
	end

	local triggerId = getStringAttribute(instance, "ObjectiveTriggerId") or getStringAttribute(instance, "ObjectiveId")
	local payload = {
		TriggerId = triggerId,
		ObjectiveId = action.ObjectiveId,
		Kind = action.Kind,
		Instance = instance,
	}

	if action.Kind == "Complete" then
		if not self.removeObjective then
			return false
		end

		local ok, didRemove, result = pcall(function()
			return self.removeObjective:Invoke(player, action.ObjectiveId)
		end)

		if not ok then
			warn(("[ObjectiveTriggerService] Failed to complete objective for %s: %s"):format(instance:GetFullName(), tostring(didRemove)))
			return false
		elseif didRemove == false then
			return false
		end

		self:invokeCallback(action.CallbackName, player, payload)
		return true
	end

	if not self.upsertObjective then
		return false
	end

	local ok, didUpsert, result = pcall(function()
		return self.upsertObjective:Invoke(player, {
			Id = action.ObjectiveId,
			Channel = getStringAttribute(instance, "ObjectiveChannel"),
			Title = getStringAttribute(instance, "ObjectiveTitle"),
			TitleKey = getStringAttribute(instance, "ObjectiveTitleKey"),
			Description = getStringAttribute(instance, "ObjectiveDescription"),
			DescriptionKey = getStringAttribute(instance, "ObjectiveDescriptionKey"),
			Order = getNumberAttribute(instance, "ObjectiveOrder"),
			Priority = getNumberAttribute(instance, "ObjectivePriority"),
		})
	end)

	if not ok then
		warn(("[ObjectiveTriggerService] Failed to invoke objective for %s: %s"):format(instance:GetFullName(), tostring(didUpsert)))
		return false
	elseif didUpsert == false then
		warn(("[ObjectiveTriggerService] Objective rejected for %s: %s"):format(instance:GetFullName(), tostring(result)))
		return false
	end

	self:invokeCallback(action.CallbackName, player, payload)
	return true
end

function ObjectiveTriggerService:fireObjective(instance: BasePart, player: Player)
	local triggerId = getStringAttribute(instance, "ObjectiveTriggerId") or getStringAttribute(instance, "ObjectiveId")
	if not triggerId then
		warn(("[ObjectiveTriggerService] %s is missing ObjectiveTriggerId/ObjectiveId"):format(instance:GetFullName()))
		return false
	end

	local actions = ObjectiveData.getTriggerActions(triggerId)
	local didFire = false
	for _, action in ipairs(actions) do
		if self:applyObjectiveAction(action, player, instance) then
			didFire = true
		end
	end

	if didFire then
		return true
	end

	if not self.upsertObjective then
		return false
	end

	local payload = {
		Id = getStringAttribute(instance, "ObjectiveId"),
		Channel = getStringAttribute(instance, "ObjectiveChannel"),
		Title = getStringAttribute(instance, "ObjectiveTitle"),
		TitleKey = getStringAttribute(instance, "ObjectiveTitleKey"),
		Description = getStringAttribute(instance, "ObjectiveDescription"),
		DescriptionKey = getStringAttribute(instance, "ObjectiveDescriptionKey"),
		Order = getNumberAttribute(instance, "ObjectiveOrder"),
		Priority = getNumberAttribute(instance, "ObjectivePriority"),
	}

	if typeof(payload.Id) ~= "string" or payload.Id == "" then
		return false
	end

	local ok, didUpsert, result = pcall(function()
		return self.upsertObjective:Invoke(player, payload)
	end)

	if not ok then
		warn(("[ObjectiveTriggerService] Failed to invoke legacy objective for %s: %s"):format(instance:GetFullName(), tostring(didUpsert)))
		return false
	elseif didUpsert == false then
		warn(("[ObjectiveTriggerService] Legacy objective rejected for %s: %s"):format(instance:GetFullName(), tostring(result)))
		return false
	end

	local callbackName = getStringAttribute(instance, "ObjectiveCallbackName")
	self:invokeCallback(callbackName, player, {
		TriggerId = triggerId,
		ObjectiveId = payload.Id,
		Kind = "Start",
		Instance = instance,
	})
	return true
end

function ObjectiveTriggerService:handleTouched(instance: BasePart, hit: BasePart)
	local player = getPlayerFromHit(hit)
	if not player then
		return
	end

	local record = self.tracked[instance]
	if not record then
		return
	end

	local userId = player.UserId
	local now = os.clock()
	local lastTouch = record.LastTouchedAtByPlayer[userId]
	if lastTouch and now - lastTouch < CONFIG.TouchDebounceWindow then
		return
	end

	record.LastTouchedAtByPlayer[userId] = now

	local oncePerPlayer = getBooleanAttribute(instance, "ObjectiveOncePerPlayer", true)
	if oncePerPlayer and record.TriggeredPlayers[userId] then
		return
	end

	local didFire = self:fireObjective(instance, player)
	if oncePerPlayer and didFire then
		record.TriggeredPlayers[userId] = true
	end
end

function ObjectiveTriggerService:track(instance: Instance)
	if self.tracked[instance] then
		return
	end

	if not instance:IsA("BasePart") then
		warn(("[ObjectiveTriggerService] %s must be a BasePart to use tag %s"):format(instance:GetFullName(), CONFIG.TagName))
		return
	end

	local connections = {
		instance.Touched:Connect(function(hit)
			self:handleTouched(instance, hit)
		end),
		instance.AncestryChanged:Connect(function()
			if not instance:IsDescendantOf(Workspace) then
				self:untrack(instance)
			end
		end),
	}

	self.tracked[instance] = {
		Connections = connections,
		TriggeredPlayers = {},
		LastTouchedAtByPlayer = {},
	}
end

function ObjectiveTriggerService:Init()
	local folder = ServerStorage:WaitForChild("ObjectiveServerApi", 15)
	if not folder then
		warn("[ObjectiveTriggerService] ObjectiveServerApi was not created")
		return
	end

	local upsertObjective = folder:WaitForChild("UpsertObjective", 15)
	if upsertObjective and upsertObjective:IsA("BindableFunction") then
		self.upsertObjective = upsertObjective
	else
		warn("[ObjectiveTriggerService] UpsertObjective was not created")
	end

	local removeObjective = folder:WaitForChild("RemoveObjective", 15)
	if removeObjective and removeObjective:IsA("BindableFunction") then
		self.removeObjective = removeObjective
	else
		warn("[ObjectiveTriggerService] RemoveObjective was not created")
	end
end

function ObjectiveTriggerService:Start()
	if not self.upsertObjective then
		return
	end

	for _, instance in ipairs(CollectionService:GetTagged(CONFIG.TagName)) do
		self:track(instance)
	end

	CollectionService:GetInstanceAddedSignal(CONFIG.TagName):Connect(function(instance)
		self:track(instance)
	end)

	CollectionService:GetInstanceRemovedSignal(CONFIG.TagName):Connect(function(instance)
		self:untrack(instance)
	end)
end

return ObjectiveTriggerService
