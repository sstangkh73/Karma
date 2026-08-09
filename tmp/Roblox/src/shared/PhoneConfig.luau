local Theme = require(script.Parent:WaitForChild("UITheme"))

local PhoneConfig = {
	UI = {
		ToggleKey = Enum.KeyCode.P,
		CloseKey = Enum.KeyCode.Backspace,
		InputPriority = Enum.ContextActionPriority.Medium.Value,
		DisplayOrder = 850,
	},
	Map = {
		StudsAcross = 520,
		ImageId = "",
		ImageCenter = Vector3.new(0, 0, 0),
		ImageSizeStuds = Vector2.new(1000, 1000),
		ImageTransparency = 0,
		ShowGridOverImage = false,
		MinZoom = 0.55,
		MaxZoom = 3,
		RefreshInterval = 0.2,
		MarkerScanInterval = 2,
		MarkerTagName = "PhoneMapPoint",
	},
	Apps = {
		{
			Id = "Diary",
			Name = "Archive",
			Icon = "NOTE",
			Accent = Theme.Colors.Brass,
		},
		{
			Id = "Map",
			Name = "Site Map",
			Icon = "MAP",
			Accent = Theme.Colors.MapGrid,
		},
	},
}

return PhoneConfig
