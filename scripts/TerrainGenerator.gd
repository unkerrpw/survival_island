extends Node3D
class_name TerrainGenerator

const MAP_SIZE     := 60
const HEIGHT_SCALE := 4.0

var noise : FastNoiseLite
var rng   := RandomNumberGenerator.new()
var _heights : Array = []

func _ready() -> void:
	add_to_group("terrain_gen")
	rng.randomize()
	noise = FastNoiseLite.new()
	noise.noise_type      = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed            = rng.randi()
	noise.frequency       = 0.035
	noise.fractal_octaves = 3
	_generate()
	_scatter_objects()

func _generate() -> void:
	var half := MAP_SIZE / 2.0
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var verts   := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors  := PackedColorArray()
	var indices := PackedInt32Array()

	# Build height grid
	_heights = []
	for z in range(MAP_SIZE + 1):
		var row := []
		for x in range(MAP_SIZE + 1):
			var wx := float(x) - half
			var wz := float(z) - half
			var d  := Vector2(wx, wz).length() / half
			var mask := clamp(1.0 - smoothstep(0.45, 0.85, d), 0.0, 1.0)
			var h := (noise.get_noise_2d(wx * 0.8, wz * 0.8) * 0.5 + 0.5) * HEIGHT_SCALE * mask
			row.append(max(h, 0.02))
		_heights.append(row)

	# Build quads
	for z in range(MAP_SIZE):
		for x in range(MAP_SIZE):
			var v00 := Vector3(x - half,     _heights[z][x],     z - half)
			var v10 := Vector3(x - half + 1, _heights[z][x+1],   z - half)
			var v01 := Vector3(x - half,     _heights[z+1][x],   z - half + 1)
			var v11 := Vector3(x - half + 1, _heights[z+1][x+1], z - half + 1)
			var avg_h := (v00.y + v10.y + v01.y + v11.y) * 0.25
			var col := _get_color(avg_h)
			var base := verts.size()
			verts.append_array([v00, v10, v11, v01])
			var n := (v10 - v00).cross(v01 - v00).normalized()
			normals.append_array([n, n, n, n])
			colors.append_array([col, col, col, col])
			indices.append_array([base,base+1,base+2, base,base+2,base+3])

	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR]  = colors
	arrays[Mesh.ARRAY_INDEX]  = indices

	var amesh := ArrayMesh.new()
	amesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# Material with emission so it's always visible regardless of lighting
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.metallic  = 0.0
	# Emission makes terrain visible even without proper lighting
	mat.emission_enabled = true
	mat.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
	mat.emission = Color(0.15, 0.22, 0.1)
	mat.emission_energy = 0.6
	amesh.surface_set_material(0, mat)

	var mi := MeshInstance3D.new()
	mi.mesh = amesh
	mi.name = "TerrainMesh"
	add_child(mi)

	# Water plane
	var wmi  := MeshInstance3D.new()
	var wpl  := PlaneMesh.new()
	wpl.size = Vector2(MAP_SIZE * 3, MAP_SIZE * 3)
	wmi.mesh  = wpl
	wmi.position.y = 0.18
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.05, 0.3, 0.6, 0.75)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.roughness    = 0.05
	wmat.emission_enabled = true
	wmat.emission = Color(0.02, 0.15, 0.35)
	wmat.emission_energy = 0.4
	wmi.set_surface_override_material(0, wmat)
	add_child(wmi)

	# Collision
	var sb  := StaticBody3D.new()
	var cs  := CollisionShape3D.new()
	cs.shape = amesh.create_trimesh_shape()
	sb.add_child(cs)
	add_child(sb)

func _get_color(h: float) -> Color:
	if h < 0.15: return Color(0.75, 0.68, 0.45)   # sand
	if h < 1.0:  return Color(0.28, 0.58, 0.18)   # light grass
	if h < 2.2:  return Color(0.20, 0.48, 0.12)   # grass
	if h < 3.2:  return Color(0.38, 0.26, 0.14)   # dirt
	return       Color(0.52, 0.50, 0.46)           # rock

func get_height_at(wx: float, wz: float) -> float:
	var half := MAP_SIZE / 2.0
	var xi := clamp(int(wx + half), 0, MAP_SIZE - 1)
	var zi := clamp(int(wz + half), 0, MAP_SIZE - 1)
	if zi < _heights.size() and xi < _heights[zi].size():
		return _heights[zi][xi]
	return 1.0

func _scatter_objects() -> void:
	var half := MAP_SIZE / 2.0 * 0.8
	for _i in 60:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var h := get_height_at(x, z)
		if h > 0.5 and h < 3.5:
			_spawn_tree(Vector3(x, h, z))
	for _i in 35:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var h := get_height_at(x, z)
		if h > 0.3:
			_spawn_rock(Vector3(x, h, z))
	for _i in 12:
		var x := rng.randf_range(-half * 0.8, half * 0.8)
		var z := rng.randf_range(-half * 0.8, half * 0.8)
		var h := get_height_at(x, z)
		if h > 0.8:
			_spawn_metal(Vector3(x, h, z))
	for _i in 25:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var h := get_height_at(x, z)
		if h > 0.2 and h < 3.0:
			_spawn_bush(Vector3(x, h, z))

