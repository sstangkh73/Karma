local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Localization = require(Shared:WaitForChild("Localization"))

local InteractionController = {
	Name = "InteractionController",
	Priority = 20,
	remote = nil,
	trackedPrompts = {},
}

local function applyPromptLocalization(prompt: ProximityPrompt)
	local actionKey = prompt:GetAttribute("LocalizationActionKey")
	if typeof(actionKey) == "string" and actionKey ~= "" then
		prompt.ActionText = Localization.translate(actionKey)
	end

	local objectKey = prompt:GetAttribute("LocalizationObjectKey")
	if typeof(objectKey) == "string" and objectKey ~= "" then
		prompt.ObjectText = Localization.translate(objectKey)
	end
end

function InteractionController:trackPrompt(prompt: ProximityPrompt)
	if self.trackedPrompts[prompt] then
		return
	end

	local connections = {
		prompt:GetAttributeChangedSignal("LocalizationActionKey"):Connect(function()
			applyPromptLocalization(prompt)
		end),
		prompt:GetAttributeChangedSignal("LocalizationObjectKey"):Connect(function()
			applyPromptLocalization(prompt)
		end),
		prompt.AncestryChanged:Connect(function()
			if prompt.Parent then
				return
			end

			local record = self.trackedPrompts[prompt]
			if not record then
				return
			end

			for _, connection in ipairs(record) do
				connection:Disconnect()
			end

			self.trackedPrompts[prompt] = nil
		end),
	}

	self.trackedPrompts[prompt] = connections
	applyPromptLocalization(prompt)
end

function InteractionController:refreshPromptLocalization()
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			self:trackPrompt(descendant)
			applyPromptLocalization(descendant)
		end
	end
end

function InteractionController:Init()
	local remotesFolder = ReplicatedStorage:WaitForChild("GameRemotes", 15)
	if not remotesFolder then
		warn("[InteractionController] GameRemotes was not created")
		return
	end

	local remote = remotesFolder:WaitForChild("InteractionEvent", 15)
	if remote and remote:IsA("RemoteEvent") then
		self.remote = remote
	else
		warn("[InteractionController] InteractionEvent was not created")
	end
end

function InteractionController:Start()
	self:refreshPromptLocalization()

	Workspace.DescendantAdded:Connect(function(instance)
		if instance:IsA("ProximityPrompt") then
			self:trackPrompt(instance)
		end
	end)

	Localization.subscribeToLanguageChanged(function()
		self:refreshPromptLocalization()
	end)

	if not self.remote then
		return
	end

	self.remote.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end

		if payload.Type ~= "Feedback" then
			return
		end

		local message = nil

		if typeof(payload.MessageKey) == "string" and payload.MessageKey ~= "" then
			message = Localization.translate(payload.MessageKey, payload.MessageParams)
		elseif typeof(payload.Message) == "string" and payload.Message ~= "" then
			message = payload.Message
		end

		if typeof(message) == "string" and message ~= "" then
			warn(("[Interaction] %s"):format(message))
		end
	end)
end

return InteractionController
