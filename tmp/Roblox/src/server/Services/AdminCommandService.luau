local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local RemoteGateway = require(Core:WaitForChild("RemoteGateway"))
local ItemDefinitions = require(Shared:WaitForChild("InventoryShared"):WaitForChild("ItemDefinitions"))

local CONFIG = {
	AllowAllInStudio = true,
	AllowedUserIds = {
		-- Add production testers here: [123456789] = true,
	},
	Cooldown = 0.5,
	MaxCommandLength = 80,
	ApiWaitTimeout = 15,
}

local TEACHER_DESK_KEY_ID = "teacher_desk_key"

local AdminCommandService = {
	Name = "AdminCommandService",
	Priority = 75,
	Dependencies = { "InventoryService", "TeacherDeskLockService" },
	feedbackRemote = nil,
	grantItem = nil,
	grantTeacherDeskKey = nil,
	lastCommandAt = {},
	connections = {},
}

local function trim(value: string): string
	return string.match(value, "^%s*(.-)%s*$") or ""
end

local function getQuestItemIds()
	local ids = {}

	for definitionId, definition in pairs(ItemDefinitions) do
		if definition.Type == "Quest" then
			table.insert(ids, definitionId)
		end
	end

	table.sort(ids, function(left, right)
		return string.lower(left) < string.lower(right)
	end)

	return ids
end

local GRANTABLE_IDS = getQuestItemIds()
table.insert(GRANTABLE_IDS, TEACHER_DESK_KEY_ID)
table.sort(GRANTABLE_IDS, function(left, right)
	return string.lower(left) < string.lower(right)
end)

local function resolveGrantableId(requestedId: string): string?
	local normalized = string.lower(trim(requestedId))
	if normalized == "" then
		return nil
	end
	if normalized == "teacherdeskkey" or normalized == "teacherkey" then
		return TEACHER_DESK_KEY_ID
	end

	for _, definitionId in ipairs(GRANTABLE_IDS) do
		local definition = ItemDefinitions[definitionId]
		if string.lower(definitionId) == normalized
			or (definition and string.lower(definition.Id) == normalized) then
			return definitionId
		end
	end

	return nil
end

local function isProductionOwner(player: Player): boolean
	return game.CreatorType == Enum.CreatorType.User
		and game.CreatorId > 0
		and player.UserId == game.CreatorId
end

function AdminCommandService:isAuthorized(player: Player): boolean
	if CONFIG.AllowAllInStudio and RunService:IsStudio() then
		return true
	end

	if CONFIG.AllowedUserIds[player.UserId] == true then
		return true
	end

	return isProductionOwner(player)
end

function AdminCommandService:sendFeedback(player: Player, message: string)
	if self.feedbackRemote and player.Parent == Players then
		self.feedbackRemote:FireClient(player, {
			Message = message,
		})
	end
end

function AdminCommandService:canRunNow(player: Player): boolean
	local now = os.clock()
	local lastCommandAt = self.lastCommandAt[player.UserId]
	if lastCommandAt and now - lastCommandAt < CONFIG.Cooldown then
		return false
	end

	self.lastCommandAt[player.UserId] = now
	return true
end

function AdminCommandService:getPlayerFromTextSource(textSource: TextSource): Player?
	if not textSource then
		return nil
	end

	return Players:GetPlayerByUserId(textSource.UserId)
end

function AdminCommandService:authorizeCommand(textSource: TextSource): Player?
	local player = self:getPlayerFromTextSource(textSource)
	if not player or not self:canRunNow(player) then
		return nil
	end

	if not self:isAuthorized(player) then
		warn(("[AdminCommand] Denied %s (%d)"):format(player.Name, player.UserId))
		self:sendFeedback(player, "[ADMIN] คุณไม่มีสิทธิ์ใช้คำสั่งนี้")
		return nil
	end

	return player
end

function AdminCommandService:handleListCommand(textSource: TextSource)
	local player = self:authorizeCommand(textSource)
	if not player then
		return
	end

	self:sendFeedback(player, "[ADMIN] Quest items: " .. table.concat(GRANTABLE_IDS, ", "))
end

