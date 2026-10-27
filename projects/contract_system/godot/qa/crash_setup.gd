extends RefCounted
func run(game: Node) -> void:
	game.set_physics_process(false)
	game.total_xp = 0
	game.first_clear = false
	game.contract_progress = 0
	game.action_open = false
	game.start_game()
	var count_value := int(OS.get_environment("NEON_CRASH_COUNT"))
	for i in range(count_value):
		game.enemies.clear()
		game.bullets.clear()
		game.aim = Vector2.RIGHT
		game.enemies.append({"pos": game.player + Vector2(65, 0), "speed": 0.0})
		game._fire()
		game._update_bullets(0.1)
	var report := FileAccess.open(OS.get_environment("NEON_QA_DIR").path_join("crash_ready.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"ready": game.save_ok, "progress": game.contract_progress}))
	report.close()
	if OS.get_environment("NEON_NORMAL_CLOSE") == "1": game._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
