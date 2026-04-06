extends Node3D
class_name BotManager

const BOT_COUNT := 7
const BOT_NAMES := ["Волк","Тень","Кабан","Лис","Ястреб","Медведь","Рысь"]
const BOT_COLORS := [
	Color(0.8,0.2,0.2), Color(0.2,0.2,0.8), Color(0.8,0.6,0.1),
	Color(0.5,0.1,0.8), Color(0.1,0.7,0.4), Color(0.9,0.4,0.1),
	Color(0.4,0.7,0.8)
]

var bots : Array = []
var gm   : GameManager
var terrain : TerrainGenerator
var rng  := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	await get_tree().process_frame  # wait for terrain
	gm      = get_tree().get_first_node_in_group("game_manager")
	terrain = get_tree().get_first_node_in_group("terrain_gen") as TerrainGenerator
	_spawn_bots()

func _spawn_bots() -> void:
	for i in BOT_COUNT:
		var bot := _create_bot(i)
		bots.append(bot)
		add_child(bot)

func _create_bot(idx: int) -> Node3D:
	var bot := Node3D.new()
	bot.name = BOT_NAMES[idx]
	bot.set_meta("bot_name", BOT_NAMES[idx])
	bot.set_meta("hp", 100.0)
	bot.set_meta("max_hp", 100.0)
	bot.set_meta("alive", true)
	bot.set_meta("kills", 0)
	bot.set_meta("food", 100.0)
	bot.set_meta("water", 100.0)
	bot.set_meta("state", "wander")   # wander / chase / flee / collect
	bot.set_meta("target", null)
	bot.set_meta("wander_target", Vector3.ZERO)
	bot.set_meta("attack_timer", 0.0)
	bot.set_meta("think_timer",  0.0)
	bot.set_meta("color_idx", idx)

	# Position
	var pos := _random_spawn()
	bot.global_position = pos

	# Visual
	_build_bot_mesh(bot, BOT_COLORS[idx])

	# Collision
	var body := CharacterBody3D.new()
	body.name = "Body"
	body.global_position = pos
	body.add_to_group("damageable")
	body.set_meta("owner_bot", bot)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35; cap.height = 1.8
	col.shape = cap; col.position.y = 0.9
	body.add_child(col)
	body.script = load("res://scripts/BotBody.gd")
	bot.add_child(body)
	bot.set_meta("body", body)

	# HP bar (billboard label)
	var hp_label := Label3D.new()
	hp_label.text = "❤ 100  " + BOT_NAMES[idx]
	hp_label.font_size = 28
	hp_label.modulate  = Color(1,0.3,0.3)
	hp_label.position  = Vector3(0, 2.3, 0)
	hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_label.no_depth_test = true
	bot.add_child(hp_label)
	bot.set_meta("hp_label", hp_label)

	return bot

func _build_bot_mesh(bot: Node3D, color: Color) -> void:
	# Body
	var body_inst := MeshInstance3D.new()
	var cap       := CapsuleMesh.new()
	cap.radius = 0.35; cap.height = 1.8
	body_inst.mesh = cap; body_inst.position.y = 0.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color; mat.roughness = 0.7
	body_inst.set_surface_override_material(0, mat)
	bot.add_child(body_inst)
	# Head
	var head := MeshInstance3D.new()
	var sph   := SphereMesh.new()
	sph.radius = 0.22; sph.height = 0.44
	head.mesh  = sph; head.position.y = 1.9
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.9,0.75,0.6)
	head.set_surface_override_material(0, head_mat)
	bot.add_child(head)

func _random_spawn() -> Vector3:
	var half := 35.0
	for _attempt in 20:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if terrain:
			var h := terrain.get_height_at(x, z)
			if h > 1.0:
				return Vector3(x, h + 0.1, z)
	return Vector3(rng.randf_range(-20, 20), 2.0, rng.randf_range(-20, 20))

func _process(delta: float) -> void:
	if gm and not gm.game_running:
		return
	for bot in bots:
		if bot.get_meta("alive"):
			_update_bot(bot, delta)

func _update_bot(bot: Node3D, delta: float) -> void:
	var hp    : float = bot.get_meta("hp")
	var food  : float = bot.get_meta("food")
	var water : float = bot.get_meta("water")
	var body  : CharacterBody3D = bot.get_meta("body")

	# Drain
	food  = max(0.0, food  - 1.0 * delta)
	water = max(0.0, water - 1.5 * delta)
	bot.set_meta("food", food)
	bot.set_meta("water", water)
	if food <= 0.0 or water <= 0.0:
		hp -= 3.0 * delta
		bot.set_meta("hp", hp)
		if hp <= 0.0:
			_kill_bot(bot, "голод")
			return

	# Think
	var think_timer : float = bot.get_meta("think_timer") - delta
	bot.set_meta("think_timer", think_timer)
	if think_timer <= 0.0:
		_decide_state(bot)
		bot.set_meta("think_timer", rng.randf_range(0.5, 1.5))

	# Execute state
	var state : String = bot.get_meta("state")
	match state:
		"wander":   _do_wander(bot, body, delta)
		"chase":    _do_chase(bot, body, delta)
		"collect":  _do_collect(bot, body, delta)
		"flee":     _do_flee(bot, body, delta)

	# Sync visual position to body
	bot.global_position = body.global_position

	# HP bar update
	var lbl : Label3D = bot.get_meta("hp_label")
	lbl.text = "❤ %d  %s" % [int(hp), bot.get_meta("bot_name")]

	# Attack timer
	var atk : float = bot.get_meta("attack_timer") - delta
	bot.set_meta("attack_timer", atk)

	# Border damage
	var dist := Vector2(body.global_position.x, body.global_position.z).length()
	if gm and dist > gm.get_border_radius():
		hp -= 10.0 * delta
		bot.set_meta("hp", hp)
		if hp <= 0.0:
			_kill_bot(bot, "зона")

