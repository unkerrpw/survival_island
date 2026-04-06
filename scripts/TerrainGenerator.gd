extends Node3D
class_name TerrainGenerator

const MAP_SIZE     := 60
const CHUNK_SIZE   := 4
const HEIGHT_SCALE := 5.0
const WATER_LEVEL  := 0.3

var noise : FastNoiseLite
var rng   : RandomNumberGenerator

# Materials
var mat_grass  : StandardMaterial3D
var mat_dirt   : StandardMaterial3D
var mat_rock   : StandardMaterial3D
var mat_sand   : StandardMaterial3D
var mat_water  : StandardMaterial3D
var mat_wood   : StandardMaterial3D
var mat_leaves : StandardMaterial3D

func _ready() -> void:
	add_to_group("terrain_gen")
	rng = RandomNumberGenerator.new()
	rng.randomize()
	_setup_materials()
	_generate_terrain()
	_place_water()
	_scatter_objects()
	_add_border_walls()

func _setup_materials() -> void:
	mat_grass = StandardMaterial3D.new()
	mat_grass.albedo_color = Color(0.2, 0.55, 0.15)
	mat_grass.roughness    = 0.9
	mat_grass.metallic     = 0.0

	mat_dirt = StandardMaterial3D.new()
	mat_dirt.albedo_color = Color(0.45, 0.3, 0.18)
	mat_dirt.roughness    = 0.95

	mat_rock = StandardMaterial3D.new()
	mat_rock.albedo_color = Color(0.5, 0.48, 0.45)
	mat_rock.roughness    = 0.8
	mat_rock.metallic     = 0.1

	mat_sand = StandardMaterial3D.new()
	mat_sand.albedo_color = Color(0.85, 0.78, 0.55)
	mat_sand.roughness    = 0.9

	mat_water = StandardMaterial3D.new()
	mat_water.albedo_color     = Color(0.05, 0.35, 0.65, 0.7)
	mat_water.roughness        = 0.05
	mat_water.metallic         = 0.3
	mat_water.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_water.refraction_scale = 0.05
	mat_water.features[BaseMaterial3D.FEATURE_REFRACTION] = true

	mat_wood = StandardMaterial3D.new()
	mat_wood.albedo_color = Color(0.35, 0.22, 0.1)
	mat_wood.roughness    = 0.85

	mat_leaves = StandardMaterial3D.new()
	mat_leaves.albedo_color = Color(0.1, 0.45, 0.1)
	mat_leaves.roughness    = 0.9
	mat_leaves.cull_mode    = BaseMaterial3D.CULL_DISABLED

func _generate_terrain() -> void:
	noise = FastNoiseLite.new()
	noise.noise_type      = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed            = rng.randi()
	noise.frequency       = 0.03
	noise.fractal_octaves = 4

	var half := MAP_SIZE / 2.0

	# Build height grid
	_verts_cache = []
	for z in range(MAP_SIZE + 1):
		var row := []
		for x in range(MAP_SIZE + 1):
			var wx := float(x) - half
			var wz := float(z) - half
			var dist_norm := Vector2(wx, wz).length() / half
			var island_mask := clamp(1.0 - smoothstep(0.5, 0.85, dist_norm), 0.0, 1.0)
			var n := (noise.get_noise_2d(wx, wz) * 0.5 + 0.5)
			var h := n * HEIGHT_SCALE * island_mask
			h = max(h, 0.05)
			row.append(Vector3(wx, h, wz))
		_verts_cache.append(row)

	# Build ArrayMesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var verts   := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs     := PackedVector2Array()
	var indices := PackedInt32Array()
	var colors  := PackedColorArray()

	for z in range(MAP_SIZE):
		for x in range(MAP_SIZE):
			var v00 := _verts_cache[z][x]
			var v10 := _verts_cache[z][x+1]
			var v01 := _verts_cache[z+1][x]
			var v11 := _verts_cache[z+1][x+1]
			var base := verts.size()
			verts.append_array([v00, v10, v11, v01])
			var n1 := (v10 - v00).cross(v01 - v00).normalized()
			normals.append_array([n1, n1, n1, n1])
			uvs.append_array([
				Vector2(float(x)/MAP_SIZE, float(z)/MAP_SIZE),
				Vector2(float(x+1)/MAP_SIZE, float(z)/MAP_SIZE),
				Vector2(float(x+1)/MAP_SIZE, float(z+1)/MAP_SIZE),
				Vector2(float(x)/MAP_SIZE, float(z+1)/MAP_SIZE),
			])
			var avg_h := (v00.y + v10.y + v01.y + v11.y) * 0.25
			var col := _height_color(avg_h)
			colors.append_array([col, col, col, col])
			indices.append_array([base, base+1, base+2, base, base+2, base+3])

	arrays[Mesh.ARRAY_VERTEX]  = verts
	arrays[Mesh.ARRAY_NORMAL]  = normals
	arrays[Mesh.ARRAY_TEX_UV]  = uvs
	arrays[Mesh.ARRAY_COLOR]   = colors
	arrays[Mesh.ARRAY_INDEX]   = indices

	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	arr_mesh.surface_set_material(0, mat)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = arr_mesh
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mesh_inst.name = "TerrainMesh"
	add_child(mesh_inst)

	# Collision
	var col_body  := StaticBody3D.new()
	var col_shape := CollisionShape3D.new()
	col_shape.shape = arr_mesh.create_trimesh_shape()
	col_body.add_child(col_shape)
	add_child(col_body)

