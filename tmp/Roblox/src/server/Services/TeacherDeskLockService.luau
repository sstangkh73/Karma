local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CONFIG = {
	KeyInstanceName = "TeacherDeskKey",
	LockInstanceName = "TeacherDeskLock",
	PromptPartName = "PromptPart",
	ContentsName = "Contents",
	OpenTargetValueName = "OpenTarget",
	KeyId = "teacher_desk_key",
	DefaultOpenOffset = Vector3.new(0, 0, -1.4),
	OpenDuration = 0.65,
	PromptDistance = 8,
	ApiFolderName = "TeacherDeskLockApi",
	RequiredChadaPlacements = 2,
	ChadaDefinitionId = "Jada",
	FogInstanceName = "Fog",
	FogDuration = 1.5,
	FogBurstCount = 35,
	LighterDefinitionId = "lighter",
	CandleNames = { "Candle1", "Candle2" },
	FlamePartName = "Flame",
	DeskEvidenceNames = { "Phone1", "Note_5" },
	NoteInstanceName = "Note_5",
	NoteId = "note_5",
	PhoneInstanceName = "Phone1",
	PhonePromptName = "PhoneInspectPrompt",
	PhoneHoldDuration = 2.5,
}

local TeacherDeskLockService = {
	Name = "TeacherDeskLockService",
	Priority = 70,
	Dependencies = { "ObjectiveService", "DialogueService" },
	keyRoot = nil,
	fogRoot = nil,
	lockRoot = nil,
	keyPrompt = nil,
	lockPrompt = nil,
	openTarget = nil,
	contentsRoot = nil,
	keyVisualState = nil,
	keyPartCFrames = {},
	contentsVisualState = nil,
	deskEvidence = {},
	phonePrompt = nil,
	teamHasKey = false,
	unlocked = false,
	busy = false,
	keyRevealInProgress = false,
	chadaComplete = false,
	teamHasLighter = false,
	lighterOwner = nil,
	candles = {},
	placedChadaZones = {},
	cutscenePlacementConnection = nil,
	inventoryPlacementConnection = nil,
	inventoryPickupConnection = nil,
}

local function allInstances(root: Instance)
	local instances = { root }
	for _, descendant in ipairs(root:GetDescendants()) do
		table.insert(instances, descendant)
	end
	return instances
end

local function findDeskEvidenceRoot(instanceName: string): Instance?
	local exactMatch = Workspace:FindFirstChild(instanceName, true)
	if exactMatch then
		return exactMatch
	end

	local normalizedName = string.lower(instanceName)
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if string.lower(descendant.Name) == normalizedName then
			return descendant
		end
	end

	if instanceName == CONFIG.NoteInstanceName then
		for _, descendant in ipairs(Workspace:GetDescendants()) do
			if descendant:GetAttribute("NoteId") == CONFIG.NoteId then
				return descendant
			end
		end
	end

	return nil
end

local function captureVisualState(root: Instance)
	local state = {}
	for _, instance in ipairs(allInstances(root)) do
		if instance:IsA("BasePart") then
			state[instance] = {
				Transparency = instance.Transparency,
				CanCollide = instance.CanCollide,
				CanTouch = instance.CanTouch,
				CanQuery = instance.CanQuery,
			}
		elseif instance:IsA("Decal") or instance:IsA("Texture") then
			state[instance] = { Transparency = instance.Transparency }
		elseif instance:IsA("ProximityPrompt")
			or instance:IsA("ParticleEmitter")
			or instance:IsA("Smoke")
			or instance:IsA("Fire")
			or instance:IsA("Sparkles")
			or instance:IsA("Trail")
			or instance:IsA("Beam")
			or instance:IsA("Light")
			or instance:IsA("BillboardGui")
			or instance:IsA("SurfaceGui") then
			state[instance] = { Enabled = instance.Enabled }
		elseif instance:IsA("GuiObject") then
			state[instance] = { Visible = instance.Visible }
		end
	end
	return state
end

local function setTreeVisible(state, visible: boolean)
	if not state then
		return
	end

	for instance, properties in pairs(state) do
		if not instance.Parent then
			continue
		end

		if visible then
			for propertyName, value in pairs(properties) do
				instance[propertyName] = value
			end
		elseif instance:IsA("BasePart") then
			instance.Transparency = 1
			instance.CanCollide = false
			instance.CanTouch = false
			instance.CanQuery = false
		elseif instance:IsA("Decal") or instance:IsA("Texture") then
			instance.Transparency = 1
		elseif properties.Enabled ~= nil then
			instance.Enabled = false
		elseif properties.Visible ~= nil then
			instance.Visible = false
		end
	end
