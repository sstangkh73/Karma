local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local DialogueData = require(Shared:WaitForChild("DialogueData"))
local RemoteGateway = require(Core:WaitForChild("RemoteGateway"))

local CONFIG = {
	RemotesFolderName = "GameRemotes",
	RemoteName = "DialogueEvent",
	ServerApiFolderName = "DialogueServerApi",
	TouchDebounceWindow = 0.5,
	NamedReachPointPollInterval = 0.2,
	NamedReachPointPadding = 3,
}

local DialogueService = {
	Name = "DialogueService",
	Priority = 65,
	remote = nil,
	serverApiFolder = nil,
	objectiveUpsert = nil,
	tracked = {},
	playedByPlayer = {},
	pendingByPlayer = {},
	namedReachSources = {},
	rateLimit = nil,
}

local settings = DialogueData.getSettings()

local function getStringAttribute(instance: Instance, attributeName: string)
	local value = instance:GetAttribute(attributeName)
	return if typeof(value) == "string" and value ~= "" then value else nil
end

local function getBooleanAttribute(instance: Instance, attributeName: string, fallback: boolean)
	local value = instance:GetAttribute(attributeName)
	return if typeof(value) == "boolean" then value else fallback
end

local function getNamedReachPointId(instance: Instance)
	local namedReachPoints = settings.NamedReachPoints
	if typeof(namedReachPoints) ~= "table" then
		return nil
	end

	return if namedReachPoints[instance.Name] == true then instance.Name else nil
end

local function getReachPointOncePerPlayer(instance: Instance, fallback: boolean)
	local repeatableNamedReachPoints = settings.RepeatableNamedReachPoints
	if typeof(repeatableNamedReachPoints) == "table" and repeatableNamedReachPoints[instance.Name] == true then
		return false
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

local function getCharacterRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function isPointInsideModelBounds(model: Model, worldPoint: Vector3, padding: number)
	local cframe, size = model:GetBoundingBox()
	local localPoint = cframe:PointToObjectSpace(worldPoint)
	local halfSize = size * 0.5

	return math.abs(localPoint.X) <= halfSize.X + padding
		and math.abs(localPoint.Y) <= halfSize.Y + padding
		and math.abs(localPoint.Z) <= halfSize.Z + padding
end

local function ensureChild(parent: Instance, name: string, className: string)
	local child = parent:FindFirstChild(name)
	if child then
		if not child:IsA(className) then
			error(("[DialogueService] %s must be a %s"):format(child:GetFullName(), className))
		end
		return child
	end

	child = Instance.new(className)
	child.Name = name
	child.Parent = parent
	return child
end

local function findObjectiveUpsert()
	local folder = ServerStorage:FindFirstChild("ObjectiveServerApi")
	if not folder then
		return nil
	end

	local upsert = folder:FindFirstChild("UpsertObjective")
	return if upsert and upsert:IsA("BindableFunction") then upsert else nil
end

function DialogueService:getPlayedBucket(player: Player)
	local bucket = self.playedByPlayer[player]
	if not bucket then
		bucket = {}
		self.playedByPlayer[player] = bucket
	end
	return bucket
end

function DialogueService:getPendingBucket(player: Player)
	local bucket = self.pendingByPlayer[player]
	if not bucket then
		bucket = {}
		self.pendingByPlayer[player] = bucket
	end
	return bucket
end

function DialogueService:playSequence(player: Player, sequenceId: string, context)
	if not player or player.Parent ~= Players then
		return false, "Player is unavailable"
	end

	local sequence = DialogueData.getSequence(sequenceId)
	if not sequence then
		return false, ("Unknown or disabled sequence: %s"):format(tostring(sequenceId))
	end

	local playedBucket = self:getPlayedBucket(player)
	local pendingBucket = self:getPendingBucket(player)
	if pendingBucket[sequenceId] then
		return false, "Sequence is already pending for this player"
	end
	if sequence.Once == true and playedBucket[sequenceId] then
		return false, "Sequence already played for this player"
	end

	if sequence.Once == true then
		playedBucket[sequenceId] = true
	end
	pendingBucket[sequenceId] = true

	self.remote:FireClient(player, {
		Type = "Play",
		SequenceId = sequenceId,
		Context = if typeof(context) == "table" then context else nil,
	})
	return true, sequenceId
