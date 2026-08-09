local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local RemoteGateway = require(Core:WaitForChild("RemoteGateway"))

local CONFIG = {
	RemotesFolderName = "GameRemotes",
	RemoteName = "LoadingGateEvent",
	StreamPhases = {
		Critical = {
			MaxPoints = 5,
			MaxDistanceFromCharacter = 180,
			PointTimeout = 4,
		},
		Nearby = {
			MaxPoints = 9,
			MaxDistanceFromCharacter = 480,
			PointTimeout = 2,
		},
	},
}

local LoadingGateService = {
	Name = "LoadingGateService",
	Priority = 5,
	remote = nil,
	gateOpen = false,
	readyPlayers = {},
	waitingPlayers = {},
	readySequenceByPlayer = {},
	criticalStreamSequenceByPlayer = {},
	activeStreamRequestByPlayer = {},
	frozenRootByPlayer = {},
	characterConnections = {},
}

local function isFiniteNumber(value)
	return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function isFiniteVector3(value)
	return typeof(value) == "Vector3"
		and isFiniteNumber(value.X)
		and isFiniteNumber(value.Y)
		and isFiniteNumber(value.Z)
end

function LoadingGateService:getCounts()
	local players = Players:GetPlayers()
	local readyCount = 0
	local totalCount = 0

	for _, player in ipairs(players) do
		if self.readyPlayers[player] ~= nil then
			totalCount += 1
			if self.readyPlayers[player] then
				readyCount += 1
			end
		end
	end

	return readyCount, totalCount
end

function LoadingGateService:sendStatus(targetPlayer: Player?)
	if not self.remote then
		return
	end

	local readyCount, totalCount = self:getCounts()
	local payload = {
		Type = "Status",
		Ready = readyCount,
		Total = totalCount,
	}

	if targetPlayer then
		self.remote:FireClient(targetPlayer, payload)
	else
		self.remote:FireAllClients(payload)
	end
end

function LoadingGateService:thawPlayer(player: Player)
	local frozenState = self.frozenRootByPlayer[player]
	self.frozenRootByPlayer[player] = nil

	if frozenState and frozenState.Root and frozenState.Root.Parent then
		frozenState.Root.Anchored = frozenState.WasAnchored
	end
end

function LoadingGateService:freezeCharacter(player: Player, character: Model)
	task.spawn(function()
		local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
		if not root or not root:IsA("BasePart") or not self.waitingPlayers[player] then
			return
		end

		self:thawPlayer(player)
		self.frozenRootByPlayer[player] = {
			Root = root,
			WasAnchored = root.Anchored,
		}
		root.Anchored = true
	end)
end

function LoadingGateService:releasePlayer(player: Player)
	if not self.waitingPlayers[player] then
		return
	end

	self.waitingPlayers[player] = false
	self:thawPlayer(player)
	player:SetAttribute("LoadingGateReleased", true)

	self.remote:FireClient(player, {
		Type = "Release",
		SequenceId = self.readySequenceByPlayer[player],
	})
end

function LoadingGateService:sendStreamResult(player: Player, payload)
	if self.remote and player.Parent == Players then
		self.remote:FireClient(player, payload)
	end
end

function LoadingGateService:handleStreamRequest(player: Player, payload)
	if typeof(payload) ~= "table" or payload.Type ~= "StreamRequest" then
		return
	end

	local sequenceId = payload.SequenceId
	local requestId = payload.RequestId
	local phaseName = payload.Phase
	local points = payload.Points
	local phaseConfig = if typeof(phaseName) == "string" then CONFIG.StreamPhases[phaseName] else nil

	if typeof(sequenceId) ~= "number"
		or typeof(requestId) ~= "number"
		or not phaseConfig
		or typeof(points) ~= "table"
		or #points < 1
		or #points > phaseConfig.MaxPoints
	then
		return
	end

	if self.activeStreamRequestByPlayer[player] then
		self:sendStreamResult(player, {
			Type = "StreamResult",
			SequenceId = sequenceId,
			RequestId = requestId,
			Phase = phaseName,
			Success = false,
			Error = "A stream request is already active",
		})
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		self:sendStreamResult(player, {
			Type = "StreamResult",
			SequenceId = sequenceId,
			RequestId = requestId,
			Phase = phaseName,
			Success = false,
			Error = "Character root is unavailable",
		})
		return
	end

	local validatedPoints = {}
	for _, point in ipairs(points) do
		if not isFiniteVector3(point) or (point - root.Position).Magnitude > phaseConfig.MaxDistanceFromCharacter then
			self:sendStreamResult(player, {
				Type = "StreamResult",
				SequenceId = sequenceId,
				RequestId = requestId,
				Phase = phaseName,
				Success = false,
				Error = "Stream point is outside the allowed radius",
			})
			return
		end

		table.insert(validatedPoints, point)
	end

	self.activeStreamRequestByPlayer[player] = requestId
	print(("[LoadingGateService][RadialLoad v1] %s phase=%s request=%d points=%d"):format(
		player.Name,
		phaseName,
		requestId,
		#validatedPoints
	))

	task.spawn(function()
		local startedAt = os.clock()
		local completed = 0
		local failures = 0
		local firstError = nil

		for _, point in ipairs(validatedPoints) do
			if player.Parent ~= Players or self.activeStreamRequestByPlayer[player] ~= requestId then
				break
			end

			local success, errorMessage = pcall(function()
				player:RequestStreamAroundAsync(point, phaseConfig.PointTimeout)
			end)

			completed += 1
			if not success then
				failures += 1
				firstError = firstError or tostring(errorMessage)
			end
		end

		if self.activeStreamRequestByPlayer[player] == requestId then
			self.activeStreamRequestByPlayer[player] = nil
		end

		local succeeded = completed == #validatedPoints and failures == 0
		if succeeded and phaseName == "Critical" then
			self.criticalStreamSequenceByPlayer[player] = sequenceId
		end

		local duration = os.clock() - startedAt
		self:sendStreamResult(player, {
			Type = "StreamResult",
			SequenceId = sequenceId,
			RequestId = requestId,
			Phase = phaseName,
			Success = succeeded,
			Completed = completed,
			Total = #validatedPoints,
			Duration = duration,
			Error = firstError,
		})

		print(("[LoadingGateService][RadialLoad v1] %s phase=%s success=%s completed=%d/%d duration=%.2fs"):format(
			player.Name,
			phaseName,
			tostring(succeeded),
			completed,
			#validatedPoints,
			duration
		))
	end)
