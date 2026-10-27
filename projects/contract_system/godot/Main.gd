extends Node2D
## Single-player standard contract loop. Geometry combat is deliberately small.
const ARENA := Rect2(48, 118, 1056, 524)
const PLAYER_RADIUS := 15.0
const ENEMY_RADIUS := 17.0
const PLAYER_SPEED := 280.0
const BULLET_SPEED := 850.0
const FIRE_INTERVAL := 0.18
const EXFIL_POSITION := Vector2(1048, 586)
const EXFIL_RADIUS := 40.0
const CYAN := Color("68e8df")
const ORANGE := Color("ffa96b")
const MUTED := Color("8496ac")

var mode := "menu"
var paused := false
var player := Vector2(576, 380)
var aim := Vector2.RIGHT
var health := 3
var kills := 0
var elapsed := 0.0
var cooldown := 0.0
var immunity := 0.0
var spawn_clock := 0.0
var enemies: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var sparks: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var font: Font
var hud: Label
var status: Label
var overlay: Control
var heading: Label
var description: Label
var action: Button
var secondary: Button
var pause_button: Button
var hit_flash := 0.0
var qa_runner: RefCounted
var contract: Dictionary
var total_xp := 0
var first_clear := false
var selected_loadout := "basic"
var loadout_buttons: Array[Button] = []
var exfil_progress := 0.0
var muzzle_flash := 0.0
var impacts: Array[Dictionary] = []
var last_reward := 0
var save_path := ""
var save_ok := true
var contract_progress := 0
var action_open := false
var recovery_note := ""
var last_bonus := 0
var last_finished_progress := 0

func _load_progress() -> void:
	if not FileAccess.file_exists(save_path): return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null: return
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary: return
	if int(data.get("version", 0)) != 3: return
	if str(data.get("contract_id", "")) != str(contract.id): return
	total_xp = clampi(int(data.get("total_xp", 0)), 0, 2000000000)
	first_clear = bool(data.get("first_clear", false))
	contract_progress = clampi(int(data.get("contract_progress", 0)), 0, int(contract.required_count))
	action_open = bool(data.get("action_open", false))
	var choice := str(data.get("loadout", "basic"))
	selected_loadout = choice if choice in ["basic", "rapid", "mobile"] else "basic"
	if total_xp < int(contract.mod_unlock_xp): selected_loadout = "basic"

func _save_progress() -> void:
	# One atomic file replacement commits progress, reward and receipt together.
	# Interrupted writes leave the last committed file intact.
	var temporary := save_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	save_ok = file != null
	if not save_ok: return
	file.store_string(JSON.stringify({"version": 3, "contract_id": str(contract.id), "total_xp": total_xp, "first_clear": first_clear, "loadout": selected_loadout, "contract_progress": contract_progress, "action_open": action_open}))
	file.flush()
	var write_ok := file.get_error() == OK
	file.close()
	if not write_ok:
		save_ok = false
		return
	save_ok = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(save_path)) == OK

func _record_kill() -> void:
	if contract_progress >= int(contract.required_count): return
	contract_progress += 1
	_save_progress()

func _settle_action(extracted: bool) -> void:
	last_reward = 0
	last_bonus = 0
	var completed := contract_progress >= int(contract.required_count)
	if bool(contract.requires_exfil): completed = completed and extracted
	if completed:
		last_bonus = 0 if first_clear else int(contract.first_clear_bonus)
		last_reward = int(contract.base_xp) + last_bonus
		total_xp += last_reward
		first_clear = true
		contract_progress = 0
	elif not bool(contract.retain_on_failure):
		contract_progress = 0
	action_open = false
	_save_progress()

func _recover_interrupted_action() -> void:
	if not action_open: return
	_settle_action(false)
	recovery_note = "上次行动补结算 +%d 经验" % last_reward if last_reward > 0 else "上次行动已结束，目标进度已保留"

func _request_quit() -> void:
	if mode == "playing": _finish(false, "主动退出")
	get_tree().quit()

