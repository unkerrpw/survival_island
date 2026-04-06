extends CharacterBody3D
class_name Player

# ── Stats ──────────────────────────────────────────────────
var hp        : float = 100.0
var max_hp    : float = 100.0
var food      : float = 100.0
var water     : float = 100.0
var kills     : int   = 0
var is_alive  : bool  = true

# ── Inventory ──────────────────────────────────────────────
const INV_SIZE := 10
var inventory     : Array = []
var selected_slot : int   = 0

# ── Input (set by HUD) ────────────────────────────────────
var joystick_vec : Vector2 = Vector2.ZERO
var look_delta   : Vector2 = Vector2.ZERO
var btn_attack   : bool = false
var btn_jump     : bool = false
var btn_sprint   : bool = false
var btn_collect  : bool = false

# ── Camera ────────────────────────────────────────────────
var cam          : Camera3D = null
var cam_yaw      : float = 0.0    # horizontal rotation degrees
var cam_pitch    : float = -25.0  # vertical angle (negative = looking down at player)
const CAM_DIST   := 5.0
const CAM_HEIGHT := 2.5
const PITCH_MIN  := -60.0
const PITCH_MAX  := 10.0

# ── Physics ───────────────────────────────────────────────
const GRAVITY    := 20.0
const MOVE_SPD   := 5.5
const SPRINT_SPD := 9.0
const JUMP_VEL   := 7.0
var _vy          : float = 0.0

# ── Combat ────────────────────────────────────────────────
var attack_cd    : float = 0.0
const ATK_RANGE  := 2.5

# ── Refs ──────────────────────────────────────────────────
var gm : GameManager = null

# ── RECIPES ───────────────────────────────────────────────
const RECIPES := [
	{result="KNIFE",  cost={WOOD=2,STONE=3}, icon="🗡", name="Нож",     damage=22.0, weapon=true},
	{result="SWORD",  cost={METAL=3,WOOD=1}, icon="⚔",  name="Меч",     damage=38.0, weapon=true},
	{result="TRAP",   cost={WOOD=3,METAL=1}, icon="⚠",  name="Ловушка", placeable=true},
	{result="WALL",   cost={WOOD=5},         icon="🧱",  name="Стена",   placeable=true},
	{result="MEDKIT", cost={FOOD=2,STONE=1}, icon="💊",  name="Аптечка", heal_hp=50},
	{result="TORCH",  cost={WOOD=2},         icon="🔦",  name="Факел",   placeable=true},
	{result="BOMB",   cost={METAL=2,STONE=2},icon="💣",  name="Бомба",   placeable=true},
]

# ══════════════════════════════════════════════════════════
func _ready() -> void:
	add_to_group("player")
	gm = get_tree().get_first_node_in_group("game_manager")

	_init_inventory()
	_build_mesh()
	_build_collision()
	_build_camera()

	# Spawn above terrain, let gravity do the rest
	global_position = Vector3(2.0, 15.0, 2.0)

# ── Build player visuals ───────────────────────────────────
func _build_mesh() -> void:
	# Body
	var mi  := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.7
	mi.mesh = cap
	mi.position.y = 0.85
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.55, 0.2)
	mat.roughness = 0.8
	mi.set_surface_override_material(0, mat)
	add_child(mi)

	# Head
	var hi  := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.22
	sph.height = 0.44
	hi.mesh = sph
	hi.position.y = 1.85
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.9, 0.76, 0.6)
	hi.set_surface_override_material(0, hmat)
	add_child(hi)

func _build_collision() -> void:
	var cs  := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	cs.shape    = cap
	cs.position.y = 0.85
	add_child(cs)

func _build_camera() -> void:
	cam = Camera3D.new()
	cam.name = "Cam"
	cam.fov  = 72.0
	cam.near = 0.1
	cam.far  = 400.0
	# Don't parent to player — add to scene root so it moves independently
	get_tree().root.add_child(cam)
	_update_camera_transform()

# ══════════════════════════════════════════════════════════
func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	_handle_gravity(delta)
	_handle_move(delta)
	_handle_look()
	_update_camera_transform()
	_drain(delta)
	_handle_attack(delta)
	_auto_collect()
	_check_border()

	move_and_slide()