end

function LoadingGateService:allCurrentPlayersReady()
	local readyCount, totalCount = self:getCounts()
	return totalCount > 0 and readyCount == totalCount
end

function LoadingGateService:tryOpenInitialGate()
	if self.gateOpen or not self:allCurrentPlayersReady() then
		return
	end

	self.gateOpen = true
	local readyCount, totalCount = self:getCounts()
	print(("[LoadingGateService] All players ready (%d/%d). Releasing initial gate."):format(readyCount, totalCount))

	for _, player in ipairs(Players:GetPlayers()) do
		self:releasePlayer(player)
	end
end

function LoadingGateService:trackPlayer(player: Player)
	if self.readyPlayers[player] ~= nil then
		return
	end

	self.readyPlayers[player] = false
	self.waitingPlayers[player] = true
	self.criticalStreamSequenceByPlayer[player] = nil
	player:SetAttribute("LoadingGateReady", false)
	player:SetAttribute("LoadingGateReleased", false)

	self.characterConnections[player] = player.CharacterAdded:Connect(function(character)
		self.activeStreamRequestByPlayer[player] = nil
		if self.waitingPlayers[player] then
			self.readyPlayers[player] = false
			self.readySequenceByPlayer[player] = nil
			self.criticalStreamSequenceByPlayer[player] = nil
			player:SetAttribute("LoadingGateReady", false)
			self:freezeCharacter(player, character)
			self:sendStatus()
		end
	end)

	if player.Character then
		self:freezeCharacter(player, player.Character)
	end

	task.defer(function()
		if player.Parent == Players then
			self:sendStatus()
		end
	end)
end

function LoadingGateService:handleReady(player: Player, payload)
	if typeof(payload) ~= "table" or payload.Type ~= "Ready" then
		return
	end

	if self.readyPlayers[player] == nil then
		self:trackPlayer(player)
	end

	local sequenceId = payload.SequenceId
	if typeof(sequenceId) ~= "number" then
		return
	end

	if self.criticalStreamSequenceByPlayer[player] ~= sequenceId then
		warn(("[LoadingGateService][RadialLoad v1] Ignored premature Ready from %s sequence=%s"):format(
			player.Name,
			tostring(sequenceId)
		))
		return
	end

	self.readyPlayers[player] = true
	self.readySequenceByPlayer[player] = sequenceId
	player:SetAttribute("LoadingGateReady", true)

	local readyCount, totalCount = self:getCounts()
	print(("[LoadingGateService] %s ready (%d/%d)"):format(player.Name, readyCount, totalCount))
	self:sendStatus()

	if self.gateOpen then
		-- Players joining after the initial party was released only wait for their own load.
		self.waitingPlayers[player] = true
		self:releasePlayer(player)
		return
	end

	self:tryOpenInitialGate()
end

function LoadingGateService:removePlayer(player: Player)
	local connection = self.characterConnections[player]
	if connection then
		connection:Disconnect()
	end

	self:thawPlayer(player)
	self.characterConnections[player] = nil
	self.readyPlayers[player] = nil
	self.waitingPlayers[player] = nil
	self.readySequenceByPlayer[player] = nil
	self.criticalStreamSequenceByPlayer[player] = nil
	self.activeStreamRequestByPlayer[player] = nil

	self:sendStatus()
	self:tryOpenInitialGate()
end

function LoadingGateService:Init()
	self.remote = RemoteGateway.getOrCreateRemote(CONFIG.RemotesFolderName, CONFIG.RemoteName, "RemoteEvent")
end

function LoadingGateService:Start()
	self.remote.OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then
			return
		end

		if payload.Type == "StreamRequest" then
			self:handleStreamRequest(player, payload)
		elseif payload.Type == "Ready" then
			self:handleReady(player, payload)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		self:trackPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:removePlayer(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		self:trackPlayer(player)
	end
end

return LoadingGateService
