local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local ModuleLoader = require(Core:WaitForChild("ModuleLoader"))
local SystemHub = require(Core:WaitForChild("SystemHub"))

SystemHub.initialize("Server")
if not SystemHub.begin("ServerCoreBootstrap", script) then
	return
end

local servicesFolder = script.Parent:FindFirstChild("Services")
if servicesFolder then
	ModuleLoader.startFolder(servicesFolder, {
		Side = "Server",
		SystemHub = SystemHub,
	})
	SystemHub.ready("ServerCoreBootstrap", script)
	SystemHub.completeStartup()
	task.delay(1, SystemHub.printSummary)
else
	SystemHub.failed("ServerCoreBootstrap", "Services folder not found", script)
end
