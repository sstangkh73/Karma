local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Localization = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Localization"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local INTRO_DELAY = 0.2
local INTER_MESSAGE_GAP = 0.2
local MESSAGE_HOLD_TIME = 1.6

local MESSAGE_FADE_IN_INFO = TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MESSAGE_FADE_OUT_INFO = TweenInfo.new(0.725, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local PANEL_FADE_OUT_INFO = TweenInfo.new(0.725, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local PRIMARY_START_POSITION = UDim2.new(0.5, 0, 0.5, 12)
local PRIMARY_VISIBLE_POSITION = UDim2.new(0.5, 0, 0.5, 2)
local PRIMARY_END_POSITION = UDim2.new(0.5, 0, 0.5, -8)

local SECONDARY_START_POSITION = UDim2.new(0.5, 0, 0.5, 72)
local SECONDARY_VISIBLE_POSITION = UDim2.new(0.5, 0, 0.5, 62)
local SECONDARY_END_POSITION = UDim2.new(0.5, 0, 0.5, 52)

local DEFAULT_PRIMARY_MAX_SIZE = 38
local DEFAULT_SECONDARY_MAX_SIZE = 22

local PRELOAD_BATCH_SIZE = 24
local PRELOAD_BATCH_DELAY = 0.03
local PRELOAD_STREAM_DISTANCES = {0, 36, 72}
local PRELOAD_NEAR_RADIUS = 70
local PRELOAD_VIEW_RADIUS = 100
local PRELOAD_GUI_SCAN_TIMEOUT = 1

local GUI_NAME_PATTERNS = {
	"crosshair",
	"stamina",
	"hint",
	"start",
	"begin",
	"play",
}

local SYSTEM_FOLDER_NAMES = {
	"FlashlightSystem",
	"SprintSystem",
	"CrouchSystem",
}

local PRELOADABLE_CLASS_NAMES = {
	Beam = true,
	Decal = true,
	ImageButton = true,
	ImageLabel = true,
	MeshPart = true,
	ParticleEmitter = true,
	Sky = true,
	Sound = true,
	SpecialMesh = true,
	SurfaceAppearance = true,
	Texture = true,
	Trail = true,
	VideoFrame = true,
}

local messageSequence = {
	{
		primaryKey = "spawn.warning.title",
		primaryMaxSize = 32,
		secondaryMaxSize = 20,
	},
	{
		primaryKey = "spawn.warning.headphones",
	},
	{
		primaryKey = "spawn.warning.effects",
	},
	{
		primaryKey = "spawn.warning.discretion",
	},
}

local activeSequenceId = 0

local function getSecondaryLanguageCode(): string
	local currentLanguageCode = Localization.getCurrentLanguageCode()
	if currentLanguageCode == "en" then
		return Localization.SOURCE_LANGUAGE
	end

	return currentLanguageCode
end

local function playTween(instance: Instance, tweenInfo: TweenInfo, properties: {[string]: any})
	local tween = TweenService:Create(instance, tweenInfo, properties)
	tween:Play()
	return tween
end

local function waitForTween(tweenInfo: TweenInfo)
	task.wait(tweenInfo.DelayTime + tweenInfo.Time)
end

local function setAllCoreGuiEnabled(enabled: boolean)
	for _ = 1, 10 do
		local success = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, enabled)
		end)

		if success then
			return
		end

		task.wait(0.1)
	end
end

local function isCurrentSequence(sequenceId: number)
	return sequenceId == activeSequenceId
end

local function isSequenceActive(sequenceId: number, gui)
	if not isCurrentSequence(sequenceId) then
		return false
	end

	if not gui.screenGui.Parent then
		setAllCoreGuiEnabled(true)
		return false
	end

	return true
end

local function createLabel(
	parent: Instance,
	name: string,
	font: Enum.Font,
	textColor: Color3,
	size: UDim2,
	position: UDim2,
	minTextSize: number,
	maxTextSize: number
)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = position
	label.Size = size
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextColor3 = textColor
	label.TextScaled = true
	label.TextTransparency = 1
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Parent = parent

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = minTextSize
	constraint.MaxTextSize = maxTextSize
	constraint.Parent = label

	return label, constraint
end

