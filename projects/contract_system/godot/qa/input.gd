extends RefCounted
var game: Node
var failures := 0
func check(ok: bool, title: String) -> void:
	print("INPUT ", "PASS " if ok else "FAIL ", title)
	if not ok: failures += 1
func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
func run(target_game: Node) -> void:
	game = target_game
	game.selected_loadout = "basic"
	game.contract_progress = 0
	game.total_xp = 0
	game.first_clear = false
	game.action_open = false
	var tree := game.get_tree()
	await tree.process_frame
	key(KEY_ENTER, true)
	await tree.physics_frame
	key(KEY_ENTER, false)
	check(game.mode == "playing", "Enter event starts gameplay")
	var origin: Vector2 = game.player
	key(KEY_D, true)
	for i in range(8): await tree.physics_frame
	key(KEY_D, false)
	check(game.player.x > origin.x + 20, "physical D key moves player")
	game.cooldown = 0.0
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = Vector2(900, 380)
	Input.parse_input_event(event)
	for i in range(4): await tree.physics_frame
	check(game.bullets.size() > 0, "mouse left fires weapon through live input")
	event.pressed = false
	Input.parse_input_event(event)
	key(KEY_ESCAPE, true)
	await tree.physics_frame
	key(KEY_ESCAPE, false)
	check(game.paused and game.overlay.visible, "Esc input pauses")
	var old_time: float = game.elapsed
	for i in range(6): await tree.physics_frame
	check(game.elapsed == old_time, "live physics remains paused")
	key(KEY_ENTER, true)
	await tree.physics_frame
	key(KEY_ENTER, false)
	check(not game.paused and game.mode == "playing", "Enter resumes")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.paused, "focus loss auto-pauses")
	game._toggle_pause()
	game.enemies.clear()
	game.spawn_clock = 10000.0
	game.player = game.EXFIL_POSITION
	key(KEY_E, true)
	for i in range(10): await tree.physics_frame
	check(game.exfil_progress > 0 and game.mode == "playing", "E key begins extraction in zone")
	key(KEY_E, false)
	await tree.physics_frame
	await tree.physics_frame
	check(game.exfil_progress == 0, "E release cancels channel")
	key(KEY_E, true)
	for i in range(90): await tree.physics_frame
	key(KEY_E, false)
	check(game.mode == "extracted" and game.last_reward == 0, "E hold completes real early extraction")
	key(KEY_ENTER, true)
	await tree.physics_frame
	key(KEY_ENTER, false)
	check(game.mode == "menu", "result Enter returns to contract board")
	key(KEY_ENTER, true)
	await tree.physics_frame
	key(KEY_ENTER, false)
	check(game.mode == "playing" and game.kills == 0, "board Enter starts another contract")
	print("INPUT RESULT: ", failures, " failures")
	var report_dir := OS.get_environment("NEON_QA_DIR")
	if not report_dir.is_empty():
		var report := FileAccess.open(report_dir.path_join("v04_input.json"), FileAccess.WRITE)
		report.store_string(JSON.stringify({"failures": failures, "completed": true}))
	game.get_tree().quit(0 if failures == 0 else 1)