end

function DialogueService:trigger(player: Player, triggerType: string, triggerId: string, context)
	if typeof(triggerType) ~= "string" or triggerType == ""
		or typeof(triggerId) ~= "string" or triggerId == "" then
		return false, "Trigger type and id are required"
	end

	local sequenceIds = DialogueData.getSequenceIdsForTrigger(triggerType, triggerId)
	local playedCount = 0
	for _, sequenceId in ipairs(sequenceIds) do
		local didPlay = self:playSequence(player, sequenceId, context)
		if didPlay then
			playedCount += 1
		end
	end

	return playedCount > 0, playedCount
end

function DialogueService:cancel(player: Player, reason: string?)
	if not player or player.Parent ~= Players then
		return false
	end

	self.remote:FireClient(player, {
		Type = "Cancel",
		Reason = reason or "ServerRequest",
	})
	table.clear(self:getPendingBucket(player))
	return true
end

function DialogueService:upsertFinishedObjective(player: Player, sequenceId: string)
	local sequence = DialogueData.getSequence(sequenceId)
	if not sequence then
		return
	end

	local objectiveId = sequence.OnFinishedObjectiveId
	if typeof(objectiveId) ~= "string" or objectiveId == "" then
		return
	end

	local upsert = self.objectiveUpsert or findObjectiveUpsert()
	self.objectiveUpsert = upsert
	if not upsert then
		warn(("[DialogueService] Cannot start objective %s; ObjectiveServerApi is unavailable"):format(objectiveId))
		return
	end

	local ok, didUpsert, result = pcall(function()
		return upsert:Invoke(player, {
			Id = objectiveId,
			DefinitionId = objectiveId,
		})
	end)

	if not ok then
		warn(("[DialogueService] Failed to start objective %s: %s"):format(objectiveId, tostring(didUpsert)))
	elseif didUpsert == false then
		warn(("[DialogueService] Objective %s was rejected: %s"):format(objectiveId, tostring(result)))
	end
end

function DialogueService:createServerApi()
	local folder = ServerStorage:FindFirstChild(CONFIG.ServerApiFolderName)
	if folder and not folder:IsA("Folder") then
		error(("[DialogueService] %s must be a Folder"):format(folder:GetFullName()))
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = CONFIG.ServerApiFolderName
		folder.Parent = ServerStorage
	end

	local playSequence = ensureChild(folder, "PlaySequence", "BindableFunction")
	local trigger = ensureChild(folder, "Trigger", "BindableFunction")
	local cancel = ensureChild(folder, "Cancel", "BindableFunction")
	ensureChild(folder, "SequenceFinished", "BindableEvent")

	playSequence.OnInvoke = function(player, sequenceId, context)
		return self:playSequence(player, sequenceId, context)
	end
	trigger.OnInvoke = function(player, triggerType, triggerId, context)
		return self:trigger(player, triggerType, triggerId, context)
	end
	cancel.OnInvoke = function(player, reason)
		return self:cancel(player, reason)
	end

	self.serverApiFolder = folder
end

function DialogueService:untrack(instance: Instance)
	local record = self.tracked[instance]
	if not record then
		return
	end

	if record.Parts then
		for part in pairs(record.Parts) do
			self:untrack(part)
		end
	end

	for _, connection in ipairs(record.Connections) do
		connection:Disconnect()
	end
	self.tracked[instance] = nil
	self.namedReachSources[instance] = nil

	local sourceInstance = record.SourceInstance
	if sourceInstance and sourceInstance ~= instance then
		local sourceRecord = self.tracked[sourceInstance]
		if sourceRecord and sourceRecord.Parts then
			sourceRecord.Parts[instance] = nil
		end
	end
end

