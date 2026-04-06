extends CharacterBody3D
class_name Player

# ─── Stats ─────────────────────────────────────────────────
@export var move_speed    : float = 6.0
@export var sprint_speed  : float = 10.0
@export var jump_velocity : float = 6.0
@export var max_hp        : float = 100.0
@export var max_food      : float = 100.0
@export var max_water     : float = 100.0

var hp        : float = 100.0
var food      : float = 100.0
var water     : float = 100.0
var kills     : int   = 0
var is_alive  : bool  = true
var is_sprinting: bool = false

# ─── Inventory ─────────────────────────────────────────────
const INV_SIZE := 10
var inventory  : Array = []   # Array of {id, qty, icon, name, ...}
var selected_slot : int = 0

# ─── Weapon / Attack ───────────────────────────────────────
var attack_cooldown : float = 0.0
var collect_timer   : float = 0.0
const ATTACK_RANGE  := 2.2
const COLLECT_RANGE := 1.8

# ─── Survival drain rates ──────────────────────────────────
const FOOD_DRAIN  := 1.2   # per sec
const WATER_DRAIN := 1.8
const DRAIN_DMG   := 4.0

# ─── Camera & rotation ─────────────────────────────────────
@onready var camera       : Camera3D   = $Camera3D
@onready var anim_player  : AnimationPlayer = null   # optional

var cam_pitch : float = -10.0   # degrees
var cam_yaw   : float = 0.0
var look_sensitivity := 0.4

# ─── Third-person ──────────────────────────────────────────
const CAM_DISTANCE := 4.5
const CAM_HEIGHT   := 1.6
const CAM_PITCH_MIN := -35.0
const CAM_PITCH_MAX := 35.0

# ─── Mobile input (set by HUD) ─────────────────────────────
var joystick_vec   : Vector2 = Vector2.ZERO
var look_delta     : Vector2 = Vector2.ZERO
var btn_attack     : bool    = false
var btn_jump       : bool    = false
var btn_sprint     : bool    = false
var btn_collect    : bool    = false

# ─── Physics ───────────────────────────────────────────────
const GRAVITY := 22.0
var _gravity_vel : float = 0.0

# ─── Refs ──────────────────────────────────────────────────
var gm : GameManager

func _ready() -> void:
	add_to_group("player")
	gm = get_tree().get_first_node_in_group("game_manager")
	_init_inventory()
	_setup_mesh()
	_setup_collision()
	_position_camera()

func _init_inventory() -> void:
	inventory.resize(INV_SIZE)
	# Starting items
	inventory[0] = {id="AXE",     qty=1, icon="🪓", name="Топор",    damage=12, weapon=true}
	inventory[1] = {id="FOOD",    qty=2, icon="🍖", name="Еда",      heal_food=40}
	inventory[2] = {id="WATER",   qty=1, icon="💧", name="Вода",     heal_water=40}

func _setup_mesh() -> void:
	# Capsule body
	var mesh_inst := MeshInstance3D.new()
	var capsule   := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	mesh_inst.mesh = capsule
	mesh_inst.position.y = 0.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.5, 0.2)
	mat.roughness = 0.7
	mat.metallic = 0.1
	mesh_inst.set_surface_override_material(0, mat)
	add_child(mesh_inst)
	# Head sphere
	var head_inst := MeshInstance3D.new()
	var sphere    := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	head_inst.mesh = sphere
	head_inst.position.y = 1.9
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.9, 0.75, 0.6)
	head_mat.roughness = 0.6
	head_inst.set_surface_override_material(0, head_mat)
	add_child(head_inst)

func _setup_collision() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)

func _position_camera() -> void:
	# Camera starts behind player
	camera.position = Vector3(0, CAM_HEIGHT, CAM_DISTANCE)
	camera.rotation_degrees.x = cam_pitch

# ─── Per-frame ─────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	_apply_gravity(delta)
	_handle_movement(delta)
	_handle_camera(delta)
	_drain_survival(delta)
	_handle_attack(delta)
	_handle_collect(delta)
	_check_border()
	move_and_slide()

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		_gravity_vel += GRAVITY * delta
	else:
		_gravity_vel = 0.1
	velocity.y = -_gravity_vel

func _handle_movement(delta: float) -> void:
	var jv := joystick_vec
	if jv.length() < 0.1:
		velocity.x = move_toward(velocity.x, 0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0, 20.0 * delta)
		return

	var spd := sprint_speed if btn_sprint else move_speed
	# Direction relative to camera yaw
	var yaw_rad := deg_to_rad(cam_yaw)
	var forward  := Vector3(-sin(yaw_rad), 0, -cos(yaw_rad))
	var right    := Vector3(cos(yaw_rad),  0, -sin(yaw_rad))
	var move_dir := (right * jv.x + forward * -jv.y).normalized()
	velocity.x = move_dir.x * spd
	velocity.z = move_dir.z * spd
	# Rotate player body toward movement
	if move_dir.length() > 0.1:
		var target_angle := atan2(move_dir.x, move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 12.0 * delta)

	if btn_jump and is_on_floor():
		_gravity_vel = -jump_velocity
		btn_jump = false

