extends CanvasLayer
class_name MobileHUD

# ─── Touch tracking ────────────────────────────────────────
var joystick_touch_id  : int = -1
var look_touch_id      : int = -1
var joystick_origin    : Vector2 = Vector2.ZERO
var joystick_current   : Vector2 = Vector2.ZERO
const JOYSTICK_RADIUS  := 80.0
const JOYSTICK_MAX     := 60.0

# ─── UI Nodes (created procedurally) ──────────────────────
var root_control    : Control
var joystick_bg     : ColorRect
var joystick_knob   : ColorRect
var btn_attack      : ColorRect
var btn_jump        : ColorRect
var btn_sprint      : ColorRect
var btn_collect     : ColorRect
var btn_craft       : ColorRect
var btn_use         : ColorRect

var hp_bar          : ColorRect
var food_bar        : ColorRect
var water_bar       : ColorRect
var hp_fill         : ColorRect
var food_fill       : ColorRect
var water_fill      : ColorRect

var timer_label     : Label
var alive_label     : Label
var day_label       : Label
var log_container   : VBoxContainer
var inventory_bar   : HBoxContainer
var inv_slots       : Array = []
var craft_panel     : Control
var craft_visible   : bool = false

var damage_overlay  : ColorRect
var border_overlay  : ColorRect
var hit_marker      : Control
var float_container : Control

var rain_overlay    : ColorRect

# Player ref
var player : Player

func _ready() -> void:
	_build_ui()
	player = get_tree().get_first_node_in_group("player") as Player
	var gm := get_tree().get_first_node_in_group("game_manager") as GameManager
	if gm:
		gm.log_message.connect(_on_log_message)
		gm.round_ended.connect(_on_round_ended)
		gm.player_died.connect(_on_player_died)
		gm.day_changed.connect(_on_day_changed)
	set_process_input(true)

# ══════════════════════════════════════════════════════════════
# UI CONSTRUCTION
# ══════════════════════════════════════════════════════════════
func _build_ui() -> void:
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)

	_build_overlays()
	_build_hud_top()
	_build_inventory()
	_build_joystick()
	_build_action_buttons()
	_build_craft_panel()
	_build_log()
	_build_float_container()

func _build_overlays() -> void:
	# Damage flash
	damage_overlay = _make_rect(Color(1,0,0,0), Vector2.ZERO, Vector2(1080,1920))
	root_control.add_child(damage_overlay)
	damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Border warning
	border_overlay = _make_rect(Color(1,0.3,0,0), Vector2.ZERO, Vector2(1080,1920))
	root_control.add_child(border_overlay)
	border_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Rain
	rain_overlay = _make_rect(Color(0.4,0.6,1.0,0), Vector2.ZERO, Vector2(1080,1920))
	root_control.add_child(rain_overlay)
	rain_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _build_hud_top() -> void:
	var panel := _make_rect(Color(0,0,0,0.45), Vector2(0,0), Vector2(1080, 90))
	root_control.add_child(panel)

	# HP
	var hp_bg := _make_rect(Color(0.15,0,0,0.9), Vector2(20,15), Vector2(200,22))
	panel.add_child(hp_bg)
	hp_fill = _make_rect(Color(0.9,0.1,0.1,1), Vector2.ZERO, Vector2(200,22))
	hp_bg.add_child(hp_fill)
	_make_label("❤ HP", Vector2(225,12), panel, 18, Color.RED)

	# FOOD
	var f_bg := _make_rect(Color(0.2,0.1,0,0.9), Vector2(20,45), Vector2(200,16))
	panel.add_child(f_bg)
	food_fill = _make_rect(Color(1,0.5,0,1), Vector2.ZERO, Vector2(200,16))
	f_bg.add_child(food_fill)

	# WATER
	var w_bg := _make_rect(Color(0,0.1,0.2,0.9), Vector2(20,66), Vector2(200,14))
	panel.add_child(w_bg)
	water_fill = _make_rect(Color(0.2,0.7,1.0,1), Vector2.ZERO, Vector2(200,14))
	w_bg.add_child(water_fill)

	# Timer (center)
	timer_label = _make_label("5:00", Vector2(480,8), panel, 36, Color.YELLOW)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.custom_minimum_size.x = 120

	# Alive count
	alive_label = _make_label("🧍 8", Vector2(800,10), panel, 26, Color.GREEN)

	# Day label
	day_label = _make_label("☀️ ДЕНЬ 1", Vector2(700,45), panel, 20, Color(1,0.9,0.4))

