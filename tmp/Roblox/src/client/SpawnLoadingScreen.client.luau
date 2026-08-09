local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local SystemHub = require(Core:WaitForChild("SystemHub"))

if not SystemHub.begin("SpawnLoadingScreen", script) then
	return
end

local Localization = require(Shared:WaitForChild("Localization"))
local RemoteGateway = require(Core:WaitForChild("RemoteGateway"))
local Theme = require(Shared:WaitForChild("UITheme"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local INTRO_DELAY = 0.2
local INTER_MESSAGE_GAP = 0.2
local MESSAGE_HOLD_TIME = 1.6
local MIN_GATE_DISPLAY_TIME = 0.6

local LOADING_REMOTE_FOLDER = "GameRemotes"
local LOADING_REMOTE_NAME = "LoadingGateEvent"

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
local PRELOAD_GUI_SCAN_TIMEOUT = 1

local CRITICAL_LOAD_RADIUS = 128
local CRITICAL_STREAM_OFFSET = 72
local NEARBY_LOAD_RADIUS = 384
local NEARBY_STREAM_OFFSET = 240
local STREAM_REQUEST_TIMEOUT = 24
local AREA_STABILITY_TIMEOUT = 8
local AREA_STABILITY_INTERVAL = 0.25
local AREA_STABILITY_REQUIRED_SAMPLES = 4
local AREA_STABILITY_MIN_PARTS = 24
local AREA_STABILITY_MIN_COVERAGE = 0.55
local LOAD_RETRY_DELAY = 1.5
local RENDER_WARMUP_VIEWS = 4
local RENDER_WARMUP_FRAMES_PER_VIEW = 10
local RENDER_WARMUP_FINAL_FRAMES = 6
local RENDER_WARMUP_FIELD_OF_VIEW = 90

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
local loadingGateRemote = RemoteGateway.waitForRemote(LOADING_REMOTE_FOLDER, LOADING_REMOTE_NAME, "RemoteEvent", 15)
local latestGateStatus = {
	Ready = 0,
	Total = math.max(#Players:GetPlayers(), 1),
}
local releasedSequences = {}
local streamResults = {}
local streamRequestId = 0

local function getStreamResultKey(sequenceId: number, requestId: number)
	return ("%d:%d"):format(sequenceId, requestId)
end

if loadingGateRemote then
	loadingGateRemote.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end

		if payload.Type == "Status" then
			latestGateStatus.Ready = if typeof(payload.Ready) == "number" then payload.Ready else latestGateStatus.Ready
			latestGateStatus.Total = if typeof(payload.Total) == "number" then payload.Total else latestGateStatus.Total
		elseif payload.Type == "Release" and typeof(payload.SequenceId) == "number" then
			releasedSequences[payload.SequenceId] = true
		elseif payload.Type == "StreamResult"
			and typeof(payload.SequenceId) == "number"
			and typeof(payload.RequestId) == "number"
		then
			streamResults[getStreamResultKey(payload.SequenceId, payload.RequestId)] = payload
		end
	end)
else
	warn("[SpawnLoadingScreen] LoadingGateEvent was not available; using local-load fallback")
end

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
	label.ZIndex = 3
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

	local colors = Theme.Colors

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = colors.Ink
	background.BorderSizePixel = 0
	background.ZIndex = 1
	background.Parent = screenGui

	local backgroundGradient = Instance.new("UIGradient")
	backgroundGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, colors.Surface),
		ColorSequenceKeypoint.new(0.52, colors.Ink),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(2, 3, 4)),
	})
	backgroundGradient.Rotation = 112
	backgroundGradient.Parent = background

	local vignette = Instance.new("Frame")
	vignette.Name = "Vignette"
	vignette.AnchorPoint = Vector2.new(0.5, 0.5)
	vignette.Position = UDim2.fromScale(0.5, 0.5)
	vignette.Size = UDim2.fromScale(1.15, 1.15)
	vignette.BackgroundColor3 = colors.Ink
	vignette.BackgroundTransparency = 0.72
	vignette.BorderSizePixel = 0
	vignette.ZIndex = 1
	vignette.Parent = background

	local vignetteCorner = Instance.new("UICorner")
	vignetteCorner.CornerRadius = UDim.new(1, 0)
	vignetteCorner.Parent = vignette

	local brand = Instance.new("TextLabel")
	brand.Name = "Brand"
	brand.Position = UDim2.fromOffset(44, 34)
	brand.Size = UDim2.fromOffset(240, 24)
	brand.BackgroundTransparency = 1
	brand.Font = Theme.Fonts.Display
	brand.Text = "K A R M A"
	brand.TextColor3 = colors.Ivory
	brand.TextSize = 15
	brand.TextTransparency = 0.08
	brand.TextXAlignment = Enum.TextXAlignment.Left
	brand.ZIndex = 3
	brand.Parent = background

	local brandMeta = Instance.new("TextLabel")
	brandMeta.Name = "BrandMeta"
	brandMeta.Position = UDim2.fromOffset(44, 58)
	brandMeta.Size = UDim2.fromOffset(280, 18)
	brandMeta.BackgroundTransparency = 1
	brandMeta.Font = Theme.Fonts.BodyStrong
	brandMeta.Text = "PSYCHOLOGICAL HORROR EXPERIENCE"
	brandMeta.TextColor3 = colors.Brass
	brandMeta.TextSize = 9
	brandMeta.TextTransparency = 0.2
	brandMeta.TextXAlignment = Enum.TextXAlignment.Left
	brandMeta.ZIndex = 3
	brandMeta.Parent = background

	local brandLine = Instance.new("Frame")
	brandLine.Name = "BrandLine"
	brandLine.Position = UDim2.fromOffset(44, 82)
	brandLine.Size = UDim2.fromOffset(72, 1)
	brandLine.BackgroundColor3 = colors.Brass
	brandLine.BackgroundTransparency = 0.25
	brandLine.BorderSizePixel = 0
	brandLine.ZIndex = 3
	brandLine.Parent = background

	local sequenceMeta = Instance.new("TextLabel")
	sequenceMeta.Name = "SequenceMeta"
	sequenceMeta.AnchorPoint = Vector2.new(1, 1)
	sequenceMeta.Position = UDim2.new(1, -44, 1, -34)
	sequenceMeta.Size = UDim2.fromOffset(260, 18)
	sequenceMeta.BackgroundTransparency = 1
	sequenceMeta.Font = Theme.Fonts.BodyStrong
	sequenceMeta.Text = "INITIALIZING  //  PLEASE WAIT"
	sequenceMeta.TextColor3 = colors.Faint
	sequenceMeta.TextSize = 9
	sequenceMeta.TextXAlignment = Enum.TextXAlignment.Right
	sequenceMeta.ZIndex = 3
	sequenceMeta.Parent = background

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(0.5, 0.5)
	container.Size = UDim2.new(0.84, 0, 0, 210)
	container.BackgroundTransparency = 1
	container.ZIndex = 2
	container.Parent = background

	local primaryLabel, primaryConstraint = createLabel(
		container,
		"Primary",
		Theme.Fonts.Heading,
		Color3.fromRGB(248, 244, 234),
		UDim2.new(1, 0, 0, 82),
		PRIMARY_START_POSITION,
		16,
		DEFAULT_PRIMARY_MAX_SIZE
	)
	primaryLabel.TextYAlignment = Enum.TextYAlignment.Bottom

	local secondaryLabel, secondaryConstraint = createLabel(
		container,
		"Secondary",
		Theme.Fonts.Body,
		Color3.fromRGB(188, 186, 180),
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
		staticElements = {brand, brandMeta, brandLine, sequenceMeta},
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

		for _, element in ipairs(gui.staticElements) do
			if element:IsA("TextLabel") then
				playTween(element, PANEL_FADE_OUT_INFO, {TextTransparency = 1})
			else
				playTween(element, PANEL_FADE_OUT_INFO, {BackgroundTransparency = 1})
			end
		end
	end

	waitForTween(MESSAGE_FADE_OUT_INFO)
	return isSequenceActive(sequenceId, gui)
end

local function showGateMessage(gui, titleKey: string, detailKey: string, params)
	gui.primaryLabel.Text = Localization.translate(titleKey, params, "en")
	gui.secondaryLabel.Text = Localization.translate(detailKey, params, getSecondaryLanguageCode())
	gui.primaryLabel.Position = PRIMARY_VISIBLE_POSITION
	gui.secondaryLabel.Position = SECONDARY_VISIBLE_POSITION
	gui.primaryLabel.TextTransparency = 0
	gui.secondaryLabel.TextTransparency = 0
end

local function fadeOutGate(gui)
	playTween(gui.primaryLabel, PANEL_FADE_OUT_INFO, {TextTransparency = 1})
	playTween(gui.secondaryLabel, PANEL_FADE_OUT_INFO, {TextTransparency = 1})
	playTween(gui.background, PANEL_FADE_OUT_INFO, {BackgroundTransparency = 1})
	playTween(gui.vignette, PANEL_FADE_OUT_INFO, {BackgroundTransparency = 1})

	for _, element in ipairs(gui.staticElements) do
		if element:IsA("TextLabel") then
			playTween(element, PANEL_FADE_OUT_INFO, {TextTransparency = 1})
		else
			playTween(element, PANEL_FADE_OUT_INFO, {BackgroundTransparency = 1})
		end
	end

	waitForTween(PANEL_FADE_OUT_INFO)
end

local function waitForPartyRelease(sequenceId: number, gui)
	if not loadingGateRemote then
		return true
	end

	loadingGateRemote:FireServer({
		Type = "Ready",
		SequenceId = sequenceId,
	})

	local lastReady = -1
	local lastTotal = -1

	while isSequenceActive(sequenceId, gui) and not releasedSequences[sequenceId] do
		local readyCount = math.max(0, latestGateStatus.Ready)
		local totalCount = math.max(1, latestGateStatus.Total)

		if readyCount ~= lastReady or totalCount ~= lastTotal then
			showGateMessage(gui, "spawn.loading.waiting", "spawn.loading.status", {
				ready = readyCount,
				total = totalCount,
			})
			lastReady = readyCount
			lastTotal = totalCount
		end

		task.wait(0.1)
	end

	local wasReleased = releasedSequences[sequenceId] == true
	releasedSequences[sequenceId] = nil
	return wasReleased
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

local function queryNearbyParts(position: Vector3, radius: number, excludedInstance: Instance?)
	local overlapParams = OverlapParams.new()
	overlapParams.MaxParts = 0
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = if excludedInstance then {excludedInstance} else {}

	local success, parts = pcall(function()
		return Workspace:GetPartBoundsInRadius(position, radius, overlapParams)
	end)

	if success and parts then
		return parts
	end

	return {}
end

local function buildCriticalStreamPoints(rootPart: BasePart)
	local origin = rootPart.Position
	local forward = rootPart.CFrame.LookVector
	local right = rootPart.CFrame.RightVector

	return {
		origin,
		origin + (forward * CRITICAL_STREAM_OFFSET),
		origin - (forward * CRITICAL_STREAM_OFFSET),
		origin + (right * CRITICAL_STREAM_OFFSET),
		origin - (right * CRITICAL_STREAM_OFFSET),
	}
end

local function buildNearbyStreamPoints(rootPart: BasePart)
	local origin = rootPart.Position
	local forward = rootPart.CFrame.LookVector
	local right = rootPart.CFrame.RightVector
	local diagonalA = (forward + right).Unit
	local diagonalB = (forward - right).Unit

	return {
		origin,
		origin + (forward * NEARBY_STREAM_OFFSET),
		origin - (forward * NEARBY_STREAM_OFFSET),
		origin + (right * NEARBY_STREAM_OFFSET),
		origin - (right * NEARBY_STREAM_OFFSET),
		origin + (diagonalA * NEARBY_STREAM_OFFSET),
		origin - (diagonalA * NEARBY_STREAM_OFFSET),
		origin + (diagonalB * NEARBY_STREAM_OFFSET),
		origin - (diagonalB * NEARBY_STREAM_OFFSET),
	}
end

local function requestStreamPhase(sequenceId: number, phaseName: string, points)
	if not loadingGateRemote then
		local success, errorMessage = pcall(function()
			for _, point in ipairs(points) do
				player:RequestStreamAroundAsync(point, 4)
			end
		end)

		return success, {
			Success = success,
			Error = if success then nil else tostring(errorMessage),
			Completed = if success then #points else 0,
			Total = #points,
		}
	end

	streamRequestId += 1
	local requestId = streamRequestId
	local resultKey = getStreamResultKey(sequenceId, requestId)
	local deadline = os.clock() + STREAM_REQUEST_TIMEOUT

	loadingGateRemote:FireServer({
		Type = "StreamRequest",
		SequenceId = sequenceId,
		RequestId = requestId,
		Phase = phaseName,
		Points = points,
	})

	while isCurrentSequence(sequenceId) and os.clock() < deadline do
		local result = streamResults[resultKey]
		if result then
			streamResults[resultKey] = nil
			return result.Success == true, result
		end

		task.wait(0.1)
	end

	streamResults[resultKey] = nil
	return false, {
		Success = false,
		Error = "Timed out waiting for the server stream result",
		Completed = 0,
		Total = #points,
	}
end

local function sampleLoadedArea(character: Model, radius: number)
	local rootPart = getCharacterRoot(character)
	if not rootPart or not rootPart:IsA("BasePart") then
		return {
			PartCount = 0,
			FarthestDistance = 0,
		}
	end

	local partCount = 0
	local farthestDistance = 0
	for _, part in ipairs(queryNearbyParts(rootPart.Position, radius, character)) do
		if part:IsA("BasePart") then
			partCount += 1
			local centerDistance = (part.Position - rootPart.Position).Magnitude
			local boundsReach = centerDistance + (part.Size.Magnitude * 0.5)
			farthestDistance = math.max(farthestDistance, math.min(radius, boundsReach))
		end
	end

	return {
		PartCount = partCount,
		FarthestDistance = farthestDistance,
	}
end

local function waitForStableArea(sequenceId: number, character: Model, radius: number)
	local deadline = os.clock() + AREA_STABILITY_TIMEOUT
	local stableSamples = 0
	local previousCount = nil
	local latestSample = sampleLoadedArea(character, radius)

	while isCurrentSequence(sequenceId) and os.clock() < deadline do
		latestSample = sampleLoadedArea(character, radius)
		local tolerance = math.max(2, math.floor(latestSample.PartCount * 0.01))
		local countStable = previousCount ~= nil and math.abs(latestSample.PartCount - previousCount) <= tolerance
		local enoughParts = latestSample.PartCount >= AREA_STABILITY_MIN_PARTS
		local enoughCoverage = latestSample.FarthestDistance >= radius * AREA_STABILITY_MIN_COVERAGE

		if countStable and enoughParts and enoughCoverage then
			stableSamples += 1
		else
			stableSamples = 0
		end

		if stableSamples >= AREA_STABILITY_REQUIRED_SAMPLES then
			return true, latestSample
		end

		previousCount = latestSample.PartCount
		task.wait(AREA_STABILITY_INTERVAL)
	end

	return false, latestSample
end

local function collectSpawnAreaTargets(character: Model, targets, seen)
	local rootPart = getCharacterRoot(character)
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	for _, part in ipairs(queryNearbyParts(rootPart.Position, CRITICAL_LOAD_RADIUS, character)) do
		collectPreloadableDescendants(part, targets, seen)
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
	if rootPart and rootPart:IsA("BasePart") then
		for _, part in ipairs(queryNearbyParts(rootPart.Position, CRITICAL_LOAD_RADIUS, character)) do
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

local function waitForRenderFrames(sequenceId: number, frameCount: number)
	for _ = 1, frameCount do
		if not isCurrentSequence(sequenceId) then
			return false
		end

		RunService.RenderStepped:Wait()
	end

	return true
end

local function warmCriticalRender(sequenceId: number, character: Model)
	local rootPart = getCharacterRoot(character)
	local camera = Workspace.CurrentCamera
	if not rootPart or not rootPart:IsA("BasePart") or not camera then
		return false, "Camera or character root is unavailable"
	end

	local startedAt = os.clock()
	local originalType = camera.CameraType
	local originalSubject = camera.CameraSubject
	local originalCFrame = camera.CFrame
	local originalFieldOfView = camera.FieldOfView
	local cameraPosition = rootPart.Position + Vector3.new(0, 3.5, 0)
	local baseForward = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)

	if baseForward.Magnitude < 0.001 then
		baseForward = Vector3.new(0, 0, -1)
	else
		baseForward = baseForward.Unit
	end

	local success, errorMessage = pcall(function()
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = RENDER_WARMUP_FIELD_OF_VIEW

		for viewIndex = 0, RENDER_WARMUP_VIEWS - 1 do
			local direction = CFrame.Angles(0, math.rad(90 * viewIndex), 0):VectorToWorldSpace(baseForward)
			local lookTarget = cameraPosition + direction + Vector3.new(0, -0.15, 0)
			local targetCFrame = CFrame.lookAt(cameraPosition, lookTarget)

			for _ = 1, RENDER_WARMUP_FRAMES_PER_VIEW do
				camera.CFrame = targetCFrame
				if not waitForRenderFrames(sequenceId, 1) then
					error("Loading sequence changed during render warm-up")
				end
			end
		end
	end)

	camera.CameraType = originalType
	camera.CameraSubject = originalSubject
	camera.CFrame = originalCFrame
	camera.FieldOfView = originalFieldOfView

	if success then
		success = waitForRenderFrames(sequenceId, RENDER_WARMUP_FINAL_FRAMES)
		if not success then
			errorMessage = "Loading sequence changed while restoring the camera"
		end
	end

	if not success then
		return false, tostring(errorMessage)
	end

	local duration = os.clock() - startedAt
	print(("[SpawnLoadingScreen][RenderWarmup v1] views=%d frames=%d duration=%.2fs"):format(
		RENDER_WARMUP_VIEWS,
		(RENDER_WARMUP_VIEWS * RENDER_WARMUP_FRAMES_PER_VIEW) + RENDER_WARMUP_FINAL_FRAMES,
		duration
	))

	return true, {
		Views = RENDER_WARMUP_VIEWS,
		Frames = (RENDER_WARMUP_VIEWS * RENDER_WARMUP_FRAMES_PER_VIEW) + RENDER_WARMUP_FINAL_FRAMES,
		Duration = duration,
	}
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
	local stats = {
		Requested = #targets,
		Fetched = 0,
		FailedAssets = 0,
		FailedBatches = 0,
	}

	while startIndex <= #targets do
		if not isCurrentSequence(sequenceId) then
			return stats
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
			local success, errorMessage = pcall(function()
				ContentProvider:PreloadAsync(batch, function(_, fetchStatus)
					if fetchStatus == Enum.AssetFetchStatus.Success then
						stats.Fetched += 1
					else
						stats.FailedAssets += 1
					end
				end)
			end)

			if not success then
				stats.FailedBatches += 1
				warn(("[SpawnLoadingScreen][RadialLoad v1] Preload batch failed: %s"):format(tostring(errorMessage)))
			end
		end

		startIndex = endIndex + 1
		task.wait(PRELOAD_BATCH_DELAY)
	end

	return stats
