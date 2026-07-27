local NoteData = require(script.Parent:WaitForChild("NoteData"))
local Localization = require(script.Parent:WaitForChild("Localization"))

local NoteJournal = {}

local entriesById = {}
local orderedIds = {}
local listeners = {}

local function cloneEntry(entry)
	local noteInfo = NoteData.getNoteById(entry.id)

	local title = entry.fallbackTitle or Localization.translate("phone.diary.page.untitled")
	local typedText = entry.fallbackTypedText or ""
	local handwritingImage = entry.handwritingImage or ""

	if noteInfo then
		if noteInfo.title and noteInfo.title ~= "" then
			title = noteInfo.title
		end

		if noteInfo.typedText and noteInfo.typedText ~= "" then
			typedText = noteInfo.typedText
		end

		if noteInfo.handwritingImage and noteInfo.handwritingImage ~= "" then
			handwritingImage = noteInfo.handwritingImage
		end
	end

	return {
		id = entry.id,
		title = title,
		typedText = typedText,
		handwritingImage = handwritingImage,
		firstReadAt = entry.firstReadAt,
		lastReadAt = entry.lastReadAt,
		readCount = entry.readCount,
	}
end

local function notifyListeners()
	local snapshot = NoteJournal.getEntries()
	for callback in pairs(listeners) do
		callback(snapshot)
	end
end

local function sortEntries()
	table.sort(orderedIds, function(leftId, rightId)
		local left = entriesById[leftId]
		local right = entriesById[rightId]
		if not left or not right then
			return leftId < rightId
		end

		if left.lastReadAt == right.lastReadAt then
			return leftId < rightId
		end

		return left.lastReadAt > right.lastReadAt
	end)
end

function NoteJournal.recordRead(noteId: string, noteInfo)
	if typeof(noteId) ~= "string" or noteId == "" or typeof(noteInfo) ~= "table" then
		return
	end

	local now = os.time()
	local entry = entriesById[noteId]
	if not entry then
		entry = {
			id = noteId,
			fallbackTitle = noteInfo.title or Localization.translate("phone.diary.page.untitled"),
			fallbackTypedText = noteInfo.typedText or "",
			handwritingImage = noteInfo.handwritingImage or "",
			firstReadAt = now,
			lastReadAt = now,
			readCount = 1,
		}
		entriesById[noteId] = entry
		table.insert(orderedIds, noteId)
	else
		entry.fallbackTitle = noteInfo.title or entry.fallbackTitle
		entry.fallbackTypedText = noteInfo.typedText or entry.fallbackTypedText
		entry.handwritingImage = noteInfo.handwritingImage or entry.handwritingImage
		entry.lastReadAt = now
		entry.readCount += 1
	end

	sortEntries()
	notifyListeners()
end

function NoteJournal.getEntry(noteId: string)
	local entry = entriesById[noteId]
	if not entry then
		return nil
	end

	return cloneEntry(entry)
end

function NoteJournal.getEntries()
	local result = {}
	for _, noteId in ipairs(orderedIds) do
		local entry = entriesById[noteId]
		if entry then
			table.insert(result, cloneEntry(entry))
		end
	end

	return result
end

function NoteJournal.subscribe(callback)
	if typeof(callback) ~= "function" then
		return function() end
	end

	listeners[callback] = true
	return function()
		listeners[callback] = nil
	end
end

NoteData.subscribeToLanguageChanged(function()
	notifyListeners()
end)

return NoteJournal