end

local function setFogEnabled(root: Instance?, enabled: boolean)
	if not root then
		return
	end

	for _, instance in ipairs(allInstances(root)) do
		if instance:IsA("ParticleEmitter") then
			instance.Enabled = enabled
			if enabled then
				local configuredBurst = instance:GetAttribute("BurstCount")
				local burstCount = if typeof(configuredBurst) == "number"
					then math.max(0, math.floor(configuredBurst))
					else CONFIG.FogBurstCount
				if burstCount > 0 then
					instance:Emit(burstCount)
				end
			else
				instance:Clear()
			end
		elseif instance:IsA("Smoke")
			or instance:IsA("Fire")
			or instance:IsA("Sparkles")
			or instance:IsA("Beam")
			or instance:IsA("Trail")
			or instance:IsA("Light") then
			instance.Enabled = enabled
		end
	end
end

local function getPromptPart(root: Instance): BasePart?
	if root:IsA("BasePart") then
		return root
	end

	local namedPart = root:FindFirstChild(CONFIG.PromptPartName, true)
	if namedPart and namedPart:IsA("BasePart") then
		return namedPart
	end

	if root:IsA("Model") and root.PrimaryPart then
		return root.PrimaryPart
	end

	return root:FindFirstChildWhichIsA("BasePart", true)
end

local function ensurePrompt(
	root: Instance,
	fallbackParent: BasePart,
	name: string,
	excludedRoot: Instance?
): ProximityPrompt
	local prompt: ProximityPrompt? = nil
	local namedPrompt = root:FindFirstChild(name, true)
	if namedPrompt and namedPrompt:IsA("ProximityPrompt") then
		prompt = namedPrompt
	else
		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("ProximityPrompt")
				and (not excludedRoot or not descendant:IsDescendantOf(excludedRoot)) then
				prompt = descendant
				break
			end
		end
	end

	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = fallbackParent
	end

	prompt.Name = name
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = CONFIG.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	return prompt
end

local function suppressOtherPrompts(root: Instance, activePrompt: ProximityPrompt)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") and descendant ~= activePrompt then
			descendant.Enabled = false
		end
	end
end

local function playSequence(player: Player, sequenceId: string)
	local folder = ServerStorage:FindFirstChild("DialogueServerApi")
	local playSequence = folder and folder:FindFirstChild("PlaySequence")
	if not playSequence or not playSequence:IsA("BindableFunction") then
		warn(("[TeacherDeskLockService] Dialogue API is unavailable for %s"):format(sequenceId))
		return
	end

	local ok, didPlay, message = pcall(function()
		return playSequence:Invoke(player, sequenceId, {
			Source = "TeacherDeskLockService",
		})
	end)
	if not ok or didPlay == false then
		warn(("[TeacherDeskLockService] Could not play %s: %s"):format(sequenceId, tostring(message)))
	end
end

local function upsertObjective(player: Player, objectiveId: string)
	local folder = ServerStorage:FindFirstChild("ObjectiveServerApi")
	local upsert = folder and folder:FindFirstChild("UpsertObjective")
	if not upsert or not upsert:IsA("BindableFunction") then
		warn(("[TeacherDeskLockService] Objective API is unavailable for %s"):format(objectiveId))
		return
	end

	local ok, didUpsert, message = pcall(function()
		return upsert:Invoke(player, {
			Id = objectiveId,
			DefinitionId = objectiveId,
		})
	end)
	if not ok or didUpsert == false then
		warn(("[TeacherDeskLockService] Could not start %s: %s"):format(objectiveId, tostring(message)))
	end
end

local function upsertObjectiveForTeam(objectiveId: string)
	for _, player in ipairs(Players:GetPlayers()) do
		upsertObjective(player, objectiveId)
	end
end

local function removeInventoryItem(player: Player?, definitionId: string)
	if not player or player.Parent ~= Players then
		return false
	end

	local folder = ServerStorage:FindFirstChild("InventoryServerApi")
	local removeItem = folder and folder:FindFirstChild("RemoveItemByDefinitionId")
	if not removeItem or not removeItem:IsA("BindableFunction") then
		warn("[TeacherDeskLockService] Inventory remove API is unavailable")
		return false
	end

	local ok, didRemove, message = pcall(function()
		return removeItem:Invoke(player, definitionId)
	end)
	if not ok or didRemove == false then
		warn(("[TeacherDeskLockService] Could not consume %s: %s"):format(definitionId, tostring(message)))
		return false
	end
	return true