# ── Gravity ───────────────────────────────────────────────
func _handle_gravity(delta: float) -> void:
	if is_on_floor():
		_vy = -1.0
		if btn_jump:
			_vy = JUMP_VEL
			btn_jump = false
	else:
		_vy -= GRAVITY * delta
	velocity.y = _vy

# ── Movement ──────────────────────────────────────────────
func _handle_move(delta: float) -> void:
	var jv := joystick_vec
	if jv.length() < 0.08:
		velocity.x = move_toward(velocity.x, 0, 18.0 * delta)
		velocity.z = move_toward(velocity.z, 0, 18.0 * delta)
		return

	var spd   := SPRINT_SPD if btn_sprint else MOVE_SPD
	var yaw_r := deg_to_rad(cam_yaw)
	var fwd   := Vector3(-sin(yaw_r), 0.0, -cos(yaw_r))
	var rgt   := Vector3( cos(yaw_r), 0.0, -sin(yaw_r))
	var dir   := (rgt * jv.x + fwd * -jv.y).normalized()

	velocity.x = dir.x * spd
	velocity.z = dir.z * spd

	# Rotate body toward movement
	var target_y := atan2(dir.x, dir.z)
	rotation.y   = lerp_angle(rotation.y, target_y, 14.0 * delta)

# ── Camera look ───────────────────────────────────────────
func _handle_look() -> void:
	if look_delta.length() < 0.3:
		return
	cam_yaw   -= look_delta.x * 0.35
	cam_pitch -= look_delta.y * 0.35
	cam_pitch  = clamp(cam_pitch, PITCH_MIN, PITCH_MAX)
	look_delta = Vector2.ZERO

func _update_camera_transform() -> void:
	if cam == null:
		return
	# Orbit camera around player head
	var origin   := global_position + Vector3(0, 1.4, 0)
	var yaw_r    := deg_to_rad(cam_yaw)
	var pitch_r  := deg_to_rad(cam_pitch)

	var offset := Vector3(
		sin(yaw_r) * cos(pitch_r),
		-sin(pitch_r),           # negative pitch → camera above
		cos(yaw_r) * cos(pitch_r)
	) * CAM_DIST

	# Simple wall avoidance
	var space  := get_world_3d().direct_space_state
	var qry    := PhysicsRayQueryParameters3D.create(origin, origin + offset)
	qry.exclude = [self]
	var hit    := space.intersect_ray(qry)
	if hit:
		var d  := origin.distance_to(hit.position) - 0.15
		offset  = offset.normalized() * max(d, 0.4)

	cam.global_position = origin + offset
	cam.look_at(origin, Vector3.UP)

# ── Survival drain ────────────────────────────────────────
func _drain(delta: float) -> void:
	food  = max(0.0, food  - 1.2 * delta)
	water = max(0.0, water - 1.8 * delta)
	if food <= 0.0 or water <= 0.0:
		take_damage(4.0 * delta, "голод")
	if gm and gm.hud:
		gm.hud.update_stats(hp, food, water, max_hp)

# ── Attack ────────────────────────────────────────────────
func _handle_attack(delta: float) -> void:
	attack_cd -= delta
	if btn_attack and attack_cd <= 0.0:
		btn_attack = false
		_do_attack()

func _do_attack() -> void:
	attack_cd = 0.5
	var wpn := _get_weapon()
	var dmg := wpn.damage if wpn else 10.0
	var hit := false

	for t in get_tree().get_nodes_in_group("damageable"):
		if t == self:
			continue
		if global_position.distance_to(t.global_position) < ATK_RANGE:
			t.take_damage(dmg, "Player")
			hit = true
			if gm and gm.hud:
				gm.hud.show_hit_marker()
			break

	if not hit and gm and gm.hud:
		gm.hud.show_miss()

# ── Auto collect resources ─────────────────────────────────
func _auto_collect() -> void:
	for r in get_tree().get_nodes_in_group("resource"):
		if global_position.distance_to(r.global_position) < 1.6:
			r.collect(self)
			break

