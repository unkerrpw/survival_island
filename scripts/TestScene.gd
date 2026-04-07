extends Node3D

func _ready() -> void:
	# Sky background
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.4, 0.7, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1,1,1)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Sun
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 0, 0)
	sun.light_energy = 1.5
	add_child(sun)

	# Green cube in center
	var mi  := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2, 2, 2)
	mi.mesh  = box
	mi.position = Vector3(0, 1, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 0.2)
	mi.set_surface_override_material(0, mat)
	add_child(mi)

	# Ground plane
	var gi   := MeshInstance3D.new()
	var gpl  := PlaneMesh.new()
	gpl.size = Vector2(20, 20)
	gi.mesh  = gpl
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.3, 0.6, 0.2)
	gi.set_surface_override_material(0, gmat)
	add_child(gi)

	# Camera — fixed position, looking at cube
	var cam := Camera3D.new()
	cam.position = Vector3(0, 4, 8)
	cam.rotation_degrees = Vector3(-20, 0, 0)
	cam.fov = 70.0
	cam.current = true
	add_child(cam)
