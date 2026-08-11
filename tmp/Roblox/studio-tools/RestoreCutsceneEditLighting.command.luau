-- Run in Roblox Studio's Command Bar after framing cutscene cameras.
-- Restores the Lighting snapshot captured by ApplyCutsceneEditLighting.

local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")

local BACKUP_NAME = "CutsceneEditLighting_Backup"

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

local backup = ServerStorage:FindFirstChild(BACKUP_NAME)
if not backup or not backup:IsA("Folder") or not backup:GetAttribute("HasSnapshot") then
	warn("[CutsceneEditLighting] No edit-mode Lighting backup found.")
	return
end

for _, child in ipairs(Lighting:GetChildren()) do
	if EFFECT_CLASSES[child.ClassName] then
		child:Destroy()
	end
end

for _, propertyName in ipairs(LIGHTING_PROPERTIES) do
	local value = backup:GetAttribute(propertyName)
	if value ~= nil then
		Lighting[propertyName] = value
	end
end

local effects = backup:FindFirstChild("Effects")
if effects and effects:IsA("Folder") then
	for _, child in ipairs(effects:GetChildren()) do
		child:Clone().Parent = Lighting
	end
end

backup:Destroy()

print("[CutsceneEditLighting] Restored previous Lighting snapshot.")