func _loadout_name() -> String:
	return {"basic": "基础", "rapid": "速射", "mobile": "机动"}[selected_loadout]

func _select_loadout(value: String) -> void:
	if value != "basic" and total_xp < int(contract.mod_unlock_xp): return
	selected_loadout = value
	for button in loadout_buttons: button.release_focus()
	_update_loadout_buttons()
	_update_hud()

func _update_loadout_buttons() -> void:
	for i in range(loadout_buttons.size()):
		var id_value: String = ["basic", "rapid", "mobile"][i]
		var locked := i > 0 and total_xp < int(contract.mod_unlock_xp)
		loadout_buttons[i].disabled = locked
		loadout_buttons[i].text = ["基础配装", "速射改装", "机动改装"][i]
		if locked: loadout_buttons[i].text += " · 200 XP"
		elif selected_loadout == id_value: loadout_buttons[i].text += " ✓"
		loadout_buttons[i].visible = mode == "menu"


func _ready() -> void:
	rng.randomize()
	var config_file := FileAccess.open("res://data/contract.json", FileAccess.READ)
	contract = JSON.parse_string(config_file.get_as_text())
	save_path = OS.get_environment("NEON_SAVE_PATH")
	if save_path.is_empty():
		save_path = "res://progress.json" if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("progress.json")
	_load_progress()
	var ui_font := FontVariation.new()
	ui_font.base_font = load("res://assets/Chinese.ttf")
	ui_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 450.0}
	font = ui_font
	_build_ui()
	get_tree().auto_accept_quit = false
	_recover_interrupted_action()
	_show_menu()
	queue_redraw()
	# Explicit developer-only launch arguments; ordinary play never invokes QA.
	var args := OS.get_cmdline_user_args()
	for option in [["--qa-logic", "run"], ["--qa-input", "input"], ["--qa-capture", "capture"], ["--qa-crash-setup", "crash_setup"], ["--qa-recovery-check", "recovery_check"]]:
		if args.has(option[0]):
			qa_runner = load("res://qa/%s.gd" % option[1]).new()
			qa_runner.call_deferred("run", self)
			break