local function buildWarningGui()
	local existingGui = playerGui:FindFirstChild("SpawnLoadingScreenGui")
	if existingGui then
		existingGui:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SpawnLoadingScreenGui"
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 1000
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(5, 5, 8)
	background.BorderSizePixel = 0
	background.Parent = screenGui

	local backgroundGradient = Instance.new("UIGradient")
	backgroundGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(12, 12, 18)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(3, 3, 5)),
	})
	backgroundGradient.Rotation = 90
	backgroundGradient.Parent = background

	local vignette = Instance.new("Frame")
	vignette.Name = "Vignette"
	vignette.AnchorPoint = Vector2.new(0.5, 0.5)
	vignette.Position = UDim2.fromScale(0.5, 0.5)
	vignette.Size = UDim2.fromScale(1.15, 1.15)
	vignette.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	vignette.BackgroundTransparency = 0.5
	vignette.BorderSizePixel = 0
	vignette.Parent = background

	local vignetteCorner = Instance.new("UICorner")
	vignetteCorner.CornerRadius = UDim.new(1, 0)
	vignetteCorner.Parent = vignette

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(0.5, 0.5)
	container.Size = UDim2.new(0.84, 0, 0, 210)
	container.BackgroundTransparency = 1
	container.Parent = background

	local primaryLabel, primaryConstraint = createLabel(
		container,
		"Primary",
		Enum.Font.GothamMedium,
		Color3.fromRGB(245, 245, 247),
		UDim2.new(1, 0, 0, 82),
		PRIMARY_START_POSITION,
		16,
		DEFAULT_PRIMARY_MAX_SIZE
	)
	primaryLabel.TextYAlignment = Enum.TextYAlignment.Bottom

	local secondaryLabel, secondaryConstraint = createLabel(
		container,
		"Secondary",
		Enum.Font.Gotham,
		Color3.fromRGB(168, 168, 176),
		UDim2.new(1, 0, 0, 48),
		SECONDARY_START_POSITION,
		11,
		DEFAULT_SECONDARY_MAX_SIZE
	)
	secondaryLabel.TextYAlignment = Enum.TextYAlignment.Top

	return {
		screenGui = screenGui,
		background = background,
		vignette = vignette,
		primaryLabel = primaryLabel,
		secondaryLabel = secondaryLabel,
		primaryConstraint = primaryConstraint,
		secondaryConstraint = secondaryConstraint,
	}
end

local function prepareMessage(gui, messageData)
	gui.primaryLabel.Text = Localization.translate(messageData.primaryKey, nil, "en")
	gui.secondaryLabel.Text = Localization.translate(messageData.primaryKey, nil, getSecondaryLanguageCode())

	gui.primaryConstraint.MaxTextSize = messageData.primaryMaxSize or DEFAULT_PRIMARY_MAX_SIZE
	gui.secondaryConstraint.MaxTextSize = messageData.secondaryMaxSize or DEFAULT_SECONDARY_MAX_SIZE

	gui.primaryLabel.Position = PRIMARY_START_POSITION
	gui.secondaryLabel.Position = SECONDARY_START_POSITION
	gui.primaryLabel.TextTransparency = 1
	gui.secondaryLabel.TextTransparency = 1
end

local function playMessage(gui, sequenceId: number, messageData, isLastMessage: boolean)
	prepareMessage(gui, messageData)

	playTween(gui.primaryLabel, MESSAGE_FADE_IN_INFO, {
		TextTransparency = 0,
		Position = PRIMARY_VISIBLE_POSITION,
	})
	playTween(gui.secondaryLabel, MESSAGE_FADE_IN_INFO, {
		TextTransparency = 0,
		Position = SECONDARY_VISIBLE_POSITION,
	})
	waitForTween(MESSAGE_FADE_IN_INFO)

	if not isSequenceActive(sequenceId, gui) then
		return false
	end

	task.wait(MESSAGE_HOLD_TIME)

	if not isSequenceActive(sequenceId, gui) then
		return false
	end

	playTween(gui.primaryLabel, MESSAGE_FADE_OUT_INFO, {
		TextTransparency = 1,
		Position = PRIMARY_END_POSITION,
	})
	playTween(gui.secondaryLabel, MESSAGE_FADE_OUT_INFO, {
		TextTransparency = 1,
		Position = SECONDARY_END_POSITION,
	})

	if isLastMessage then
		playTween(gui.background, PANEL_FADE_OUT_INFO, {
			BackgroundTransparency = 1,
		})
		playTween(gui.vignette, PANEL_FADE_OUT_INFO, {
			BackgroundTransparency = 1,
		})
	end

	waitForTween(MESSAGE_FADE_OUT_INFO)
	return isSequenceActive(sequenceId, gui)
