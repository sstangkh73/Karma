-- LightingGuard
-- Night lighting preset for Realistic/Future lighting.
-- Place this Script in ServerScriptService when syncing with Rojo.

local Lighting = game:GetService("Lighting")

local CONFIG = {
	DEBUG = true,

	-- 3 AM is almost no natural light in Realistic lighting. Use late evening
	-- for a night mood that still leaves enough scene detail to play.
	CLOCK_TIME = 18.7,
	BRIGHTNESS = 4,
	EXPOSURE_COMPENSATION = 0.25,

	AMBIENT = Color3.fromRGB(45, 48, 64),
	OUTDOOR_AMBIENT = Color3.fromRGB(70, 76, 96),
	ENVIRONMENT_DIFFUSE_SCALE = 0.55,
	ENVIRONMENT_SPECULAR_SCALE = 0.35,

	FOG_START = 120,
	FOG_END = 520,
	FOG_COLOR = Color3.fromRGB(82, 94, 122),

	COLOR_TINT = Color3.fromRGB(195, 210, 255),
	COLOR_BRIGHTNESS = 0.08,
	COLOR_CONTRAST = 0.18,
	COLOR_SATURATION = -0.1,

	ATMOSPHERE_DENSITY = 0.18,
	ATMOSPHERE_OFFSET = 0.12,
	ATMOSPHERE_COLOR = Color3.fromRGB(135, 150, 190),
	ATMOSPHERE_DECAY = Color3.fromRGB(45, 48, 70),

	BLOOM_INTENSITY = 0.12,
	BLOOM_SIZE = 18,
	BLOOM_THRESHOLD = 2.4,

	SKYBOX_ID = "rbxassetid://13943307",
}

local applying = false

local function getOrCreate(className: string): Instance
	local existing = Lighting:FindFirstChildOfClass(className)
	if existing then
		return existing
	end

	local created = Instance.new(className)
	created.Parent = Lighting
	return created
end

local function applyPreset(reason: string)
	if applying then
		return
	end

	applying = true

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

	local color = getOrCreate("ColorCorrectionEffect") :: ColorCorrectionEffect
	color.TintColor = CONFIG.COLOR_TINT
	color.Brightness = CONFIG.COLOR_BRIGHTNESS
	color.Contrast = CONFIG.COLOR_CONTRAST
	color.Saturation = CONFIG.COLOR_SATURATION

	local atmosphere = getOrCreate("Atmosphere") :: Atmosphere
	atmosphere.Density = CONFIG.ATMOSPHERE_DENSITY
	atmosphere.Offset = CONFIG.ATMOSPHERE_OFFSET
	atmosphere.Color = CONFIG.ATMOSPHERE_COLOR
	atmosphere.Decay = CONFIG.ATMOSPHERE_DECAY

	local bloom = getOrCreate("BloomEffect") :: BloomEffect
	bloom.Intensity = CONFIG.BLOOM_INTENSITY
	bloom.Size = CONFIG.BLOOM_SIZE
	bloom.Threshold = CONFIG.BLOOM_THRESHOLD

	local sky = getOrCreate("Sky") :: Sky
	sky.SkyboxBk = CONFIG.SKYBOX_ID
	sky.SkyboxDn = CONFIG.SKYBOX_ID
	sky.SkyboxFt = CONFIG.SKYBOX_ID
	sky.SkyboxLf = CONFIG.SKYBOX_ID
	sky.SkyboxRt = CONFIG.SKYBOX_ID
	sky.SkyboxUp = CONFIG.SKYBOX_ID

	if CONFIG.DEBUG then
		print(("[LightingGuard] Applied Realistic night preset: %s"):format(reason))
	end

	applying = false
end

applyPreset("startup")

local watchedProperties = {
	"ClockTime",
	"TimeOfDay",
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

for _, propertyName in ipairs(watchedProperties) do
	Lighting:GetPropertyChangedSignal(propertyName):Connect(function()
		if not applying then
			if CONFIG.DEBUG then
				warn(("[LightingGuard] Lighting.%s changed; restoring preset"):format(propertyName))
			end

			applyPreset(("Lighting.%s changed"):format(propertyName))
		end
	end)
end

Lighting.ChildAdded:Connect(function(child)
	if child:IsA("ColorCorrectionEffect")
		or child:IsA("Atmosphere")
		or child:IsA("BloomEffect")
		or child:IsA("Sky")
	then
		applyPreset(("%s added"):format(child.ClassName))
	end
end)
