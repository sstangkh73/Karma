-- Run in Roblox Studio's Command Bar while editing the place.
-- Applies the same temporary dark/fog mood used by LightingGuard so cutscene
-- camera angles can be framed without entering Play mode.

local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")

local BACKUP_NAME = "CutsceneEditLighting_Backup"

local CONFIG = {
	CLOCK_TIME = 18.7,
	BRIGHTNESS = 4,
	EXPOSURE_COMPENSATION = 0.25,

	AMBIENT = Color3.fromRGB(45, 48, 64),
	OUTDOOR_AMBIENT = Color3.fromRGB(70, 76, 96),
	ENVIRONMENT_DIFFUSE_SCALE = 0.55,
	ENVIRONMENT_SPECULAR_SCALE = 0.35,

	FOG_START = 50,
	FOG_END = 120,
	FOG_COLOR = Color3.fromRGB(0, 0, 0),

	COLOR_TINT = Color3.fromRGB(195, 210, 255),
	COLOR_BRIGHTNESS = 0.08,
	COLOR_CONTRAST = 0.18,
	COLOR_SATURATION = -0.1,

	BLOOM_INTENSITY = 0.12,
	BLOOM_SIZE = 18,
	BLOOM_THRESHOLD = 2.4,

	SKYBOX_ID = "rbxassetid://13943307",
}

local LIGHTING_PROPERTIES = {
	"ClockTime",
	"Brightness",
	"ExposureCompensation",
	"Ambient",
	"OutdoorAmbient",
	"EnvironmentDiffuseScale",
	"EnvironmentSpecularScale",
	"FogStart",
	"FogEnd",
	"FogColor",
}

local EFFECT_CLASSES = {
	Atmosphere = true,
	ColorCorrectionEffect = true,
	BloomEffect = true,
	Sky = true,
}

local function getOrCreateBackup(): Folder
	local existing = ServerStorage:FindFirstChild(BACKUP_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local backup = Instance.new("Folder")
	backup.Name = BACKUP_NAME
	backup.Parent = ServerStorage
	return backup
end

local function snapshotLighting(backup: Folder)
	if backup:GetAttribute("HasSnapshot") then
		return
	end

	for _, propertyName in ipairs(LIGHTING_PROPERTIES) do
		backup:SetAttribute(propertyName, Lighting[propertyName])
	end

	local effects = Instance.new("Folder")
	effects.Name = "Effects"
	effects.Parent = backup

	for _, child in ipairs(Lighting:GetChildren()) do
		if EFFECT_CLASSES[child.ClassName] then
			child:Clone().Parent = effects
		end
	end

	backup:SetAttribute("HasSnapshot", true)
end

local function clearLightingEffects()
	for _, child in ipairs(Lighting:GetChildren()) do
		if EFFECT_CLASSES[child.ClassName] then
			child:Destroy()
		end
	end
end

local function applyPreset()
	Lighting.ClockTime = CONFIG.CLOCK_TIME
	Lighting.Brightness = CONFIG.BRIGHTNESS
	Lighting.ExposureCompensation = CONFIG.EXPOSURE_COMPENSATION
	Lighting.Ambient = CONFIG.AMBIENT
	Lighting.OutdoorAmbient = CONFIG.OUTDOOR_AMBIENT
	Lighting.EnvironmentDiffuseScale = CONFIG.ENVIRONMENT_DIFFUSE_SCALE
	Lighting.EnvironmentSpecularScale = CONFIG.ENVIRONMENT_SPECULAR_SCALE

	Lighting.FogStart = CONFIG.FOG_START
	Lighting.FogEnd = CONFIG.FOG_END
	Lighting.FogColor = CONFIG.FOG_COLOR

	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "CutsceneEdit_ColorCorrection"
	color.TintColor = CONFIG.COLOR_TINT
	color.Brightness = CONFIG.COLOR_BRIGHTNESS
	color.Contrast = CONFIG.COLOR_CONTRAST
	color.Saturation = CONFIG.COLOR_SATURATION
	color.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "CutsceneEdit_Bloom"
	bloom.Intensity = CONFIG.BLOOM_INTENSITY
	bloom.Size = CONFIG.BLOOM_SIZE
	bloom.Threshold = CONFIG.BLOOM_THRESHOLD
	bloom.Parent = Lighting

	local sky = Instance.new("Sky")
	sky.Name = "CutsceneEdit_Sky"
	sky.SkyboxBk = CONFIG.SKYBOX_ID
	sky.SkyboxDn = CONFIG.SKYBOX_ID
	sky.SkyboxFt = CONFIG.SKYBOX_ID
	sky.SkyboxLf = CONFIG.SKYBOX_ID
	sky.SkyboxRt = CONFIG.SKYBOX_ID
	sky.SkyboxUp = CONFIG.SKYBOX_ID
	sky.Parent = Lighting
end

local backup = getOrCreateBackup()
snapshotLighting(backup)
clearLightingEffects()
applyPreset()

print(("[CutsceneEditLighting] Applied temporary edit-mode fog/darkness. Run RestoreCutsceneEditLighting.command.luau to return the previous Lighting snapshot. fog=%.1f-%.1f"):format(
	CONFIG.FOG_START,
	CONFIG.FOG_END
))
