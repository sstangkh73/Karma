-- SprintSystem
-- Hold Shift to sprint, drain stamina while sprinting,
-- regenerate stamina when stopping, and hide the bar when full.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local SystemHub = require(Core:WaitForChild("SystemHub"))

if not SystemHub.begin("SprintSystem", script) then
	return
end

local SprintSystem = {}
SprintSystem.RENDER_STEP_NAME = "SprintSystemCameraEffects"

SprintSystem.player = Players.LocalPlayer
SprintSystem.CONFIG = {
	SPRINT_KEY = Enum.KeyCode.LeftShift,
	WALK_SPEED = 14,
	SPRINT_SPEED = 20,
	MAX_STAMINA = 100,
	DRAIN_RATE = 20,
	REGEN_RATE = 15,
	STATIONARY_REGEN_MULTIPLIER = 1.3,
	EXHAUSTED_UNLOCK_RATIO = 0.5,
	POST_UNLOCK_REGEN_MULTIPLIER = 0.7,
	LOW_STAMINA_COLOR_START_RATIO = 0.5,
	HIGH_STAMINA_COLOR = Color3.new(1, 1, 1),
	LOW_STAMINA_COLOR = Color3.fromRGB(255, 0, 0),
	BAR_HEIGHT = 3,
	BAR_FADE_TIME = 0.2,
	MOVE_THRESHOLD = 0.1,
	SPRINT_FOV_BOOST = 5,
	FOV_TWEEN_TIME = 0.18,
	CAMERA_SHAKE = {
		LOW_STAMINA_START_RATIO = 0.5,
		MAX_PITCH_DEGREES = 0.18,
		MAX_ROLL_DEGREES = 0.3,
		PITCH_FREQUENCY = 18,
		ROLL_FREQUENCY = 24,
	},
	SOUND = {
		ENABLED = false,
		MASTER_VOLUME = 1,
		PLAYBACK_SPEED = 1,
		SPRINT_LOOP = {
			SOUND_ID = "",
			VOLUME = 0.3,
			LOOPED = true,
		},
		LOW_STAMINA_LOOP = {
			SOUND_ID = "",
			VOLUME = 0.25,
			LOOPED = true,
		},
		EXHAUSTED = {
			SOUND_ID = "",
			VOLUME = 0.4,
			LOOPED = false,
		},
	},
}

SprintSystem.state = {
	stamina = SprintSystem.CONFIG.MAX_STAMINA,
	isSprinting = false,
	shiftHeld = false,
	isExhausted = false,
	barShowing = false,
	fadeTween = nil,
	fieldOfViewTween = nil,
	defaultFieldOfView = nil,
	currentFovTarget = nil,
	activeCamera = nil,
	isSprintFovApplied = false,
	cameraShakeTime = 0,
	wasExhausted = false,
}

SprintSystem.ui = {}
SprintSystem.audio = {
	folder = nil,
	sounds = {},
}

function SprintSystem:createUi()
	local playerGui = self.player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SprintBarGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 50
	screenGui.Parent = playerGui

	local barBg = Instance.new("CanvasGroup")
	barBg.Name = "StaminaBarBg"
	barBg.Size = UDim2.new(1, 0, 0, self.CONFIG.BAR_HEIGHT)
	barBg.Position = UDim2.new(0, 0, 1, -self.CONFIG.BAR_HEIGHT)
	barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	barBg.BackgroundTransparency = 0.6
	barBg.BorderSizePixel = 0
	barBg.ZIndex = 90
	barBg.GroupTransparency = 1
	barBg.Parent = screenGui

	local barFill = Instance.new("Frame")
	barFill.Name = "StaminaBarFill"
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.Position = UDim2.new(0, 0, 0, 0)
	barFill.BackgroundColor3 = self.CONFIG.HIGH_STAMINA_COLOR
	barFill.BackgroundTransparency = 0.1
	barFill.BorderSizePixel = 0
	barFill.ZIndex = 91
	barFill.Parent = barBg

	self.ui.screenGui = screenGui
	self.ui.barBg = barBg
	self.ui.barFill = barFill
end

function SprintSystem:getCamera(): Camera?
	return workspace.CurrentCamera
end