function DialogueService:triggerFromSource(player: Player, sourceInstance: Instance, touchedInstance: BasePart?)
	local record = self.tracked[sourceInstance] or (if touchedInstance then self.tracked[touchedInstance] else nil)
	if not player or not record then
		return false
	end
	local triggerInstance = touchedInstance or sourceInstance

	local now = os.clock()
	local lastTouched = record.LastTouchedAtByPlayer[player.UserId]
	if lastTouched and now - lastTouched < CONFIG.TouchDebounceWindow then
		return false
	end
	record.LastTouchedAtByPlayer[player.UserId] = now

	local onceAttribute = settings.OncePerPlayerAttribute or "DialogueOncePerPlayer"
	local oncePerPlayer = getBooleanAttribute(sourceInstance, onceAttribute, getReachPointOncePerPlayer(sourceInstance, true))
	if oncePerPlayer and record.TriggeredPlayers[player.UserId] then
		return
	end

	local directAttribute = settings.DirectSequenceAttribute or "DialogueSequenceId"
	local triggerAttribute = settings.ReachPointIdAttribute or "DialogueTriggerId"
	local directSequenceId = getStringAttribute(sourceInstance, directAttribute) or getStringAttribute(triggerInstance, directAttribute)
	local triggerId = getStringAttribute(sourceInstance, triggerAttribute)
		or getStringAttribute(triggerInstance, triggerAttribute)
		or getNamedReachPointId(sourceInstance)
	local didPlay = false

	if directSequenceId then
		didPlay = self:playSequence(player, directSequenceId, {
			TriggerType = "ReachPoint",
			TriggerId = triggerId,
			Source = sourceInstance:GetFullName(),
		})
	elseif triggerId then
		didPlay = self:trigger(player, "ReachPoint", triggerId, {
			TriggerType = "ReachPoint",
			TriggerId = triggerId,
			Source = sourceInstance:GetFullName(),
		})
	else
		warn(("[DialogueService] %s is missing %s/%s"):format(
			sourceInstance:GetFullName(),
			triggerAttribute,
			directAttribute
		))
	end

	if oncePerPlayer and didPlay then
		record.TriggeredPlayers[player.UserId] = true
	end
	return didPlay
end

function DialogueService:handleTouched(instance: BasePart, hit: BasePart)
	local player = getPlayerFromHit(hit)
	local record = self.tracked[instance]
	if not player or not record then
		return
	end

	self:triggerFromSource(player, record.SourceInstance or instance, instance)
end

function DialogueService:trackPart(part: BasePart, sourceInstance: Instance?)
	if self.tracked[part] then
		return
	end

	local sourceRecord = if sourceInstance and sourceInstance ~= part then self.tracked[sourceInstance] else nil
	local record = {
		Connections = {
			part.Touched:Connect(function(hit)
				self:handleTouched(part, hit)
			end),
			part.AncestryChanged:Connect(function()
				if not part:IsDescendantOf(Workspace)
					or (sourceInstance and sourceInstance ~= part and not part:IsDescendantOf(sourceInstance)) then
					self:untrack(part)
				end
			end),
		},
		TriggeredPlayers = if sourceRecord then sourceRecord.TriggeredPlayers else {},
		LastTouchedAtByPlayer = if sourceRecord then sourceRecord.LastTouchedAtByPlayer else {},
		SourceInstance = sourceInstance or part,
	}
	self.tracked[part] = record

	if sourceRecord and sourceRecord.Parts then
		sourceRecord.Parts[part] = true
	end
end

function DialogueService:trackModel(model: Model)
	if self.tracked[model] then
		return
	end

	self.tracked[model] = {
		Connections = {
			model.DescendantAdded:Connect(function(descendant)
				if descendant:IsA("BasePart") then
					self:trackPart(descendant, model)
				end
			end),
			model.AncestryChanged:Connect(function()
				if not model:IsDescendantOf(Workspace) then
					self:untrack(model)
				end
			end),
		},
		TriggeredPlayers = {},
		LastTouchedAtByPlayer = {},
		Parts = {},
	}

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			self:trackPart(descendant, model)
		end
	end
end

function DialogueService:track(instance: Instance)
	if self.tracked[instance] then
		return
	end

	if instance:IsA("BasePart") then
		self:trackPart(instance, instance)
	elseif instance:IsA("Model") then
		self:trackModel(instance)
	else
		warn(("[DialogueService] %s must be a BasePart or Model"):format(instance:GetFullName()))
		return
	end
