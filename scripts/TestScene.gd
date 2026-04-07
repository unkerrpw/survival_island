extends Node3D

# ── refs ──────────────────────────────────────────────────
var cam       : Camera3D
var player_body : Node3D
var cam_yaw   : float = 0.0
var cam_pitch : float = -25.0

# ── touch ─────────────────────────────────────────────────
var joy_id    : int = -1
var look_id   : int = -1
var joy_origin: Vector2
var joy_vec   : Vector2
var joy_knob  : ColorRect

# ── player state ──────────────────────────────────────────
var px : float = 0.0
var pz : float = 0.0
var py : float = 5.0
var vy : float = 0.0
var player_yaw : float = 0.0

# ── game state ────────────────────────────────────────────
var hp    : float = 100.0
var food  : float = 100.0
var water : float = 100.0
var kills : int   = 0
var timer : float = 300.0
var alive_count : int = 8
var is_night : bool = false
var day_timer : float = 60.0

# ── terrain heights cache ─────────────────────────────────
var heights : Array = []
const MAP  := 60
const HALF := 30.0

# ── noise ─────────────────────────────────────────────────
var noise : FastNoiseLite

# ── bots ──────────────────────────────────────────────────
var bots : Array = []

# ── HUD nodes ─────────────────────────────────────────────
var hp_fill    : ColorRect
var food_fill  : ColorRect
var water_fill : ColorRect
var timer_lbl  : Label
var alive_lbl  : Label
var day_lbl    : Label
var log_vbox   : VBoxContainer
var inv_slots  : Array = []
var inventory  : Array = []
const INV_SIZE := 8

# ── inventory ─────────────────────────────────────────────
var wood  : int = 0
var stone : int = 0
var metal : int = 0
var food_items : int = 0

func _ready() -> void:
	set_process_input(true)
	_make_world()
	_make_player()
	_make_camera()
	_make_hud()
	_spawn_bots()
	_log("🏝 Выживи любой ценой!", Color.YELLOW)

# ════════════════════════════════════════════════════════
# WORLD
# ════════════════════════════════════════════════════════
func _make_world() -> void:
	# Sky + lighting
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.72, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color  = Color(1,1,1)
	env.ambient_light_energy = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.8
	sun.shadow_enabled = false
	add_child(sun)

	# Noise for terrain
	noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = randi()
	noise.frequency = 0.04
	noise.fractal_octaves = 3

	# Build terrain mesh
	var arrays = []; arrays.resize(Mesh.ARRAY_MAX)
	var verts   := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors  := PackedColorArray()
	var indices := PackedInt32Array()

	heights = []
	for z in range(MAP+1):
		var row := []
		for x in range(MAP+1):
			var wx := float(x) - HALF
			var wz := float(z) - HALF
			var d  := Vector2(wx,wz).length() / HALF
			var mask := clamp(1.0 - smoothstep(0.45, 0.88, d), 0.0, 1.0)
			var h := (noise.get_noise_2d(wx, wz)*0.5+0.5) * 5.0 * mask
			row.append(max(h, 0.05))
		heights.append(row)

	for z in range(MAP):
		for x in range(MAP):
			var v00 := Vector3(x-HALF,   heights[z][x],   z-HALF)
			var v10 := Vector3(x-HALF+1, heights[z][x+1], z-HALF)
			var v01 := Vector3(x-HALF,   heights[z+1][x], z-HALF+1)
			var v11 := Vector3(x-HALF+1, heights[z+1][x+1], z-HALF+1)
			var avg := (v00.y+v10.y+v01.y+v11.y)*0.25
			var col := Color(0.76,0.68,0.45) if avg<0.2 else (Color(0.28,0.58,0.18) if avg<2.0 else (Color(0.38,0.26,0.14) if avg<3.5 else Color(0.52,0.50,0.46)))
			var b := verts.size()
			verts.append_array([v00,v10,v11,v01])
			var n := (v10-v00).cross(v01-v00).normalized()
			normals.append_array([n,n,n,n])
			colors.append_array([col,col,col,col])
			indices.append_array([b,b+1,b+2, b,b+2,b+3])

	arrays[Mesh.ARRAY_VERTEX]=verts; arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors; arrays[Mesh.ARRAY_INDEX]=indices
	var amesh := ArrayMesh.new()
	amesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var tmat := StandardMaterial3D.new()
	tmat.vertex_color_use_as_albedo = true
	tmat.roughness = 1.0
	amesh.surface_set_material(0, tmat)

	var mi := MeshInstance3D.new(); mi.mesh = amesh
	add_child(mi)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = amesh.create_trimesh_shape()
	sb.add_child(cs); add_child(sb)

	# Water
	var wmi := MeshInstance3D.new()
	var wpl := PlaneMesh.new(); wpl.size = Vector2(200,200)
	wmi.mesh = wpl; wmi.position.y = 0.15
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.1,0.35,0.7,0.7)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmi.set_surface_override_material(0, wmat)
	add_child(wmi)

	# Trees & rocks
	var rng2 := RandomNumberGenerator.new(); rng2.randomize()
	for _i in 50:
		var x := rng2.randf_range(-HALF*0.8, HALF*0.8)
		var z := rng2.randf_range(-HALF*0.8, HALF*0.8)
		var h := _height_at(x,z)
		if h > 0.5 and h < 3.5:
			_spawn_tree(x, h, z, rng2)
	for _i in 30:
		var x := rng2.randf_range(-HALF*0.8, HALF*0.8)
		var z := rng2.randf_range(-HALF*0.8, HALF*0.8)
		var h := _height_at(x,z)
		if h > 0.3:
			_spawn_rock(x, h, z, rng2)