func _build_inventory() -> void:
	var inv_bg := _make_rect(Color(0,0,0,0.6), Vector2(0,1820), Vector2(1080,100))
	root_control.add_child(inv_bg)
	inv_slots = []
	for i in 10:
		var slot := _make_rect(
			Color(0.1,0.15,0.1,0.85),
			Vector2(10 + i*106, 1828),
			Vector2(98, 84)
		)
		root_control.add_child(slot)
		var lbl := _make_label("", Vector2(8,8), slot, 36, Color.WHITE)
		lbl.name = "icon"
		var cnt := _make_label("", Vector2(60,55), slot, 18, Color.YELLOW)
		cnt.name = "count"
		var border := ColorRect.new()
		border.color = Color(0.3,0.6,0.3,0) if i != 0 else Color(0.3,1,0.3,0.8)
		border.set_anchors_preset(Control.PRESET_FULL_RECT)
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		border.name = "border"
		slot.add_child(border)
		inv_slots.append(slot)

func _build_joystick() -> void:
	joystick_bg = _make_rect(Color(1,1,1,0.08), Vector2(60, 1600), Vector2(160,160))
	joystick_bg.name = "JoystickBG"
	root_control.add_child(joystick_bg)
	_add_border(joystick_bg, Color(1,1,1,0.2), 3)

	joystick_knob = _make_rect(Color(1,1,1,0.25), Vector2(55,55), Vector2(50,50))
	joystick_bg.add_child(joystick_knob)

func _build_action_buttons() -> void:
	# Right side buttons layout
	var btns := [
		["⚔", "ATTACK", Vector2(860,1640), Color(0.9,0.1,0.1,0.7)],
		["⬆", "JUMP",   Vector2(760,1700), Color(0.1,0.5,0.9,0.7)],
		["💨", "SPRINT", Vector2(960,1700), Color(0.2,0.8,0.2,0.7)],
		["✋", "COLLECT",Vector2(760,1560), Color(0.9,0.7,0.1,0.7)],
		["🎒", "USE",    Vector2(960,1560), Color(0.5,0.2,0.8,0.7)],
		["🔨", "CRAFT",  Vector2(860,1550), Color(0.8,0.4,0.1,0.7)],
	]
	for b in btns:
		var btn := _make_circle_btn(b[0], b[2], 70, b[3])
		btn.name = b[1]
		root_control.add_child(btn)
		match b[1]:
			"ATTACK":  btn_attack  = btn
			"JUMP":    btn_jump    = btn
			"SPRINT":  btn_sprint  = btn
			"COLLECT": btn_collect = btn
			"USE":     btn_use     = btn
			"CRAFT":   btn_craft   = btn

	# Hit marker (center cross)
	hit_marker = Control.new()
	hit_marker.set_anchors_preset(Control.PRESET_CENTER)
	hit_marker.size = Vector2(40,40)
	hit_marker.position = Vector2(520,940)
	hit_marker.visible = false
	root_control.add_child(hit_marker)
	for line_data in [
		[Vector2(16,20), Vector2(8,1)],
		[Vector2(36,20), Vector2(8,1)],
		[Vector2(20,16), Vector2(1,8)],
		[Vector2(20,36), Vector2(1,8)],
	]:
		var line := ColorRect.new()
		line.position = line_data[0]
		line.size = line_data[1]
		line.color = Color.RED
		hit_marker.add_child(line)

func _build_craft_panel() -> void:
	craft_panel = Control.new()
	craft_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	craft_panel.visible = false
	root_control.add_child(craft_panel)

	var bg := _make_rect(Color(0,0,0,0.85), Vector2(0,0), Vector2(1080,1920))
	craft_panel.add_child(bg)
	_make_label("🔨 КРАФТ", Vector2(400,60), craft_panel, 48, Color.YELLOW)
	_make_label("Нажми ещё раз — закрыть", Vector2(300,130), craft_panel, 26, Color(0.6,0.6,0.6))

	var recipes := Player.RECIPES if "RECIPES" in Player else _get_fallback_recipes()
	for i in recipes.size():
		var r := recipes[i]
		var btn_bg := _make_rect(Color(0.1,0.2,0.1,0.9), Vector2(40, 200 + i*110), Vector2(1000,95))
		craft_panel.add_child(btn_bg)
		_make_label(r.icon + " " + r.name, Vector2(15,10), btn_bg, 34, Color.WHITE)
		var cost_str := ""
		for item_id in r.cost:
			cost_str += "[%s×%d] " % [item_id, r.cost[item_id]]
		_make_label(cost_str, Vector2(15, 55), btn_bg, 24, Color(0.7,0.7,0.7))
		var close_btn := btn_bg
		var idx_capture := i
		close_btn.gui_input.connect(func(ev):
			if ev is InputEventScreenTouch and ev.pressed:
				player.try_craft(idx_capture)
		)

