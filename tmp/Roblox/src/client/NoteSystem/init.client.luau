local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Core = Shared:WaitForChild("Core")
local SystemHub = require(Core:WaitForChild("SystemHub"))

if not SystemHub.begin("NoteSystem", script) then
	return
end

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
local dialogueRemote = nil
local imageZoom = 1
local imagePan = Vector2.zero
local imageAspectRatio = 2 / 3
local isDraggingImage = false
local dragStartPosition = Vector2.zero
local dragStartPan = Vector2.zero

local MIN_IMAGE_ZOOM = 1
local MAX_IMAGE_ZOOM = 4
local IMAGE_ZOOM_STEP = 0.25

local function resizeImageFrame()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local viewportSize = camera.ViewportSize
	local maxWidth = viewportSize.X * 0.92
	local maxHeight = viewportSize.Y * 0.92
	local frameAspectRatio = 0.72
	local frameHeight = math.min(maxHeight, maxWidth / frameAspectRatio)
	local frameWidth = frameHeight * frameAspectRatio

	gui.NoteFrame.Size = UDim2.fromOffset(math.floor(frameWidth), math.floor(frameHeight))
end

local function updateImageTransform()
	local viewportSize = gui.ImageViewport.AbsoluteSize
	if viewportSize.X <= 0 or viewportSize.Y <= 0 then
		return
	end

	local viewportAspectRatio = viewportSize.X / viewportSize.Y
	local baseWidth
	local baseHeight

	if imageAspectRatio >= viewportAspectRatio then
		baseWidth = viewportSize.X
		baseHeight = baseWidth / imageAspectRatio
	else
		baseHeight = viewportSize.Y
		baseWidth = baseHeight * imageAspectRatio
	end

	local imageWidth = baseWidth * imageZoom
	local imageHeight = baseHeight * imageZoom
	local maxPanX = math.max(0, (imageWidth - viewportSize.X) * 0.5)
	local maxPanY = math.max(0, (imageHeight - viewportSize.Y) * 0.5)

	imagePan = Vector2.new(
		math.clamp(imagePan.X, -maxPanX, maxPanX),
		math.clamp(imagePan.Y, -maxPanY, maxPanY)
	)

	gui.ImageLayer.Size = UDim2.fromOffset(imageWidth, imageHeight)
	gui.ImageLayer.Position = UDim2.new(0.5, imagePan.X, 0.5, imagePan.Y)
	gui.ZoomResetButton.Text = ("%d%%"):format(math.floor(imageZoom * 100 + 0.5))
	gui.ZoomOutButton.AutoButtonColor = imageZoom > MIN_IMAGE_ZOOM
	gui.ZoomInButton.AutoButtonColor = imageZoom < MAX_IMAGE_ZOOM
end

local function setImageZoom(nextZoom: number, resetPan: boolean?)
	imageZoom = math.clamp(nextZoom, MIN_IMAGE_ZOOM, MAX_IMAGE_ZOOM)
	if resetPan then
		imagePan = Vector2.zero
	end
	updateImageTransform()
end

local function resetImageView()
	imageZoom = MIN_IMAGE_ZOOM
	imagePan = Vector2.zero
	isDraggingImage = false
	resizeImageFrame()
	task.defer(updateImageTransform)
end

local function applyNoteInfo(noteInfo)
	local isImageNote = noteInfo.viewType == "image"
	local hasHandwritingImage = typeof(noteInfo.handwritingImage) == "string" and noteInfo.handwritingImage ~= ""
	local image = if isImageNote then noteInfo.image else noteInfo.handwritingImage

	gui.ImageLayer.Image = image or ""
	imageAspectRatio = noteInfo.imageAspectRatio or (2 / 3)
	gui.ToggleButton.Visible = hasHandwritingImage
	gui.BackButton.Visible = hasHandwritingImage
	gui.ZoomControls.Visible = isImageNote or hasHandwritingImage
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
	resetImageView()

	if fromOpen then
		gui.NoteFrame.Position = UDim2.fromScale(0.5, 1.5)
		gui.Overlay.BackgroundTransparency = 1

		local tweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(gui.NoteFrame, tweenInfo, {
			Position = UDim2.fromScale(0.5, 0.5),
		}):Play()
		TweenService:Create(gui.Overlay, TweenInfo.new(0.25), {
			BackgroundTransparency = 0.5,
		}):Play()
	else
		gui.NoteFrame.Position = UDim2.fromScale(0.5, 0.5)
		gui.Overlay.BackgroundTransparency = 0.5
	end
end

local function showLayer2()
	currentLayer = 2
	gui.ScreenGui.Enabled = true
	gui.Overlay.Visible = false
	gui.NoteFrame.Visible = false
	gui.TextOverlay.Visible = true
	gui.TextOverlay.BackgroundTransparency = 1

	TweenService:Create(gui.TextOverlay, TweenInfo.new(0.3), {
		BackgroundTransparency = 0.25,
	}):Play()
end