func _height_at(wx:float, wz:float) -> float:
	var xi := clamp(int(wx+HALF), 0, MAP-1)
	var zi := clamp(int(wz+HALF), 0, MAP-1)
	return heights[zi][xi] if not heights.is_empty() else 1.0

func _spawn_tree(x:float, h:float, z:float, rng2:RandomNumberGenerator) -> void:
	var th := rng2.randf_range(2.5, 4.5)
	var tmi := MeshInstance3D.new()
	var tc  := CylinderMesh.new(); tc.top_radius=0.1; tc.bottom_radius=0.16; tc.height=th
	tmi.mesh=tc; tmi.position=Vector3(x, h+th*0.5, z)
	var tmat:=StandardMaterial3D.new(); tmat.albedo_color=Color(0.32,0.20,0.10)
	tmi.set_surface_override_material(0,tmat); add_child(tmi)
	var lmi:=MeshInstance3D.new()
	var sc:=SphereMesh.new(); sc.radius=rng2.randf_range(0.9,1.6); sc.height=sc.radius*1.5
	lmi.mesh=sc; lmi.position=Vector3(x, h+th*0.85, z)
	var lmat:=StandardMaterial3D.new(); lmat.albedo_color=Color(rng2.randf_range(0.1,0.18),rng2.randf_range(0.4,0.6),0.1)
	lmi.set_surface_override_material(0,lmat); add_child(lmi)

func _spawn_rock(x:float, h:float, z:float, rng2:RandomNumberGenerator) -> void:
	var s:=rng2.randf_range(0.3,1.2)
	var rmi:=MeshInstance3D.new()
	var sph:=SphereMesh.new(); sph.radius=s*0.55; sph.height=s*0.8
	rmi.mesh=sph; rmi.position=Vector3(x,h+s*0.3,z)
	var rmat:=StandardMaterial3D.new(); rmat.albedo_color=Color(0.5,0.48,0.44)
	rmi.set_surface_override_material(0,rmat); add_child(rmi)

# ════════════════════════════════════════════════════════
# PLAYER
# ════════════════════════════════════════════════════════
func _make_player() -> void:
	player_body = Node3D.new()
	add_child(player_body)
	# Body mesh
	var mi:=MeshInstance3D.new(); var cap:=CapsuleMesh.new()
	cap.radius=0.35; cap.height=1.7; mi.mesh=cap; mi.position.y=0.85
	var mat:=StandardMaterial3D.new(); mat.albedo_color=Color(0.2,0.55,0.2)
	mi.set_surface_override_material(0,mat); player_body.add_child(mi)
	# Head
	var hi:=MeshInstance3D.new(); var sph:=SphereMesh.new()
	sph.radius=0.22; sph.height=0.44; hi.mesh=sph; hi.position.y=1.85
	var hm:=StandardMaterial3D.new(); hm.albedo_color=Color(0.9,0.76,0.6)
	hi.set_surface_override_material(0,hm); player_body.add_child(hi)
	# Spawn on terrain
	px=2.0; pz=2.0; py=_height_at(px,pz)+1.0