func _get_fallback_recipes() -> Array:
	return [
		{result="KNIFE", cost={WOOD=2,STONE=3}, icon="🗡", name="Нож"},
		{result="SWORD", cost={METAL=3,WOOD=1}, icon="⚔", name="Меч"},
		{result="TRAP",  cost={WOOD=3,METAL=1}, icon="⚠", name="Ловушка"},
		{result="WALL",  cost={WOOD=5},         icon="🧱",name="Стена"},
		{result="MEDKIT",cost={FOOD=2,STONE=1}, icon="💊", name="Аптечка"},
	]

func _build_log() -> void:
	log_container = VBoxContainer.new()
	log_container.position = Vector2(10, 100)
	log_container.custom_minimum_size = Vector2(400, 200)
	log_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(log_container)

func _build_float_container() -> void:
	float_container = Control.new()
	float_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	float_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(float_container)

# ══════════════════════════════════════════════════════════════
# TOUCH INPUT
# ══════════════════════════════════════════════════════════════
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)

func _handle_touch(ev: InputEventScreenTouch) -> void:
	var pos := ev.position
	if ev.pressed:
		# Joystick zone: left half of screen, below y=1200
		if pos.x < 540 and pos.y > 1200:
			if joystick_touch_id == -1:
				joystick_touch_id = ev.index
				joystick_origin = pos
				joystick_current = pos
				_update_joystick(pos)
			return
		# Right half: look camera zone
		if pos.x >= 540 and pos.y < 1600 and look_touch_id == -1:
			look_touch_id = ev.index
			return
		# Buttons
		_check_button_press(pos, true)
	else:
		if ev.index == joystick_touch_id:
			joystick_touch_id = -1
			joystick_current = joystick_origin
			_reset_joystick()
			if player: player.joystick_vec = Vector2.ZERO
		if ev.index == look_touch_id:
			look_touch_id = -1
		_check_button_press(pos, false)

func _handle_drag(ev: InputEventScreenDrag) -> void:
	if ev.index == joystick_touch_id:
		joystick_current = ev.position
		_update_joystick(ev.position)
	elif ev.index == look_touch_id:
		if player:
			player.look_delta += ev.relative * 0.8

func _update_joystick(touch_pos: Vector2) -> void:
	var delta := touch_pos - joystick_origin
	var clamped := delta.limit_length(JOYSTICK_MAX)
	joystick_knob.position = Vector2(55,55) + clamped * 0.8 - Vector2(25,25)
	if player:
		player.joystick_vec = clamped / JOYSTICK_MAX

func _reset_joystick() -> void:
	joystick_knob.position = Vector2(55,55)

func _check_button_press(pos: Vector2, pressed: bool) -> void:
	if player == null:
		return
	var btns_map := {
		btn_attack: func(): player.btn_attack = pressed,
		btn_jump:   func(): player.btn_jump   = pressed,
		btn_sprint: func(): player.btn_sprint  = pressed,
		btn_collect:func(): player.btn_collect = pressed,
	}
	for btn in btns_map:
		if btn != null and btn.get_global_rect().has_point(pos):
			btns_map[btn].call()
			_animate_button(btn, pressed)
			return
	if btn_craft != null and btn_craft.get_global_rect().has_point(pos) and pressed:
		craft_visible = !craft_visible
		craft_panel.visible = craft_visible
	if btn_use != null and btn_use.get_global_rect().has_point(pos) and pressed:
		player.use_selected()

# ══════════════════════════════════════════════════════════════
# PUBLIC UPDATE METHODS
# ══════════════════════════════════════════════════════════════
func update_stats(hp: float, food: float, water: float, max_hp: float) -> void:
	hp_fill.size.x    = 200 * hp / max_hp
	food_fill.size.x  = 200 * food / 100.0
	water_fill.size.x = 200 * water / 100.0
	# Color warning
	hp_fill.color = Color.RED if hp < 25 else Color(0.9,0.1,0.1)

func update_alive(count: int) -> void:
	alive_label.text = "🧍 %d" % count

func update_inventory(inv: Array, selected: int) -> void:
	for i in inv_slots.size():
		var slot  := inv_slots[i]
		var item  = inv[i] if i < inv.size() else null
		var icon  := slot.get_node("icon") as Label
		var count := slot.get_node("count") as Label
		var bdr   := slot.get_node("border") as ColorRect
		icon.text  = item.icon if item else ""
		count.text = str(item.qty) if item and item.qty > 1 else ""
		bdr.color  = Color(0.3,1.0,0.3,0.8) if i == selected else Color(0.3,0.6,0.3,0.0)

func flash_damage() -> void:
	var tween := create_tween()
	tween.tween_property(damage_overlay, "color", Color(1,0,0,0.35), 0.0)
	tween.tween_property(damage_overlay, "color", Color(1,0,0,0), 0.4)

func show_hit_marker() -> void:
	hit_marker.visible = true
	hit_marker.modulate = Color.RED
	var tween := create_tween()
	tween.tween_property(hit_marker, "modulate", Color(1,0,0,0), 0.4)
	tween.tween_callback(func(): hit_marker.visible = false)