function SprintSystem:createSound(name: string, soundConfig)
	if not self.CONFIG.SOUND.ENABLED then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundConfig.SOUND_ID or ""
	sound.Looped = soundConfig.LOOPED == true
	sound.Volume = (soundConfig.VOLUME or 1) * self.CONFIG.SOUND.MASTER_VOLUME
	sound.PlaybackSpeed = soundConfig.PLAYBACK_SPEED or self.CONFIG.SOUND.PLAYBACK_SPEED
	sound.Parent = self.audio.folder
	return sound
end

function SprintSystem:createAudio()
	if not self.CONFIG.SOUND.ENABLED then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "SprintSystemAudio"
	folder.Parent = SoundService

	self.audio.folder = folder
	self.audio.sounds.sprintLoop = self:createSound("SprintLoop", self.CONFIG.SOUND.SPRINT_LOOP)
	self.audio.sounds.lowStaminaLoop = self:createSound("LowStaminaLoop", self.CONFIG.SOUND.LOW_STAMINA_LOOP)
	self.audio.sounds.exhausted = self:createSound("Exhausted", self.CONFIG.SOUND.EXHAUSTED)
end

function SprintSystem:getUnlockStamina(): number
	return self.CONFIG.MAX_STAMINA * self.CONFIG.EXHAUSTED_UNLOCK_RATIO
end

function SprintSystem:setWalkSpeed(humanoid: Humanoid, speed: number)
	if humanoid.WalkSpeed ~= speed then
		humanoid.WalkSpeed = speed
	end
end

function SprintSystem:setBarShown(shouldShow: boolean, instant: boolean?)
	if self.state.barShowing == shouldShow and not instant then
		return
	end

	self.state.barShowing = shouldShow

	if self.state.fadeTween then
		self.state.fadeTween:Cancel()
		self.state.fadeTween = nil
	end

	local targetTransparency = shouldShow and 0 or 1
	if instant then
		self.ui.barBg.GroupTransparency = targetTransparency
		return
	end

	local tween = TweenService:Create(self.ui.barBg, TweenInfo.new(self.CONFIG.BAR_FADE_TIME), {
		GroupTransparency = targetTransparency,
	})
	self.state.fadeTween = tween
	tween.Completed:Once(function()
		if self.state.fadeTween == tween then
			self.state.fadeTween = nil
		end
	end)
	tween:Play()
end

function SprintSystem:showBar()
	self:setBarShown(true)
end

function SprintSystem:hideBar(instant: boolean?)
	self:setBarShown(false, instant)
end

function SprintSystem:getBarColor(ratio: number): Color3
	if ratio > self.CONFIG.LOW_STAMINA_COLOR_START_RATIO then
		return self.CONFIG.HIGH_STAMINA_COLOR
	end

	local colorT = math.clamp(ratio / self.CONFIG.LOW_STAMINA_COLOR_START_RATIO, 0, 1)
	return self.CONFIG.LOW_STAMINA_COLOR:Lerp(self.CONFIG.HIGH_STAMINA_COLOR, colorT)
end

function SprintSystem:getRegenRate(ratio: number, isMoving: boolean): number
	local regenRate = self.CONFIG.REGEN_RATE

	if not isMoving then
		regenRate *= self.CONFIG.STATIONARY_REGEN_MULTIPLIER
	end

	if ratio >= self.CONFIG.EXHAUSTED_UNLOCK_RATIO then
		regenRate *= self.CONFIG.POST_UNLOCK_REGEN_MULTIPLIER
	end

	return regenRate
end

function SprintSystem:getCameraShakeAlpha(): number
	local staminaRatio = self.state.stamina / self.CONFIG.MAX_STAMINA
	local shakeStartRatio = self.CONFIG.CAMERA_SHAKE.LOW_STAMINA_START_RATIO

	if not self.state.isSprinting or staminaRatio > shakeStartRatio then
		return 0
	end

	return math.clamp((shakeStartRatio - staminaRatio) / shakeStartRatio, 0, 1)
end