function AdminCommandService:handleGiveCommand(textSource: TextSource, rawText: string)
	local player = self:authorizeCommand(textSource)
	if not player then
		return
	end

	if #rawText > CONFIG.MaxCommandLength then
		self:sendFeedback(player, "[ADMIN] คำสั่งยาวเกินไป")
		return
	end

	local _, requestedId = string.match(rawText, "^%s*(%S+)%s*(.-)%s*$")
	local definitionId = resolveGrantableId(requestedId or "")
	if not definitionId then
		self:sendFeedback(player, "[ADMIN] ใช้ /qitem <ItemId> และดูชื่อด้วย /qitems")
		return
	end

	local ok, grantedOrReason
	if definitionId == TEACHER_DESK_KEY_ID then
		if not self.grantTeacherDeskKey then
			self:sendFeedback(player, "[ADMIN] ระบบกุญแจโต๊ะครูยังไม่พร้อม")
			return
		end
		ok, grantedOrReason = self.grantTeacherDeskKey:Invoke(player)
	else
		if not self.grantItem then
			self:sendFeedback(player, "[ADMIN] ระบบกระเป๋ายังไม่พร้อม")
			return
		end
		ok, grantedOrReason = self.grantItem:Invoke(player, definitionId)
	end

	if not ok then
		local reasons = {
			["Already own maximum amount"] = "มีไอเทมนี้อยู่แล้ว",
			["Already owned by another player"] = "ไอเทมนี้อยู่กับผู้เล่นอื่นแล้ว",
			["Inventory full"] = "กระเป๋าเต็ม",
			["Teacher desk key already collected"] = "เก็บกุญแจโต๊ะครูไปแล้ว",
		}
		local reason = reasons[tostring(grantedOrReason)] or "ไม่สามารถเสกไอเทมได้"
		self:sendFeedback(player, ("[ADMIN] %s: %s"):format(definitionId, reason))
		return
	end

	print(("[AdminCommand] %s (%d) granted quest item %s to self"):format(
		player.Name,
		player.UserId,
		definitionId
	))
	self:sendFeedback(player, ("[ADMIN] ได้รับ %s แล้ว"):format(definitionId))
end

function AdminCommandService:createCommand(name: string, primaryAlias: string, secondaryAlias: string?)
	local command = TextChatService:FindFirstChild(name)
	if command and not command:IsA("TextChatCommand") then
		error(("[AdminCommand] %s must be a TextChatCommand"):format(command:GetFullName()))
	end

	if not command then
		command = Instance.new("TextChatCommand")
		command.Name = name
		command.Parent = TextChatService
	end

	command.PrimaryAlias = primaryAlias
	command.SecondaryAlias = secondaryAlias or ""
	command.AutocompleteVisible = false
	command.Enabled = true
	return command
end

function AdminCommandService:Init()
	self.feedbackRemote = RemoteGateway.getOrCreateRemote(nil, "AdminCommandFeedback", "RemoteEvent")

	local serverApi = ServerStorage:WaitForChild("InventoryServerApi", CONFIG.ApiWaitTimeout)
	local grantItem = serverApi and serverApi:WaitForChild("GrantItemByDefinitionId", CONFIG.ApiWaitTimeout)
	if not grantItem or not grantItem:IsA("BindableFunction") then
		error("InventoryServerApi.GrantItemByDefinitionId was not created")
	end

	self.grantItem = grantItem

	local keyApi = ServerStorage:WaitForChild("TeacherDeskLockApi", CONFIG.ApiWaitTimeout)
	local grantKey = keyApi and keyApi:WaitForChild("GrantKey", CONFIG.ApiWaitTimeout)
	if not grantKey or not grantKey:IsA("BindableFunction") then
		error("TeacherDeskLockApi.GrantKey was not created")
	end

	self.grantTeacherDeskKey = grantKey
end

function AdminCommandService:Start()
	local giveCommand = self:createCommand("KarmaGiveQuestItem", "/qitem", "/givequest")
	local listCommand = self:createCommand("KarmaListQuestItems", "/qitems", "/questitems")

	table.insert(self.connections, giveCommand.Triggered:Connect(function(textSource, rawText)
		self:handleGiveCommand(textSource, rawText)
	end))

	table.insert(self.connections, listCommand.Triggered:Connect(function(textSource)
		self:handleListCommand(textSource)
	end))

	table.insert(self.connections, Players.PlayerRemoving:Connect(function(player)
		self.lastCommandAt[player.UserId] = nil
	end))

	print(("[AdminCommand] Ready with %d grantable quest items"):format(#GRANTABLE_IDS))
end

return AdminCommandService
