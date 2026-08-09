local Localization = require(script.Parent:WaitForChild("Localization"))
local NoteContent = require(script.Parent:WaitForChild("NoteContent"))

local NoteData = {}

local notes = NoteContent

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
	return {
		id = note.id,
		title = resolveLocalizedText(note, "title", "titleKey", languageCode),
		typedText = resolveLocalizedText(note, "body", "typedTextKey", languageCode),
		handwritingImage = note.handwritingImage or "",
		viewType = note.viewType or "text",
		image = note.image or "",
		imageAspectRatio = note.imageAspectRatio or (2 / 3),
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
