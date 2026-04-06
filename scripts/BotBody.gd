extends CharacterBody3D

func _ready() -> void:
	add_to_group("damageable")

func take_damage(amount: float, source: String) -> void:
	var bot : Node3D = get_meta("owner_bot", null)
	if bot == null:
		return
	var hp := bot.get_meta("hp", 100.0) - amount
	bot.set_meta("hp", hp)
	if hp <= 0.0:
		var bm := get_tree().get_first_node_in_group("bot_manager") as BotManager
		if bm:
			bm._kill_bot(bot, "убит " + source)