end

local function setTeamKeyAttribute(hasKey: boolean)
	Workspace:SetAttribute("TeacherDeskKeyCollected", hasKey)
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("HasTeacherDeskKey", hasKey)
	end
end

local function getPivot(target: Instance): CFrame?
	if target:IsA("BasePart") then
		return target.CFrame
	elseif target:IsA("Model") then
		return target:GetPivot()
	end
	return nil
end

local function pivotTarget(target: Instance, cframe: CFrame)
	if target:IsA("BasePart") then
		target.CFrame = cframe
	elseif target:IsA("Model") then
		target:PivotTo(cframe)
	end
end

function TeacherDeskLockService:refreshKey()
	if not self.keyRoot or not self.keyPrompt then
		return
	end

	local available = self.keyRoot:GetAttribute("KarmaKeyAvailable") == true
	local shouldShow = available and not self.teamHasKey
	for part, initialCFrame in pairs(self.keyPartCFrames) do
		if part.Parent then
			part.Anchored = true
			if shouldShow then
				part.CFrame = initialCFrame
			end
		end
	end
	setTreeVisible(self.keyVisualState, shouldShow)
	if shouldShow then
		for instance, properties in pairs(self.keyVisualState) do
			if instance.Parent
				and instance:IsA("BasePart")
				and instance.Name ~= CONFIG.PromptPartName
				and properties.Transparency >= 1 then
				instance.Transparency = 0
			end
		end
	end
	self.keyPrompt.Enabled = shouldShow
	self.keyPrompt.ActionText = "เก็บ"
	self.keyPrompt.ObjectText = "กุญแจโต๊ะครู"
	if self.fogRoot and not self.keyRevealInProgress then
		setFogEnabled(self.fogRoot, false)
	end
end

function TeacherDeskLockService:refreshLockPrompt()
	if not self.lockPrompt then
		return
	end

	self.lockPrompt.Enabled = not self.unlocked
	self.lockPrompt.ActionText = if self.teamHasKey then "ไขกุญแจ" else "ตรวจสอบ"
	self.lockPrompt.ObjectText = "ลิ้นชักโต๊ะครู"
end

function TeacherDeskLockService:setDeskEvidenceVisible(visible: boolean)
	for _, record in pairs(self.deskEvidence) do
		setTreeVisible(record.VisualState, visible)
	end
	Workspace:SetAttribute("TeacherDeskEvidenceVisible", visible)
end

function TeacherDeskLockService:inspectPhone(player: Player)
	if not self.unlocked then
		return
	end

	playSequence(player, "phone_battery_dead")
end

function TeacherDeskLockService:setupDeskEvidence(instanceName: string, root: Instance)
	local existing = self.deskEvidence[instanceName]
	if existing and existing.Root == root then
		return true
	end

	if instanceName == CONFIG.PhoneInstanceName then
		local promptPart = getPromptPart(root)
		if not promptPart then
			warn("[TeacherDeskLockService] Phone1 needs a BasePart for its prompt")
			return false
		end

		local prompt = ensurePrompt(root, promptPart, CONFIG.PhonePromptName, nil)
		suppressOtherPrompts(root, prompt)
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = CONFIG.PhoneHoldDuration
		prompt.ActionText = "ตรวจสอบ"
		prompt.ObjectText = "โทรศัพท์"
		prompt.Triggered:Connect(function(player)
			self:inspectPhone(player)
		end)
		self.phonePrompt = prompt
	end

	local visualState = captureVisualState(root)
	local record = {
		Root = root,
		VisualState = visualState,
	}
	self.deskEvidence[instanceName] = record
	record.DescendantAddedConnection = root.DescendantAdded:Connect(function(instance)
		task.defer(function()
			if not instance:IsDescendantOf(root) then
				return
			end

			local addedState = captureVisualState(instance)
			for addedInstance, properties in pairs(addedState) do
				if record.VisualState[addedInstance] == nil then
					record.VisualState[addedInstance] = properties
				end
			end

			if not self.unlocked then
				setTreeVisible(addedState, false)
			end
		end)
	end)
	setTreeVisible(visualState, self.unlocked)
	print(("[TeacherDeskLockService] Tracking hidden evidence %s at %s"):format(
		instanceName,
		root:GetFullName()
	))
	return true
