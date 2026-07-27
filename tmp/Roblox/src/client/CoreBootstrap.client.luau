local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local ModuleLoader = require(Core:WaitForChild("ModuleLoader"))

local controllersFolder = script.Parent:FindFirstChild("Controllers")
if controllersFolder then
	ModuleLoader.startFolder(controllersFolder, {
		Side = "Client",
	})
end