func _label(value: String, pos: Vector2, extent: Vector2, font_size: int, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = value
	label.position = pos
	label.size = extent
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(value: String, pos: Vector2, extent: Vector2, primary: bool) -> Button:
	var button := Button.new()
	button.text = value
	button.position = pos
	button.size = extent
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", 20)
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("287c7b") if primary else Color("1a293c")
		if state == "hover": box.bg_color = Color("369a96") if primary else Color("2e445d")
		if state == "pressed": box.bg_color = Color("205f65")
		box.border_color = CYAN if primary or state == "focus" else Color("3b4e64")
		box.set_border_width_all(2 if state == "focus" else 1)
		box.set_corner_radius_all(8)
		button.add_theme_stylebox_override(state, box)
	return button

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(_label("微光竞技场", Vector2(48, 20), Vector2(350, 40), 30))
	layer.add_child(_label("CONTRACT_002   /   MVP 0.4", Vector2(49, 64), Vector2(360, 28), 14, MUTED))
	hud = _label("", Vector2(425, 20), Vector2(520, 72), 20)
	layer.add_child(hud)
	pause_button = _button("暂停  Esc", Vector2(962, 30), Vector2(142, 46), false)
	pause_button.pressed.connect(_toggle_pause)
	layer.add_child(pause_button)
	layer.add_child(_label("WASD 移动 · 鼠标瞄准 / 左键射击 · E 按住撤离 · Esc 暂停", Vector2(48, 664), Vector2(800, 34), 17, MUTED))
	status = _label("", Vector2(830, 664), Vector2(274, 34), 17, CYAN)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	layer.add_child(status)
	overlay = Control.new()
	overlay.size = Vector2(1152, 720)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(overlay)
	var veil := ColorRect.new()
	veil.color = Color(0.015, 0.025, 0.05, 0.9)
	veil.position = ARENA.position
	veil.size = ARENA.size
	overlay.add_child(veil)
	var panel := Panel.new()
	panel.position = Vector2(270, 145)
	panel.size = Vector2(612, 460)
	var box := StyleBoxFlat.new()
	box.bg_color = Color("101e30")
	box.border_color = Color("36506a")
	box.set_border_width_all(1)
	box.set_corner_radius_all(16)
	panel.add_theme_stylebox_override("panel", box)
	overlay.add_child(panel)
	overlay.add_child(_label("CONTRACT_002   /   成长合约", Vector2(306, 170), Vector2(540, 30), 17, CYAN))
	heading = _label("", Vector2(306, 207), Vector2(540, 56), 34)
	overlay.add_child(heading)
	description = _label("", Vector2(306, 266), Vector2(540, 132), 19, Color("b5c8db"))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay.add_child(description)
	for i in range(3):
		var button := _button("", Vector2(306 + i * 184, 408), Vector2(172, 44), false)
		button.add_theme_font_size_override("font_size", 16)
		var id_value: String = ["basic", "rapid", "mobile"][i]
		button.pressed.connect(_select_loadout.bind(id_value))
		loadout_buttons.append(button)
		overlay.add_child(button)
	action = _button("", Vector2(306, 478), Vector2(334, 58), true)
	action.pressed.connect(_primary_action)
	overlay.add_child(action)
	secondary = _button("退出游戏", Vector2(656, 478), Vector2(190, 58), false)
	secondary.pressed.connect(_request_quit)
	overlay.add_child(secondary)
	overlay.add_child(_label("目标进度实时保留 · 合约达标后在离局时结算", Vector2(306, 557), Vector2(540, 25), 15, MUTED))

func _show_menu() -> void:
	mode = "menu"
	paused = false
	heading.text = str(contract.name)
	description.text = "累计步枪击败 %d 个目标，无需成功撤离。\n当前进度 %d / %d，阵亡或退出后仍保留。\n达标后在离局时结算：首通 200，重玩 80。\n异常退出将在下次进入时检查并补结算。" % [contract.required_count, contract_progress, contract.required_count]
	action.text = "接取合约并出发  Enter"
	action.release_focus()
	overlay.show()
	pause_button.hide()
	_update_loadout_buttons()
	_update_hud()
	queue_redraw()

func start_game() -> void:
	mode = "playing"
	paused = false
	action_open = true
	recovery_note = ""
	_save_progress()
	player = ARENA.get_center()
	aim = Vector2.RIGHT
	health = 3
	kills = 0
	elapsed = 0.0
	cooldown = 0.15
	immunity = 0.0
	spawn_clock = 0.6
	hit_flash = 0.0
	muzzle_flash = 0.0
	exfil_progress = 0.0
	last_reward = 0
	last_finished_progress = 0
	impacts.clear()
	enemies.clear()
	bullets.clear()
	sparks.clear()
	overlay.hide()
	pause_button.show()
	_update_loadout_buttons()
	pause_button.release_focus()
	action.release_focus()
	_update_hud()
	queue_redraw()

func _primary_action() -> void:
	if mode == "playing" and paused: _toggle_pause()
	elif mode == "menu": start_game()
	else: _show_menu()

func _toggle_pause() -> void:
	if mode != "playing": return
	paused = not paused
	overlay.visible = paused
	if paused:
		heading.text = "行动已暂停"
		description.text = "休息一下，场内时间已停止。\n点击继续，或按 Esc 返回战斗。"
		action.text = "继续行动  Enter"
	else:
		pause_button.release_focus()
		action.release_focus()
	_update_loadout_buttons()
	_update_hud()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_request_quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready():
		if mode == "playing" and not paused: _toggle_pause()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_P: _toggle_pause()
		elif event.keycode == KEY_ENTER and (mode != "playing" or paused): _primary_action()
		elif event.keycode == KEY_R and mode in ["won", "lost", "extracted"]: _show_menu()

func _physics_process(delta: float) -> void:
	if mode != "playing" or paused: return
	var direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	simulate(delta, direction, get_global_mouse_position(), Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), Input.is_physical_key_pressed(KEY_E))

