extends Node3D
class_name MonsterManager

const MAX_MONSTERS := 12
const MONSTER_TYPES := [
	{name="Зомби",   hp=60.0,  dmg=12.0, speed=2.8, color=Color(0.2,0.5,0.2), size=1.0},
	{name="Мутант",  hp=120.0, dmg=22.0, speed=2.0, color=Color(0.6,0.2,0.1), size=1.4},
	{name="Летун",   hp=40.0,  dmg=8.0,  speed=5.0, color=Color(0.2,0.1,0.5), size=0.7},
	{name="Громила", hp=200.0, dmg=35.0, speed=1.4, color=Color(0.4,0.1,0.1), size=1.8},
]

var monsters : Array = []
var gm       : GameManager
var terrain  : TerrainGenerator
var rng      := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("monster_manager")
	rng.randomize()
	await get_tree().process_frame
	gm      = get_tree().get_first_node_in_group("game_manager")
	terrain = get_tree().get_first_node_in_group("terrain_gen") as TerrainGenerator
	# Spawn a few day monsters
	for _i in 3:
		_spawn_monster(false)

func spawn_night_wave() -> void:
	var count := rng.randi_range(3, 5)
	for _i in count:
		if monsters.filter(func(m): return m.get_meta("alive")).size() < MAX_MONSTERS:
			_spawn_monster(true)

func _spawn_monster(is_night: bool) -> void:
	var type_data := MONSTER_TYPES[rng.randi() % MONSTER_TYPES.size()]
	if not is_night and type_data.name == "Громила":
		return  # Громила only at night

	var body := CharacterBody3D.new()
	body.add_to_group("damageable")
	body.add_to_group("monster")
	body.set_meta("alive",       true)
	body.set_meta("hp",          type_data.hp)
	body.set_meta("max_hp",      type_data.hp)
	body.set_meta("damage",      type_data.dmg)
	body.set_meta("speed",       type_data.speed)
	body.set_meta("mon_name",    type_data.name)
	body.set_meta("attack_timer",0.0)
	body.set_meta("wander_timer",0.0)
	body.set_meta("wander_target",Vector3.ZERO)
	body.script = load("res://scripts/MonsterBody.gd")

	# Position near edge or random
	var half := 30.0
	var x    := rng.randf_range(-half, half)
	var z    := rng.randf_range(-half, half)
	var h    := terrain.get_height_at(x, z) if terrain else 1.0
	body.global_position = Vector3(x, h + 0.2, z)

	# Visual
	var s := type_data.size
	var mesh_inst := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35 * s; cap.height = 1.6 * s
	mesh_inst.mesh = cap; mesh_inst.position.y = 0.8 * s
	var mat := StandardMaterial3D.new()
	mat.albedo_color = type_data.color
	mat.roughness    = 0.8
	mat.emission_enabled = true
	mat.emission = type_data.color * 0.4
	mesh_inst.set_surface_override_material(0, mat)
	body.add_child(mesh_inst)

	# Eyes glow
	var eye := OmniLight3D.new()
	eye.light_color = Color(1, 0.1, 0.1)
	eye.light_energy = 2.0
	eye.omni_range   = 3.0
	eye.position      = Vector3(0, 1.5 * s, 0.2)
	body.add_child(eye)

	# Collision
	var col := CollisionShape3D.new()
	var cs  := CapsuleShape3D.new()
	cs.radius = 0.35 * s; cs.height = 1.6 * s
	col.shape = cs; col.position.y = 0.8 * s
	body.add_child(col)

	# HP label
	var lbl := Label3D.new()
	lbl.text = "☠ " + type_data.name
	lbl.font_size = 26
	lbl.modulate  = Color(1, 0.2, 0.2)
	lbl.position  = Vector3(0, 2.2 * s, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	body.add_child(lbl)
	body.set_meta("label", lbl)
	body.set_meta("mesh",  mesh_inst)

	monsters.append(body)
	add_child(body)

func _process(delta: float) -> void:
	if gm and not gm.game_running:
		return
	for m in monsters:
		if m.get_meta("alive"):
			_update_monster(m, delta)

func _update_monster(m: CharacterBody3D, delta: float) -> void:
	var speed : float = m.get_meta("speed")
	var is_night : bool = gm.is_night if gm else false
	var effective_speed := speed * (1.6 if is_night else 0.7)

	# Find nearest player
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	var target_pos : Vector3
	var has_target := false

	if player and player.is_alive:
		var d := m.global_position.distance_to(player.global_position)
		if d < 20.0:
			target_pos = player.global_position
			has_target = true

	var atk_timer : float = m.get_meta("attack_timer") - delta
	m.set_meta("attack_timer", atk_timer)

	if has_target:
		var dir := (target_pos - m.global_position)
		dir.y = 0.0
		var dist := dir.length()
		if dist > 0.5:
			dir = dir.normalized()
			m.velocity.x = dir.x * effective_speed
			m.velocity.z = dir.z * effective_speed
			m.rotation.y = lerp_angle(m.rotation.y, atan2(dir.x, dir.z), 8.0 * delta)
		# Attack
		if dist < 1.8 and atk_timer <= 0.0:
			m.set_meta("attack_timer", 1.5)
			if player:
				player.take_damage(m.get_meta("damage"), m.get_meta("mon_name"))
	else:
		# Wander
		var wt : float = m.get_meta("wander_timer") - delta
		m.set_meta("wander_timer", wt)
		if wt <= 0.0:
			var wtgt := Vector3(rng.randf_range(-30,30), 0, rng.randf_range(-30,30))
			m.set_meta("wander_target", wtgt)
			m.set_meta("wander_timer", rng.randf_range(2.0, 5.0))
		var wander_tgt : Vector3 = m.get_meta("wander_target")
		var wdir := (wander_tgt - m.global_position); wdir.y = 0.0
		if wdir.length() > 1.0:
			wdir = wdir.normalized()
			m.velocity.x = wdir.x * effective_speed * 0.4
			m.velocity.z = wdir.z * effective_speed * 0.4

	# Gravity
	if not m.is_on_floor():
		m.velocity.y -= 22.0 * delta
	else:
		m.velocity.y = -0.2
	m.move_and_slide()

func kill_monster(m: CharacterBody3D, killer: String) -> void:
	m.set_meta("alive", false)
	var lbl : Label3D = m.get_meta("label")
	lbl.visible = false
	var mesh : MeshInstance3D = m.get_meta("mesh")
	# Death animation
	var tween := create_tween()
	tween.tween_property(mesh, "scale", Vector3.ZERO, 0.3)
	tween.tween_callback(func(): m.visible = false)
	if gm and killer == "Player":
		gm.add_score(80)
		gm.hud.float_text("☠ Монстр убит! +80", Color.ORANGE)
