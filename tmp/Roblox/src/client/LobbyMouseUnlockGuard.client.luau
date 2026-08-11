local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LOBBY_PLACE_ID = 99041403537198
local UNLOCK_KEY = Enum.KeyCode.V

if game.PlaceId ~= LOBBY_PLACE_ID then
	return
end

local mouseReleased = false

local function applyMouseRelease()
	if not mouseReleased then
		return
	end

	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed or UserInputService:GetFocusedTextBox() then
		return
	end

	if input.KeyCode == UNLOCK_KEY then
		mouseReleased = not mouseReleased
		applyMouseRelease()
	end
end)

RunService.RenderStepped:Connect(applyMouseRelease)