## Shared simulation for actual gameplay and repeatable automated checks.
func simulate(delta: float, direction: Vector2, target: Vector2, firing: bool, extracting: bool = false) -> void:
	if mode != "playing" or paused: return
	elapsed += delta
	cooldown = maxf(0.0, cooldown - delta)
	immunity = maxf(0.0, immunity - delta)
	hit_flash = maxf(0.0, hit_flash - delta)
	muzzle_flash = maxf(0.0, muzzle_flash - delta)
	var speed := 320.0 if selected_loadout == "mobile" else PLAYER_SPEED
	player = _clamp_player(player + direction.limit_length() * speed * delta)
	if target.distance_squared_to(player) > 1.0: aim = player.direction_to(target)
	if firing and cooldown <= 0.0: _fire()
	spawn_clock -= delta
	if spawn_clock <= 0.0 and enemies.size() < 6:
		_spawn_enemy()
		spawn_clock = maxf(0.65, 1.15 - float(kills) * 0.02)
	for enemy in enemies:
		var pos: Vector2 = enemy.pos
		enemy.pos = pos + pos.direction_to(player) * float(enemy.speed) * delta
	_update_bullets(delta)
	if mode != "playing":
		queue_redraw()
		return
	for enemy in enemies:
		if player.distance_to(enemy.pos) < PLAYER_RADIUS + ENEMY_RADIUS:
			_take_damage()
			var push: Vector2 = (enemy.pos - player).normalized()
			if push.is_zero_approx(): push = Vector2.RIGHT
			enemy.pos = player + push * 86.0
			if mode != "playing": break
	if mode == "playing":
		if extracting and player.distance_to(EXFIL_POSITION) <= EXFIL_RADIUS:
			exfil_progress += delta
			if exfil_progress >= float(contract.exfil_hold_seconds): _finish(true)
		else: exfil_progress = 0.0
	for i in range(impacts.size() - 1, -1, -1):
		impacts[i].ttl -= delta
		if impacts[i].ttl <= 0.0: impacts.remove_at(i)
	for i in range(sparks.size() - 1, -1, -1):
		sparks[i].ttl -= delta
		sparks[i].pos += sparks[i].velocity * delta
		if sparks[i].ttl <= 0.0: sparks.remove_at(i)
	_update_hud()
	queue_redraw()

func _clamp_player(pos: Vector2) -> Vector2:
	return pos.clamp(ARENA.position + Vector2.ONE * PLAYER_RADIUS, ARENA.end - Vector2.ONE * PLAYER_RADIUS)

func _fire() -> void:
	bullets.append({"pos": player + aim * 24.0, "velocity": aim * BULLET_SPEED, "ttl": 1.6})
	cooldown = 0.14 if selected_loadout == "rapid" else FIRE_INTERVAL
	muzzle_flash = 0.045

func _spawn_enemy() -> void:
	var pos: Vector2
	match rng.randi_range(0, 3):
		0: pos = Vector2(ARENA.position.x + 20, rng.randf_range(140, 620))
		1: pos = Vector2(ARENA.end.x - 20, rng.randf_range(140, 620))
		2: pos = Vector2(rng.randf_range(70, 1080), ARENA.position.y + 20)
		_: pos = Vector2(rng.randf_range(70, 1080), ARENA.end.y - 20)
	# Keep spawns at least 240 pixels away, including when player hugs the edge.
	if pos.distance_to(player) < 240.0: pos = ARENA.get_center() * 2.0 - pos
	enemies.append({"pos": pos, "speed": 72.0 + minf(kills * 1.8, 32.0)})

