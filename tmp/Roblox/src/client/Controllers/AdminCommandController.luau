local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local RemoteGateway = require(Core:WaitForChild("RemoteGateway"))

local AdminCommandController = {
	Name = "AdminCommandController",
	Priority = 25,
	remote = nil,
}

local function displaySystemMessage(message: string)
	local channels = TextChatService:FindFirstChild("TextChannels")
	if not channels then
		warn("[AdminCommand] TextChannels is unavailable: " .. message)
		return
	end

	local channel = channels:FindFirstChild("RBXSystem") or channels:FindFirstChild("RBXGeneral")
	if not channel or not channel:IsA("TextChannel") then
		warn("[AdminCommand] Default text channel is unavailable: " .. message)
		return
	end

	local ok, displayError = pcall(function()
		channel:DisplaySystemMessage(message, "KarmaAdminCommand")
	end)
	if not ok then
		warn("[AdminCommand] Could not display feedback: " .. tostring(displayError))
	end
end

function AdminCommandController:Init()
	self.remote = RemoteGateway.waitForRemote(nil, "AdminCommandFeedback", "RemoteEvent", 15)
	if not self.remote then
		warn("[AdminCommandController] AdminCommandFeedback was not created")
	end
end

function AdminCommandController:Start()
	if not self.remote then
		return
	end

	self.remote.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end

		local message = payload.Message
		if typeof(message) ~= "string" or message == "" or #message > 500 then
			return
		end

		displaySystemMessage(message)
	end)
end

return AdminCommandController