func _make_camera() -> void:
	cam = Camera3D.new()
	cam.fov=70.0; cam.near=0.05; cam.far=500.0; cam.current=true
	add_child(cam)
	_update_camera()

func _update_camera() -> void:
	var yr:=deg_to_rad(cam_yaw); var pr:=deg_to_rad(cam_pitch)
	var ox:=sin(yr)*cos(pr)*5.5; var oy:=-sin(pr)*5.5; var oz:=cos(yr)*cos(pr)*5.5
	oy = max(oy, 1.2)
	cam.position = Vector3(px+ox, py+oy, pz+oz)
	cam.look_at(Vector3(px, py+1.2, pz), Vector3.UP)

# ════════════════════════════════════════════════════════
# BOTS (visual only)
# ════════════════════════════════════════════════════════
var BOT_NAMES := ["Волк","Тень","Кабан","Лис","Ястреб","Медведь","Рысь"]
func _spawn_bots() -> void:
	var rng2:=RandomNumberGenerator.new(); rng2.randomize()
	var cols:=[Color(0.8,0.2,0.2),Color(0.2,0.2,0.8),Color(0.8,0.6,0.1),
		Color(0.5,0.1,0.8),Color(0.1,0.7,0.4),Color(0.9,0.4,0.1),Color(0.4,0.7,0.8)]
	for i in 7:
		var bx:=rng2.randf_range(-20,20); var bz:=rng2.randf_range(-20,20)
		var bh:=_height_at(bx,bz)+0.85
		var bn:=Node3D.new(); bn.position=Vector3(bx,bh,bz)
		var bmi:=MeshInstance3D.new(); var bc:=CapsuleMesh.new()
		bc.radius=0.35; bc.height=1.7; bmi.mesh=bc; bmi.position.y=0.0
		var bmat:=StandardMaterial3D.new(); bmat.albedo_color=cols[i]
		bmi.set_surface_override_material(0,bmat); bn.add_child(bmi)
		var lbl:=Label3D.new(); lbl.text=BOT_NAMES[i]; lbl.font_size=28
		lbl.modulate=Color(1,1,0); lbl.position.y=2.0
		lbl.billboard=BaseMaterial3D.BILLBOARD_ENABLED; bn.add_child(lbl)
		add_child(bn)
		bots.append({node=bn,x=bx,z=bz,hp=100.0,alive=true,
			dir=Vector2(rng2.randf_range(-1,1),rng2.randf_range(-1,1)).normalized(),
			timer=rng2.randf_range(1,3), name=BOT_NAMES[i]})

# ════════════════════════════════════════════════════════
# HUD
# ════════════════════════════════════════════════════════
func _make_hud() -> void:
	var cl:=CanvasLayer.new(); cl.layer=10; add_child(cl)
	var root:=Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter=Control.MOUSE_FILTER_IGNORE; cl.add_child(root)

	# Top bar
	var top:=ColorRect.new(); top.color=Color(0,0,0,0.5)
	top.position=Vector2(0,0); top.size=Vector2(1080,88); root.add_child(top)

	func_make_bar(top, root)

	# Joystick
	var jbg:=ColorRect.new(); jbg.color=Color(1,1,1,0.1)
	jbg.position=Vector2(50,1580); jbg.size=Vector2(160,160); root.add_child(jbg)
	var jbdr:=_border_rect(jbg,Color(1,1,1,0.3)); jbg.add_child(jbdr)
	joy_knob=ColorRect.new(); joy_knob.color=Color(1,1,1,0.3)
	joy_knob.position=Vector2(55,55); joy_knob.size=Vector2(50,50); jbg.add_child(joy_knob)
	jbg.set_meta("is_joy",true)

	# Action buttons
	_make_btn(root, "⚔", Vector2(870,1620), Color(0.9,0.1,0.1,0.75), "atk")
	_make_btn(root, "⬆", Vector2(770,1700), Color(0.1,0.5,0.9,0.75), "jump")
	_make_btn(root, "💨", Vector2(970,1700), Color(0.2,0.8,0.2,0.75), "sprint")
	_make_btn(root, "✋", Vector2(770,1560), Color(0.9,0.7,0.1,0.75), "use")
	_make_btn(root, "🔨", Vector2(970,1560), Color(0.8,0.4,0.1,0.75), "craft")

	# Inventory bar
	for i in INV_SIZE:
		var sl:=ColorRect.new(); sl.color=Color(0.08,0.12,0.08,0.88)
		sl.position=Vector2(10+i*133, 1822); sl.size=Vector2(120,90); root.add_child(sl)
		var il:=Label.new(); il.position=Vector2(10,8); il.add_theme_font_size_override("font_size",44)
		il.add_theme_color_override("font_color",Color.WHITE); il.mouse_filter=Control.MOUSE_FILTER_IGNORE
		sl.add_child(il); inv_slots.append({bg=sl,lbl=il})

	# Log
	log_vbox=VBoxContainer.new(); log_vbox.position=Vector2(10,95)
	log_vbox.custom_minimum_size=Vector2(420,0)
	log_vbox.mouse_filter=Control.MOUSE_FILTER_IGNORE; root.add_child(log_vbox)

	# Damage overlay
	var dmg:=ColorRect.new(); dmg.color=Color(1,0,0,0)
	dmg.set_anchors_preset(Control.PRESET_FULL_RECT)
	dmg.mouse_filter=Control.MOUSE_FILTER_IGNORE
	dmg.name="DmgOverlay"; root.add_child(dmg)