func _height_color(h: float) -> Color:
	if h < 0.4:  return Color(0.76, 0.70, 0.50)  # sand
	if h < 1.5:  return Color(0.22, 0.52, 0.14)  # grass
	if h < 3.0:  return Color(0.18, 0.42, 0.10)  # dark grass
	if h < 4.2:  return Color(0.40, 0.28, 0.16)  # dirt
	return       Color(0.50, 0.48, 0.44)          # rock

var _verts_cache : Array = []

func get_height_at(wx: float, wz: float) -> float:
	if _verts_cache.is_empty():
		return 0.0
	var half := MAP_SIZE / 2.0
	var xi := clamp(int(wx + half), 0, MAP_SIZE - 1)
	var zi := clamp(int(wz + half), 0, MAP_SIZE - 1)
	return _verts_cache[zi][xi].y

func _place_water() -> void:
	var water_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(MAP_SIZE * 2, MAP_SIZE * 2)
	plane.subdivide_width  = 20
	plane.subdivide_depth  = 20
	water_mesh.mesh = plane
	water_mesh.set_surface_override_material(0, mat_water)
	water_mesh.position.y = WATER_LEVEL
	water_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water_mesh)

func _scatter_objects() -> void:
	var half := MAP_SIZE / 2.0 * 0.85
	# Trees
	for _i in 80:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var h := get_height_at(x, z)
		if h > 0.8 and h < 4.0:
			_spawn_tree(Vector3(x, h, z))
	# Rocks
	for _i in 40:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var h := get_height_at(x, z)
		if h > 0.5:
			_spawn_rock(Vector3(x, h, z))
	# Metal deposits
	for _i in 15:
		var x := rng.randf_range(-half * 0.8, half * 0.8)
		var z := rng.randf_range(-half * 0.8, half * 0.8)
		var h := get_height_at(x, z)
		if h > 1.0:
			_spawn_metal(Vector3(x, h, z))
	# Food bushes
	for _i in 30:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var h := get_height_at(x, z)
		if h > 0.4 and h < 3.5:
			_spawn_bush(Vector3(x, h, z))