end

local function runPriorityPreload(sequenceId: number, character: Model)
	local seen = {}
	local totals = {
		Requested = 0,
		Fetched = 0,
		FailedAssets = 0,
		FailedBatches = 0,
	}

	local function addStats(stats)
		if not stats then
			return
		end

		for key in pairs(totals) do
			totals[key] += stats[key] or 0
		end
	end

	local mapTargets = {}
	collectSpawnAreaTargets(character, mapTargets, seen)
	addStats(preloadTargets(sequenceId, mapTargets))

	if not isCurrentSequence(sequenceId) then
		return totals
	end

	local lightingTargets = {}
	collectLightingTargets(character, lightingTargets, seen)
	addStats(preloadTargets(sequenceId, lightingTargets))

	if not isCurrentSequence(sequenceId) then
		return totals
	end

	local playerSystemTargets = {}
	collectPlayerSystemTargets(character, playerSystemTargets, seen)
	addStats(preloadTargets(sequenceId, playerSystemTargets))

	if not isCurrentSequence(sequenceId) then
		return totals
	end

	local uiTargets = {}
	collectImportantUiTargets(uiTargets, seen)
	addStats(preloadTargets(sequenceId, uiTargets))

	return totals
end

local function runCriticalLoadAttempt(sequenceId: number, character: Model)
	local rootPart = getCharacterRoot(character)
	if not rootPart or not rootPart:IsA("BasePart") then
		return false, "Character root is unavailable"
	end

	local phaseStartedAt = os.clock()
	local streamSucceeded, streamResult = requestStreamPhase(
		sequenceId,
		"Critical",
		buildCriticalStreamPoints(rootPart)
	)

	if not streamSucceeded then
		return false, streamResult.Error or "Server streaming request failed"
	end

	local areaStable, areaSample = waitForStableArea(sequenceId, character, CRITICAL_LOAD_RADIUS)
	if not areaStable then
		return false, ("Area did not stabilize (parts=%d farthest=%.1f)"):format(
			areaSample.PartCount,
			areaSample.FarthestDistance
		)
	end

	local preloadStats = runPriorityPreload(sequenceId, character)
	local renderReady, renderStats = warmCriticalRender(sequenceId, character)
	if not renderReady then
		return false, ("Render warm-up failed: %s"):format(tostring(renderStats))
	end

	local duration = os.clock() - phaseStartedAt
	print(("[SpawnLoadingScreen][RadialLoad v2] phase=Critical renderReady=true radius=%d parts=%d farthest=%.1f targets=%d fetched=%d failedAssets=%d failedBatches=%d renderFrames=%d duration=%.2fs"):format(
		CRITICAL_LOAD_RADIUS,
		areaSample.PartCount,
		areaSample.FarthestDistance,
		preloadStats.Requested,
		preloadStats.Fetched,
		preloadStats.FailedAssets,
		preloadStats.FailedBatches,
		renderStats.Frames,
		duration
	))

	return true, {
		Area = areaSample,
		Preload = preloadStats,
		Render = renderStats,
		Duration = duration,
	}
