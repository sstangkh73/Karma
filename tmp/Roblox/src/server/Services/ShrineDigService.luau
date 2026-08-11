local Workspace = game:GetService("Workspace")

local ShrineDigService = {
	Name = "ShrineDigService",
	Priority = 31,
}

local CONFIG = {
	DigSpotName = "ShrineDigSpot",
	NoteName = "note_2",
	PromptActionText = "ขุดหาโทรศัพท์",
	PromptObjectText = "ดินที่ถูกกลบไว้",
	HoldDuration = 4,
	Distance = 10,
	NoteReadDistance = 10,
}

local digSpot: BasePart? = nil
local noteInstance: Instance? = nil
local hasBeenDug = false

local function getBaseParts(instance: Instance?): { BasePart }
	local parts = {}
	if not instance then
		return parts
	end

	if instance:IsA("BasePart") then
		table.insert(parts, instance)
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	return parts
end

local function setPromptAndClickEnabled(instance: Instance?, enabled: boolean)
	if not instance then
		return
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			descendant.Enabled = enabled
		elseif descendant:IsA("ClickDetector") then
			descendant.MaxActivationDistance = if enabled then CONFIG.NoteReadDistance else 0
		end
	end

	if instance:IsA("ProximityPrompt") then
		instance.Enabled = enabled
	elseif instance:IsA("ClickDetector") then
		instance.MaxActivationDistance = if enabled then CONFIG.NoteReadDistance else 0
	end
end

local function setNoteGuiEnabled(instance: Instance?, enabled: boolean)
	if not instance then
		return
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("SurfaceGui") or descendant:IsA("BillboardGui") then
			descendant.Enabled = enabled
		end
	end

	if instance:IsA("SurfaceGui") or instance:IsA("BillboardGui") then
		instance.Enabled = enabled
	end
end

local function setNoteVisible(visible: boolean)
	for _, part in ipairs(getBaseParts(noteInstance)) do
		part.Transparency = if visible then 0 else 1
		part.CanCollide = false
		part.CanTouch = visible
		part.CanQuery = visible
	end

	setNoteGuiEnabled(noteInstance, visible)
	setPromptAndClickEnabled(noteInstance, visible)
end

local function findWorkspaceDescendant(name: string): Instance?
	return Workspace:FindFirstChild(name, true)
end

local function findNoteInstance(): Instance?
	local namedNote = findWorkspaceDescendant(CONFIG.NoteName)
	if namedNote then
		return namedNote
	end

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:GetAttribute("NoteId") == CONFIG.NoteName then
			return descendant
		end
	end

	return nil
end

local function revealNote()
	hasBeenDug = true
	setNoteVisible(true)

	if digSpot then
		local prompt = digSpot:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = false
		end

		digSpot.Transparency = 1
		digSpot.CanCollide = false
		digSpot.CanTouch = false
		digSpot.CanQuery = false
	end

	print("[ShrineDigService] Shrine dig complete; note_2 is visible.")
end

local function configureDigSpot()
	if not digSpot then
		return
	end

	digSpot.Anchored = true
	digSpot.CanCollide = false

	local prompt = digSpot:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = digSpot
	end

	prompt.ActionText = CONFIG.PromptActionText
	prompt.ObjectText = CONFIG.PromptObjectText
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = CONFIG.HoldDuration
	prompt.MaxActivationDistance = CONFIG.Distance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = not hasBeenDug

	prompt.Triggered:Connect(function()
		if hasBeenDug then
			return
		end

		revealNote()
	end)
end

local function refreshTargets()
	local foundDigSpot = findWorkspaceDescendant(CONFIG.DigSpotName)
	if foundDigSpot and foundDigSpot:IsA("BasePart") then
		digSpot = foundDigSpot
	elseif foundDigSpot then
		warn(("[ShrineDigService] %s must be a BasePart."):format(CONFIG.DigSpotName))
		digSpot = nil
	else
		digSpot = nil
	end

	noteInstance = findNoteInstance()
	if noteInstance then
		setNoteVisible(hasBeenDug)
	end

	configureDigSpot()
end

function ShrineDigService:Start()
	refreshTargets()

	Workspace.DescendantAdded:Connect(function(instance)
		if instance.Name == CONFIG.DigSpotName
			or instance.Name == CONFIG.NoteName
			or instance:GetAttribute("NoteId") == CONFIG.NoteName then
			task.defer(refreshTargets)
		end
	end)

	Workspace.DescendantAdded:Connect(function(instance)
		if not noteInstance or not instance:IsDescendantOf(noteInstance) then
			return
		end

		task.defer(function()
			setNoteVisible(hasBeenDug)
		end)
	end)
end

return ShrineDigService
