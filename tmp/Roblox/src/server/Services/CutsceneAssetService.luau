local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DialogueContent = require(Shared:WaitForChild("DialogueContent"))

local CONFIG = {
	FolderName = "Cutscenes",
}

local CutsceneAssetService = {
	Name = "CutsceneAssetService",
	Priority = 25,
}

local function ensureFolder()
	local folder = ReplicatedStorage:FindFirstChild(CONFIG.FolderName)
	if folder then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = CONFIG.FolderName
	folder.Parent = ReplicatedStorage
	return folder
end

local function normalizeAssetId(assetId)
	if typeof(assetId) == "number" then
		return assetId
	end
	if typeof(assetId) ~= "string" then
		return nil
	end

	local digits = assetId:match("%d+")
	return if digits then tonumber(digits) else nil
end

local function findCutsceneRoot(assetModel: Instance, cutsceneName: string)
	if assetModel.Name == cutsceneName then
		return assetModel
	end

	local direct = assetModel:FindFirstChild(cutsceneName)
	if direct then
		return direct
	end

	return assetModel:FindFirstChild(cutsceneName, true)
end

function CutsceneAssetService:loadCutscene(config)
	local assetId = normalizeAssetId(config.CameraCutsceneAssetId)
	local cutsceneName = if typeof(config.CameraCutsceneName) == "string" and config.CameraCutsceneName ~= ""
		then config.CameraCutsceneName
		else "END_DEMO"
	if not assetId then
		return
	end

	local folder = ensureFolder()
	if folder:FindFirstChild(cutsceneName) then
		return
	end

	local ok, assetModel = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or not assetModel then
		warn(("[CutsceneAssetService] Failed to load camera cutscene asset %s: %s"):format(tostring(assetId), tostring(assetModel)))
		return
	end

	local cutsceneRoot = findCutsceneRoot(assetModel, cutsceneName)
	if not cutsceneRoot then
		warn(("[CutsceneAssetService] Asset %s did not contain %s."):format(tostring(assetId), cutsceneName))
		assetModel:Destroy()
		return
	end

	local cloned = cutsceneRoot:Clone()
	cloned.Name = cutsceneName
	cloned:SetAttribute("AssetId", tostring(assetId))
	cloned.Parent = folder
	assetModel:Destroy()
end

function CutsceneAssetService:Start()
	for _, sequence in pairs(DialogueContent.Sequences or {}) do
		local endDemo = sequence.EndDemo
		if typeof(endDemo) == "table" then
			self:loadCutscene(endDemo)
		end
	end
end

return CutsceneAssetService
