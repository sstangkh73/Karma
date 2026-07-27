local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local TOOL_NAME = "Flashlight"
local RENDER_STEP_NAME = "FlashlightCameraAim"
local AIM_ATTACHMENT_NAME = "FlashlightCameraAimAttachment"
local PROXY_LIGHT_NAME = "FlashlightCameraAimLight"
local REFRESH_INTERVAL = 0.1

local state = {
	activeTool = nil,
	targets = {},
	connections = {},
	legacyScripts = {},
	isOn = false,
	nextRefreshAt = 0,
	hasLoggedAim = false,
}

local function disconnectAll()
	for _, connection in ipairs(state.connections) do
		connection:Disconnect()
	end

	table.clear(state.connections)
end

local function findAncestorPart(instance: Instance?): BasePart?
	local current = instance

	while current and current ~= Workspace do
		if current:IsA("BasePart") then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function getEquippedFlashlight(): Tool?
	local character = player.Character
	if not character then
		return nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child.Name == TOOL_NAME then
			return child
		end
	end

	return nil
end

local function getMuzzleWorldPosition(target): Vector3
	local origin = target.origin
	if origin and origin.Parent then
		if origin:IsA("Attachment") then
			return origin.WorldPosition
		end

		if origin:IsA("BasePart") then
			return origin.Position
		end
	end

	return target.parentPart.CFrame:PointToWorldSpace(target.localPosition)
end

local function createTarget(sourceLight: SpotLight?, origin: Instance, parentPart: BasePart)
	local worldPosition
	if origin:IsA("Attachment") then
		worldPosition = origin.WorldPosition
	else
		worldPosition = parentPart.Position
	end

	local localPosition = parentPart.CFrame:PointToObjectSpace(worldPosition)

	local aimAttachment = Instance.new("Attachment")
	aimAttachment.Name = AIM_ATTACHMENT_NAME
	aimAttachment.CFrame = CFrame.new(localPosition)
	aimAttachment:SetAttribute("FlashlightCameraAimProxy", true)
	aimAttachment.Parent = parentPart

	local proxyLight
	local originalEnabled = true

	if sourceLight then
		originalEnabled = sourceLight.Enabled
		proxyLight = sourceLight:Clone()
		sourceLight.Enabled = false
	else
		proxyLight = Instance.new("SpotLight")
		proxyLight.Angle = 55
		proxyLight.Brightness = 3
		proxyLight.Color = Color3.fromRGB(255, 244, 214)
		proxyLight.Range = 40
		proxyLight.Shadows = true
	end

	proxyLight.Name = PROXY_LIGHT_NAME
	proxyLight.Face = Enum.NormalId.Front
	proxyLight.Enabled = false
	proxyLight:SetAttribute("FlashlightCameraAimProxy", true)
	proxyLight.Parent = aimAttachment

	table.insert(state.targets, {
		sourceLight = sourceLight,
		originalEnabled = originalEnabled,
		origin = origin,
		parentPart = parentPart,
		localPosition = localPosition,
		attachment = aimAttachment,
		proxyLight = proxyLight,
	})

	return originalEnabled
end

local function restoreLegacyScripts()
	for scriptInstance, wasEnabled in pairs(state.legacyScripts) do
		if scriptInstance.Parent then
			scriptInstance.Enabled = wasEnabled
		end
	end

	table.clear(state.legacyScripts)
end

local function clearActiveTool()
	disconnectAll()

	for _, target in ipairs(state.targets) do
		local sourceLight = target.sourceLight
		if sourceLight and sourceLight.Parent then
			sourceLight.Enabled = target.originalEnabled
		end

		local attachment = target.attachment
		if attachment and attachment.Parent then
			attachment:Destroy()
		end
	end

	table.clear(state.targets)
	restoreLegacyScripts()

	state.activeTool = nil
	state.isOn = false
	state.hasLoggedAim = false
end