func func_make_bar(top, root) -> void:
	# HP
	var hbg:=ColorRect.new(); hbg.color=Color(0.2,0,0,0.9); hbg.position=Vector2(15,12); hbg.size=Vector2(180,20); top.add_child(hbg)
	hp_fill=ColorRect.new(); hp_fill.color=Color(0.9,0.1,0.1); hp_fill.position=Vector2.ZERO; hp_fill.size=Vector2(180,20); hbg.add_child(hp_fill)
	var hl:=Label.new(); hl.text="❤"; hl.position=Vector2(200,8); hl.add_theme_font_size_override("font_size",22)
	hl.add_theme_color_override("font_color",Color.RED); hl.mouse_filter=Control.MOUSE_FILTER_IGNORE; top.add_child(hl)
	# Food
	var fbg:=ColorRect.new(); fbg.color=Color(0.2,0.1,0,0.9); fbg.position=Vector2(15,38); fbg.size=Vector2(180,16); top.add_child(fbg)
	food_fill=ColorRect.new(); food_fill.color=Color(1,0.5,0); food_fill.position=Vector2.ZERO; food_fill.size=Vector2(180,16); fbg.add_child(food_fill)
	# Water
	var wbg:=ColorRect.new(); wbg.color=Color(0,0.1,0.2,0.9); wbg.position=Vector2(15,60); wbg.size=Vector2(180,16); top.add_child(wbg)
	water_fill=ColorRect.new(); water_fill.color=Color(0.2,0.7,1.0); water_fill.position=Vector2.ZERO; water_fill.size=Vector2(180,16); wbg.add_child(water_fill)
	# Timer
	timer_lbl=Label.new(); timer_lbl.position=Vector2(460,10); timer_lbl.add_theme_font_size_override("font_size",42)
	timer_lbl.add_theme_color_override("font_color",Color.YELLOW); timer_lbl.mouse_filter=Control.MOUSE_FILTER_IGNORE; top.add_child(timer_lbl)
	# Alive
	alive_lbl=Label.new(); alive_lbl.text="🧍 8"; alive_lbl.position=Vector2(820,10); alive_lbl.add_theme_font_size_override("font_size",30)
	alive_lbl.add_theme_color_override("font_color",Color.GREEN); alive_lbl.mouse_filter=Control.MOUSE_FILTER_IGNORE; top.add_child(alive_lbl)
	# Day
	day_lbl=Label.new(); day_lbl.text="☀ ДЕНЬ"; day_lbl.position=Vector2(700,48); day_lbl.add_theme_font_size_override("font_size",22)
	day_lbl.add_theme_color_override("font_color",Color(1,0.9,0.3)); day_lbl.mouse_filter=Control.MOUSE_FILTER_IGNORE; top.add_child(day_lbl)