# ── Border damage ─────────────────────────────────────────
func _check_border() -> void:
	if gm == null:
		return
	var d2 := Vector2(global_position.x, global_position.z).length()
	var in_zone := d2 > gm.get_border_radius()
	if in_zone:
		take_damage(12.0 * get_physics_process_delta_time(), "зона")
	if gm.hud:
		gm.hud.show_border_warning(in_zone)

# ── Damage / Death ────────────────────────────────────────
func take_damage(amount: float, source: String = "") -> void:
	if not is_alive:
		return
	hp -= amount
	if gm and gm.hud:
		gm.hud.flash_damage()
	if hp <= 0.0:
		hp = 0.0
		_die(source)

func _die(reason: String) -> void:
	is_alive = false
	visible  = false
	if gm:
		gm.player_dead(reason)

# ── Inventory helpers ─────────────────────────────────────
func _init_inventory() -> void:
	inventory.resize(INV_SIZE)
	inventory[0] = {id="AXE",   qty=1, icon="🪓", name="Топор",  damage=12.0, weapon=true}
	inventory[1] = {id="FOOD",  qty=2, icon="🍖", name="Еда",    heal_food=40}
	inventory[2] = {id="WATER", qty=1, icon="💧", name="Вода",   heal_water=40}

func add_item(id: String, qty: int, icon: String, iname: String, extra: Dictionary = {}) -> bool:
	for i in INV_SIZE:
		if inventory[i] != null and inventory[i].id == id:
			inventory[i].qty += qty
			if gm and gm.hud: gm.hud.update_inventory(inventory, selected_slot)
			return true
	for i in INV_SIZE:
		if inventory[i] == null:
			var s := {id=id, qty=qty, icon=icon, name=iname}
			s.merge(extra)
			inventory[i] = s
			if gm and gm.hud: gm.hud.update_inventory(inventory, selected_slot)
			return true
	return false

func remove_item(id: String, qty: int) -> bool:
	for i in INV_SIZE:
		if inventory[i] != null and inventory[i].id == id:
			inventory[i].qty -= qty
			if inventory[i].qty <= 0:
				inventory[i] = null
			if gm and gm.hud: gm.hud.update_inventory(inventory, selected_slot)
			return true
	return false

func count_item(id: String) -> int:
	for s in inventory:
		if s != null and s.id == id:
			return s.qty
	return 0

func select_slot(idx: int) -> void:
	selected_slot = clamp(idx, 0, INV_SIZE - 1)
	if gm and gm.hud: gm.hud.update_inventory(inventory, selected_slot)

func use_selected() -> void:
	var slot = inventory[selected_slot]
	if slot == null: return
	if slot.get("heal_food", 0) > 0:
		food = min(100.0, food + slot.heal_food)
		remove_item(slot.id, 1)
		if gm and gm.hud: gm.hud.float_text("+%d 🍖" % slot.heal_food, Color.ORANGE)
	elif slot.get("heal_water", 0) > 0:
		water = min(100.0, water + slot.heal_water)
		remove_item(slot.id, 1)
		if gm and gm.hud: gm.hud.float_text("+%d 💧" % slot.heal_water, Color.CYAN)
	elif slot.get("heal_hp", 0) > 0:
		hp = min(max_hp, hp + slot.heal_hp)
		remove_item(slot.id, 1)
		if gm and gm.hud: gm.hud.float_text("+%d ❤" % slot.heal_hp, Color.RED)

func _get_weapon() -> Variant:
	var cur = inventory[selected_slot]
	if cur != null and cur.get("weapon", false): return cur
	for s in inventory:
		if s != null and s.get("weapon", false): return s
	return null

func try_craft(idx: int) -> void:
	if idx >= RECIPES.size(): return
	var r := RECIPES[idx]
	for item_id in r.cost:
		if count_item(item_id) < r.cost[item_id]:
			if gm and gm.hud: gm.hud.float_text("❌ Нет ресурсов", Color.RED)
			return
	for item_id in r.cost:
		remove_item(item_id, r.cost[item_id])
	var extra := {}
	for key in r:
		if key not in ["result","cost","icon","name"]:
			extra[key] = r[key]
	add_item(r.result, 1, r.icon, r.name, extra)
	if gm and gm.hud: gm.hud.float_text("%s создан!" % r.name, Color.YELLOW)