function SprintSystem:updateCameraEffects(dt: number)
	local camera = self:getCamera()
	if not camera then
		return
	end

	local shakeAlpha = self:getCameraShakeAlpha()
	if shakeAlpha <= 0 then
		self.state.cameraShakeTime = 0
		return
	end

	self.state.cameraShakeTime += dt

	local pitch = math.rad(
		math.sin(self.state.cameraShakeTime * self.CONFIG.CAMERA_SHAKE.PITCH_FREQUENCY)
			* self.CONFIG.CAMERA_SHAKE.MAX_PITCH_DEGREES
			* shakeAlpha
	)
	local roll = math.rad(
		math.cos(self.state.cameraShakeTime * self.CONFIG.CAMERA_SHAKE.ROLL_FREQUENCY)
			* self.CONFIG.CAMERA_SHAKE.MAX_ROLL_DEGREES
			* shakeAlpha
	)

	camera.CFrame = camera.CFrame * CFrame.Angles(pitch, 0, roll)
end

function SprintSystem:playSound(sound: Sound?, restart: boolean?)
	if not sound or sound.SoundId == "" then
		return
	end

	if restart then
		sound:Stop()
		sound.TimePosition = 0
	end

	if not sound.IsPlaying then
		sound:Play()
	end
end

function SprintSystem:stopSound(sound: Sound?)
	if sound and sound.IsPlaying then
		sound:Stop()
	end
end

function SprintSystem:updateAudio(staminaRatio: number)
	if not self.CONFIG.SOUND.ENABLED then
		self.state.wasExhausted = self.state.isExhausted
		return
	end

	local sprintLoop = self.audio.sounds.sprintLoop
	local lowStaminaLoop = self.audio.sounds.lowStaminaLoop
	local exhaustedSound = self.audio.sounds.exhausted

	if self.state.isSprinting then
		self:playSound(sprintLoop)
	else
		self:stopSound(sprintLoop)
	end

	if self.state.isSprinting and staminaRatio <= self.CONFIG.CAMERA_SHAKE.LOW_STAMINA_START_RATIO then
		self:playSound(lowStaminaLoop)
	else
		self:stopSound(lowStaminaLoop)
	end

	if self.state.isExhausted and not self.state.wasExhausted then
		self:playSound(exhaustedSound, true)
	end

	self.state.wasExhausted = self.state.isExhausted
end

function SprintSystem:setSprintFieldOfView(shouldUseSprintFov: boolean, instant: boolean?)
	local camera = self:getCamera()
	if not camera then
		return
	end

	if camera ~= self.state.activeCamera then
		self.state.activeCamera = camera
		self.state.defaultFieldOfView = camera.FieldOfView
		self.state.currentFovTarget = nil
		self.state.isSprintFovApplied = false
	end

	-- Only refresh the baseline FOV while fully at rest.
	-- If we update it during the return tween, the boosted value can become the new baseline.
	if not shouldUseSprintFov and not self.state.isSprintFovApplied and not self.state.fieldOfViewTween then
		self.state.defaultFieldOfView = camera.FieldOfView
	end

	local baseFieldOfView = self.state.defaultFieldOfView or camera.FieldOfView
	local targetFov = shouldUseSprintFov and (baseFieldOfView + self.CONFIG.SPRINT_FOV_BOOST) or baseFieldOfView

	if self.state.currentFovTarget == targetFov and not instant then
		return
	end

	self.state.currentFovTarget = targetFov
	self.state.isSprintFovApplied = shouldUseSprintFov

	if self.state.fieldOfViewTween then
		self.state.fieldOfViewTween:Cancel()
		self.state.fieldOfViewTween = nil
	end

	if instant then
		camera.FieldOfView = targetFov
		if not shouldUseSprintFov then
			self.state.defaultFieldOfView = targetFov
		end
		return
	end

	local tween = TweenService:Create(camera, TweenInfo.new(self.CONFIG.FOV_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = targetFov,
	})
	self.state.fieldOfViewTween = tween
	tween.Completed:Once(function(playbackState)
		if self.state.fieldOfViewTween == tween then
			self.state.fieldOfViewTween = nil
		end

		if playbackState == Enum.PlaybackState.Completed and not shouldUseSprintFov and self.state.currentFovTarget == targetFov then
			self.state.defaultFieldOfView = camera.FieldOfView
		end
	end)
	tween:Play()
end