func _handle_camera(delta: float) -> void:
	if look_delta.length() > 0.5:
		cam_yaw   -= look_delta.x * look_sensitivity
		cam_pitch -= look_delta.y * look_sensitivity
		cam_pitch  = clamp(cam_pitch, CAM_PITCH_MIN, CAM_PITCH_MAX)
	look_delta = Vector2.ZERO

	# Third-person camera orbit
	var yaw_rad   := deg_to_rad(cam_yaw)
	var pitch_rad := deg_to_rad(cam_pitch)
	var offset := Vector3(
		CAM_DISTANCE * sin(yaw_rad) * cos(pitch_rad),
		CAM_HEIGHT + CAM_DISTANCE * sin(pitch_rad),
		CAM_DISTANCE * cos(yaw_rad) * cos(pitch_rad)
	)
	# Collision check
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 1.6, 0),
		global_position + offset, 0b100)
	var result := space.intersect_ray(query)
	if result:
		var dist := global_position.distance_to(result.position) - 0.2
		var dir   := offset.normalized()
		offset = dir * max(dist, 0.5)

	camera.global_position = global_position + offset
	camera.look_at(global_position + Vector3(0, 1.2, 0), Vector3.UP)

func _drain_survival(delta: float) -> void:
	food  = max(0.0, food  - FOOD_DRAIN  * delta)
	water = max(0.0, water - WATER_DRAIN * delta)
	if food <= 0.0 or water <= 0.0:
		take_damage(DRAIN_DMG * delta, "голод/жажда")
	gm.hud.update_stats(hp, food, water, max_hp)

func _handle_attack(delta: float) -> void:
	attack_cooldown -= delta
	if btn_attack and attack_cooldown <= 0.0:
		btn_attack = false
		_do_attack()

func _do_attack() -> void:
	var weapon := _get_weapon()
	var dmg    := weapon.damage if weapon else 8.0
	attack_cooldown = 0.45 if weapon else 0.6

	# Check all damageable nearby
	var origin := global_position + Vector3(0, 1.0, 0)
	var targets := get_tree().get_nodes_in_group("damageable")
	for t in targets:
		if t == self:
			continue
		var dist : float = global_position.distance_to(t.global_position)
		if dist < ATTACK_RANGE:
			t.take_damage(dmg, "Player")
			gm.hud.show_hit_marker()
			return
	gm.hud.show_miss()

func _handle_collect(delta: float) -> void:
	collect_timer -= delta
	if btn_collect and collect_timer <= 0.0:
		btn_collect = false
		_try_collect()
	# Auto collect resources on walk
	var resources := get_tree().get_nodes_in_group("resource")
	for r in resources:
		if global_position.distance_to(r.global_position) < COLLECT_RANGE:
			r.collect(self)

func _try_collect() -> void:
	var resources := get_tree().get_nodes_in_group("resource")
	for r in resources:
		if global_position.distance_to(r.global_position) < COLLECT_RANGE + 0.5:
			r.collect(self)
			collect_timer = 0.3
			return

func _check_border() -> void:
	var dist_from_center := Vector2(global_position.x, global_position.z).length()
	if dist_from_center > gm.get_border_radius():
		take_damage(15.0 * get_physics_process_delta_time(), "зона смерти")
		gm.hud.show_border_warning(true)
	else:
		gm.hud.show_border_warning(false)

# ─── Damage / Death ────────────────────────────────────────
func take_damage(amount: float, source: String = "") -> void:
	if not is_alive:
		return
	hp -= amount
	gm.hud.flash_damage()
	if hp <= 0.0:
		hp = 0.0
		_die(source)

func _die(reason: String) -> void:
	is_alive = false
	gm.player_dead(reason)
	# Drop inventory
	for slot in inventory:
		if slot != null:
			_drop_item(slot)
	visible = false

func _drop_item(slot: Dictionary) -> void:
	# Spawn a resource pickup at player's location
	var drop := preload("res://scenes/ResourcePickup.tscn").instantiate()
	drop.setup(slot.id, slot.qty, slot.get("icon","?"), slot.get("name","item"))
	drop.global_position = global_position + Vector3(randf_range(-1,1), 0.5, randf_range(-1,1))
	get_tree().root.add_child(drop)

