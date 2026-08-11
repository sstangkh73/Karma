-- Dialogue authoring lives here. Runtime code should refer to sequence and
-- trigger ids instead of embedding dialogue text in world scripts.

return {
	Settings = {
		CharacterDelay = 0.020833,
		AutoAdvanceDelay = 3.75,
		InputCooldown = 0.12,
		ReachPointTag = "DialogueTrigger",
		ReachPointIdAttribute = "DialogueTriggerId",
		DirectSequenceAttribute = "DialogueSequenceId",
		OncePerPlayerAttribute = "DialogueOncePerPlayer",
		NamedReachPoints = {
			["BarrierPart(E)"] = true,
			["BarrierPart(S)"] = true,
			["Folhas caíndo"] = true,
			Zone1 = true,
			Zone2 = true,
		},
		RepeatableNamedReachPoints = {
			["BarrierPart(E)"] = true,
			["BarrierPart(S)"] = true,
		},
		SubtitleUI = {
			WidthScale = 0.36,
			PositionY = 0.82,
			HeightScale = 0.065,
			MinWidth = 140,
			MaxWidth = 575,
			MinHeight = 48,
			MaxHeight = 70,
			MinTextSize = 18,
			MaxTextSize = 26,
			ShowSpeaker = false,
			ShowHint = false,
			ShowSkipButton = false,
			TextColor = { 246, 246, 246 },
			LineColor = { 245, 245, 245 },
		},
	},

	Sequences = {
		after_note_0 = {
			Enabled = true,
			Priority = 10,
			Once = true,
			Triggers = {
				{ Type = "NoteRead", Id = "note_0" },
			},
			Lines = {
				{
					Speaker = { th = "วิน", en = "Win" },
					Text = {
						th = "แม่ง มันรู้ได้ยังไง",
						en = "How the hell did it know?",
					},
				},
			},
		},

		after_note_1 = {
			Enabled = true,
			Priority = 10,
			Once = true,
			OnFinishedObjectiveId = "go_to_cafeteria_shrine",
			Triggers = {
				{ Type = "NoteRead", Id = "note_1" },
			},
			Lines = {
				{
					Speaker = { th = "ตัวเรา", en = "Me" },
					Text = {
						th = "แม่ง มันรู้ได้ยังไง",
						en = "How the hell did it know?",
					},
				},
				{
					Speaker = { th = "ตัวเรา", en = "Me" },
					Text = {
						th = "ต้องรีบไปแล้ว หวังว่าศาลจะยังอยู่นะ",
						en = "I need to hurry. I hope the shrine is still there.",
					},
				},
			},
		},

		after_note_2 = {
			Enabled = true,
			Priority = 10,
			Once = true,
			OnFinishedObjectiveId = "go_to_new_building",
			Triggers = {
				{ Type = "NoteRead", Id = "note_2" },
			},
			Lines = {
				{
					Speaker = { th = "ตัวเรา", en = "Me" },
					Text = {
						th = "ครูฟ้าเก็บไปหรอ ทำไมกัน",
						en = "Teacher Fa took it? Why?",
					},
				},
			},
		},

		after_note_5 = {
			Enabled = true,
			Priority = 10,
			Once = true,
			EndDemo = {
				CameraCutsceneAssetId = "89170980344167",
				CameraCutsceneName = "END_DEMO",
				CameraFramesPerSecond = 60,
				HoldBeforeAnimation = 2.5,
				FadeDuration = 2.5,
				Text = "กรรม 1/10\n\nบางความจริง\nตกทอดมาพร้อมนามสกุล\n\nEND OF DEMO",
			},
			Triggers = {
				{ Type = "NoteRead", Id = "note_5" },
			},
			Lines = {
				{
					Speaker = { th = "วิน", en = "Win" },
					AutoAdvanceDelay = 0,
					Text = {
						th = "นี่มันนามสกุลฉัน",
						en = "That's my last name.",
					},
				},
			},
		},

		teacher_desk_locked = {
			Enabled = true,
			Priority = 10,
			Once = false,
			Lines = {
				{
					Speaker = { th = "ตัวเรา", en = "Me" },
					Text = {
						th = "ลิ้นชักล็อกอยู่... ต้องหากุญแจมาเปิด",
						en = "The drawer is locked... I need to find its key.",
					},
				},
			},
		},

		phone_battery_dead = {
			Enabled = true,
			Priority = 10,
			Once = false,
			Lines = {
				{
					Speaker = { th = "ตัวเรา", en = "Me" },
					Text = {
						th = "แบตหมด ทำไงดีทีนี้",
						en = "The battery is dead. What do I do now?",
					},
				},
			},
		},

		chada_complete_need_lighter = {
			Enabled = true,
			Priority = 10,
			Once = false,
			OnFinishedObjectiveId = "find_lighter_for_candles",
			Lines = {
				{
					Speaker = { th = "ตัวเรา", en = "Me" },
					Text = {
						th = "อาจจะต้องจุดเทียนด้วย หาไฟแช็กมาจุดมัน",
						en = "Maybe the candles need to be lit too. I should find a lighter.",
					},
				},
			},
		},

		teacher_desk_key_collected = {
			Enabled = true,
			Priority = 10,
			Once = true,
			Lines = {
				{
					Speaker = { th = "ตัวเรา", en = "Me" },
					Text = {
						th = "กุญแจดอกนี้น่าจะใช้เปิดลิ้นชักโต๊ะครูได้",
						en = "This key should open the teacher's desk drawer.",
					},
				},
			},
		},

		teacher_desk_unlocked = {
			Enabled = true,
			Priority = 10,
			Once = true,
			Lines = {
				{
					Speaker = { th = "ตัวเรา", en = "Me" },
					Text = {
						th = "เปิดได้แล้ว... โทรศัพท์อยู่ในนี้จริงๆ",
						en = "It opened... the phone really is in here.",
					},
				},
			},
		},

		zone1_new_building = {
			Enabled = true,
			Priority = 5,
			Once = true,
			Triggers = {
				{ Type = "ReachPoint", Id = "Zone1" },
			},
			Lines = {
				{
					Speaker = { th = "ตัวเรา", en = "Me" },
					Text = {
						th = "นี่น่าจะตึกใหม่ที่ผอ.คนนั้นสร้างแน่เลย",
						en = "This must be the new building that director built.",
					},
				},
				{
					Speaker = { th = "ตัวเรา", en = "Me" },
					Text = {
						th = "เดี๋ยวมาแวะแล้วกัน มีสิ่งที่สำคัญกว่า",
						en = "The teacher's desk should be inside. I should take a look.",
					},
				},
			},
		},

		zone2_new_building_wood = {
			Enabled = true,
			Priority = 5,
			Once = true,
			Triggers = {
				{ Type = "ReachPoint", Id = "Zone2" },
			},
			Lines = {
				{
					Speaker = { th = "ตัวเรา", en = "Me" },
					Text = {
						th = "ทำไมเป้นไม้",
						en = "Wait, why is the building made of wood?",
					},
				},
			},
		},

		folhas_caindo_dig_karma = {
			Enabled = true,
			Priority = 5,
			Once = true,
			OnFinishedObjectiveId = "dig_karma",
			Triggers = {
				{ Type = "ReachPoint", Id = "Folhas caíndo" },
			},
			Lines = {
				{
					Speaker = { th = "ตัวเรา", en = "Me" },
					Text = {
						th = "ถ้าจำไม่ผิดน่าจะอยู่แล้วหินนะ",
						en = "If I remember correctly, it should be by the rock.",
					},
				},
			},
		},

		barrier_part_s = {
			Enabled = true,
			Priority = 5,
			Once = false,
			Triggers = {
				{ Type = "ReachPoint", Id = "BarrierPart(S)" },
			},
			Lines = {
				{
					Speaker = { th = "ตัวเรา", en = "Me" },
					Text = {
						th = "ฉันยังไปไม่ได้",
						en = "I still cannot go yet.",
					},
				},
			},
		},

		barrier_part_e = {
			Enabled = true,
			Priority = 5,
			Once = false,
			Triggers = {
				{ Type = "ReachPoint", Id = "BarrierPart(E)" },
			},
			Lines = {
				{
					Speaker = { th = "ตัวเรา", en = "Me" },
					Text = {
						th = "ฉันยังไม่ควรไปตอนนี้",
						en = "I should not go there right now.",
					},
				},
			},
		},

		-- Template for a walk-to-point trigger. Enable it, change the id/text,
		-- then tag a BasePart with DialogueTrigger and set DialogueTriggerId.
		reach_point_example = {
			Enabled = false,
			Priority = 5,
			Once = true,
			Triggers = {
				{ Type = "ReachPoint", Id = "example_hallway" },
			},
			Lines = {
				{
					Speaker = { th = "ตัวเรา", en = "Me" },
					Text = {
						th = "แทนที่ข้อความตัวอย่างนี้ใน DialogueContent",
						en = "Replace this example line in DialogueContent.",
					},
				},
			},
		},
	},
}