end

function TeacherDeskLockService:refreshCandlePrompts()
	for _, record in pairs(self.candles) do
		record.Prompt.Enabled = self.chadaComplete and not record.Lit
		record.Prompt.ActionText = "จุด"
		record.Prompt.ObjectText = "เทียน"
	end
end

function TeacherDeskLockService:getLitCandleCount()
	local count = 0
	for _, record in pairs(self.candles) do
		if record.Lit then
			count += 1
		end
	end
	return count
end

function TeacherDeskLockService:lightCandle(player: Player, record)
	if not self.chadaComplete or record.Lit then
		return
	end

	if not self.teamHasLighter then
		playSequence(player, "chada_complete_need_lighter")
		upsertObjective(player, "find_lighter_for_candles")
		return
	end

	record.Lit = true
	setTreeVisible(record.VisualState, true)
	record.Prompt.Enabled = false

	local litCount = self:getLitCandleCount()
	Workspace:SetAttribute("LitCandleCount", litCount)
	if litCount >= #CONFIG.CandleNames then
		removeInventoryItem(self.lighterOwner or player, CONFIG.LighterDefinitionId)
		self.teamHasLighter = false
		self.lighterOwner = nil
		Workspace:SetAttribute("TeamHasLighter", false)
		self:playKeyRevealEffect()
	else
		upsertObjectiveForTeam("light_remaining_candle")
	end
end

function TeacherDeskLockService:setupCandle(candleName: string, root: Instance)
	local flame = root:FindFirstChild(CONFIG.FlamePartName, true)
	if not flame or not flame:IsA("BasePart") then
		return false
	end

	local visualState = captureVisualState(flame)
	setTreeVisible(visualState, false)
	local prompt = ensurePrompt(root, flame, "CandleIgnitionPrompt", nil)
	suppressOtherPrompts(root, prompt)

	local record = {
		Root = root,
		Flame = flame,
		Prompt = prompt,
		VisualState = visualState,
		Lit = false,
	}
	self.candles[candleName] = record
	prompt.Triggered:Connect(function(player)
		self:lightCandle(player, record)
	end)
	self:refreshCandlePrompts()
	return true
end

function TeacherDeskLockService:beginCandleQuest(player: Player?)
	if self.chadaComplete then
		return
	end

	self.chadaComplete = true
	Workspace:SetAttribute("ChadaComplete", true)
	self:refreshCandlePrompts()
	if player and player:IsA("Player") then
		playSequence(player, "chada_complete_need_lighter")
	else
		upsertObjectiveForTeam("find_lighter_for_candles")
	end
end

function TeacherDeskLockService:onLighterPickedUp(player: Player)
	self.teamHasLighter = true
	self.lighterOwner = player
	Workspace:SetAttribute("TeamHasLighter", true)
	if self.chadaComplete then
		upsertObjectiveForTeam("return_to_light_candles")
	end
	self:refreshCandlePrompts()
end

function TeacherDeskLockService:grantKey(player: Player, playPickupFeedback: boolean?)
	if not player or player.Parent ~= Players then
		return false, "Invalid player"
	end
	if self.teamHasKey then
		return false, "Teacher desk key already collected"
	end

	self.teamHasKey = true
	setTeamKeyAttribute(true)
	self:refreshKey()
	self:refreshLockPrompt()
	upsertObjectiveForTeam("unlock_teacher_desk")

	if playPickupFeedback then
		playSequence(player, "teacher_desk_key_collected")

		local sound = self.keyRoot and self.keyRoot:FindFirstChild("PickupSound", true)
		if sound and sound:IsA("Sound") then
			sound:Play()
		end
	end

	return true, CONFIG.KeyId
end

function TeacherDeskLockService:collectKey(player: Player)
	if self.teamHasKey or not self.keyRoot then
		return
	end
	if self.keyRoot:GetAttribute("KarmaKeyAvailable") ~= true then
		return
	end

	self:grantKey(player, true)
end