# ─── Inventory ─────────────────────────────────────────────
func add_item(id: String, qty: int, icon: String, name: String, extra: Dictionary = {}) -> bool:
	# Stack existing
	for i in INV_SIZE:
		if inventory[i] != null and inventory[i].id == id:
			inventory[i].qty += qty
			gm.hud.update_inventory(inventory, selected_slot)
			return true
	# Empty slot
	for i in INV_SIZE:
		if inventory[i] == null:
			var slot := {id=id, qty=qty, icon=icon, name=name}
			slot.merge(extra)
			inventory[i] = slot
			gm.hud.update_inventory(inventory, selected_slot)
			return true
	return false  # full

func remove_item(id: String, qty: int) -> bool:
	for i in INV_SIZE:
		if inventory[i] != null and inventory[i].id == id:
			inventory[i].qty -= qty
			if inventory[i].qty <= 0:
				inventory[i] = null
			gm.hud.update_inventory(inventory, selected_slot)
			return true
	return false

func count_item(id: String) -> int:
	for s in inventory:
		if s != null and s.id == id:
			return s.qty
	return 0

func use_selected() -> void:
	var slot := inventory[selected_slot]
	if slot == null:
		return
	if slot.get("heal_food", 0) > 0:
		food = min(max_food, food + slot.heal_food)
		remove_item(slot.id, 1)
		gm.hud.float_text("+%d 🍖" % slot.heal_food, Color.ORANGE)
	elif slot.get("heal_water", 0) > 0:
		water = min(max_water, water + slot.heal_water)
		remove_item(slot.id, 1)
		gm.hud.float_text("+%d 💧" % slot.heal_water, Color.CYAN)
	elif slot.get("heal_hp", 0) > 0:
		hp = min(max_hp, hp + slot.heal_hp)
		remove_item(slot.id, 1)
		gm.hud.float_text("+%d ❤" % slot.heal_hp, Color.RED)
	elif slot.get("placeable", false):
		_place_item(slot)

func _place_item(slot: Dictionary) -> void:
	var placed_pos := global_position + -global_transform.basis.z * 2.0
	placed_pos.y = global_position.y
	var scene_path := "res://scenes/Placed_%s.tscn" % slot.id.to_lower()
	if ResourceLoader.exists(scene_path):
		var inst := load(scene_path).instantiate()
		inst.global_position = placed_pos
		get_tree().root.add_child(inst)
		remove_item(slot.id, 1)
		gm.hud.float_text("%s размещён" % slot.name, Color.GREEN)

func select_slot(idx: int) -> void:
	selected_slot = clamp(idx, 0, INV_SIZE - 1)
	gm.hud.update_inventory(inventory, selected_slot)

func _get_weapon() -> Variant:
	var cur := inventory[selected_slot]
	if cur != null and cur.get("weapon", false):
		return cur
	for s in inventory:
		if s != null and s.get("weapon", false):
			return s
	return null

# ─── Crafting ──────────────────────────────────────────────
const RECIPES := [
	{result="KNIFE",  cost={WOOD=2,STONE=3}, icon="🗡", name="Нож",    damage=22.0, weapon=true},
	{result="SWORD",  cost={METAL=3,WOOD=1}, icon="⚔",  name="Меч",    damage=38.0, weapon=true},
	{result="SPEAR",  cost={WOOD=4,METAL=1}, icon="🏹",  name="Копьё",  damage=28.0, weapon=true},
	{result="TRAP",   cost={WOOD=3,METAL=1}, icon="⚠",  name="Ловушка", placeable=true},
	{result="WALL",   cost={WOOD=5},         icon="🧱",  name="Стена",   placeable=true},
	{result="MEDKIT", cost={FOOD=2,STONE=1}, icon="💊",  name="Аптечка", heal_hp=50},
	{result="TORCH",  cost={WOOD=2},         icon="🔦",  name="Факел",   placeable=true},
	{result="BOMB",   cost={METAL=2,STONE=2},icon="💣",  name="Бомба",   placeable=true},
]

func try_craft(recipe_idx: int) -> void:
	if recipe_idx >= RECIPES.size():
		return
	var r := RECIPES[recipe_idx]
	for item_id in r.cost:
		if count_item(item_id) < r.cost[item_id]:
			gm.hud.float_text("❌ Нет ресурсов", Color.RED)
			return
	for item_id in r.cost:
		remove_item(item_id, r.cost[item_id])
	var extra := {}
	for key in r:
		if key != "result" and key != "cost" and key != "icon" and key != "name":
			extra[key] = r[key]
	add_item(r.result, 1, r.icon, r.name, extra)
	gm.hud.float_text("%s %s создан!" % [r.icon, r.name], Color.YELLOW)
	gm.add_score(20)