end

local function runNearbyBackgroundLoad(sequenceId: number, character: Model)
	local rootPart = getCharacterRoot(character)
	if not rootPart or not rootPart:IsA("BasePart") or not isCurrentSequence(sequenceId) then
		return
	end

	local startedAt = os.clock()
	local succeeded, result = requestStreamPhase(sequenceId, "Nearby", buildNearbyStreamPoints(rootPart))
	if not succeeded then
		warn(("[SpawnLoadingScreen][RadialLoad v1] phase=Nearby failed: %s"):format(tostring(result.Error)))
		return
	end

	local sample = sampleLoadedArea(character, NEARBY_LOAD_RADIUS)
	print(("[SpawnLoadingScreen][RadialLoad v1] phase=Nearby requested radius=%d parts=%d farthest=%.1f duration=%.2fs"):format(
		NEARBY_LOAD_RADIUS,
		sample.PartCount,
		sample.FarthestDistance,
		os.clock() - startedAt
	))
end

local function showLoadingScreen(character: Model)
	activeSequenceId += 1
	local sequenceId = activeSequenceId

	setAllCoreGuiEnabled(false)

	local gui = buildWarningGui()
	local criticalLoad = {
		Finished = false,
		Success = false,
		Attempt = 0,
		Error = nil,
		Stats = nil,
	}

	task.spawn(function()
		while isSequenceActive(sequenceId, gui) and not criticalLoad.Success do
			criticalLoad.Attempt += 1
			local callSucceeded, loadSucceeded, result = pcall(runCriticalLoadAttempt, sequenceId, character)

			if callSucceeded and loadSucceeded then
				criticalLoad.Success = true
				criticalLoad.Stats = result
				criticalLoad.Error = nil
			else
				criticalLoad.Error = if callSucceeded then tostring(result) else tostring(loadSucceeded)
				warn(("[SpawnLoadingScreen][RadialLoad v1] Critical attempt %d failed: %s"):format(
					criticalLoad.Attempt,
					criticalLoad.Error
				))
				task.wait(LOAD_RETRY_DELAY)
			end
		end

		criticalLoad.Finished = criticalLoad.Success or not isSequenceActive(sequenceId, gui)
	end)

	task.wait(INTRO_DELAY)

	if not isSequenceActive(sequenceId, gui) then
		return
	end

	for index, messageData in ipairs(messageSequence) do
		local isLastMessage = index == #messageSequence
		local completed = playMessage(gui, sequenceId, messageData, false)

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

	showGateMessage(gui, "spawn.loading.title", "spawn.loading.radius", {
		radius = CRITICAL_LOAD_RADIUS,
		attempt = criticalLoad.Attempt,
	})
	local gateShownAt = os.clock()
	local displayedAttempt = criticalLoad.Attempt

	while isSequenceActive(sequenceId, gui) and not criticalLoad.Finished do
		if criticalLoad.Attempt ~= displayedAttempt then
			showGateMessage(gui, "spawn.loading.title", "spawn.loading.radius", {
				radius = CRITICAL_LOAD_RADIUS,
				attempt = criticalLoad.Attempt,
			})
			displayedAttempt = criticalLoad.Attempt
		end

		task.wait(0.1)
	end

	if not isSequenceActive(sequenceId, gui) or not criticalLoad.Success then
		return
	end

	local remainingDisplayTime = MIN_GATE_DISPLAY_TIME - (os.clock() - gateShownAt)
	if remainingDisplayTime > 0 then
		task.wait(remainingDisplayTime)
	end

	if not isSequenceActive(sequenceId, gui) or not waitForPartyRelease(sequenceId, gui) then
		return
	end

	fadeOutGate(gui)
	cleanupSequence(sequenceId, gui)

	task.spawn(runNearbyBackgroundLoad, sequenceId, character)
end

local function onCharacterAdded(character: Model)
	character:WaitForChild("Humanoid", 5)
	task.defer(showLoadingScreen, character)
end

player.CharacterAdded:Connect(onCharacterAdded)

if player.Character then
	onCharacterAdded(player.Character)
end

SystemHub.ready("SpawnLoadingScreen", script)