local noteViewOpeners = {
	text = function()
		local noteInfo = currentNoteId and NoteData.getNoteById(currentNoteId)
		if noteInfo and typeof(noteInfo.handwritingImage) == "string" and noteInfo.handwritingImage ~= "" then
			showLayer1(true)
		else
			showLayer2()
		end
	end,
	image = function()
		showLayer1(true)
	end,
}

local function hideAll()
	if isAnimating then
		return
	end

	isAnimating = true
	isOpen = false
	local closedNoteId = currentNoteId

	local function finish()
		gui.ScreenGui.Enabled = false
		gui.NoteFrame.Visible = false
		gui.Overlay.Visible = false
		gui.TextOverlay.Visible = false
		currentLayer = 0
		currentNoteId = nil
		isAnimating = false

		if dialogueRemote and closedNoteId then
			dialogueRemote:FireServer({
				Type = "Trigger",
				TriggerType = "NoteRead",
				TriggerId = closedNoteId,
			})
		end
	end

	if currentLayer == 1 then
		local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local closeTween = TweenService:Create(gui.NoteFrame, tweenInfo, {
			Position = UDim2.fromScale(0.5, 1.5),
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

	local openView = noteViewOpeners[noteInfo.viewType] or noteViewOpeners.text
	openView()
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

local function connectGameRemotes()
	local remotesFolder = ReplicatedStorage:WaitForChild("GameRemotes", 15)
	if not remotesFolder then
		warn("[NoteSystem] GameRemotes was not created; note prompts are server-managed.")
		return
	end

	local interactionEvent = remotesFolder:WaitForChild("InteractionEvent", 15)
	if not interactionEvent or not interactionEvent:IsA("RemoteEvent") then
		warn("[NoteSystem] InteractionEvent was not created; note prompts are server-managed.")
		interactionEvent = nil
	end

	local dialogueEvent = remotesFolder:WaitForChild("DialogueEvent", 15)
	if dialogueEvent and dialogueEvent:IsA("RemoteEvent") then
		dialogueRemote = dialogueEvent
	else
		warn("[NoteSystem] DialogueEvent was not created; post-note dialogue is disabled.")
	end

	if not interactionEvent then
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

task.spawn(connectGameRemotes)

gui.ToggleButton.MouseButton1Click:Connect(function()
	if currentLayer == 1 then
		showLayer2()
	end
end)

gui.BackButton.MouseButton1Click:Connect(function()
	if currentLayer == 2 and currentNoteId then
		local noteInfo = NoteData.getNoteById(currentNoteId)
		if noteInfo and typeof(noteInfo.handwritingImage) == "string" and noteInfo.handwritingImage ~= "" then
			showLayer1(false)
		end
	end
end)

gui.CloseButton.MouseButton1Click:Connect(closeNote)
gui.CloseButton2.MouseButton1Click:Connect(closeNote)

gui.ZoomOutButton.MouseButton1Click:Connect(function()
	setImageZoom(imageZoom - IMAGE_ZOOM_STEP)
end)

gui.ZoomResetButton.MouseButton1Click:Connect(function()
	setImageZoom(MIN_IMAGE_ZOOM, true)
end)

gui.ZoomInButton.MouseButton1Click:Connect(function()
	setImageZoom(imageZoom + IMAGE_ZOOM_STEP)
end)

gui.ImageViewport.InputChanged:Connect(function(input)
	if currentLayer ~= 1 or input.UserInputType ~= Enum.UserInputType.MouseWheel then
		return
	end

	local direction = if input.Position.Z > 0 then 1 else -1
	setImageZoom(imageZoom + direction * IMAGE_ZOOM_STEP)
end)

gui.ImageViewport.InputBegan:Connect(function(input)
	if currentLayer ~= 1 or imageZoom <= MIN_IMAGE_ZOOM then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		isDraggingImage = true
		dragStartPosition = Vector2.new(input.Position.X, input.Position.Y)
		dragStartPan = imagePan

		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				isDraggingImage = false
			end
		end)
	end
end)

gui.ImageViewport:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if currentLayer == 1 then
		updateImageTransform()
	end
end)

local function isInputInside(guiObject: GuiObject, input: InputObject): boolean
	local point = Vector2.new(input.Position.X, input.Position.Y)
	local topLeft = guiObject.AbsolutePosition
	local bottomRight = topLeft + guiObject.AbsoluteSize

	return point.X >= topLeft.X
		and point.X <= bottomRight.X
		and point.Y >= topLeft.Y
		and point.Y <= bottomRight.Y
end

gui.Overlay.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		if currentLayer == 1 and isInputInside(gui.NoteFrame, input) then
			return
		end

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
		return
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not isDraggingImage or currentLayer ~= 1 then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
		local inputPosition = Vector2.new(input.Position.X, input.Position.Y)
		imagePan = dragStartPan + (inputPosition - dragStartPosition)
		updateImageTransform()
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

SystemHub.ready("NoteSystem", script)
print("[NoteSystem] Note system ready.")
