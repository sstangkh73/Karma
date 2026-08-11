local Localization = require(script.Parent:WaitForChild("Localization"))
local NoteContent = require(script.Parent:WaitForChild("NoteContent"))

local NoteData = {}

local notes = NoteContent
local validViewTypes = {
	text = true,
	image = true,
}

local function resolveViewType(note): string
	local viewType = note.viewType or "text"
	if not validViewTypes[viewType] then
		warn(("[NoteData] Unknown viewType '%s' on %s; using text"):format(
			tostring(viewType),
			tostring(note.id)
		))
		return "text"
	end

	if viewType == "image" and (typeof(note.image) ~= "string" or note.image == "") then
		warn(("[NoteData] Image note %s has no image; using text"):format(tostring(note.id)))
		return "text"
	end

	return viewType
end

local function resolveImageAspectRatio(note): number
	if typeof(note.imageAspectRatio) == "number" and note.imageAspectRatio > 0 then
		return note.imageAspectRatio
	end

	return 2 / 3
end

local function resolveHandwritingImage(note): string
	local handwritingImage = note.handwritingImage
	if typeof(handwritingImage) == "string"
		and handwritingImage ~= ""
		and handwritingImage ~= "rbxassetid://0" then
		return handwritingImage
	end

	return ""
end

local function resolveLocalizedText(note, fieldName: string, keyFieldName: string, languageCode: string?): string
	local localized = note[fieldName]
	if typeof(localized) == "table" then
		local resolvedLanguageCode = languageCode or Localization.getCurrentLanguageCode()
		local value = localized[resolvedLanguageCode]
		if typeof(value) == "string" then
			return value
		end
	elseif typeof(localized) == "string" then
		return localized
	end

	local key = note[keyFieldName]
	if typeof(key) == "string" and key ~= "" then
		return Localization.translate(key, nil, languageCode)
	end

	if typeof(localized) == "table" then
		local fallback = localized.en or localized.th
		if typeof(fallback) == "string" then
			return fallback
		end
	end

	return ""
end

local function createResolvedNote(note, languageCode: string?)
	local viewType = resolveViewType(note)

	return {
		id = note.id,
		title = resolveLocalizedText(note, "title", "titleKey", languageCode),
		typedText = resolveLocalizedText(note, "body", "typedTextKey", languageCode),
		viewType = viewType,
		image = if viewType == "image" then note.image else "",
		handwritingImage = resolveHandwritingImage(note),
		imageAspectRatio = resolveImageAspectRatio(note),
	}
end

function NoteData.getCurrentLanguageCode()
	return Localization.getCurrentLanguageCode()
end

function NoteData.subscribeToLanguageChanged(callback)
	return Localization.subscribeToLanguageChanged(callback)
end

function NoteData.getNoteById(noteId: string, languageCode: string?)
	for _, note in ipairs(notes) do
		if note.id == noteId then
			return createResolvedNote(note, languageCode)
		end
	end

	return nil
end

function NoteData.getAllNotes(languageCode: string?)
	local resolvedNotes = {}

	for _, note in ipairs(notes) do
		table.insert(resolvedNotes, createResolvedNote(note, languageCode))
	end

	return resolvedNotes
end

return NoteData
