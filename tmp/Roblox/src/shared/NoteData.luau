local Localization = require(script.Parent:WaitForChild("Localization"))

local NoteData = {}

local notes = {
	{
		id = "note_1",
		titleKey = "notes.note_1.title",
		typedTextKey = "notes.note_1.body",
		handwritingImage = "rbxassetid://0",
	},

	-- Add more notes here:
	-- {
	-- 	id = "note_2",
	-- 	titleKey = "notes.note_2.title",
	-- 	typedTextKey = "notes.note_2.body",
	-- 	handwritingImage = "rbxassetid://XXXXX",
	-- },
}

local function createResolvedNote(note, languageCode: string?)
	return {
		id = note.id,
		title = note.titleKey and Localization.translate(note.titleKey, nil, languageCode) or "",
		typedText = note.typedTextKey and Localization.translate(note.typedTextKey, nil, languageCode) or "",
		handwritingImage = note.handwritingImage or "",
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
