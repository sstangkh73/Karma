local ObjectiveData = {}

local configSources = {
	require(script.Parent:WaitForChild("ObjectiveConfigs"):WaitForChild("QuestConfig")),
}
local placePointConfig = require(script.Parent:WaitForChild("ObjectiveConfigs"):WaitForChild("QuestPlacePointConfig"))

local function cloneTable(source)
	if typeof(source) ~= "table" then
		return nil
	end

	local clone = {}
	for key, value in pairs(source) do
		clone[key] = value
	end

	return clone
end

local objectivesById = {}
local triggerActionsById = {}
local pickupActionsByDefinitionId = {}
local placeActionsByDefinitionId = {}
local placePointActionsById = {}

local function appendAction(targetMap, key, action)
	if typeof(key) ~= "string" or key == "" or typeof(action) ~= "table" then
		return
	end

	local bucket = targetMap[key]
	if not bucket then
		bucket = {}
		targetMap[key] = bucket
	end

	table.insert(bucket, action)
end

local function cloneAction(action)
	if typeof(action) ~= "table" then
		return nil
	end

	return {
		Kind = action.Kind,
		ObjectiveId = action.ObjectiveId,
		CallbackName = action.CallbackName,
		RequiredDefinitionIds = cloneTable(action.RequiredDefinitionIds),
	}
end

local function cloneActionList(actions)
	local result = {}
	if typeof(actions) ~= "table" then
		return result
	end

	for _, action in ipairs(actions) do
		local clone = cloneAction(action)
		if clone then
			table.insert(result, clone)
		end
	end

	return result
end

local function registerActionIds(targetMap, ids, kind: string, objectiveId: string, callbackName: string?)
	if typeof(ids) ~= "table" then
		return
	end

	for _, id in ipairs(ids) do
		appendAction(targetMap, id, {
			Kind = kind,
			ObjectiveId = objectiveId,
			CallbackName = callbackName,
		})
	end
end

local function registerPlacePointObjectiveIds(targetMap, pointId: string, objectiveIds, kind: string, callbackName: string?, requiredDefinitionIds)
	if typeof(pointId) ~= "string" or pointId == "" or typeof(objectiveIds) ~= "table" then
		return
	end

	for _, objectiveId in ipairs(objectiveIds) do
		appendAction(targetMap, pointId, {
			Kind = kind,
			ObjectiveId = objectiveId,
			CallbackName = callbackName,
			RequiredDefinitionIds = cloneTable(requiredDefinitionIds),
		})
	end
end

local function registerDefinition(definition, fallbackId)
	if typeof(definition) ~= "table" then
		return
	end

	local resolvedId = nil
	if typeof(definition.Id) == "string" and definition.Id ~= "" then
		resolvedId = definition.Id
	elseif typeof(fallbackId) == "string" and fallbackId ~= "" then
		resolvedId = fallbackId
	end

	if not resolvedId then
		warn("[ObjectiveData] Skipped objective definition without Id")
		return
	end

	local clone = cloneTable(definition)
	clone.Id = resolvedId
	objectivesById[resolvedId] = clone

	local startTriggerIds = clone.StartTriggerIds
	if typeof(startTriggerIds) ~= "table" or #startTriggerIds == 0 then
		startTriggerIds = { resolvedId }
	end

	registerActionIds(triggerActionsById, startTriggerIds, "Start", resolvedId, clone.OnStartedCallback)
	registerActionIds(triggerActionsById, clone.CompleteTriggerIds, "Complete", resolvedId, clone.OnCompletedCallback)
	registerActionIds(pickupActionsByDefinitionId, clone.StartPickupDefinitionIds, "Start", resolvedId, clone.OnStartedCallback)
	registerActionIds(pickupActionsByDefinitionId, clone.CompletePickupDefinitionIds, "Complete", resolvedId, clone.OnCompletedCallback)
	registerActionIds(placeActionsByDefinitionId, clone.StartPlaceDefinitionIds, "Start", resolvedId, clone.OnStartedCallback)
	registerActionIds(placeActionsByDefinitionId, clone.CompletePlaceDefinitionIds, "Complete", resolvedId, clone.OnCompletedCallback)
end

for _, source in ipairs(configSources) do
	for key, definition in pairs(source) do
		registerDefinition(definition, if typeof(key) == "string" then key else nil)
	end
end

for _, pointDefinition in ipairs(placePointConfig.Points or {}) do
	if typeof(pointDefinition) == "table" and typeof(pointDefinition.Id) == "string" and pointDefinition.Id ~= "" then
		registerPlacePointObjectiveIds(
			placePointActionsById,
			pointDefinition.Id,
			pointDefinition.StartObjectiveIds,
			"Start",
			pointDefinition.OnStartedCallback,
			pointDefinition.RequiredDefinitionIds
		)
		registerPlacePointObjectiveIds(
			placePointActionsById,
			pointDefinition.Id,
			pointDefinition.CompleteObjectiveIds,
			"Complete",
			pointDefinition.OnCompletedCallback,
			pointDefinition.RequiredDefinitionIds
		)
	end
end

local function actionMatchesDefinition(action, definitionId: string)
	if typeof(action) ~= "table" then
		return false
	end

	local requiredDefinitionIds = action.RequiredDefinitionIds
	if typeof(requiredDefinitionIds) ~= "table" or #requiredDefinitionIds == 0 then
		return true
	end

	for _, requiredDefinitionId in ipairs(requiredDefinitionIds) do
		if requiredDefinitionId == definitionId then
			return true
		end
	end

	return false
end

function ObjectiveData.getObjectiveById(objectiveId: string)
	local definition = objectivesById[objectiveId]
	if typeof(definition) ~= "table" then
		return nil
	end

	return cloneTable(definition)
end

function ObjectiveData.getTriggerActions(triggerId: string)
	return cloneActionList(triggerActionsById[triggerId])
end

function ObjectiveData.getPickupActions(definitionId: string)
	return cloneActionList(pickupActionsByDefinitionId[definitionId])
end

function ObjectiveData.getPlaceActions(definitionId: string)
	return cloneActionList(placeActionsByDefinitionId[definitionId])
end

function ObjectiveData.getPlacePointActions(placePointId: string, definitionId: string)
	local result = {}
	local actions = placePointActionsById[placePointId]
	if typeof(actions) ~= "table" then
		return result
	end

	for _, action in ipairs(actions) do
		if actionMatchesDefinition(action, definitionId) then
			local clone = cloneAction(action)
			if clone then
				table.insert(result, clone)
			end
		end
	end

	return result
end

function ObjectiveData.getPlacePointTagName()
	local tagName = placePointConfig.TagName
	if typeof(tagName) == "string" and tagName ~= "" then
		return tagName
	end

	return "QuestPlacePoint"
end

function ObjectiveData.getPlacePointIdAttributeName()
	local attributeName = placePointConfig.IdAttribute
	if typeof(attributeName) == "string" and attributeName ~= "" then
		return attributeName
	end

	return "QuestPlacePointId"
end

return ObjectiveData