func _make_resource_body(pos: Vector3, type: String, qty: int, icon: String, iname: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.add_to_group("resource")
	body.set_meta("type", type)
	body.set_meta("qty",  qty)
	body.set_meta("icon", icon)
	body.set_meta("item_name", iname)
	body.global_position = pos
	body.script = load("res://scripts/ResourceBody.gd")
	return body

func _spawn_tree(pos: Vector3) -> void:
	var root := Node3D.new()
	root.global_position = pos
	add_child(root)
	var h := rng.randf_range(2.5, 5.0)
	# Trunk
	var tmi := MeshInstance3D.new()
	var tc  := CylinderMesh.new()
	tc.top_radius = 0.12; tc.bottom_radius = 0.18; tc.height = h
	tmi.mesh = tc; tmi.position.y = h * 0.5
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.32, 0.20, 0.10)
	tmat.emission_enabled = true; tmat.emission = Color(0.15,0.09,0.04); tmat.emission_energy = 0.3
	tmi.set_surface_override_material(0, tmat)
	root.add_child(tmi)
	# Leaves
	for i in 2:
		var lmi := MeshInstance3D.new()
		var sc  := SphereMesh.new()
		var r   := rng.randf_range(1.0, 1.8) * (1.0 - i * 0.3)
		sc.radius = r; sc.height = r * 1.5
		lmi.mesh = sc
		lmi.position.y = h * 0.65 + i * r * 0.7
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color(rng.randf_range(0.1,0.18), rng.randf_range(0.4,0.6), rng.randf_range(0.08,0.16))
		lmat.emission_enabled = true; lmat.emission = Color(0.05,0.2,0.04); lmat.emission_energy = 0.4
		lmi.set_surface_override_material(0, lmat)
		root.add_child(lmi)
	# Resource collision
	var rb := _make_resource_body(pos + Vector3(0, 0.5, 0), "WOOD", rng.randi_range(2,5), "🪵", "Дерево")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new(); cap.radius = 0.2; cap.height = h
	cs.shape = cap; cs.position.y = h * 0.5
	rb.add_child(cs)
	root.add_child(rb)

func _spawn_rock(pos: Vector3) -> void:
	var s   := rng.randf_range(0.4, 1.4)
	var rb  := _make_resource_body(pos + Vector3(0, s*0.3, 0), "STONE", rng.randi_range(2,4), "🪨", "Камень")
	var mi  := MeshInstance3D.new()
	var sph := SphereMesh.new(); sph.radius = s*0.55; sph.height = s*0.8
	mi.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5,0.48,0.44)
	mat.emission_enabled = true; mat.emission = Color(0.2,0.19,0.17); mat.emission_energy = 0.35
	mi.set_surface_override_material(0, mat)
	rb.add_child(mi)
	var cs := CollisionShape3D.new()
	var ss := SphereShape3D.new(); ss.radius = s * 0.6
	cs.shape = ss
	rb.add_child(cs)
	add_child(rb)

func _spawn_metal(pos: Vector3) -> void:
	var rb := _make_resource_body(pos + Vector3(0,0.25,0), "METAL", rng.randi_range(1,3), "⚙️", "Металл")
	var mi := MeshInstance3D.new()
	var bx := BoxMesh.new(); bx.size = Vector3(0.5,0.35,0.5)
	mi.mesh = bx
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55,0.6,0.65)
	mat.metallic = 0.9; mat.roughness = 0.2
	mat.emission_enabled = true; mat.emission = Color(0.3,0.35,0.4); mat.emission_energy = 0.5
	mi.set_surface_override_material(0, mat)
	rb.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = BoxShape3D.new(); (cs.shape as BoxShape3D).size = Vector3(0.55,0.4,0.55)
	rb.add_child(cs)
	add_child(rb)

func _spawn_bush(pos: Vector3) -> void:
	var rb := _make_resource_body(pos + Vector3(0,0.25,0), "FOOD", rng.randi_range(1,3), "🍖", "Еда")
	for i in 3:
		var mi  := MeshInstance3D.new()
		var sph := SphereMesh.new(); sph.radius = 0.3; sph.height = 0.5
		mi.mesh = sph
		mi.position = Vector3(rng.randf_range(-0.25,0.25), rng.randf_range(0,0.2), rng.randf_range(-0.25,0.25))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.15,0.45,0.1)
		mat.emission_enabled = true; mat.emission = Color(0.06,0.18,0.04); mat.emission_energy = 0.4
		mi.set_surface_override_material(0, mat)
		rb.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = SphereShape3D.new(); (cs.shape as SphereShape3D).radius = 0.55
	rb.add_child(cs)
	add_child(rb)