end

local function cleanupSequence(sequenceId: number, gui)
	if gui.screenGui.Parent then
		gui.screenGui:Destroy()
	end

	if isCurrentSequence(sequenceId) then
		setAllCoreGuiEnabled(true)
	end
end

local function addPreloadTarget(targets, seen, instance: Instance?)
	if not instance or seen[instance] then
		return
	end

	if not instance.Parent then
		return
	end

	seen[instance] = true
	table.insert(targets, instance)
end

local function collectPreloadableDescendants(root: Instance?, targets, seen)
	if not root then
		return
	end

	if PRELOADABLE_CLASS_NAMES[root.ClassName] then
		addPreloadTarget(targets, seen, root)
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if PRELOADABLE_CLASS_NAMES[descendant.ClassName] then
			addPreloadTarget(targets, seen, descendant)
		end
	end
end

local function getCharacterRoot(character: Model)
	return character:FindFirstChild("HumanoidRootPart")
		or character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
		or character.PrimaryPart
end

local function requestStreamAround(position: Vector3)
	pcall(function()
		player:RequestStreamAroundAsync(position)
	end)
end

local function queryNearbyParts(position: Vector3, radius: number)
	local overlapParams = OverlapParams.new()
	overlapParams.MaxParts = 0
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {}

	local success, parts = pcall(function()
		return Workspace:GetPartBoundsInRadius(position, radius, overlapParams)
	end)

	if success and parts then
		return parts
	end

	return {}
end

local function collectSpawnAreaTargets(character: Model, targets, seen)
	local rootPart = getCharacterRoot(character)
	if not rootPart then
		return
	end

	local origin = rootPart.Position
	local lookVector = rootPart.CFrame.LookVector

	for _, distance in ipairs(PRELOAD_STREAM_DISTANCES) do
		local samplePosition = origin + (lookVector * distance)
		requestStreamAround(samplePosition)

		for _, part in ipairs(queryNearbyParts(samplePosition, PRELOAD_NEAR_RADIUS)) do
			collectPreloadableDescendants(part, targets, seen)
		end
	end

	for _, part in ipairs(queryNearbyParts(origin, PRELOAD_VIEW_RADIUS)) do
		local toPart = part.Position - origin
		local distance = toPart.Magnitude

		if distance > 0 then
			local facingScore = lookVector:Dot(toPart.Unit)
			if facingScore >= 0.15 then
				collectPreloadableDescendants(part, targets, seen)
			end
		end
	end
end

local function warmLightingState()
	local _ = Lighting.Ambient
	local _ = Lighting.OutdoorAmbient
	local _ = Lighting.GlobalShadows
	local _ = Lighting.Brightness
	local _ = Lighting.FogColor
	local _ = Lighting.FogStart
	local _ = Lighting.FogEnd

	for _, descendant in ipairs(Lighting:GetDescendants()) do
		if descendant:IsA("Atmosphere") then
			local _ = descendant.Density + descendant.Offset + descendant.Haze
		elseif descendant:IsA("ColorCorrectionEffect") then
			local _ = descendant.Brightness + descendant.Contrast + descendant.Saturation
		elseif descendant:IsA("BloomEffect") then
			local _ = descendant.Intensity + descendant.Size
		elseif descendant:IsA("SunRaysEffect") then
			local _ = descendant.Intensity + descendant.Spread
		elseif descendant:IsA("BlurEffect") then
			local _ = descendant.Size
		elseif descendant:IsA("DepthOfFieldEffect") then
			local _ = descendant.FarIntensity + descendant.InFocusRadius
		end
	end
end

local function collectLightingTargets(character: Model, targets, seen)
	warmLightingState()
	collectPreloadableDescendants(Lighting, targets, seen)

	for _, sound in ipairs(SoundService:GetDescendants()) do
		if sound:IsA("Sound") and (sound.Looped or string.find(string.lower(sound.Name), "ambient", 1, true)) then
			addPreloadTarget(targets, seen, sound)
		end
	end

	local rootPart = getCharacterRoot(character)
	if rootPart then
		for _, part in ipairs(queryNearbyParts(rootPart.Position, PRELOAD_NEAR_RADIUS)) do
			for _, descendant in ipairs(part:GetDescendants()) do
				if descendant:IsA("Sound") then
					addPreloadTarget(targets, seen, descendant)
				end
			end
		end
	end

	local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
	if sharedFolder then
		collectPreloadableDescendants(sharedFolder:FindFirstChild("Phone"), targets, seen)
	end
