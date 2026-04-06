extends CharacterBody3D

func _ready() -> void:
	add_to_group("damageable")

func take_damage(amount: float, source: String) -> void:
	var hp := get_meta("hp", 100.0) - amount
	set_meta("hp", hp)
	if hp <= 0.0:
		var mm := get_tree().get_first_node_in_group("monster_manager") as MonsterManager
		if mm:
			mm.kill_monster(self, source)