func _spawn_tree(pos: Vector3) -> void:
	var tree := Node3D.new()
	tree.global_position = pos
	add_child(tree)

	var height := rng.randf_range(3.0, 6.0)
	# Trunk
	var trunk_inst := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius    = rng.randf_range(0.12, 0.2)
	trunk_mesh.bottom_radius = trunk_mesh.top_radius + 0.05
	trunk_mesh.height        = height
	trunk_inst.mesh = trunk_mesh
	trunk_inst.set_surface_override_material(0, mat_wood)
	trunk_inst.position.y = height / 2.0
	tree.add_child(trunk_inst)

	# Canopy layers
	for i in 3:
		var canopy := MeshInstance3D.new()
		var cone   := ConeMesh.new()
		var rad    := rng.randf_range(1.2, 2.2) * (1.0 - i * 0.2)
		cone.radius = rad
		cone.height = rad * 1.4
		canopy.mesh = cone
		var leaf_mat := mat_leaves.duplicate() as StandardMaterial3D
		leaf_mat.albedo_color = Color(
			rng.randf_range(0.05, 0.15),
			rng.randf_range(0.35, 0.55),
			rng.randf_range(0.05, 0.15)
		)
		canopy.set_surface_override_material(0, leaf_mat)
		canopy.position.y = height * 0.55 + i * cone.height * 0.6
		tree.add_child(canopy)

	# Collision + resource
	var body := StaticBody3D.new()
	body.add_to_group("resource")
	body.set_meta("type", "WOOD")
	body.set_meta("qty", rng.randi_range(3, 6))
	body.set_meta("icon", "🪵")
	body.set_meta("item_name", "Дерево")
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = trunk_mesh.bottom_radius + 0.1
	cyl.height = height
	col.shape  = cyl
	col.position.y = height / 2.0
	body.add_child(col)
	body.script = load("res://scripts/ResourceBody.gd")
	tree.add_child(body)
	tree.rotation.y = rng.randf_range(0, TAU)

func _spawn_rock(pos: Vector3) -> void:
	var scale := rng.randf_range(0.5, 1.8)
	var body := StaticBody3D.new()
	body.add_to_group("resource")
	body.set_meta("type",      "STONE")
	body.set_meta("qty",       rng.randi_range(2, 5))
	body.set_meta("icon",      "🪨")
	body.set_meta("item_name", "Камень")
	body.global_position = pos + Vector3(0, scale*0.4, 0)
	body.script = load("res://scripts/ResourceBody.gd")

	var mesh_inst := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = scale * 0.6
	sph.height = scale * 0.9
	mesh_inst.mesh = sph
	mesh_inst.set_surface_override_material(0, mat_rock)
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = scale * 0.65
	col.shape = shape
	body.add_child(col)
	add_child(body)

func _spawn_metal(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.add_to_group("resource")
	body.set_meta("type",      "METAL")
	body.set_meta("qty",       rng.randi_range(1, 3))
	body.set_meta("icon",      "⚙️")
	body.set_meta("item_name", "Металл")
	body.global_position = pos + Vector3(0, 0.3, 0)
	body.script = load("res://scripts/ResourceBody.gd")

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6,0.65,0.7)
	mat.metallic     = 0.9
	mat.roughness    = 0.3

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.4, 0.5)
	mesh_inst.mesh = box
	mesh_inst.set_surface_override_material(0, mat)
	body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	(col.shape as BoxShape3D).size = Vector3(0.55,0.45,0.55)
	body.add_child(col)
	add_child(body)

func _spawn_bush(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.add_to_group("resource")
	body.set_meta("type",      "FOOD")
	body.set_meta("qty",       rng.randi_range(2, 4))
	body.set_meta("icon",      "🍖")
	body.set_meta("item_name", "Еда")
	body.global_position = pos + Vector3(0, 0.3, 0)
	body.script = load("res://scripts/ResourceBody.gd")

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.5, 0.1)
	mat.roughness = 0.9

	for i in 3:
		var mesh_inst := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.35
		sph.height = 0.6
		mesh_inst.mesh = sph
		mesh_inst.set_surface_override_material(0, mat)
		mesh_inst.position = Vector3(
			randf_range(-0.3, 0.3),
			randf_range(0.0, 0.3),
			randf_range(-0.3, 0.3)
		)
		body.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	col.shape = SphereShape3D.new()
	(col.shape as SphereShape3D).radius = 0.6
	body.add_child(col)
	add_child(body)

func _add_border_walls() -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 27.0
	torus.outer_radius = 30.0
	torus.rings = 64
	torus.ring_segments = 8
	ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1,0.3,0,0.4)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1,0.3,0)
	ring_mat.emission_energy = 2.0
	ring.set_surface_override_material(0, ring_mat)
	ring.position.y = 1.0
	add_child(ring)
