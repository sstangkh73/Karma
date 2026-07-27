local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteGateway = {}

RemoteGateway.DEFAULT_FOLDER_NAME = "GameRemotes"

function RemoteGateway.getOrCreateFolder(folderName: string?, parent: Instance?)
	local root = parent or ReplicatedStorage
	local name = folderName or RemoteGateway.DEFAULT_FOLDER_NAME
	local folder = root:FindFirstChild(name)

	if folder then
		if not folder:IsA("Folder") then
			error(("[RemoteGateway] %s exists but is not a Folder"):format(folder:GetFullName()))
		end

		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = root
	return folder
end

function RemoteGateway.getOrCreateRemote(folderName: string?, remoteName: string, className: string)
	local folder = RemoteGateway.getOrCreateFolder(folderName)
	local remote = folder:FindFirstChild(remoteName)

	if remote then
		if not remote:IsA(className) then
			error(("[RemoteGateway] %s exists but is not a %s"):format(remote:GetFullName(), className))
		end

		return remote
	end

	remote = Instance.new(className)
	remote.Name = remoteName
	remote.Parent = folder
	return remote
end

function RemoteGateway.waitForRemote(folderName: string?, remoteName: string, className: string, timeout: number?)
	local folder = ReplicatedStorage:WaitForChild(folderName or RemoteGateway.DEFAULT_FOLDER_NAME, timeout or 10)
	if not folder then
		return nil
	end

	local remote = folder:WaitForChild(remoteName, timeout or 10)
	if remote and remote:IsA(className) then
		return remote
	end

	return nil
end

function RemoteGateway.validatePayload(payload, schema)
	if typeof(payload) ~= "table" then
		return false, "Payload must be a table"
	end

	for fieldName, expectedType in schema do
		local value = payload[fieldName]
		local isOptional = false

		if typeof(expectedType) == "string" and string.sub(expectedType, 1, 1) == "?" then
			isOptional = true
			expectedType = string.sub(expectedType, 2)
		end

		if value == nil then
			if not isOptional then
				return false, ("Missing field '%s'"):format(fieldName)
			end
		elseif typeof(value) ~= expectedType then
			return false, ("Field '%s' must be %s"):format(fieldName, expectedType)
		end
	end

	return true, nil
end

function RemoteGateway.createRateLimiter(options)
	options = options or {}

	local window = options.Window or 0.25
	local lastByKey = {}

	return function(player: Player, key: string?)
		local now = os.clock()
		local bucketKey = ("%d:%s"):format(player.UserId, key or "default")
		local last = lastByKey[bucketKey]

		if last and now - last < window then
			return false, window - (now - last)
		end

		lastByKey[bucketKey] = now
		return true, 0
	end
end

return RemoteGateway