func show_miss() -> void:
	float_text("Промах", Color(0.5,0.5,0.5))

func show_border_warning(show: bool) -> void:
	var target_alpha := 0.25 if show else 0.0
	border_overlay.color.a = lerp(border_overlay.color.a, target_alpha, 0.1)

func toggle_rain(on: bool) -> void:
	var tween := create_tween()
	tween.tween_property(rain_overlay, "color", Color(0.4,0.6,1.0, 0.08 if on else 0.0), 2.0)

func float_text(text: String, color: Color = Color.WHITE) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 32)
	lbl.position = Vector2(460, 900)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	float_container.add_child(lbl)
	var tween := create_tween()
	tween.tween_property(lbl, "position", Vector2(460, 800), 1.2)
	tween.parallel().tween_property(lbl, "modulate", Color(color, 0.0), 1.2)
	tween.tween_callback(lbl.queue_free)

func _on_log_message(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.custom_minimum_size.x = 400
	log_container.add_child(lbl)
	if log_container.get_child_count() > 8:
		log_container.get_child(0).queue_free()
	# Fade out
	var tween := create_tween()
	tween.tween_interval(6.0)
	tween.tween_property(lbl, "modulate", Color(1,1,1,0), 1.0)
	tween.tween_callback(lbl.queue_free)

func _on_day_changed(is_night: bool) -> void:
	day_label.text = "🌙 НОЧЬ" if is_night else "☀️ ДЕНЬ"

func _on_round_ended(winner: String) -> void:
	_show_end_screen(winner, true)

func _on_player_died(reason: String) -> void:
	_show_end_screen("Вы умерли: " + reason, false)

func _show_end_screen(message: String, won: bool) -> void:
	var overlay := _make_rect(Color(0,0,0,0.85), Vector2(0,0), Vector2(1080,1920))
	root_control.add_child(overlay)
	var color := Color.YELLOW if won else Color.RED
	_make_label("🏆 ПОБЕДА!" if won else "☠ СМЕРТЬ", Vector2(300,600), overlay, 72, color)
	_make_label(message, Vector2(150,750), overlay, 36, Color.WHITE)
	var gm := get_tree().get_first_node_in_group("game_manager") as GameManager
	if gm:
		_make_label("Счёт: %d    Убийств: %d" % [gm.player_score, gm.player_kills],
			Vector2(200, 850), overlay, 36, Color.YELLOW)
	var restart_btn := _make_rect(Color(0.2,0.5,0.2,1), Vector2(290,1000), Vector2(500,120))
	overlay.add_child(restart_btn)
	_make_label("▶ ЗАНОВО", Vector2(130,35), restart_btn, 48, Color.WHITE)
	restart_btn.gui_input.connect(func(ev):
		if ev is InputEventScreenTouch and ev.pressed:
			get_tree().reload_current_scene()
	)

func _process(_delta: float) -> void:
	# Update timer from GM
	var gm := get_tree().get_first_node_in_group("game_manager") as GameManager
	if gm and timer_label:
		var t := int(gm.get_round_time())
		timer_label.text = "%d:%02d" % [t/60, t%60]

# ══════════════════════════════════════════════════════════════
# HELPERS
# ══════════════════════════════════════════════════════════════
func _make_rect(color: Color, pos: Vector2, size: Vector2) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.position = pos
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r

func _make_label(text: String, pos: Vector2, parent: Control, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _make_circle_btn(icon_text: String, pos: Vector2, size: float, color: Color) -> ColorRect:
	var btn := ColorRect.new()
	btn.color = color
	btn.position = pos - Vector2(size/2, size/2)
	btn.size = Vector2(size, size)
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	var lbl := Label.new()
	lbl.text = icon_text
	lbl.add_theme_font_size_override("font_size", 36)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.position = Vector2(size*0.2, size*0.1)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl)
	return btn

func _add_border(node: ColorRect, color: Color, width: int) -> void:
	for i in 4:
		var b := ColorRect.new()
		b.color = color
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		match i:
			0: b.position = Vector2.ZERO;                        b.size = Vector2(node.size.x, width)
			1: b.position = Vector2(0, node.size.y - width);     b.size = Vector2(node.size.x, width)
			2: b.position = Vector2.ZERO;                        b.size = Vector2(width, node.size.y)
			3: b.position = Vector2(node.size.x - width, 0);     b.size = Vector2(width, node.size.y)
		node.add_child(b)

func _animate_button(btn: ColorRect, pressed: bool) -> void:
	var tween := create_tween()
	var target := Color(btn.color.r, btn.color.g, btn.color.b, 1.0 if pressed else 0.7)
	tween.tween_property(btn, "color", target, 0.08)
