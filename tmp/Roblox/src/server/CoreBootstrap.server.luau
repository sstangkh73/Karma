local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local ModuleLoader = require(Core:WaitForChild("ModuleLoader"))

local servicesFolder = script.Parent:FindFirstChild("Services")
if servicesFolder then
	ModuleLoader.startFolder(servicesFolder, {
		Side = "Server",
	})
end