local function disableLegacyTurnScripts(tool: Tool)
	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("LocalScript") and string.lower(descendant.Name) == "turn" then
			state.legacyScripts[descendant] = descendant.Enabled
			descendant.Enabled = false
		end
	end
end

local function collectSourceLights(tool: Tool): {SpotLight}
	local sourceLights = {}

	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("SpotLight") and descendant:GetAttribute("FlashlightCameraAimProxy") ~= true then
			table.insert(sourceLights, descendant)
		end
	end

	return sourceLights
end

local function bindTool(tool: Tool)
	clearActiveTool()

	state.activeTool = tool
	disableLegacyTurnScripts(tool)

	local anySourceEnabled = false
	local sourceLights = collectSourceLights(tool)

	for _, sourceLight in ipairs(sourceLights) do
		local origin = sourceLight.Parent
		local parentPart = findAncestorPart(origin)

		if origin and parentPart then
			anySourceEnabled = createTarget(sourceLight, origin, parentPart) or anySourceEnabled
		end
	end

	if #state.targets == 0 then
		local handle = tool:FindFirstChild("Handle", true)
		if handle and handle:IsA("BasePart") then
			createTarget(nil, handle, handle)
			anySourceEnabled = true
			warn("[FlashlightSystem] No SpotLight found; using a camera-aimed fallback light")
		else
			warn("[FlashlightSystem] Flashlight has no SpotLight or Handle")
		end
	end

	state.isOn = anySourceEnabled
	for _, target in ipairs(state.targets) do
		target.proxyLight.Enabled = state.isOn
	end

	table.insert(state.connections, tool.Activated:Connect(function()
		state.isOn = not state.isOn

		for _, target in ipairs(state.targets) do
			if target.proxyLight.Parent then
				target.proxyLight.Enabled = state.isOn
			end
		end
	end))

	table.insert(state.connections, tool.AncestryChanged:Connect(function()
		if tool.Parent ~= player.Character then
			clearActiveTool()
		end
	end))
end

local function refreshActiveTool()
	local equippedTool = getEquippedFlashlight()
	if equippedTool ~= state.activeTool then
		if equippedTool then
			bindTool(equippedTool)
		else
			clearActiveTool()
		end
	end
end

local function updateAim()
	local now = os.clock()
	if now >= state.nextRefreshAt then
		state.nextRefreshAt = now + REFRESH_INTERVAL
		refreshActiveTool()
	end

	if not state.activeTool or #state.targets == 0 then
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local cameraCFrame = camera.CFrame

	for _, target in ipairs(state.targets) do
		local parentPart = target.parentPart
		local attachment = target.attachment
		local proxyLight = target.proxyLight

		if parentPart.Parent and attachment.Parent == parentPart and proxyLight.Parent == attachment then
			local muzzlePosition = getMuzzleWorldPosition(target)
			local desiredWorldCFrame = CFrame.lookAt(
				muzzlePosition,
				muzzlePosition + cameraCFrame.LookVector,
				cameraCFrame.UpVector
			)

			attachment.CFrame = parentPart.CFrame:ToObjectSpace(desiredWorldCFrame)
			proxyLight.Enabled = state.isOn

			if target.sourceLight and target.sourceLight.Parent then
				target.sourceLight.Enabled = false
			end

			if not state.hasLoggedAim then
				local aimDot = attachment.WorldCFrame.LookVector:Dot(cameraCFrame.LookVector)
				print(("[FlashlightSystem] Camera aim active targets=%d dot=%.4f"):format(#state.targets, aimDot))
				state.hasLoggedAim = true
			end
		end
	end
end

RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
RunService:BindToRenderStep(
	RENDER_STEP_NAME,
	Enum.RenderPriority.Camera.Value + 1,
	updateAim
)

script.Destroying:Connect(function()
	RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
	clearActiveTool()
end)

print("[FlashlightSystem] Boot v2")
