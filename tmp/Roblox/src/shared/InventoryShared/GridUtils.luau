local GridUtils = {}

local function getCellKey(column: number, row: number): string
	return string.format("%d:%d", column, row)
end

function GridUtils.getFootprint(itemDefinition, rotated: boolean?)
	local width = itemDefinition.Width
	local height = itemDefinition.Height

	if rotated and itemDefinition.Rotatable then
		width, height = height, width
	end

	return width, height
end

function GridUtils.isWithinBounds(columns: number, rows: number, gridX: number, gridY: number, width: number, height: number)
	return gridX >= 1
		and gridY >= 1
		and (gridX + width - 1) <= columns
		and (gridY + height - 1) <= rows
end

function GridUtils.canPlaceItem(
	occupancy,
	columns: number,
	rows: number,
	gridX: number,
	gridY: number,
	width: number,
	height: number,
	ignoredItemId: string?
)
	if not GridUtils.isWithinBounds(columns, rows, gridX, gridY, width, height) then
		return false
	end

	for row = gridY, gridY + height - 1 do
		for column = gridX, gridX + width - 1 do
			local occupantId = occupancy[getCellKey(column, row)]
			if occupantId ~= nil and occupantId ~= ignoredItemId then
				return false
			end
		end
	end

	return true
end

function GridUtils.writeItemToGrid(occupancy, itemId: string, gridX: number, gridY: number, width: number, height: number)
	for row = gridY, gridY + height - 1 do
		for column = gridX, gridX + width - 1 do
			occupancy[getCellKey(column, row)] = itemId
		end
	end
end

function GridUtils.clearItemFromGrid(occupancy, itemId: string)
	for cellKey, occupantId in occupancy do
		if occupantId == itemId then
			occupancy[cellKey] = nil
		end
	end
end

function GridUtils.buildOccupancyFromItems(items, definitions)
	local occupancy = {}

	for itemId, itemState in items do
		local definition = definitions[itemState.DefinitionId]
		if definition and itemState.Location ~= "Hand" and itemState.GridX ~= nil and itemState.GridY ~= nil then
			local width, height = GridUtils.getFootprint(definition, itemState.Rotated)
			GridUtils.writeItemToGrid(occupancy, itemId, itemState.GridX, itemState.GridY, width, height)
		end
	end

	return occupancy
end

return GridUtils