end

function DialogueService:trackNamedReachPoint(instance: Instance)
	if getNamedReachPointId(instance) then
		self:track(instance)
		if self.tracked[instance] then
			self.namedReachSources[instance] = true
		end
	end
end

function DialogueService:pollNamedReachPoints()
	local padding = CONFIG.NamedReachPointPadding
	for instance in pairs(self.namedReachSources) do
		if not instance:IsDescendantOf(Workspace) then
			self:untrack(instance)
			continue
		end

		if instance:IsA("Model") then
			for _, player in ipairs(Players:GetPlayers()) do
				local root = getCharacterRoot(player)
				if root and isPointInsideModelBounds(instance, root.Position, padding) then
					self:triggerFromSource(player, instance, nil)
				end
			end
		elseif instance:IsA("BasePart") then
			local halfSize = instance.Size * 0.5
			for _, player in ipairs(Players:GetPlayers()) do
				local root = getCharacterRoot(player)
				if root then
					local localPoint = instance.CFrame:PointToObjectSpace(root.Position)
					if math.abs(localPoint.X) <= halfSize.X + padding
						and math.abs(localPoint.Y) <= halfSize.Y + padding
						and math.abs(localPoint.Z) <= halfSize.Z + padding then
						self:triggerFromSource(player, instance, instance)
					end
				end
			end
		end
	end
end

function DialogueService:handleClientPayload(player: Player, payload)
	if typeof(payload) ~= "table" or typeof(payload.Type) ~= "string" then
		return
	end

	if payload.Type == "Trigger" then
		if payload.TriggerType ~= "NoteRead"
			or typeof(payload.TriggerId) ~= "string"
			or #payload.TriggerId > 100 then
			return
		end

		local allowed = self.rateLimit(player, "Trigger:" .. payload.TriggerId)
		if allowed then
			self:trigger(player, "NoteRead", payload.TriggerId, {
				TriggerType = "NoteRead",
				TriggerId = payload.TriggerId,
			})
		end
	elseif payload.Type == "Finished" and typeof(payload.SequenceId) == "string" then
		local pendingBucket = self:getPendingBucket(player)
		if not pendingBucket[payload.SequenceId] then
			return
		end
		pendingBucket[payload.SequenceId] = nil

		self:upsertFinishedObjective(player, payload.SequenceId)

		local finishedEvent = self.serverApiFolder and self.serverApiFolder:FindFirstChild("SequenceFinished")
		if finishedEvent and finishedEvent:IsA("BindableEvent") then
			finishedEvent:Fire(player, payload.SequenceId, payload.Result or "Completed")
		end
	end
end

function DialogueService:Init()
	self.remote = RemoteGateway.getOrCreateRemote(CONFIG.RemotesFolderName, CONFIG.RemoteName, "RemoteEvent")
	self.rateLimit = RemoteGateway.createRateLimiter({ Window = 0.25 })
	self:createServerApi()
end

function DialogueService:Start()
	self.remote.OnServerEvent:Connect(function(player, payload)
		self:handleClientPayload(player, payload)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self.playedByPlayer[player] = nil
		self.pendingByPlayer[player] = nil
	end)

	local tagName = settings.ReachPointTag or "DialogueTrigger"
	for _, instance in ipairs(CollectionService:GetTagged(tagName)) do
		self:track(instance)
	end
	CollectionService:GetInstanceAddedSignal(tagName):Connect(function(instance)
		self:track(instance)
	end)
	CollectionService:GetInstanceRemovedSignal(tagName):Connect(function(instance)
		self:untrack(instance)
	end)

	for _, instance in ipairs(Workspace:GetDescendants()) do
		self:trackNamedReachPoint(instance)
	end
	Workspace.DescendantAdded:Connect(function(instance)
		self:trackNamedReachPoint(instance)
	end)

	task.spawn(function()
		while true do
			self:pollNamedReachPoints()
			task.wait(CONFIG.NamedReachPointPollInterval)
		end
	end)
end

return DialogueService
