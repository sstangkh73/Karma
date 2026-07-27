local ModuleLoader = {}

local function getPriority(moduleTable)
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

local function callLifecycle(record, methodName: string, context)
	local method = record.Module[methodName]
	if typeof(method) ~= "function" then
		return true
	end

	local ok, result = pcall(function()
		return method(record.Module, context)
	end)

	if not ok then
		warn(("[ModuleLoader] %s.%s failed: %s"):format(record.Name, methodName, tostring(result)))
		return false
	end

	return true
end

function ModuleLoader.collect(folder: Instance)
	local records = {}

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ModuleScript") then
			local ok, moduleTable = pcall(require, child)
			if not ok then
				warn(("[ModuleLoader] Failed to require %s: %s"):format(child:GetFullName(), tostring(moduleTable)))
			elseif typeof(moduleTable) ~= "table" then
				warn(("[ModuleLoader] %s did not return a table"):format(child:GetFullName()))
			else
				table.insert(records, {
					Instance = child,
					Module = moduleTable,
					Name = getName(child, moduleTable),
					Priority = getPriority(moduleTable),
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

	local records = ModuleLoader.collect(folder)
	for _, record in ipairs(records) do
		context.Modules[record.Name] = record.Module
	end

	for _, record in ipairs(records) do
		callLifecycle(record, "Init", context)
	end

	for _, record in ipairs(records) do
		callLifecycle(record, "Start", context)
	end

	return {
		Context = context,
		Records = records,
	}
end

return ModuleLoader