function SprintSystem:updateUi()
	local ratio = math.clamp(self.state.stamina / self.CONFIG.MAX_STAMINA, 0, 1)
	self.ui.barFill.Size = UDim2.new(ratio, 0, 1, 0)
	self.ui.barFill.BackgroundColor3 = self:getBarColor(ratio)

	if self.state.isSprinting then
		self:showBar()
	else
		self:hideBar()
	end
end

function SprintSystem:resetState()
	self.state.stamina = self.CONFIG.MAX_STAMINA
	self.state.isSprinting = false
	self.state.shiftHeld = false
	self.state.isExhausted = false
	self.state.defaultFieldOfView = nil
	self.state.currentFovTarget = nil
	self.state.activeCamera = nil
	self.state.isSprintFovApplied = false
	self.state.cameraShakeTime = 0
	self.state.wasExhausted = false
	self:updateUi()
	self:hideBar(true)
	self:setSprintFieldOfView(false, true)
	self:updateAudio(1)
end

function SprintSystem:onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	if input.KeyCode == self.CONFIG.SPRINT_KEY then
		self.state.shiftHeld = true
	end
end

function SprintSystem:onInputEnded(input: InputObject)
	if input.KeyCode == self.CONFIG.SPRINT_KEY then
		self.state.shiftHeld = false
	end
end

function SprintSystem:update(dt: number)
	local character = self.player.Character
	if not character then
		self.state.isSprinting = false
		self:updateUi()
		self:setSprintFieldOfView(false)
		self:updateAudio(math.clamp(self.state.stamina / self.CONFIG.MAX_STAMINA, 0, 1))
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		self.state.isSprinting = false
		self:updateUi()
		self:setSprintFieldOfView(false)
		self:updateAudio(math.clamp(self.state.stamina / self.CONFIG.MAX_STAMINA, 0, 1))
		return
	end

	local isMoving = humanoid.MoveDirection.Magnitude > self.CONFIG.MOVE_THRESHOLD
	local unlockStamina = self:getUnlockStamina()

	if self.state.isExhausted and self.state.stamina >= unlockStamina then
		self.state.isExhausted = false
	end

	local canSprint = self.state.stamina > 0 and not self.state.isExhausted
	local wantSprint = self.state.shiftHeld and isMoving and canSprint

	if wantSprint then
		self.state.isSprinting = true
		self:setWalkSpeed(humanoid, self.CONFIG.SPRINT_SPEED)
		self.state.stamina = math.max(0, self.state.stamina - (self.CONFIG.DRAIN_RATE * dt))

		if self.state.stamina <= 0 then
			self.state.isExhausted = true
			self.state.isSprinting = false
			self:setWalkSpeed(humanoid, self.CONFIG.WALK_SPEED)
		end
	else
		if self.state.isSprinting then
			self:setWalkSpeed(humanoid, self.CONFIG.WALK_SPEED)
		end
		self.state.isSprinting = false

		if self.state.stamina < self.CONFIG.MAX_STAMINA then
			local staminaRatio = self.state.stamina / self.CONFIG.MAX_STAMINA
			local regenRate = self:getRegenRate(staminaRatio, isMoving)
			self.state.stamina = math.min(self.CONFIG.MAX_STAMINA, self.state.stamina + (regenRate * dt))
		end
	end

	local staminaRatio = math.clamp(self.state.stamina / self.CONFIG.MAX_STAMINA, 0, 1)
	self:updateUi()
	self:setSprintFieldOfView(self.state.isSprinting)
	self:updateAudio(staminaRatio)
end

function SprintSystem:bind()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		self:onInputBegan(input, gameProcessed)
	end)

	UserInputService.InputEnded:Connect(function(input)
		self:onInputEnded(input)
	end)

	RunService.Heartbeat:Connect(function(dt)
		self:update(dt)
	end)

	RunService:UnbindFromRenderStep(self.RENDER_STEP_NAME)
	RunService:BindToRenderStep(self.RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
		self:updateCameraEffects(dt)
	end)

	self.player.CharacterAdded:Connect(function()
		self:resetState()
	end)
end

function SprintSystem:start()
	self:createUi()
	self:createAudio()
	self:resetState()
	self:bind()
	print("[SprintSystem] Ready - hold Shift to sprint")
end

SprintSystem:start()
SystemHub.ready("SprintSystem", script)
