local Localization = require(script.Parent:WaitForChild("Localization"))
local DialogueContent = require(script.Parent:WaitForChild("DialogueContent"))

local DialogueData = {}

local sequencesById = {}
local triggerIndex = {}

local function cloneTable(source)
	if typeof(source) ~= "table" then
		return source
	end

	local clone = {}
	for key, value in pairs(source) do
		clone[key] = if typeof(value) == "table" then cloneTable(value) else value
	end
	return clone
end

local function addTrigger(sequenceId: string, trigger)
	if typeof(trigger) ~= "table"
		or typeof(trigger.Type) ~= "string"
		or trigger.Type == ""
		or typeof(trigger.Id) ~= "string"
		or trigger.Id == "" then
		warn(("[DialogueData] Ignored invalid trigger in %s"):format(sequenceId))
		return
	end

	local typeBucket = triggerIndex[trigger.Type]
	if not typeBucket then
		typeBucket = {}
		triggerIndex[trigger.Type] = typeBucket
	end

	local idBucket = typeBucket[trigger.Id]
	if not idBucket then
		idBucket = {}
		typeBucket[trigger.Id] = idBucket
	end

	table.insert(idBucket, sequenceId)
end

for sequenceId, sequence in pairs(DialogueContent.Sequences or {}) do
	if typeof(sequenceId) == "string" and sequenceId ~= "" and typeof(sequence) == "table" then
		local normalized = cloneTable(sequence)
		normalized.Id = sequenceId
		sequencesById[sequenceId] = normalized

		if normalized.Enabled ~= false then
			for _, trigger in ipairs(normalized.Triggers or {}) do
				addTrigger(sequenceId, trigger)
			end
		end
	end
end

local function resolveLocalized(value, languageCode: string?)
	if typeof(value) == "string" then
		return value
	end

	if typeof(value) ~= "table" then
		return ""
	end

	local code = languageCode or Localization.getCurrentLanguageCode()
	local localized = value[code] or value.en or value.th
	return if typeof(localized) == "string" then localized else ""
end

function DialogueData.getSettings()
	return cloneTable(DialogueContent.Settings or {})
end

function DialogueData.getSequence(sequenceId: string)
	local sequence = sequencesById[sequenceId]
	if not sequence or sequence.Enabled == false then
		return nil
	end

	return cloneTable(sequence)
end

function DialogueData.getResolvedSequence(sequenceId: string, languageCode: string?)
	local sequence = DialogueData.getSequence(sequenceId)
	if not sequence then
		return nil
	end

	for _, line in ipairs(sequence.Lines or {}) do
		line.Speaker = resolveLocalized(line.Speaker, languageCode)
		line.Text = resolveLocalized(line.Text, languageCode)
	end

	return sequence
end

function DialogueData.getSequenceIdsForTrigger(triggerType: string, triggerId: string)
	local typeBucket = triggerIndex[triggerType]
	local ids = if typeBucket then typeBucket[triggerId] else nil
	return cloneTable(ids or {})
end

function DialogueData.getCurrentLanguageCode()
	return Localization.getCurrentLanguageCode()
end

function DialogueData.subscribeToLanguageChanged(callback)
	return Localization.subscribeToLanguageChanged(callback)
end

return DialogueData