func _decide_state(bot: Node3D) -> void:
	var hp   : float = bot.get_meta("hp")
	var food : float = bot.get_meta("food")
	var body : CharacterBody3D = bot.get_meta("body")

	# Flee if low hp
	if hp < 25.0:
		bot.set_meta("state", "flee")
		return

	# Find nearest player or other bot
	var nearest : Node3D = null
	var min_d   : float  = 999.0
	var player  := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player and player.is_alive:
		var d := body.global_position.distance_to(player.global_position)
		if d < min_d:
			min_d = d; nearest = player

	for other_bot in bots:
		if other_bot == bot or not other_bot.get_meta("alive"):
			continue
		var other_body : CharacterBody3D = other_bot.get_meta("body")
		var d := body.global_position.distance_to(other_body.global_position)
		if d < min_d:
			min_d = d; nearest = other_body

	if nearest and min_d < 15.0 and hp > 40.0:
		bot.set_meta("state", "chase")
		bot.set_meta("target", nearest)
	elif food < 30.0:
		bot.set_meta("state", "collect")
	else:
		bot.set_meta("state", "wander")
		var wt := Vector3(rng.randf_range(-35,35), 0, rng.randf_range(-35,35))
		bot.set_meta("wander_target", wt)

func _do_wander(bot: Node3D, body: CharacterBody3D, delta: float) -> void:
	var target : Vector3 = bot.get_meta("wander_target")
	target.y = body.global_position.y
	_move_toward(body, target, 2.5, delta)

func _do_chase(bot: Node3D, body: CharacterBody3D, delta: float) -> void:
	var target = bot.get_meta("target")
	if target == null or not is_instance_valid(target):
		bot.set_meta("state", "wander"); return
	var tpos : Vector3 = target.global_position
	var dist  : float  = body.global_position.distance_to(tpos)
	if dist < 1.8:
		_bot_attack(bot, target)
	else:
		_move_toward(body, tpos, 3.8, delta)

func _do_collect(bot: Node3D, body: CharacterBody3D, delta: float) -> void:
	# Find nearest resource
	var resources := get_tree().get_nodes_in_group("resource")
	var best : Node3D = null
	var best_d := 999.0
	for r in resources:
		var d := body.global_position.distance_to(r.global_position)
		if d < best_d:
			best_d = d; best = r
	if best == null:
		bot.set_meta("state", "wander"); return
	if best_d < 1.5:
		if best.has_method("collect"):
			best.collect(body)   # bots also collect
		bot.set_meta("food", min(100.0, bot.get_meta("food") + 15.0))
		bot.set_meta("state", "wander")
	else:
		_move_toward(body, best.global_position, 3.0, delta)

func _do_flee(bot: Node3D, body: CharacterBody3D, delta: float) -> void:
	# Run away from nearest threat
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player:
		var dir := (body.global_position - player.global_position).normalized()
		var flee_target := body.global_position + dir * 15.0
		_move_toward(body, flee_target, 4.0, delta)

func _move_toward(body: CharacterBody3D, target: Vector3, speed: float, delta: float) -> void:
	var dir := (target - body.global_position)
	dir.y = 0.0
	if dir.length() < 0.5:
		return
	dir = dir.normalized()
	body.velocity.x = dir.x * speed
	body.velocity.z = dir.z * speed
	# Gravity
	if not body.is_on_floor():
		body.velocity.y -= 22.0 * delta
	else:
		body.velocity.y = -0.5
	body.move_and_slide()
	# Rotate toward movement
	if dir.length() > 0.1:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(dir.x, dir.z), 10.0 * delta)

func _bot_attack(bot: Node3D, target: Node3D) -> void:
	if bot.get_meta("attack_timer") > 0.0:
		return
	bot.set_meta("attack_timer", 1.0)
	var dmg := rng.randf_range(8.0, 18.0)
	if target.has_method("take_damage"):
		target.take_damage(dmg, bot.get_meta("bot_name"))
	elif target is CharacterBody3D and target.get_meta("owner_bot", null) != null:
		var other_bot : Node3D = target.get_meta("owner_bot")
		var oh : float = other_bot.get_meta("hp") - dmg
		other_bot.set_meta("hp", oh)
		if oh <= 0.0:
			_kill_bot(other_bot, "убит " + bot.get_meta("bot_name"))
			bot.set_meta("kills", bot.get_meta("kills") + 1)

func _kill_bot(bot: Node3D, reason: String) -> void:
	bot.set_meta("alive", false)
	bot.set_meta("hp", 0.0)
	var body : CharacterBody3D = bot.get_meta("body")
	body.visible = false
	var lbl : Label3D = bot.get_meta("hp_label")
	lbl.visible = false
	if gm:
		gm.register_kill("", bot.get_meta("bot_name"))
