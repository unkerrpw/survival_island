extends StaticBody3D

var collected : bool = false
var respawn_timer : float = 30.0
var _timer : float = 0.0

func _ready() -> void:
	add_to_group("resource")

func collect(player: CharacterBody3D) -> void:
	if collected:
		return
	collected = true
	var qty  : int    = get_meta("qty", 1)
	var type : String = get_meta("type", "WOOD")
	var icon : String = get_meta("icon", "?")
	var name : String = get_meta("item_name", type)
	player.add_item(type, qty, icon, name)
	# Visual: shrink and hide
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.25)
	tween.tween_callback(func(): visible = false)
	_timer = respawn_timer

func _process(delta: float) -> void:
	if not collected:
		return
	_timer -= delta
	if _timer <= 0.0:
		_respawn()

func _respawn() -> void:
	collected = false
	visible   = true
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE, 0.4)
