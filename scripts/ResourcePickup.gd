extends Area3D

var item_id   : String = ""
var item_qty  : int    = 1
var item_icon : String = "?"
var item_name : String = ""
var collected : bool   = false
var bob_time  : float  = 0.0

func setup(id: String, qty: int, icon: String, name: String) -> void:
	item_id   = id
	item_qty  = qty
	item_icon = icon
	item_name = name
	# Build mesh
	var mesh_inst := $MeshInstance3D as MeshInstance3D
	var sph := SphereMesh.new()
	sph.radius = 0.25; sph.height = 0.5
	mesh_inst.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.8, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.6, 0) * 0.5
	mesh_inst.set_surface_override_material(0, mat)
	# Label
	var lbl := $Label3D as Label3D
	lbl.text = icon
	# Collision
	var col := $CollisionShape3D as CollisionShape3D
	var shape := SphereShape3D.new()
	shape.radius = 0.5
	col.shape = shape
	# Connect
	body_entered.connect(_on_body_entered)
	add_to_group("pickup")

func _process(delta: float) -> void:
	bob_time += delta * 2.5
	position.y = position.y + sin(bob_time) * 0.003
	rotation.y += delta * 1.5

func _on_body_entered(body: Node3D) -> void:
	if collected:
		return
	if body is CharacterBody3D and body.is_in_group("player"):
		collected = true
		body.add_item(item_id, item_qty, item_icon, item_name)
		queue_free()
