local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SystemConfig = require(script.Parent:WaitForChild("SystemConfig"))

local SystemHub = {}

local runtimeSide = if RunService:IsServer() then "Server" else "Client"
local statusRoot = nil

local function listToString(values)
	if typeof(values) ~= "table" then
		return ""
	end

	return table.concat(values, ", ")
end

local function getStatusParent()
	if runtimeSide == "Server" then
		return ReplicatedStorage
	end

	local player = Players.LocalPlayer
	return player:WaitForChild("PlayerScripts")
end

local function refreshCounts()
	if not statusRoot then
		return
	end

	local counts = {
		Blocked = 0,
		Configured = 0,
		Disabled = 0,
		Failed = 0,
		Initialized = 0,
		Running = 0,
		Starting = 0,
	}

	for _, child in ipairs(statusRoot:GetChildren()) do
		local status = child:GetAttribute("Status")
		if counts[status] ~= nil then
			counts[status] += 1
		end
	end

	statusRoot:SetAttribute("TotalCount", #statusRoot:GetChildren())
	for status, count in pairs(counts) do
		statusRoot:SetAttribute(status .. "Count", count)
	end

	if statusRoot:GetAttribute("Ready") == true then
		local hasProblems = counts.Failed > 0 or counts.Blocked > 0
		local hasPending = counts.Configured > 0 or counts.Initialized > 0 or counts.Starting > 0
		local rootStatus = if hasProblems then "Degraded" elseif hasPending then "Incomplete" else "Running"
		statusRoot:SetAttribute("Status", rootStatus)
	end
end

local function ensureRoot()
	if statusRoot and statusRoot.Parent then
		return statusRoot
	end

	local parent = getStatusParent()
	local existing = parent:FindFirstChild(SystemConfig.StatusRootName)
	if existing and not existing:IsA("Folder") then
		error(("[SystemHub] %s must be a Folder"):format(existing:GetFullName()))
	end

	statusRoot = existing
	if not statusRoot then
		statusRoot = Instance.new("Folder")
		statusRoot.Name = SystemConfig.StatusRootName
		statusRoot.Parent = parent
	end

	statusRoot:SetAttribute("Version", SystemConfig.Version)
	statusRoot:SetAttribute("Side", runtimeSide)
	statusRoot:SetAttribute("Ready", false)
	statusRoot:SetAttribute("Status", "Starting")
	return statusRoot
end

local function syncDefinition(node: Instance, systemName: string, definition)
	node:SetAttribute("SystemName", systemName)
	node:SetAttribute("Side", definition and definition.Side or runtimeSide)
	node:SetAttribute("Kind", definition and definition.Kind or "Unregistered")
	node:SetAttribute("Enabled", not definition or definition.Enabled ~= false)
	node:SetAttribute("Priority", definition and definition.Priority or 100)
	node:SetAttribute("Dependencies", listToString(definition and definition.Dependencies))
	node:SetAttribute("IntegratesWith", listToString(definition and definition.IntegratesWith))
	node:SetAttribute("Description", definition and definition.Description or "")
end

local function ensureNode(systemName: string, source: Instance?)
	local root = ensureRoot()
	local definition = SystemConfig.get(systemName)
	local node = root:FindFirstChild(systemName)

	if node and not node:IsA("Folder") then
		error(("[SystemHub] %s must be a Folder"):format(node:GetFullName()))
	end

	if not node then
		node = Instance.new("Folder")
		node.Name = systemName
		node.Parent = root
	end

	syncDefinition(node, systemName, definition)
	if source then
		node:SetAttribute("Source", source:GetFullName())
		source:SetAttribute("SystemHubName", systemName)
	end

	return node, definition
end

local function setStatus(systemName: string, status: string, detail: string?, source: Instance?)
	local node = ensureNode(systemName, source)
	node:SetAttribute("Status", status)
	node:SetAttribute("Detail", detail or "")
	node:SetAttribute("UpdatedAt", workspace:GetServerTimeNow())

	if source then
		source:SetAttribute("SystemHubStatus", status)
	end

	refreshCounts()
	return node
end

function SystemHub.getDefinition(systemName: string)
	return SystemConfig.get(systemName)
end

function SystemHub.resolveName(sourceName: string)
	local systemName = SystemConfig.findBySource(runtimeSide, sourceName)
	return systemName or sourceName
end

function SystemHub.initialize(expectedSide: string?)
	if expectedSide and expectedSide ~= runtimeSide then
		error(("[SystemHub] Expected %s runtime, got %s"):format(expectedSide, runtimeSide))
	end

	ensureRoot()
	for systemName, definition in pairs(SystemConfig.Systems) do
		if definition.Side == runtimeSide then
			local node = ensureNode(systemName)
			if node:GetAttribute("Status") == nil then
				local status = if definition.Enabled == false then "Disabled" else "Configured"
				node:SetAttribute("Status", status)
				node:SetAttribute("Detail", "")
			end
		end
	end

	refreshCounts()
	return SystemHub
end

function SystemHub.begin(systemName: string, source: Instance?)
	SystemHub.initialize()
	local node, definition = ensureNode(systemName, source)
	local enabled = not definition or definition.Enabled ~= false

	if definition and definition.Side ~= runtimeSide then
		setStatus(systemName, "Failed", ("Configured for %s, running on %s"):format(definition.Side, runtimeSide), source)
		return false
	end

	if not enabled then
		setStatus(systemName, "Disabled", "Disabled in SystemConfig", source)
		if SystemConfig.Debug then
			print(("[SystemHub][%s] %s disabled"):format(runtimeSide, systemName))
		end
		return false
	end

	node:SetAttribute("StartedAt", workspace:GetServerTimeNow())
	setStatus(systemName, "Starting", nil, source)
	return true
end

function SystemHub.setStatus(systemName: string, status: string, detail: string?, source: Instance?)
	return setStatus(systemName, status, detail, source)
end

function SystemHub.ready(systemName: string, source: Instance?)
	setStatus(systemName, "Running", nil, source)
	if SystemConfig.Debug then
		print(("[SystemHub][%s] %s running"):format(runtimeSide, systemName))
	end
end

function SystemHub.failed(systemName: string, detail, source: Instance?)
	local message = tostring(detail)
	setStatus(systemName, "Failed", message, source)
	warn(("[SystemHub][%s] %s failed: %s"):format(runtimeSide, systemName, message))
end

function SystemHub.blocked(systemName: string, dependencyName: string, source: Instance?)
	local detail = ("Dependency %s is unavailable"):format(dependencyName)
	setStatus(systemName, "Blocked", detail, source)
	warn(("[SystemHub][%s] %s blocked by %s"):format(runtimeSide, systemName, dependencyName))
end

function SystemHub.getStatus(systemName: string)
	local root = ensureRoot()
	local node = root:FindFirstChild(systemName)
	return if node then node:GetAttribute("Status") else nil
end

function SystemHub.completeStartup()
	local root = ensureRoot()
	root:SetAttribute("Ready", true)
	refreshCounts()
end

function SystemHub.printSummary()
	local root = ensureRoot()
	refreshCounts()
	local pendingCount = (root:GetAttribute("ConfiguredCount") or 0)
		+ (root:GetAttribute("InitializedCount") or 0)
		+ (root:GetAttribute("StartingCount") or 0)
	print(("[SystemHub][%s] status=%s running=%d pending=%d failed=%d blocked=%d disabled=%d total=%d"):format(
		runtimeSide,
		root:GetAttribute("Status") or "Unknown",
		root:GetAttribute("RunningCount") or 0,
		pendingCount,
		root:GetAttribute("FailedCount") or 0,
		root:GetAttribute("BlockedCount") or 0,
		root:GetAttribute("DisabledCount") or 0,
		root:GetAttribute("TotalCount") or 0
	))
end

return SystemHub
