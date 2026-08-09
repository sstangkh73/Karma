local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local ObjectiveData = require(Shared:WaitForChild("ObjectiveData"))
local ObjectiveShared = require(Shared:WaitForChild("ObjectiveShared"))
local RemoteGateway = require(Core:WaitForChild("RemoteGateway"))

local CONFIG = {
	RemotesFolderName = "GameRemotes",
	RemoteName = "ObjectiveEvent",
	ServerApiFolderName = "ObjectiveServerApi",
	SingleObjectiveChannels = {
		Quest = true,
	},
}

local ObjectiveService = {
	Name = "ObjectiveService",
	Priority = 25,
	remote = nil,
	objectivesByPlayer = {},
	serverApiFolder = nil,
}

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

local function mergeObjectiveDefinition(payload)
	if typeof(payload) ~= "table" then
		return payload
	end

	local lookupId = if typeof(payload.DefinitionId) == "string" and payload.DefinitionId ~= ""
		then payload.DefinitionId
		else payload.Id
	local definition = if typeof(lookupId) == "string" and lookupId ~= ""
		then ObjectiveData.getObjectiveById(lookupId)
		else nil

	if not definition then
		return payload
	end

	return {
		Id = if typeof(payload.Id) == "string" and payload.Id ~= "" then payload.Id else definition.Id,
		Channel = if payload.Channel ~= nil then payload.Channel else definition.Channel,
		Title = if payload.Title ~= nil then payload.Title else definition.Title,
		TitleKey = if payload.TitleKey ~= nil then payload.TitleKey else definition.TitleKey,
		TitleParams = if payload.TitleParams ~= nil then cloneTable(payload.TitleParams) else cloneTable(definition.TitleParams),
		Description = if payload.Description ~= nil then payload.Description else definition.Description,
		DescriptionKey = if payload.DescriptionKey ~= nil then payload.DescriptionKey else definition.DescriptionKey,
		DescriptionParams = if payload.DescriptionParams ~= nil
			then cloneTable(payload.DescriptionParams)
			else cloneTable(definition.DescriptionParams),
		Order = if payload.Order ~= nil then payload.Order else definition.Order,
		Priority = if payload.Priority ~= nil then payload.Priority else definition.Priority,
		Visible = if payload.Visible ~= nil then payload.Visible else definition.Visible,
		AccentColor = if payload.AccentColor ~= nil then payload.AccentColor else definition.AccentColor,
	}
end

local function getPlayerBucket(self, player: Player)
	local bucket = self.objectivesByPlayer[player]
	if bucket then
		return bucket
	end

	bucket = {}
	self.objectivesByPlayer[player] = bucket
	return bucket
end

function ObjectiveService:getSnapshot(player: Player)
	return ObjectiveShared.toArray(getPlayerBucket(self, player))
end

function ObjectiveService:syncPlayer(player: Player)
	if not self.remote then
		return
	end

	self.remote:FireClient(player, {
		Type = "Snapshot",
		Objectives = self:getSnapshot(player),
	})
end

function ObjectiveService:upsertObjective(player: Player, payload)
	local objective, errorMessage = ObjectiveShared.normalizeObjective(mergeObjectiveDefinition(payload))
	if not objective then
		warn(("[ObjectiveService] Failed to upsert objective: %s"):format(tostring(errorMessage)))
		return false, errorMessage
	end

	local bucket = getPlayerBucket(self, player)
	if CONFIG.SingleObjectiveChannels[objective.Channel] == true then
		for objectiveId, existingObjective in pairs(bucket) do
			if existingObjective.Channel == objective.Channel and objectiveId ~= objective.Id then
				bucket[objectiveId] = nil
			end
		end
	end

	bucket[objective.Id] = objective
	self:syncPlayer(player)
	return true, objective
end

function ObjectiveService:removeObjective(player: Player, objectiveId: string)
	if typeof(objectiveId) ~= "string" or objectiveId == "" then
		return false, "Objective id is required"
	end

	local bucket = getPlayerBucket(self, player)
	if bucket[objectiveId] == nil then
		return false, "Objective was not found"
	end

	bucket[objectiveId] = nil
	self:syncPlayer(player)
	return true
end

function ObjectiveService:clearObjectives(player: Player, channel: string?)
	local bucket = getPlayerBucket(self, player)
	local resolvedChannel = if typeof(channel) == "string" then ObjectiveShared.normalizeChannel(channel) else nil

	if resolvedChannel == nil then
		table.clear(bucket)
	else
		for objectiveId, objective in pairs(bucket) do
			if objective.Channel == resolvedChannel then
				bucket[objectiveId] = nil
			end
		end
	end

	self:syncPlayer(player)
	return true
end

function ObjectiveService:createServerApi()
	local folder = ServerStorage:FindFirstChild(CONFIG.ServerApiFolderName)
	if folder and not folder:IsA("Folder") then
		error(("[ObjectiveService] %s exists but is not a Folder"):format(folder:GetFullName()))
	end

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = CONFIG.ServerApiFolderName
		folder.Parent = ServerStorage
	end

	local upsertBindable = folder:FindFirstChild("UpsertObjective")
	if not upsertBindable then
		upsertBindable = Instance.new("BindableFunction")
		upsertBindable.Name = "UpsertObjective"
		upsertBindable.Parent = folder
	end

	local removeBindable = folder:FindFirstChild("RemoveObjective")
	if not removeBindable then
		removeBindable = Instance.new("BindableFunction")
		removeBindable.Name = "RemoveObjective"
		removeBindable.Parent = folder
	end

	local clearBindable = folder:FindFirstChild("ClearObjectives")
	if not clearBindable then
		clearBindable = Instance.new("BindableFunction")
		clearBindable.Name = "ClearObjectives"
		clearBindable.Parent = folder
	end

	local getBindable = folder:FindFirstChild("GetObjectives")
	if not getBindable then
		getBindable = Instance.new("BindableFunction")
		getBindable.Name = "GetObjectives"
		getBindable.Parent = folder
	end

	upsertBindable.OnInvoke = function(player, payload)
		return self:upsertObjective(player, payload)
	end

	removeBindable.OnInvoke = function(player, objectiveId)
		return self:removeObjective(player, objectiveId)
	end

	clearBindable.OnInvoke = function(player, channel)
		return self:clearObjectives(player, channel)
	end

	getBindable.OnInvoke = function(player)
		return self:getSnapshot(player)
	end

	self.serverApiFolder = folder
end

function ObjectiveService:Init()
	self.remote = RemoteGateway.getOrCreateRemote(CONFIG.RemotesFolderName, CONFIG.RemoteName, "RemoteEvent")
	self:createServerApi()
end

function ObjectiveService:Start()
	Players.PlayerAdded:Connect(function(player)
		self:syncPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self.objectivesByPlayer[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		self:syncPlayer(player)
	end
end

return ObjectiveService
