local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local localeFolder = script.Parent:WaitForChild("Locales")

local localeTables = {
	en = require(localeFolder:WaitForChild("en")),
	th = require(localeFolder:WaitForChild("th")),
	["zh-cn"] = require(localeFolder:WaitForChild("zh-cn")),
	es = require(localeFolder:WaitForChild("es")),
	["pt-br"] = require(localeFolder:WaitForChild("pt-br")),
	fr = require(localeFolder:WaitForChild("fr")),
	de = require(localeFolder:WaitForChild("de")),
	ru = require(localeFolder:WaitForChild("ru")),
	ko = require(localeFolder:WaitForChild("ko")),
	id = require(localeFolder:WaitForChild("id")),
}

local Localization = {}

-- Keep one canonical authoring language for content review. New keys should be
-- written in the source locale first, then translated into other locale files.
Localization.DEFAULT_LANGUAGE = "en"
Localization.SOURCE_LANGUAGE = "th"

local LANGUAGE_ALIASES = {
	th = "th",
	["th-th"] = "th",
	["th_th"] = "th",
	en = "en",
	["en-us"] = "en",
	["en_us"] = "en",
	["en-gb"] = "en",
	["en_gb"] = "en",
	zh = "zh-cn",
	["zh-cn"] = "zh-cn",
	["zh_cn"] = "zh-cn",
	["zh-sg"] = "zh-cn",
	["zh_sg"] = "zh-cn",
	["zh-hans"] = "zh-cn",
	["zh_hans"] = "zh-cn",
	es = "es",
	["es-es"] = "es",
	["es_es"] = "es",
	["es-mx"] = "es",
	["es_mx"] = "es",
	["pt-br"] = "pt-br",
	["pt_br"] = "pt-br",
	pt = "pt-br",
	fr = "fr",
	["fr-fr"] = "fr",
	["fr_fr"] = "fr",
	de = "de",
	["de-de"] = "de",
	["de_de"] = "de",
	ru = "ru",
	["ru-ru"] = "ru",
	["ru_ru"] = "ru",
	ko = "ko",
	["ko-kr"] = "ko",
	["ko_kr"] = "ko",
	id = "id",
	["id-id"] = "id",
	["id_id"] = "id",
	["in-id"] = "id",
	["in_id"] = "id",
	["in"] = "id",
}

local languageChangedEvent = Instance.new("BindableEvent")
local trackingInitialized = false
local translatorLocaleConnection = nil
local playerLocaleConnection = nil
local activeTranslator = nil

local function normalizeLanguageCode(localeId: string?): string
	if typeof(localeId) ~= "string" or localeId == "" then
		return Localization.DEFAULT_LANGUAGE
	end

	local lowered = string.lower(localeId)
	if LANGUAGE_ALIASES[lowered] then
		return LANGUAGE_ALIASES[lowered]
	end

	local shortCode = string.match(lowered, "^[a-z]+")
	if shortCode and LANGUAGE_ALIASES[shortCode] then
		return LANGUAGE_ALIASES[shortCode]
	end

	return Localization.DEFAULT_LANGUAGE
end

local function formatTemplate(template: string, params): string
	if typeof(params) ~= "table" then
		return template
	end

	return string.gsub(template, "{([%w_]+)}", function(token)
		local value = params[token]
		if value == nil then
			return "{" .. token .. "}"
		end

		return tostring(value)
	end)
end

local function getTranslatorLocaleId(): string?
	if not activeTranslator then
		return nil
	end

	local success, localeId = pcall(function()
		return activeTranslator.LocaleId
	end)

	if success and typeof(localeId) == "string" and localeId ~= "" then
		return localeId
	end

	return nil
end

local function getLocalPlayerLocaleId(): string?
	if not RunService:IsClient() then
		return nil
	end

	local player = Players.LocalPlayer
	if not player then
		return nil
	end

	local success, localeId = pcall(function()
		return player.LocaleId
	end)

	if success and typeof(localeId) == "string" and localeId ~= "" then
		return localeId
	end

	return nil
end

local function getRobloxLocaleId(): string?
	local success, localeId = pcall(function()
		return LocalizationService.RobloxLocaleId
	end)

	if success and typeof(localeId) == "string" and localeId ~= "" then
		return localeId
	end

	return nil
end

local function getSystemLocaleId(): string?
	local success, localeId = pcall(function()
		return LocalizationService.SystemLocaleId
	end)

	if success and typeof(localeId) == "string" and localeId ~= "" then
		return localeId
	end

	return nil
end

local function getCurrentLanguageCodeInternal(): string
	local localeId = getTranslatorLocaleId()
		or getLocalPlayerLocaleId()
		or getRobloxLocaleId()
		or getSystemLocaleId()

	return normalizeLanguageCode(localeId)
end

local function emitLanguageChanged()
	languageChangedEvent:Fire(getCurrentLanguageCodeInternal())
end

local function connectTranslator(translator)
	if activeTranslator == translator then
		return
	end

	if translatorLocaleConnection then
		translatorLocaleConnection:Disconnect()
		translatorLocaleConnection = nil
	end

	activeTranslator = translator
	if activeTranslator then
		translatorLocaleConnection = activeTranslator:GetPropertyChangedSignal("LocaleId"):Connect(function()
			emitLanguageChanged()
		end)
	end
end

local function refreshClientTranslator()
	if not RunService:IsClient() then
		return
	end

	local player = Players.LocalPlayer
	if not player then
		return
	end

	task.spawn(function()
		local success, translator = pcall(function()
			return LocalizationService:GetTranslatorForPlayerAsync(player)
		end)

		if success and translator then
			connectTranslator(translator)
		end

		emitLanguageChanged()
	end)
end

local function ensureClientLanguageTracking()
	if trackingInitialized or not RunService:IsClient() then
		return
	end

	trackingInitialized = true

	local player = Players.LocalPlayer
	if not player then
		return
	end

	playerLocaleConnection = player:GetPropertyChangedSignal("LocaleId"):Connect(function()
		refreshClientTranslator()
	end)

	refreshClientTranslator()
end

function Localization.getCurrentLanguageCode()
	ensureClientLanguageTracking()
	return getCurrentLanguageCodeInternal()
end

function Localization.subscribeToLanguageChanged(callback)
	if typeof(callback) ~= "function" then
		return function() end
	end

	if not RunService:IsClient() then
		return function() end
	end

	ensureClientLanguageTracking()

	local connection = languageChangedEvent.Event:Connect(function(languageCode)
		callback(languageCode)
	end)

	return function()
		connection:Disconnect()
	end
end

function Localization.translate(key: string, params, languageCode: string?): string
	local resolvedLanguageCode = normalizeLanguageCode(languageCode or getCurrentLanguageCodeInternal())
	local selectedTable = localeTables[resolvedLanguageCode] or localeTables[Localization.DEFAULT_LANGUAGE]
	local defaultTable = localeTables[Localization.DEFAULT_LANGUAGE]
	local sourceTable = localeTables[Localization.SOURCE_LANGUAGE]

	local template = selectedTable and selectedTable[key]
		or defaultTable and defaultTable[key]
		or sourceTable and sourceTable[key]

	if typeof(template) ~= "string" then
		return key
	end

	return formatTemplate(template, params)
end

return Localization
