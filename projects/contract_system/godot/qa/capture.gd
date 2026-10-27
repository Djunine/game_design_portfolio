extends RefCounted
var tree: SceneTree
var game: Node
var out_dir := ""
func capture(name_value: String) -> void:
	game.queue_redraw()
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var image := tree.root.get_texture().get_image()
	print("CAPTURE ", name_value, " result=", image.save_png(out_dir.path_join(name_value + ".png")))
func shoot(count_value: int) -> void:
	for i in range(count_value):
		game.enemies.clear()
		game.bullets.clear()
		game.aim = Vector2.RIGHT
		game.enemies.append({"pos": game.player + Vector2(65, 0), "speed": 0.0})
		game._fire()
		game._update_bullets(0.1)
func run(target_game: Node) -> void:
	game = target_game
	tree = game.get_tree()
	out_dir = OS.get_environment("NEON_CAPTURE_DIR")
	if OS.get_environment("NEON_SAVE_PATH").is_empty(): game.save_path = "user://neon_qa_capture_v03.json"
	game.set_physics_process(false)
	game.total_xp = 0
	game.first_clear = false
	game.contract_progress = 0
	game.action_open = false
	game.selected_loadout = "basic"
	game.recovery_note = ""
	game._show_menu()
	await capture("01_board")
	game.start_game()
	shoot(7)
	game.health = 1
	game._take_damage()
	await capture("02_partial_death_retained")
	game._primary_action()
	await capture("03_resume_seven")
	game.start_game()
	shoot(5)
	game._update_hud()
	await capture("04_achieved_pending")
	game.health = 1
	game.immunity = 0
	game._take_damage()
	await capture("05_death_but_rewarded")
	game._primary_action()
	DisplayServer.window_set_size(Vector2i(960, 600))
	await tree.process_frame
	await capture("06_small_window")
	game.start_game()
	shoot(12)
	game._load_progress()
	game._recover_interrupted_action()
	game._show_menu()
	await capture("07_recovered_once")
	tree.quit()
