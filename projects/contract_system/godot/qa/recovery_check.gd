extends RefCounted
func run(game: Node) -> void:
	game.set_physics_process(false)
	var expected_xp := int(OS.get_environment("NEON_EXPECT_XP"))
	var expected_progress := int(OS.get_environment("NEON_EXPECT_PROGRESS"))
	var passed: bool = game.total_xp == expected_xp and game.contract_progress == expected_progress and not game.action_open and game.save_ok
	var report := FileAccess.open(OS.get_environment("NEON_QA_DIR").path_join("recovery_result.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed": passed, "xp": game.total_xp, "progress": game.contract_progress, "action_open": game.action_open, "note": game.recovery_note}))
	print("RECOVERY ", "PASS" if passed else "FAIL", " xp=", game.total_xp, " progress=", game.contract_progress)
	game.get_tree().quit(0 if passed else 1)
