extends RefCounted
var game: Node
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS: " if ok else "FAIL: ", label)
	if not ok: failures += 1
func fresh() -> void:
	game.mode = "menu"
	game.total_xp = 0
	game.first_clear = false
	game.contract_progress = 0
	game.action_open = false
	game.selected_loadout = "basic"
	game._show_menu()
	game.start_game()
	game.spawn_clock = 10000.0
func shoot(count_value: int) -> void:
	for i in range(count_value):
		game.enemies.clear()
		game.bullets.clear()
		game.aim = Vector2.RIGHT
		game.enemies.append({"pos": game.player + Vector2(65, 0), "speed": 0.0})
		game._fire()
		game._update_bullets(0.1)
func bot(seed_value: int) -> void:
	game.rng.seed = seed_value
	game.spawn_clock = 0.0
	for i in range(10800):
		var target: Vector2 = game.player + Vector2.RIGHT * 200
		var best := INF
		for enemy in game.enemies:
			var distance: float = game.player.distance_squared_to(enemy.pos)
			if distance < best:
				best = distance
				target = enemy.pos
		var direction := Vector2.ZERO
		if game.contract_progress >= 12 and game.player.distance_to(game.EXFIL_POSITION) > 7:
			direction = game.player.direction_to(game.EXFIL_POSITION)
		var channel: bool = game.contract_progress >= 12 and game.player.distance_to(game.EXFIL_POSITION) < 30
		game.simulate(1.0 / 60.0, direction, target, true, channel)
		if game.mode != "playing": break
func run(target_game: Node) -> void:
	game = target_game
	game.set_physics_process(false)
	if OS.get_environment("NEON_SAVE_PATH").is_empty(): game.save_path = "user://neon_qa_v03.json"
	fresh()
	check(str(game.contract.id) == "CONTRACT_002" and str(game.contract.name) == "步枪成长训练", "published contract identity matches design baseline")
	check(game.save_ok, "action-start journal commits")
	var origin: Vector2 = game.player
	game.simulate(0.25, Vector2.ONE, origin, false)
	check(is_equal_approx(game.player.distance_to(origin), 70), "normalized movement unchanged")
	shoot(7)
	check(game.contract_progress == 7 and game.total_xp == 0, "real bullets accumulate progress without paying XP")
	var data = JSON.parse_string(FileAccess.get_file_as_string(game.save_path))
	check(data.version == 3 and data.contract_id == "CONTRACT_002", "save belongs to the published contract")
	check(data.contract_progress == 7 and data.action_open, "each kill writes progress before match ends")
	game.health = 1
	game._take_damage()
	check(game.mode == "lost" and game.contract_progress == 7 and game.total_xp == 0, "death preserves partial contract progress")
	game._primary_action()
	game._primary_action()
	check(game.kills == 0 and game.contract_progress == 7, "next action resumes same contract with fresh round")
	shoot(5)
	check(game.contract_progress == 12 and game.total_xp == 0 and game.mode == "playing", "cross-round target reached, reward still pending")
	shoot(3)
	check(game.contract_progress == 12 and game.kills == 8, "extra kills do not prepay another acceptance")
	game.health = 1
	game.immunity = 0.0
	game._take_damage()
	check(game.mode == "won" and game.total_xp == 200 and game.last_reward == 200, "death after target awards full first-clear XP")
	check(game.contract_progress == 0 and not game.action_open and game.first_clear, "settlement resets accepted objective and commits receipt")
	game._finish(false)
	check(game.total_xp == 200, "duplicate terminal event cannot award again")
	game._show_menu()
	check(not game.loadout_buttons[1].disabled, "persistent XP unlocks actual choices")
	game.start_game()
	shoot(12)
	game._finish(false, "主动退出")
	check(game.total_xp == 280 and game.last_reward == 80, "voluntary ending gives repeat base XP only")
	game._show_menu()
	game.start_game()
	shoot(3)
	game._finish(true)
	check(game.contract_progress == 3 and game.total_xp == 280, "early extraction preserves progress without reward")
	game.start_game()
	shoot(9)
	game._finish(true)
	check(game.total_xp == 360 and game.contract_progress == 0, "extraction also settles accumulated contract")
	game.total_xp = 0
	game.first_clear = false
	game.contract_progress = 0
	game._load_progress()
	check(game.total_xp == 360 and game.first_clear and not game.action_open, "saved XP and receipt reload together")
	fresh()
	shoot(7)
	game.contract_progress = 0
	game.action_open = false
	game._load_progress()
	game._recover_interrupted_action()
	check(game.contract_progress == 7 and game.total_xp == 0 and not game.action_open, "interrupted partial action recovers without reward")
	game.start_game()
	shoot(5)
	game.contract_progress = 0
	game.action_open = false
	game._load_progress()
	game._recover_interrupted_action()
	check(game.total_xp == 200 and game.last_reward == 200 and not game.action_open, "interrupted achieved action settles on restart")
	game._load_progress()
	game._recover_interrupted_action()
	check(game.total_xp == 200, "another restart does not duplicate recovered reward")
	fresh()
	shoot(12)
	game._toggle_pause()
	var old_time: float = game.elapsed
	game.simulate(2.0, Vector2.ONE, game.player, true)
	check(game.elapsed == old_time and game.total_xp == 0, "pause does not settle achieved contract")
	game._finish(false, "主动退出")
	check(game.total_xp == 200, "ending from paused state can settle")
	fresh()
	shoot(12)
	game.contract.requires_exfil = true
	game._finish(false)
	check(game.total_xp == 0, "end check never invents a required successful extraction")
	game.contract.requires_exfil = false
	for seed_value in [12, 48, 137]:
		fresh()
		bot(seed_value)
		check(game.mode == "won" and game.total_xp == 200, "full ordinary combat and ending seed %d" % seed_value)
	fresh()
	game._fire()
	check(game.muzzle_flash > 0, "muzzle feedback retained")
	shoot(1)
	check(not game.impacts.is_empty(), "localized impact feedback retained")
	var out_dir := OS.get_environment("NEON_QA_DIR")
	if not out_dir.is_empty():
		var report := FileAccess.open(out_dir.path_join("v04_logic.json"), FileAccess.WRITE)
		report.store_string(JSON.stringify({"checks": checks, "failures": failures, "completed": true}))
	print("RESULT: %d checks, %d failures" % [checks, failures])
	game.get_tree().quit(0 if failures == 0 else 1)