var _btn_map : Dictionary = {}
func _make_btn(root:Control, icon:String, pos:Vector2, col:Color, id:String) -> void:
	var btn:=ColorRect.new(); btn.color=col
	btn.position=pos-Vector2(35,35); btn.size=Vector2(70,70); root.add_child(btn)
	var lbl:=Label.new(); lbl.text=icon; lbl.position=Vector2(8,4)
	lbl.add_theme_font_size_override("font_size",38); lbl.mouse_filter=Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl); _btn_map[id]=btn

func _border_rect(parent:ColorRect, col:Color) -> Control:
	var c:=Control.new(); c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for i in 4:
		var b:=ColorRect.new(); b.color=col; b.mouse_filter=Control.MOUSE_FILTER_IGNORE
		match i:
			0: b.position=Vector2.ZERO; b.size=Vector2(parent.size.x,3)
			1: b.position=Vector2(0,parent.size.y-3); b.size=Vector2(parent.size.x,3)
			2: b.position=Vector2.ZERO; b.size=Vector2(3,parent.size.y)
			3: b.position=Vector2(parent.size.x-3,0); b.size=Vector2(3,parent.size.y)
		c.add_child(b)
	return c

# ════════════════════════════════════════════════════════
# INPUT
# ════════════════════════════════════════════════════════
var _sprint : bool = false
var _attack_pressed : bool = false

func _input(ev:InputEvent) -> void:
	if ev is InputEventScreenTouch:
		var pos:=ev.position
		if ev.pressed:
			# Joystick zone
			if pos.x < 540 and pos.y > 1200 and joy_id == -1:
				joy_id=ev.index; joy_origin=pos; joy_vec=Vector2.ZERO
				return
			# Look zone
			if pos.x >= 540 and pos.y < 1600 and look_id == -1:
				look_id=ev.index; return
			# Buttons
			for id in _btn_map:
				if _btn_map[id].get_global_rect().has_point(pos):
					match id:
						"atk":    _attack_pressed=true
						"jump":   vy=7.0
						"sprint": _sprint=true
						"use":    _use_item()
		else:
			if ev.index==joy_id: joy_id=-1; joy_vec=Vector2.ZERO; joy_knob.position=Vector2(55,55)
			if ev.index==look_id: look_id=-1
			for id in _btn_map:
				if _btn_map[id].get_global_rect().has_point(pos):
					if id=="sprint": _sprint=false
					if id=="atk":    _attack_pressed=false
	elif ev is InputEventScreenDrag:
		if ev.index==joy_id:
			var d:=(ev.position-joy_origin).limit_length(60)
			joy_knob.position=Vector2(55,55)+d*0.8
			joy_vec=d/60.0
		elif ev.index==look_id:
			cam_yaw  -= ev.relative.x*0.35
			cam_pitch = clamp(cam_pitch - ev.relative.y*0.35, -70.0, 10.0)

# ════════════════════════════════════════════════════════
# GAME LOOP
# ════════════════════════════════════════════════════════
var atk_cd : float = 0.0

func _process(delta:float) -> void:
	if hp <= 0: return

	# Timer
	timer = max(0.0, timer-delta)
	var t:=int(timer); timer_lbl.text="%d:%02d"%[t/60,t%60]

	# Day/night
	day_timer -= delta
	if day_timer <= 0:
		is_night = !is_night
		day_timer = 40.0 if is_night else 60.0
		day_lbl.text = "🌙 НОЧЬ" if is_night else "☀ ДЕНЬ"
		if is_night: _log("🌙 Ночь — монстры активны!", Color.RED)
		else: _log("☀ Рассвет. Выживай.", Color(1,0.9,0.3))

	# Player movement
	var spd := 9.0 if _sprint else 5.5
	if joy_vec.length() > 0.08:
		var yr:=deg_to_rad(cam_yaw)
		var dx:=sin(yr)*joy_vec.x - sin(yr+PI/2)*joy_vec.y*-1
		var dz:=cos(yr)*joy_vec.x - cos(yr+PI/2)*joy_vec.y*-1
		# simpler:
		var fwd:=Vector2(-sin(yr),-cos(yr))
		var rgt:=Vector2(cos(yr),-sin(yr))
		var move:=(rgt*joy_vec.x + fwd*-joy_vec.y).normalized()*spd*delta
		px += move.x; pz += move.y
		px = clamp(px,-HALF+1,HALF-1); pz=clamp(pz,-HALF+1,HALF-1)
		player_yaw = lerp_angle(player_yaw, atan2(move.x,move.y), 12*delta)
		player_body.rotation.y = player_yaw

	# Gravity
	var ground:=_height_at(px,pz)+0.85
	if py > ground:
		vy -= 20.0*delta
		py += vy*delta
	if py <= ground:
		py=ground; vy=0.0

	player_body.position=Vector3(px,py,pz)
	_update_camera()

	# Drain
	food  = max(0.0, food  - 1.2*delta)
	water = max(0.0, water - 1.8*delta)
	if food<=0 or water<=0:
		hp -= 4.0*delta
		if hp<=0: _die("голод/жажда")
	hp_fill.size.x   = 180*hp/100.0
	food_fill.size.x  = 180*food/100.0
	water_fill.size.x = 180*water/100.0

	# Attack
	atk_cd -= delta
	if _attack_pressed and atk_cd<=0:
		atk_cd=0.5; _attack_pressed=false
		_do_attack()

	# Bot update
	_update_bots(delta)

	# Auto collect (wood/food from walking near objects)
	if randf() < 0.01:
		wood += 1
		_update_inv_display()