end

local function primePlayerControls(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 2)
	if humanoid then
		local _ = humanoid.WalkSpeed
		local _ = humanoid.JumpPower
	end

	local camera = Workspace.CurrentCamera
	if camera then
		local _ = camera.CFrame
		local _ = camera.FieldOfView
	end
end

local function collectPlayerSystemTargets(character: Model, targets, seen)
	primePlayerControls(character)

	for _, folderName in ipairs(SYSTEM_FOLDER_NAMES) do
		collectPreloadableDescendants(script.Parent:FindFirstChild(folderName), targets, seen)
	end

	local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
	if sharedFolder then
		collectPreloadableDescendants(sharedFolder:FindFirstChild("Phone"), targets, seen)
	end
end

local function matchesGuiPattern(name: string)
	local loweredName = string.lower(name)

	for _, pattern in ipairs(GUI_NAME_PATTERNS) do
		if string.find(loweredName, pattern, 1, true) then
			return true
		end
	end

	return false
end

local function collectImportantUiTargets(targets, seen)
	local deadline = os.clock() + PRELOAD_GUI_SCAN_TIMEOUT

	repeat
		for _, descendant in ipairs(playerGui:GetDescendants()) do
			if matchesGuiPattern(descendant.Name) then
				collectPreloadableDescendants(descendant, targets, seen)
				addPreloadTarget(targets, seen, descendant)
			end
		end

		task.wait(0.1)
	until os.clock() >= deadline
end

local function preloadTargets(sequenceId: number, targets)
	local startIndex = 1

	while startIndex <= #targets do
		if not isCurrentSequence(sequenceId) then
			return
		end

		local batch = {}
		local endIndex = math.min(startIndex + PRELOAD_BATCH_SIZE - 1, #targets)

		for index = startIndex, endIndex do
			local instance = targets[index]
			if instance and instance.Parent then
				table.insert(batch, instance)
			end
		end

		if #batch > 0 then
			pcall(function()
				ContentProvider:PreloadAsync(batch)
			end)
		end

		startIndex = endIndex + 1
		task.wait(PRELOAD_BATCH_DELAY)
	end
end

local function runPriorityPreload(sequenceId: number, character: Model)
	local seen = {}

	local mapTargets = {}
	collectSpawnAreaTargets(character, mapTargets, seen)
	preloadTargets(sequenceId, mapTargets)

	if not isCurrentSequence(sequenceId) then
		return
	end

	local lightingTargets = {}
	collectLightingTargets(character, lightingTargets, seen)
	preloadTargets(sequenceId, lightingTargets)

	if not isCurrentSequence(sequenceId) then
		return
	end

	local playerSystemTargets = {}
	collectPlayerSystemTargets(character, playerSystemTargets, seen)
	preloadTargets(sequenceId, playerSystemTargets)

	if not isCurrentSequence(sequenceId) then
		return
	end

	local uiTargets = {}
	collectImportantUiTargets(uiTargets, seen)
	preloadTargets(sequenceId, uiTargets)
end

local function showLoadingScreen(character: Model)
	activeSequenceId += 1
	local sequenceId = activeSequenceId

	setAllCoreGuiEnabled(false)

	local gui = buildWarningGui()

	task.spawn(function()
		runPriorityPreload(sequenceId, character)
	end)

	task.wait(INTRO_DELAY)

	if not isSequenceActive(sequenceId, gui) then
		return
	end

	for index, messageData in ipairs(messageSequence) do
		local isLastMessage = index == #messageSequence
		local completed = playMessage(gui, sequenceId, messageData, isLastMessage)

		if not completed then
			return
		end

		if not isLastMessage then
			task.wait(INTER_MESSAGE_GAP)

			if not isSequenceActive(sequenceId, gui) then
				return
			end
		end
	end

	cleanupSequence(sequenceId, gui)
end

local function onCharacterAdded(character: Model)
	character:WaitForChild("Humanoid", 5)
	task.defer(showLoadingScreen, character)
end

player.CharacterAdded:Connect(onCharacterAdded)

if player.Character then
	onCharacterAdded(player.Character)
end
