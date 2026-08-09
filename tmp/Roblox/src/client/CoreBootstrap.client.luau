local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local ModuleLoader = require(Core:WaitForChild("ModuleLoader"))
local SystemHub = require(Core:WaitForChild("SystemHub"))

SystemHub.initialize("Client")
if not SystemHub.begin("ClientCoreBootstrap", script) then
	return
end

local controllersFolder = script.Parent:FindFirstChild("Controllers")
if controllersFolder then
	ModuleLoader.startFolder(controllersFolder, {
		Side = "Client",
		SystemHub = SystemHub,
	})
	SystemHub.ready("ClientCoreBootstrap", script)
	SystemHub.completeStartup()
	task.delay(1, SystemHub.printSummary)
else
	SystemHub.failed("ClientCoreBootstrap", "Controllers folder not found", script)
end
