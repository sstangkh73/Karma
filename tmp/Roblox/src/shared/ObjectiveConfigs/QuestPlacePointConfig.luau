return {
	TagName = "QuestPlacePoint",
	IdAttribute = "QuestPlacePointId",
	Points = {
		{
			Id = "find_jada_altar",
			RequiredDefinitionIds = { "Jada" },
			CompleteObjectiveIds = { "find_jada" },
			-- OnCompletedCallback = "FindJadaCompleted",
		},
		-- Add more quest place point definitions here:
		-- {
		-- 	Id = "your_place_point_id",
		-- 	RequiredDefinitionIds = { "YourPlacedItemDefinitionId" },
		-- 	StartObjectiveIds = { "your_quest_id" },
		-- 	CompleteObjectiveIds = { "your_quest_id" },
		-- 	OnStartedCallback = "YourQuestStarted",
		-- 	OnCompletedCallback = "YourQuestCompleted",
		-- },
	},
}
