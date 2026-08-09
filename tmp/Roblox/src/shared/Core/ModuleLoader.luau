local ModuleLoader = {}

local function getPriority(moduleTable, definition)
	if definition and typeof(definition.Priority) == "number" then
		return definition.Priority
	end

	if typeof(moduleTable.Priority) == "number" then
		return moduleTable.Priority
	end

	return 100
end

local function getName(moduleScript: ModuleScript, moduleTable)
	if typeof(moduleTable.Name) == "string" and moduleTable.Name ~= "" then
		return moduleTable.Name
	end

	return moduleScript.Name
end

local function getDependencies(moduleTable, definition)
	if definition and typeof(definition.Dependencies) == "table" then
		return definition.Dependencies
	end

	if typeof(moduleTable.Dependencies) == "table" then
		return moduleTable.Dependencies
	end

	return {}
end

local function callLifecycle(record, methodName: string, context)
	local method = record.Module[methodName]
	if typeof(method) ~= "function" then
		return true, nil
	end

	local ok, result = pcall(function()
		return method(record.Module, context)
	end)

	if not ok then
		warn(("[ModuleLoader] %s.%s failed: %s"):format(record.Name, methodName, tostring(result)))
		return false, result
	end

	return true, nil
end

function ModuleLoader.collect(folder: Instance, context)
	context = context or {}
	local hub = context.SystemHub
	local records = {}

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ModuleScript") then
			local configuredName = if hub then hub.resolveName(child.Name) else child.Name
			local definition = if hub then hub.getDefinition(configuredName) else nil
			if definition and definition.Enabled == false then
				table.insert(records, {
					Instance = child,
					Module = nil,
					Name = configuredName,
					Priority = definition.Priority or 100,
					Dependencies = definition.Dependencies or {},
					Disabled = true,
				})
				continue
			end

			local ok, moduleTable = pcall(require, child)
			if not ok then
				warn(("[ModuleLoader] Failed to require %s: %s"):format(child:GetFullName(), tostring(moduleTable)))
				table.insert(records, {
					Instance = child,
					Module = nil,
					Name = configuredName,
					Priority = definition and definition.Priority or 100,
					Dependencies = definition and definition.Dependencies or {},
					LoadError = moduleTable,
				})
			elseif typeof(moduleTable) ~= "table" then
				warn(("[ModuleLoader] %s did not return a table"):format(child:GetFullName()))
				table.insert(records, {
					Instance = child,
					Module = nil,
					Name = configuredName,
					Priority = definition and definition.Priority or 100,
					Dependencies = definition and definition.Dependencies or {},
					LoadError = "Module did not return a table",
				})
			else
				local moduleName = getName(child, moduleTable)
				local systemName = if hub then hub.resolveName(moduleName) else moduleName
				definition = if hub then hub.getDefinition(systemName) else definition
				table.insert(records, {
					Instance = child,
					Module = moduleTable,
					Name = systemName,
					Priority = getPriority(moduleTable, definition),
					Dependencies = getDependencies(moduleTable, definition),
				})
			end
		end
	end

	table.sort(records, function(left, right)
		if left.Priority == right.Priority then
			return left.Name < right.Name
		end

		return left.Priority < right.Priority
	end)

	return records
end

function ModuleLoader.startFolder(folder: Instance, context)
	context = context or {}
	context.Modules = context.Modules or {}
	local hub = context.SystemHub

	local records = ModuleLoader.collect(folder, context)
	for _, record in ipairs(records) do
		if record.Module then
			context.Modules[record.Name] = record.Module
		end

		if hub then
			if record.Disabled then
				hub.setStatus(record.Name, "Disabled", "Disabled in SystemConfig", record.Instance)
			elseif record.LoadError then
				hub.failed(record.Name, record.LoadError, record.Instance)
			else
				hub.begin(record.Name, record.Instance)
			end
		end

	for _, record in ipairs(records) do
		if record.Module and not record.Disabled and not record.LoadError then
			local blockedBy = nil
			for _, dependencyName in ipairs(record.Dependencies) do
				local dependencyStatus = if hub then hub.getStatus(dependencyName) else nil
				if dependencyStatus == "Failed" or dependencyStatus == "Blocked" or dependencyStatus == "Disabled" then
					blockedBy = dependencyName
					break
				end
			end

			if blockedBy then
				record.Blocked = true
				if hub then
					hub.blocked(record.Name, blockedBy, record.Instance)
				end
			else
				local ok, lifecycleError = callLifecycle(record, "Init", context)
				if not ok then
					record.Failed = true
					if hub then
						hub.failed(record.Name, lifecycleError, record.Instance)
					end
				elseif hub then
					hub.setStatus(record.Name, "Initialized", nil, record.Instance)
				end
			end
		end
	end

	for _, record in ipairs(records) do
		if record.Module and not record.Disabled and not record.LoadError and not record.Blocked and not record.Failed then
			local blockedBy = nil
			for _, dependencyName in ipairs(record.Dependencies) do
				local dependencyStatus = if hub then hub.getStatus(dependencyName) else nil
				if dependencyStatus == "Failed" or dependencyStatus == "Blocked" or dependencyStatus == "Disabled" then
					blockedBy = dependencyName
					break
				end
			end

			if blockedBy then
				record.Blocked = true
				if hub then
					hub.blocked(record.Name, blockedBy, record.Instance)
				end
			else
				local ok, lifecycleError = callLifecycle(record, "Start", context)
				if not ok then
					record.Failed = true
					if hub then
						hub.failed(record.Name, lifecycleError, record.Instance)
					end
				elseif hub then
					hub.ready(record.Name, record.Instance)
				end
			end
		end
	end

	return {
		Context = context,
		Records = records,
	}
end

return ModuleLoader
