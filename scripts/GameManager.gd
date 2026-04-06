extends Node3D
class_name GameManager

# ─── Signals ───────────────────────────────────────────────
signal day_changed(is_night: bool)
signal round_ended(winner_name: String)
signal player_died(reason: String)
signal log_message(text: String, color: Color)

# ─── Constants ─────────────────────────────────────────────
const ROUND_DURATION   := 300.0   # 5 min
const DAY_DURATION     := 60.0
const NIGHT_DURATION   := 40.0
const MAP_SIZE         := 80.0
const BORDER_SHRINK_RATE := 0.05  # units/sec

# ─── State ─────────────────────────────────────────────────
var round_timer    : float = ROUND_DURATION
var day_timer      : float = DAY_DURATION
var is_night       : bool  = false
var is_rain        : bool  = false
var rain_timer     : float = 30.0
var border_radius  : float = 40.0
var day_number     : int   = 1
var alive_count    : int   = 8
var game_running   : bool  = false
var player_score   : int   = 0
var player_kills   : int   = 0

# ─── Refs ──────────────────────────────────────────────────
@onready var sun    : DirectionalLight3D = $DirectionalLight
var _hud : MobileHUD = null

var hud : MobileHUD:
	get:
		if _hud == null:
			_hud = get_tree().get_first_node_in_group("mobile_hud") as MobileHUD
		return _hud

static var instance : GameManager

func _ready() -> void:
	instance = self
	game_running = true
	add_to_group("game_manager")
	_setup_scene()
	emit_signal("log_message", "🏝 Раунд начался! Выживи!", Color.YELLOW)

func _setup_scene() -> void:
	pass  # terrain + bots generate themselves

func _process(delta: float) -> void:
	if not game_running:
		return
	_update_round_timer(delta)
	_update_day_cycle(delta)
	_update_rain(delta)
	_update_border(delta)
	_update_sun_position()

# ─── Round Timer ───────────────────────────────────────────
func _update_round_timer(delta: float) -> void:
	round_timer -= delta
	if round_timer <= 0.0:
		_end_round_timeout()

func _end_round_timeout() -> void:
	game_running = false
	emit_signal("round_ended", "Время вышло!")

# ─── Day / Night ───────────────────────────────────────────
func _update_day_cycle(delta: float) -> void:
	day_timer -= delta
	if day_timer <= 0.0:
		is_night = !is_night
		day_timer = NIGHT_DURATION if is_night else DAY_DURATION
		if is_night:
			day_number += 1
			emit_signal("log_message", "🌙 Ночь %d — монстры активны!" % day_number, Color.RED)
			monsters.spawn_night_wave()
		else:
			emit_signal("log_message", "☀️ День %d — выживай." % day_number, Color(1,0.9,0.4))
		emit_signal("day_changed", is_night)

func _update_sun_position() -> void:
	var t := day_timer / (NIGHT_DURATION if is_night else DAY_DURATION)
	var angle := t * 180.0 if not is_night else 180.0 + t * 180.0
	sun.rotation_degrees.x = angle - 90.0
	var day_col  := Color(1.0, 0.95, 0.85)
	var night_col:= Color(0.1, 0.15, 0.35)
	sun.light_color = day_col.lerp(night_col, float(is_night))
	sun.light_energy = 1.8 if not is_night else 0.2

# ─── Rain ──────────────────────────────────────────────────
func _update_rain(delta: float) -> void:
	rain_timer -= delta
	if rain_timer <= 0.0:
		is_rain = !is_rain
		rain_timer = randf_range(20.0, 50.0)
		var msg := "🌧 Начался дождь..." if is_rain else "🌤 Дождь закончился."
		emit_signal("log_message", msg, Color.CYAN)
		hud.toggle_rain(is_rain)

# ─── Zone Border ───────────────────────────────────────────
func _update_border(delta: float) -> void:
	border_radius = max(8.0, border_radius - BORDER_SHRINK_RATE * delta)

func get_border_radius() -> float:
	return border_radius

# ─── Public API ────────────────────────────────────────────
func register_kill(killer_name: String, victim_name: String) -> void:
	alive_count -= 1
	if killer_name == "Player":
		player_kills += 1
		player_score += 150
		emit_signal("log_message", "⚔ Вы убили %s!" % victim_name, Color.YELLOW)
	else:
		emit_signal("log_message", "💀 %s убит %s" % [victim_name, killer_name], Color(0.8,0.3,0.3))
	if hud:
		hud.update_alive(alive_count)
	if alive_count <= 1:
		game_running = false
		emit_signal("round_ended", "Победа!")

func player_dead(reason: String) -> void:
	game_running = false
	emit_signal("player_died", reason)

func add_score(pts: int) -> void:
	player_score += pts

func get_round_time() -> float:
	return round_timer

func get_day_timer_normalized() -> float:
	var total := NIGHT_DURATION if is_night else DAY_DURATION
	return 1.0 - day_timer / total
