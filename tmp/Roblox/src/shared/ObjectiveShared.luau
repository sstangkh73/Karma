local ObjectiveShared = {}

ObjectiveShared.DEFAULT_CHANNEL = "Quest"

ObjectiveShared.CHANNELS = {
	Event = {
		SortPriority = 10,
		AccentColor = Color3.fromRGB(244, 193, 74),
	},
	Quest = {
		SortPriority = 20,
		AccentColor = Color3.fromRGB(120, 185, 255),
	},
}

local function cloneTable(source)
	if typeof(source) ~= "table" then
		return nil
	end

	local result = {}
	for key, value in pairs(source) do
		result[key] = value
	end

	return result
end

function ObjectiveShared.getChannelConfig(channel: string?)
	local resolvedChannel = ObjectiveShared.CHANNELS[channel or ""]
	if resolvedChannel then
		return resolvedChannel
	end

	return ObjectiveShared.CHANNELS[ObjectiveShared.DEFAULT_CHANNEL]
end

function ObjectiveShared.normalizeChannel(channel: string?): string
	if typeof(channel) == "string" and channel ~= "" then
		return channel
	end

	return ObjectiveShared.DEFAULT_CHANNEL
end

function ObjectiveShared.normalizeObjective(payload)
	if typeof(payload) ~= "table" then
		return nil, "Objective payload must be a table"
	end

	if typeof(payload.Id) ~= "string" or payload.Id == "" then
		return nil, "Objective payload is missing Id"
	end

	local channel = ObjectiveShared.normalizeChannel(payload.Channel)
	local config = ObjectiveShared.getChannelConfig(channel)

	return {
		Id = payload.Id,
		Channel = channel,
		Title = if typeof(payload.Title) == "string" then payload.Title else "",
		TitleKey = if typeof(payload.TitleKey) == "string" then payload.TitleKey else nil,
		TitleParams = cloneTable(payload.TitleParams),
		Description = if typeof(payload.Description) == "string" then payload.Description else "",
		DescriptionKey = if typeof(payload.DescriptionKey) == "string" then payload.DescriptionKey else nil,
		DescriptionParams = cloneTable(payload.DescriptionParams),
		Order = if typeof(payload.Order) == "number" then payload.Order else 100,
		Priority = if typeof(payload.Priority) == "number" then payload.Priority else config.SortPriority,
		Visible = payload.Visible ~= false,
		AccentColor = if typeof(payload.AccentColor) == "Color3" then payload.AccentColor else config.AccentColor,
	}
end

function ObjectiveShared.cloneObjective(objective)
	if typeof(objective) ~= "table" then
		return nil
	end

	return {
		Id = objective.Id,
		Channel = objective.Channel,
		Title = objective.Title,
		TitleKey = objective.TitleKey,
		TitleParams = cloneTable(objective.TitleParams),
		Description = objective.Description,
		DescriptionKey = objective.DescriptionKey,
		DescriptionParams = cloneTable(objective.DescriptionParams),
		Order = objective.Order,
		Priority = objective.Priority,
		Visible = objective.Visible,
		AccentColor = objective.AccentColor,
	}
end

function ObjectiveShared.toArray(objectivesById)
	local objectives = {}

	if typeof(objectivesById) ~= "table" then
		return objectives
	end

	for _, objective in pairs(objectivesById) do
		if objective.Visible ~= false then
			table.insert(objectives, ObjectiveShared.cloneObjective(objective))
		end
	end

	table.sort(objectives, function(left, right)
		if left.Priority ~= right.Priority then
			return left.Priority < right.Priority
		end

		if left.Order ~= right.Order then
			return left.Order < right.Order
		end

		if left.Channel ~= right.Channel then
			return left.Channel < right.Channel
		end

		return left.Id < right.Id
	end)

	return objectives
end

return ObjectiveShared
