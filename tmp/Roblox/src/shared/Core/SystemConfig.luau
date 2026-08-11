-- Central switchboard for every runtime system in KARMA.
-- Change Enabled here, then start a new Play session for the change to apply.

local SystemConfig = {
	Version = "1.3.0",
	Debug = true,
	StatusRootName = "KarmaSystemHub",

	Systems = {
		-- Server
		ServerCoreBootstrap = {
			Side = "Server",
			Kind = "Bootstrap",
			Enabled = true,
			Priority = 0,
			SourceName = "CoreBootstrap",
			Description = "Starts and monitors server service modules.",
		},
		LoadingGateService = {
			Side = "Server",
			Kind = "Service",
			Enabled = true,
			Priority = 10,
			Description = "Streams and verifies the critical spawn radius before releasing players.",
		},
		LightingGuard = {
			Side = "Server",
			Kind = "Standalone",
			Enabled = true,
			Priority = 20,
			Description = "Owns and restores the global night lighting preset.",
		},
		CutsceneAssetService = {
			Side = "Server",
			Kind = "Service",
			Enabled = true,
			Priority = 25,
			Description = "Loads camera cutscene assets into ReplicatedStorage for client playback.",
		},
		ObjectiveService = {
			Side = "Server",
			Kind = "Service",
			Enabled = true,
			Priority = 30,
			Description = "Owns player objective state and the objective server API.",
		},
		InventoryService = {
			Side = "Server",
			Kind = "Standalone",
			Enabled = true,
			Priority = 40,
			IntegratesWith = { "ObjectiveService", "InteractionService" },
			Description = "Owns authoritative inventory and held-item state.",
		},
		AdminCommandService = {
			Side = "Server",
			Kind = "Service",
			Enabled = true,
			Priority = 75,
			Dependencies = { "InventoryService", "TeacherDeskLockService" },
			Description = "Runs permission-gated testing commands through TextChatService.",
		},
		InteractionService = {
			Side = "Server",
			Kind = "Service",
			Enabled = true,
			Priority = 50,
			IntegratesWith = { "InventoryService", "ObjectiveService" },
			Description = "Validates world interactions and creates prompts.",
		},
		ObjectiveTriggerService = {
			Side = "Server",
			Kind = "Service",
			Enabled = true,
			Priority = 60,
			Dependencies = { "ObjectiveService" },
			Description = "Translates tagged world triggers into objective updates.",
		},
		DialogueService = {
			Side = "Server",
			Kind = "Service",
			Enabled = true,
			Priority = 65,
			IntegratesWith = { "InteractionService", "ObjectiveTriggerService" },
			Description = "Routes note, reach-point, and custom events into authoritative dialogue sequences.",
		},
		TeacherDeskLockService = {
			Side = "Server",
			Kind = "Service",
			Enabled = true,
			Priority = 70,
			Dependencies = { "ObjectiveService", "DialogueService" },
			Description = "Owns the dance-room key pickup and teacher-desk lock sequence.",
		},

		-- Client
		ClientCoreBootstrap = {
			Side = "Client",
			Kind = "Bootstrap",
			Enabled = true,
			Priority = 0,
			SourceName = "CoreBootstrap",
			Description = "Starts and monitors client controller modules.",
		},
		SpawnLoadingScreen = {
			Side = "Client",
			Kind = "Standalone",
			Enabled = true,
			Priority = 10,
			IntegratesWith = { "LoadingGateService" },
			Description = "Verifies radial streaming, preloads critical assets, warms materials and shadows, and coordinates the warning gate.",
		},
		InventorySystem = {
			Side = "Client",
			Kind = "Standalone",
			Enabled = true,
			Priority = 20,
			IntegratesWith = { "InventoryService" },
			Description = "Renders inventory UI and sends inventory requests.",
		},
		AdminCommandController = {
			Side = "Client",
			Kind = "Controller",
			Enabled = true,
			Priority = 25,
			IntegratesWith = { "AdminCommandService" },
			Description = "Displays private admin command feedback in the local chat window.",
		},
		InteractionController = {
			Side = "Client",
			Kind = "Controller",
			Enabled = true,
			Priority = 30,
			IntegratesWith = { "InteractionService" },
			Description = "Renders localized prompts and interaction feedback.",
		},
		NoteSystem = {
			Side = "Client",
			Kind = "Standalone",
			Enabled = true,
			Priority = 40,
			IntegratesWith = { "InteractionController", "InteractionService" },
			Description = "Opens notes and records discovered journal entries.",
		},
		ObjectiveController = {
			Side = "Client",
			Kind = "Controller",
			Enabled = true,
			Priority = 50,
			IntegratesWith = { "ObjectiveService" },
			Description = "Renders current player objectives.",
		},
		PhoneController = {
			Side = "Client",
			Kind = "Controller",
			Enabled = true,
			Priority = 60,
			IntegratesWith = { "NoteSystem", "ObjectiveController" },
			Description = "Owns the in-game phone, journal, and map UI.",
		},
		DialogueController = {
			Side = "Client",
			Kind = "Controller",
			Enabled = true,
			Priority = 65,
			IntegratesWith = { "DialogueService", "NoteSystem" },
			Description = "Queues, localizes, presents, advances, and skips dialogue without UI overlap.",
		},
		FlashlightSystem = {
			Side = "Client",
			Kind = "Standalone",
			Enabled = true,
			Priority = 70,
			IntegratesWith = { "InventorySystem" },
			Description = "Keeps equipped flashlight beams aligned to the camera.",
		},
		SprintSystem = {
			Side = "Client",
			Kind = "Standalone",
			Enabled = true,
			Priority = 80,
			Description = "Owns sprint input, stamina, audio, and camera effects.",
		},
	},
}

function SystemConfig.get(systemName: string)
	return SystemConfig.Systems[systemName]
end

function SystemConfig.findBySource(side: string, sourceName: string)
	for systemName, definition in pairs(SystemConfig.Systems) do
		if definition.Side == side and (definition.SourceName or systemName) == sourceName then
			return systemName, definition
		end
	end

	return nil, nil
end

return SystemConfig