function TeacherDeskLockService:openLock(player: Player)
	if self.unlocked or self.busy then
		return
	end

	if not self.teamHasKey then
		upsertObjective(player, "find_teacher_desk_key")
		playSequence(player, "teacher_desk_locked")
		return
	end

	local target = self.openTarget
	local closedPivot = target and getPivot(target)
	if not target or not closedPivot then
		warn("[TeacherDeskLockService] OpenTarget must point to a BasePart or Model")
		return
	end

	self.busy = true
	self.unlocked = true
	Workspace:SetAttribute("TeacherDeskUnlocked", true)
	self:refreshLockPrompt()

	local sound = self.lockRoot and self.lockRoot:FindFirstChild("UnlockSound", true)
	if sound and sound:IsA("Sound") then
		sound:Play()
	end

	local configuredOffset = self.lockRoot and self.lockRoot:GetAttribute("OpenOffset")
	local openOffset = if typeof(configuredOffset) == "Vector3" then configuredOffset else CONFIG.DefaultOpenOffset
	local openPivot = closedPivot * CFrame.new(openOffset)
	local tweenInfo = TweenInfo.new(CONFIG.OpenDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	if target:IsA("BasePart") then
		local tween = TweenService:Create(target, tweenInfo, { CFrame = openPivot })
		tween:Play()
	else
		local pivotValue = Instance.new("CFrameValue")
		pivotValue.Value = closedPivot
		local connection = pivotValue:GetPropertyChangedSignal("Value"):Connect(function()
			if target.Parent then
				pivotTarget(target, pivotValue.Value)
			end
		end)
		local tween = TweenService:Create(pivotValue, tweenInfo, { Value = openPivot })
		tween.Completed:Connect(function()
			connection:Disconnect()
			pivotTarget(target, openPivot)
			pivotValue:Destroy()
		end)
		tween:Play()
	end

	task.delay(CONFIG.OpenDuration * 0.55, function()
		setTreeVisible(self.contentsVisualState, true)
		self:setDeskEvidenceVisible(true)
	end)
	task.delay(CONFIG.OpenDuration, function()
		self.busy = false
	end)

	upsertObjectiveForTeam("inspect_teacher_desk")
	playSequence(player, "teacher_desk_unlocked")
end

function TeacherDeskLockService:revealKey()
	self:trySetup()
	if not self.keyRoot then
		warn("[TeacherDeskLockService] TeacherDeskKey was not found")
		return false
	end

	self.keyRoot:SetAttribute("KarmaKeyAvailable", true)
	self:refreshKey()
	upsertObjectiveForTeam("collect_teacher_desk_key")
	print(("[TeacherDeskLockService] Revealed key at %s"):format(self.keyRoot:GetFullName()))
	return true
end

function TeacherDeskLockService:playKeyRevealEffect()
	if self.keyRevealInProgress or self.teamHasKey then
		return false
	end

	self:trySetup()
	self.keyRevealInProgress = true
	if self.fogRoot then
		setFogEnabled(self.fogRoot, true)
	else
		warn("[TeacherDeskLockService] Fog effect was not found in Workspace")
	end

	task.delay(CONFIG.FogDuration, function()
		setFogEnabled(self.fogRoot, false)
		self.keyRevealInProgress = false
		self:revealKey()
		setFogEnabled(self.fogRoot, false)
	end)
	return true
end

function TeacherDeskLockService:recordChadaPlacement(player: Player?, zone: Instance?)
	if typeof(zone) ~= "Instance" or not zone:IsDescendantOf(Workspace) then
		warn("[TeacherDeskLockService] RecordChadaPlacement requires a zone inside Workspace")
		return false
	end
	if self.placedChadaZones[zone] then
		return false
	end

	self.placedChadaZones[zone] = true
	local placedCount = 0
	for _ in pairs(self.placedChadaZones) do
		placedCount += 1
	end
	Workspace:SetAttribute("PlacedChadaCount", placedCount)

	if placedCount >= CONFIG.RequiredChadaPlacements then
		self:beginCandleQuest(player)
	else
		upsertObjectiveForTeam("place_remaining_chada")
	end

	print(("[TeacherDeskLockService] Chada placed %d/%d by %s"):format(
		placedCount,
		CONFIG.RequiredChadaPlacements,
		if player and player:IsA("Player") then player.Name else "Unknown"
	))
	return true
end

function TeacherDeskLockService:setupKey(root: Instance)
	local promptPart = getPromptPart(root)
	if not promptPart then
		return false
	end

	self.keyRoot = root
	self.keyVisualState = captureVisualState(root)
	table.clear(self.keyPartCFrames)
	for _, instance in ipairs(allInstances(root)) do
		if instance:IsA("BasePart") then
			self.keyPartCFrames[instance] = instance.CFrame
			instance.Anchored = true
		end
	end
	self.keyPrompt = ensurePrompt(root, promptPart, "TeacherDeskKeyPrompt", nil)
	suppressOtherPrompts(root, self.keyPrompt)
	self.keyPrompt.Triggered:Connect(function(player)
		self:collectKey(player)
	end)
	root:GetAttributeChangedSignal("KarmaKeyAvailable"):Connect(function()
		self:refreshKey()
	end)
	local placedCount = Workspace:GetAttribute("PlacedChadaCount")
	if typeof(placedCount) == "number" and placedCount >= CONFIG.RequiredChadaPlacements then
		root:SetAttribute("KarmaKeyAvailable", true)
	else
		root:SetAttribute("KarmaKeyAvailable", false)
	end
	self:refreshKey()
	return true
end

function TeacherDeskLockService:setupLock(root: Instance)
	local promptPart = getPromptPart(root)
	if not promptPart then
		return false
	end

	local targetReference = root:FindFirstChild(CONFIG.OpenTargetValueName, true)
	local openTarget = if targetReference and targetReference:IsA("ObjectValue") then targetReference.Value else nil
	if not openTarget then
		openTarget = root:FindFirstChild("Drawer", true) or root
	end
	if not openTarget:IsA("BasePart") and not openTarget:IsA("Model") then
		return false
	end

	self.lockRoot = root
	self.openTarget = openTarget
	self.contentsRoot = root:FindFirstChild(CONFIG.ContentsName, true)
	if self.contentsRoot then
		self.contentsVisualState = captureVisualState(self.contentsRoot)
		setTreeVisible(self.contentsVisualState, false)
	end

	self.lockPrompt = ensurePrompt(root, promptPart, "TeacherDeskLockPrompt", self.contentsRoot)
	suppressOtherPrompts(root, self.lockPrompt)
	self.lockPrompt.Triggered:Connect(function(player)
		self:openLock(player)
	end)
	self:refreshLockPrompt()
	return true
end

function TeacherDeskLockService:trySetup()
	if not self.keyRoot then
		local keyRoot = Workspace:FindFirstChild(CONFIG.KeyInstanceName, true)
		if keyRoot then
			self:setupKey(keyRoot)
		end
	end

	for _, instanceName in ipairs(CONFIG.DeskEvidenceNames) do
		local record = self.deskEvidence[instanceName]
		if not record or not record.Root.Parent then
			self.deskEvidence[instanceName] = nil
			local root = findDeskEvidenceRoot(instanceName)
			if root then
				self:setupDeskEvidence(instanceName, root)
			end
		end
	end

	if not self.lockRoot then
		local lockRoot = Workspace:FindFirstChild(CONFIG.LockInstanceName, true)
		if lockRoot then
			self:setupLock(lockRoot)
		end
	end

	if not self.fogRoot then
		local fogRoot = if self.keyRoot then self.keyRoot:FindFirstChild(CONFIG.FogInstanceName, true) else nil
		fogRoot = fogRoot or Workspace:FindFirstChild(CONFIG.FogInstanceName, true)
		if fogRoot then
			self.fogRoot = fogRoot
			setFogEnabled(self.fogRoot, false)
		end
	end

	for _, candleName in ipairs(CONFIG.CandleNames) do
		if not self.candles[candleName] then
			local candleRoot = Workspace:FindFirstChild(candleName, true)
			if candleRoot then
				self:setupCandle(candleName, candleRoot)
			end
		end
	end
end

function TeacherDeskLockService:createServerApi()
	local folder = ServerStorage:FindFirstChild(CONFIG.ApiFolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = CONFIG.ApiFolderName
		folder.Parent = ServerStorage
	end

	local revealKey = folder:FindFirstChild("RevealKey")
	if not revealKey then
		revealKey = Instance.new("BindableEvent")
		revealKey.Name = "RevealKey"
		revealKey.Parent = folder
	end
	if not revealKey:IsA("BindableEvent") then
		error("[TeacherDeskLockService] RevealKey must be a BindableEvent")
	end

	local grantKey = folder:FindFirstChild("GrantKey")
	if not grantKey then
		grantKey = Instance.new("BindableFunction")
		grantKey.Name = "GrantKey"
		grantKey.Parent = folder
	end
	if not grantKey:IsA("BindableFunction") then
		error("[TeacherDeskLockService] GrantKey must be a BindableFunction")
	end

	local recordChadaPlacement = folder:FindFirstChild("RecordChadaPlacement")
	if not recordChadaPlacement then
		recordChadaPlacement = Instance.new("BindableEvent")
		recordChadaPlacement.Name = "RecordChadaPlacement"
		recordChadaPlacement.Parent = folder
	end
	if not recordChadaPlacement:IsA("BindableEvent") then
		error("[TeacherDeskLockService] RecordChadaPlacement must be a BindableEvent")
	end

	revealKey.Event:Connect(function(keyId)
		if keyId ~= nil and keyId ~= CONFIG.KeyId then
			return
		end
		self:revealKey()
	end)

	grantKey.OnInvoke = function(player)
		return self:grantKey(player, false)
	end

	recordChadaPlacement.Event:Connect(function(player, zone)
		self:recordChadaPlacement(player, zone)
	end)
end

function TeacherDeskLockService:connectCutscenePlacementEvent()
	task.spawn(function()
		while not self.cutscenePlacementConnection do
			local folder = ServerStorage:FindFirstChild("CutsceneEvents")
			local recordPlacement = folder and folder:FindFirstChild("RecordPlacement")
			if recordPlacement and recordPlacement:IsA("BindableEvent") then
				self.cutscenePlacementConnection = recordPlacement.Event:Connect(function(player, placedTool)
					if typeof(placedTool) ~= "Instance" or placedTool.Name ~= CONFIG.ChadaDefinitionId then
						return
					end
					self:recordChadaPlacement(player, placedTool)
				end)
				break
			end
			task.wait(0.5)
		end
	end)
end

function TeacherDeskLockService:connectInventoryPlacementEvent()
	task.spawn(function()
		while not self.inventoryPlacementConnection do
			local folder = ServerStorage:FindFirstChild("InventoryServerApi")
			local questItemPlaced = folder and folder:FindFirstChild("QuestItemPlaced")
			if questItemPlaced and questItemPlaced:IsA("BindableEvent") then
				self.inventoryPlacementConnection = questItemPlaced.Event:Connect(function(
					player,
					definitionId,
					_,
					placedTool
				)
					if definitionId ~= CONFIG.ChadaDefinitionId or typeof(placedTool) ~= "Instance" then
						return
					end
					self:recordChadaPlacement(player, placedTool)
				end)
				break
			end
			task.wait(0.5)
		end
	end)
end

function TeacherDeskLockService:connectInventoryPickupEvent()
	task.spawn(function()
		while not self.inventoryPickupConnection do
			local folder = ServerStorage:FindFirstChild("InventoryServerApi")
			local itemPickedUp = folder and folder:FindFirstChild("ItemPickedUp")
			if itemPickedUp and itemPickedUp:IsA("BindableEvent") then
				self.inventoryPickupConnection = itemPickedUp.Event:Connect(function(player, definitionId)
					if definitionId == CONFIG.LighterDefinitionId and player and player:IsA("Player") then
						self:onLighterPickedUp(player)
					end
				end)
				break
			end
			task.wait(0.5)
		end
	end)
end

function TeacherDeskLockService:Init()
	self:createServerApi()
end

function TeacherDeskLockService:Start()
	self.teamHasKey = false
	self.unlocked = false
	self.keyRevealInProgress = false
	self.chadaComplete = false
	self.teamHasLighter = false
	self.lighterOwner = nil
	self.phonePrompt = nil
	table.clear(self.candles)
	table.clear(self.placedChadaZones)
	table.clear(self.deskEvidence)
	Workspace:SetAttribute("TeacherDeskUnlocked", false)
	Workspace:SetAttribute("TeacherDeskEvidenceVisible", false)
	Workspace:SetAttribute("PlacedChadaCount", 0)
	Workspace:SetAttribute("LitCandleCount", 0)
	Workspace:SetAttribute("ChadaComplete", false)
	Workspace:SetAttribute("TeamHasLighter", false)
	setTeamKeyAttribute(false)
	self:trySetup()
	self:connectCutscenePlacementEvent()
	self:connectInventoryPlacementEvent()
	self:connectInventoryPickupEvent()

	Workspace.DescendantAdded:Connect(function()
		task.defer(function()
			self:trySetup()
		end)
	end)

	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute("HasTeacherDeskKey", self.teamHasKey)
	end)
end

return TeacherDeskLockService