func _update_bullets(delta: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var bullet := bullets[i]
		var start: Vector2 = bullet.pos
		var end: Vector2 = start + bullet.velocity * delta
		var hit := -1
		var nearest := INF
		for j in range(enemies.size()):
			var pos: Vector2 = enemies[j].pos
			var closest := Geometry2D.get_closest_point_to_segment(pos, start, end)
			if closest.distance_to(pos) <= ENEMY_RADIUS + 4.0:
				var distance := start.distance_squared_to(closest)
				if distance < nearest:
					nearest = distance
					hit = j
		if hit >= 0:
			_impacts_at(enemies[hit].pos)
			enemies.remove_at(hit)
			bullets.remove_at(i)
			kills += 1
			_record_kill()
		else:
			bullet.pos = end
			bullet.ttl -= delta
			if bullet.ttl <= 0.0 or not ARENA.grow(30).has_point(end): bullets.remove_at(i)

func _take_damage() -> void:
	if immunity > 0.0 or mode != "playing": return
	health -= 1
	immunity = 1.2
	hit_flash = 0.18
	_burst(player, CYAN)
	if health <= 0: _finish(false, "阵亡")

func _burst(pos: Vector2, color: Color) -> void:
	for i in range(10):
		sparks.append({"pos": pos, "velocity": Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(45, 170), "ttl": 0.32, "color": color})

func _impacts_at(pos: Vector2) -> void:
	impacts.append({"pos": pos, "ttl": 0.12})
	for i in range(6):
		sparks.append({"pos": pos, "velocity": Vector2.RIGHT.rotated(rng.randf() * TAU) * rng.randf_range(45, 95), "ttl": 0.2, "color": ORANGE})

func _finish(extracted: bool, reason: String = "") -> void:
	if mode != "playing": return
	last_finished_progress = contract_progress
	_settle_action(extracted)
	mode = "won" if last_reward > 0 else ("extracted" if extracted else "lost")
	paused = false
	var ending := "撤离" if extracted else (reason if not reason.is_empty() else "行动结束")
	heading.text = "合约已结算 · " + ending if last_reward > 0 else "行动结束 · 进度保留"
	var reward_line := "基础 %d + 首通 %d = %d 经验" % [int(contract.base_xp) if last_reward > 0 else 0, last_bonus, last_reward]
	var save_line := "累计经验 %d · 已有解锁保留" % total_xp if save_ok else "保存失败，当前进度仅本次运行有效"
	description.text = "本局击败 %d · 合约记录 %d / %d\n%s\n%s\n%s" % [kills, last_finished_progress, contract.required_count, reward_line, save_line, "返回合约板可再次接取。" if last_reward > 0 else "返回后可继续累计，不必单局完成。"]
	action.text = "返回合约板  Enter / R"
	pause_button.hide()
	overlay.show()
	_update_loadout_buttons()
	_update_hud()
	queue_redraw()

func _visible_progress() -> int:
	return last_finished_progress if mode == "won" else contract_progress

func _update_hud() -> void:
	hud.text = "生命 %d / 3    合约 %02d / %d    %05.1f 秒\n挑战经验 %d    临时配装：%s" % [health, _visible_progress(), contract.required_count, elapsed, total_xp, _loadout_name()]
	status.text = "进度跨局保留 · E 可撤离"
	if contract_progress >= int(contract.required_count): status.text = "已达标 · 结束对局后结算"
	if paused: status.text = "已暂停 · 退出也保留进度"
	elif mode == "won": status.text = "+%d 经验 · 合约已结算" % last_reward
	elif mode in ["lost", "extracted"]: status.text = "本次进度已保留"
	elif mode == "menu": status.text = recovery_note if not recovery_note.is_empty() else "接取 → 累计 → 离局结算"
	if not save_ok: status.text = "保存失败 · 请使用可写目录"

func _draw() -> void:
	draw_rect(ARENA, Color("0c1726"))
	for x in range(48, 1105, 44): draw_line(Vector2(x, 118), Vector2(x, 642), Color("142337"))
	for y in range(118, 643, 44): draw_line(Vector2(48, y), Vector2(1104, y), Color("142337"))
	draw_rect(ARENA, Color("365069"), false, 2.0)
	draw_rect(Rect2(48, 106, 1056, 3), Color("20364b"))
	draw_rect(Rect2(48, 106, 1056 * clampf(float(_visible_progress()) / float(contract.required_count), 0, 1), 3), CYAN)
	var zone_color := CYAN if contract_progress >= int(contract.required_count) else MUTED
	draw_circle(EXFIL_POSITION, EXFIL_RADIUS, Color(zone_color, 0.09))
	draw_arc(EXFIL_POSITION, EXFIL_RADIUS, 0, TAU, 48, zone_color, 2, true)
	draw_string(font, EXFIL_POSITION + Vector2(-25, 5), "撤离 E", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, zone_color)
	if exfil_progress > 0:
		draw_arc(EXFIL_POSITION, EXFIL_RADIUS + 5, -PI / 2, -PI / 2 + TAU * minf(exfil_progress / float(contract.exfil_hold_seconds), 1), 48, CYAN, 4, true)
	for bullet in bullets:
		var pos: Vector2 = bullet.pos
		var velocity: Vector2 = bullet.velocity
		draw_line(pos - velocity.normalized() * 14, pos, CYAN, 4, true)
		draw_circle(pos, 3, Color.WHITE)
	for enemy in enemies:
		var pos: Vector2 = enemy.pos
		draw_circle(pos + Vector2(0, 5), 20, Color(0, 0, 0, 0.25))
		var points := PackedVector2Array([pos + Vector2(0, -19), pos + Vector2(19, 0), pos + Vector2(0, 19), pos + Vector2(-19, 0)])
		draw_colored_polygon(points, Color("643f3b"))
		points.append(points[0])
		draw_polyline(points, ORANGE, 2.0, true)
		draw_circle(pos, 4, ORANGE)
	for impact in impacts:
		var pos: Vector2 = impact.pos
		var alpha := clampf(float(impact.ttl) / 0.12, 0.0, 1.0)
		var color := Color(1.0, 0.94, 0.8, alpha)
		draw_arc(pos, 6 + (1 - alpha) * 8, 0, TAU, 24, Color(1, 0.66, 0.42, alpha), 1.5, true)
		draw_line(pos - Vector2(5, 5), pos + Vector2(5, 5), color, 2, true)
		draw_line(pos + Vector2(-5, 5), pos + Vector2(5, -5), color, 2, true)
	for spark in sparks:
		var color: Color = spark.color
		color.a = clampf(float(spark.ttl) / 0.32, 0, 1)
		draw_circle(spark.pos, 2, color)
	if mode != "menu":
		var color := CYAN
		if immunity > 0 and int(immunity * 12) % 2 == 0: color.a = 0.35
		draw_circle(player + Vector2(0, 5), 21, Color(0, 0, 0, 0.3))
		draw_circle(player, PLAYER_RADIUS, Color("1d555e"))
		draw_arc(player, PLAYER_RADIUS, 0, TAU, 40, color, 2.5, true)
		draw_line(player, player + aim * 25, color, 7, true)
		draw_circle(player, 4, Color.WHITE)
		if muzzle_flash > 0:
			var tip := player + aim * 29
			var side := aim.orthogonal() * 4
			draw_colored_polygon(PackedVector2Array([tip - side, tip + aim * 11, tip + side]), Color(1, 0.9, 0.6, muzzle_flash / 0.045))
			draw_circle(tip, 3, Color(1, 1, 0.9, muzzle_flash / 0.045))
		if immunity > 0: draw_arc(player, 23, 0, TAU, 48, Color(0.4, 0.9, 0.87, 0.4), 1, true)
		if mode == "playing" and not paused:
			var cursor := get_global_mouse_position()
			if ARENA.has_point(cursor):
				draw_arc(cursor, 8, 0, TAU, 24, Color(0.6, 0.9, 0.9, 0.7), 1, true)
				draw_line(cursor - Vector2(12, 0), cursor + Vector2(12, 0), Color(0.6, 0.9, 0.9, 0.7))
	if hit_flash > 0: draw_rect(ARENA, Color(1, 0.3, 0.25, hit_flash * 0.8))