func _do_attack() -> void:
	var hit:=false
	for b in bots:
		if not b.alive: continue
		var d:=Vector2(px-b.x,pz-b.z).length()
		if d < 2.5:
			b.hp -= 25.0; hit=true
			if b.hp<=0:
				b.alive=false; b.node.visible=false
				kills+=1; alive_count-=1
				alive_lbl.text="🧍 %d"%alive_count
				_log("⚔ Вы убили %s!"%b.name, Color.YELLOW)
			break
	# Flash
	var overlay:=get_tree().root.find_child("DmgOverlay",true,false)
	if overlay:
		var tw:=create_tween()
		tw.tween_property(overlay,"color",Color(1,1,1,0.3 if hit else 0.0),0.0)
		tw.tween_property(overlay,"color",Color(1,1,1,0.0),0.3)

func _update_bots(delta:float) -> void:
	var rng2:=RandomNumberGenerator.new()
	for b in bots:
		if not b.alive: continue
		b.timer -= delta
		if b.timer <= 0:
			b.dir=Vector2(randf_range(-1,1),randf_range(-1,1)).normalized()
			b.timer=randf_range(1.5,3.5)
		b.x += b.dir.x*2.5*delta; b.z += b.dir.y*2.5*delta
		b.x=clamp(b.x,-HALF+1,HALF-1); b.z=clamp(b.z,-HALF+1,HALF-1)
		var bh:=_height_at(b.x,b.z)+0.85
		b.node.position=Vector3(b.x,bh,b.z)
		# Attack player if close
		if Vector2(px-b.x,pz-b.z).length()<1.8:
			hp-=8.0*delta
			if hp<=0: _die("убит "+b.name)

func _die(reason:String) -> void:
	_log("☠ Вы умерли: "+reason, Color.RED)
	hp=0.0

func _use_item() -> void:
	if food_items > 0:
		food_items-=1; food=min(100.0,food+40)
		_log("🍖 Съел еду",Color.ORANGE)
		_update_inv_display()

func _update_inv_display() -> void:
	var items:=[
		["🪵",str(wood)] if wood>0 else ["",""],
		["🪨",str(stone)] if stone>0 else ["",""],
		["⚙️",str(metal)] if metal>0 else ["",""],
		["🍖",str(food_items)] if food_items>0 else ["",""],
	]
	for i in inv_slots.size():
		inv_slots[i].lbl.text = items[i][0] if i < items.size() else ""

func _log(msg:String, col:Color) -> void:
	var lbl:=Label.new(); lbl.text=msg
	lbl.add_theme_color_override("font_color",col)
	lbl.add_theme_font_size_override("font_size",22)
	lbl.mouse_filter=Control.MOUSE_FILTER_IGNORE
	log_vbox.add_child(lbl)
	if log_vbox.get_child_count()>7: log_vbox.get_child(0).queue_free()
	var tw:=create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(lbl,"modulate",Color(1,1,1,0),1.0)
	tw.tween_callback(lbl.queue_free)
