local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Localization = require(Shared:WaitForChild("Localization"))
local NoteGui = require(Shared:WaitForChild("NoteGui"))
local NoteData = require(Shared:WaitForChild("NoteData"))
local NoteJournal = require(Shared:WaitForChild("NoteJournal"))
local NoteReader = require(Shared:WaitForChild("NoteReader"))

local gui = NoteGui.create()

local isOpen = false
local isAnimating = false
local currentLayer = 0
local currentNoteId = nil
local USE_SERVER_INTERACTION_SERVICE = true

local function applyNoteInfo(noteInfo)
	gui.HandwritingLayer.Image = noteInfo.handwritingImage or ""
	gui.TextLabel.Text = noteInfo.typedText or ""

	if noteInfo.title and noteInfo.title ~= "" then
		gui.TitleLabel.Text = noteInfo.title
	else
		gui.TitleLabel.Text = ""
	end
end

local function showLayer1(fromOpen: boolean?)
	currentLayer = 1
	gui.TextOverlay.Visible = false
	gui.Overlay.Visible = true
	gui.NoteFrame.Visible = true
	gui.ScreenGui.Enabled = true

	if fromOpen then
		gui.NoteFrame.Position = UDim2.new(0.5, -250, 1.5, 0)
		gui.Overlay.BackgroundTransparency = 1

		local tweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(gui.NoteFrame, tweenInfo, {
			Position = UDim2.new(0.5, -250, 0.5, -325),
		}):Play()
		TweenService:Create(gui.Overlay, TweenInfo.new(0.25), {
			BackgroundTransparency = 0.5,
		}):Play()
	else
		gui.NoteFrame.Position = UDim2.new(0.5, -250, 0.5, -325)
		gui.Overlay.BackgroundTransparency = 0.5
	end
end

local function showLayer2()
	currentLayer = 2
	gui.Overlay.Visible = false
	gui.NoteFrame.Visible = false
	gui.TextOverlay.Visible = true
	gui.TextOverlay.BackgroundTransparency = 1

	TweenService:Create(gui.TextOverlay, TweenInfo.new(0.3), {
		BackgroundTransparency = 0.25,
	}):Play()
end

local function hideAll()
	if isAnimating then
		return
	end

	isAnimating = true
	isOpen = false

	local function finish()
		gui.ScreenGui.Enabled = false
		gui.NoteFrame.Visible = false
		gui.Overlay.Visible = false
		gui.TextOverlay.Visible = false
		currentLayer = 0
		currentNoteId = nil
		isAnimating = false
	end

	if currentLayer == 1 then
		local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local closeTween = TweenService:Create(gui.NoteFrame, tweenInfo, {
			Position = UDim2.new(0.5, -250, 1.5, 0),
		})

		TweenService:Create(gui.Overlay, TweenInfo.new(0.2), {
			BackgroundTransparency = 1,
		}):Play()

		closeTween:Play()
		closeTween.Completed:Once(finish)
	elseif currentLayer == 2 then
		local closeTween = TweenService:Create(gui.TextOverlay, TweenInfo.new(0.25), {
			BackgroundTransparency = 1,
		})

		closeTween:Play()
		closeTween.Completed:Once(finish)
	else
		finish()
	end
end

local function openNote(noteId: string)
	if isOpen or isAnimating then
		return
	end

	local noteInfo = NoteData.getNoteById(noteId)
	if not noteInfo then
		warn("[NoteSystem] Missing note: " .. noteId)
		return
	end

	currentNoteId = noteId
	isOpen = true
	NoteJournal.recordRead(noteId, noteInfo)
	applyNoteInfo(noteInfo)
	showLayer1(true)
end

local function closeNote()
	if not isOpen or isAnimating then
		return
	end

	hideAll()
end

NoteReader.subscribe(function(noteId: string)
	if isOpen or isAnimating then
		return
	end

	openNote(noteId)
end)

NoteData.subscribeToLanguageChanged(function()
	if not currentNoteId then
		return
	end

	local noteInfo = NoteData.getNoteById(currentNoteId)
	if not noteInfo then
		return
	end

	applyNoteInfo(noteInfo)
end)

local function connectInteractionRemote()
	local remotesFolder = ReplicatedStorage:WaitForChild("GameRemotes", 15)
	if not remotesFolder then
		warn("[NoteSystem] GameRemotes was not created; note prompts are server-managed.")
		return
	end

	local interactionEvent = remotesFolder:WaitForChild("InteractionEvent", 15)
	if not interactionEvent or not interactionEvent:IsA("RemoteEvent") then
		warn("[NoteSystem] InteractionEvent was not created; note prompts are server-managed.")
		return
	end

	interactionEvent.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end

		if payload.Type == "Note" and typeof(payload.NoteId) == "string" then
			openNote(payload.NoteId)
		end
	end)
end

task.spawn(connectInteractionRemote)

gui.ToggleButton.MouseButton1Click:Connect(function()
	if currentLayer == 1 then
		showLayer2()
	end
end)

gui.BackButton.MouseButton1Click:Connect(function()
	if currentLayer == 2 then
		showLayer1()
	end
end)

gui.CloseButton.MouseButton1Click:Connect(closeNote)
gui.CloseButton2.MouseButton1Click:Connect(closeNote)

gui.Overlay.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		closeNote()
	end
end)

gui.TextOverlay.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		closeNote()
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not isOpen then
		return
	end

	if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.Escape then
		closeNote()
	end

	if input.KeyCode == Enum.KeyCode.Tab then
		if currentLayer == 1 then
			showLayer2()
		elseif currentLayer == 2 then
			showLayer1()
		end
	end
end)

local function connectNote(part: Part)
	if USE_SERVER_INTERACTION_SERVICE then
		return
	end

	local clickDetector = part:FindFirstChildOfClass("ClickDetector")
	if not clickDetector then
		clickDetector = Instance.new("ClickDetector")
		clickDetector.MaxActivationDistance = 10
		clickDetector.Parent = part
	end

	local proximityPrompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not proximityPrompt then
		proximityPrompt = Instance.new("ProximityPrompt")
		proximityPrompt.ActionText = Localization.translate("note.prompt.read")
		proximityPrompt.ObjectText = Localization.translate("note.prompt.object")
		proximityPrompt.KeyboardKeyCode = Enum.KeyCode.E
		proximityPrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		proximityPrompt.HoldDuration = 0
		proximityPrompt.MaxActivationDistance = 10
		proximityPrompt.RequiresLineOfSight = false
		proximityPrompt.Parent = part
	end

	local noteId = part:GetAttribute("NoteId")
	if noteId then
		clickDetector.MouseClick:Connect(function()
			if not isOpen then
				openNote(noteId)
			end
		end)

		proximityPrompt.Triggered:Connect(function(triggeringPlayer)
			if triggeringPlayer == player and not isOpen then
				openNote(noteId)
			end
		end)
	end
end

for _, obj in pairs(workspace:GetDescendants()) do
	if obj:IsA("BasePart") and obj:GetAttribute("NoteId") then
		connectNote(obj)
	end
end

workspace.DescendantAdded:Connect(function(obj)
	if obj:IsA("BasePart") and obj:GetAttribute("NoteId") then
		task.wait(0.1)
		connectNote(obj)
	end
end)

print("[NoteSystem] Note system ready.")
