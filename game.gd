extends Node3D
# Game logic + 3D presentation. Entities are plain Dictionaries with an "m" node reference.

const D = preload("res://data.gd")
const Hud = preload("res://hud.gd")
const Menu = preload("res://menu.gd")
var AW := 20.0  # current room half width
var AH := 13.0  # current room half depth
const FLOORS := 5
const DIRS := {"N": Vector2i(0, -1), "S": Vector2i(0, 1), "E": Vector2i(1, 0), "W": Vector2i(-1, 0)}
const OPP := {"N": "S", "S": "N", "E": "W", "W": "E"}

var P: Dictionary = {}
var enemies: Array = []
var bullets: Array = []
var items: Array = []
var chests: Array = []
var spikes: Array = []
var doors: Array = []
var fx: Array = []
var spawn_q: Array = []
var altar = null
var room: Dictionary = {}
var floor_n := 0
var over := false
var time := 0.0
var msg := ""
var msg_t := 0.0
var dirty := true
var pending_room = null
var kills := 0
var fires: Array = []  # burning ground left by a rocket leg
var flyers: Array = []  # thrown boomerang arms
var slow_t := 0.0  # pacemaker slow motion
var debug := false  # in the debug room
var god := false  # debug: take no damage
var vis_radius := -1.0
var vis_side := 0.0
var aim_pt := Vector2.ZERO
var rooms: Array = []
var solid := PackedByteArray()  # grid of cells blocked by walls, for pathfinding
var ff := PackedInt32Array()  # steps to the player from each cell
var ff_w := 0
var ff_h := 0
var ff_t := 0.0
var stairs = null
var won := false
var state := "menu"  # "menu" (main menu), "play", "paused"
var menu
# test hooks
var t_aim = null
var t_move = null
var t_lmb := false
var t_rmb := false
var t_f := false
var t_space := false
var shot_frames := -1
var shot_path := ""

var cam: Camera3D
var cam_t := Vector2.ZERO
var room_g: Node3D
var pg: Node3D
var floor_mesh: MeshInstance3D
var sun: DirectionalLight3D
var env: Environment
var vision: ColorRect

const VISION_SHADER := """
shader_type canvas_item;
uniform vec2 center;
uniform vec2 vsize;
uniform float radius = -1.0;
uniform float side = 0.0;
void fragment() {
	vec2 p = UV * vsize;
	float a = 0.0;
	if (radius > 0.0) { a = max(a, smoothstep(radius * 0.55, radius, distance(p, center)) * 0.95); }
	if (side < -0.5) { a = max(a, (1.0 - smoothstep(0.0, vsize.x * 0.55, p.x)) * 0.95); }
	if (side > 0.5) { a = max(a, smoothstep(vsize.x * 0.45, vsize.x, p.x) * 0.95); }
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
"""

# ---------------- mesh helpers ----------------
func mat(c) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c) if c is String else c
	m.roughness = 0.8
	return m

func _mi(mesh: PrimitiveMesh, c, x: float, y: float, z: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mesh.material = mat(c)
	mi.mesh = mesh
	mi.position = Vector3(x, y, z)
	return mi

func box(w: float, h: float, d: float, c, x := 0.0, y := 0.0, z := 0.0) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = Vector3(w, h, d)
	return _mi(b, c, x, y, z)

func ball(r: float, c, x := 0.0, y := 0.0, z := 0.0) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2
	return _mi(s, c, x, y, z)

func cyl(r: float, h: float, c, x := 0.0, y := 0.0, z := 0.0, top := -1.0) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.bottom_radius = r
	m.top_radius = r if top < 0 else top
	m.height = h
	return _mi(m, c, x, y, z)

func cone(r: float, h: float, c, x := 0.0, y := 0.0, z := 0.0) -> MeshInstance3D:
	return cyl(r, h, c, x, y, z, 0.0)

func fwd(n: MeshInstance3D) -> MeshInstance3D:
	n.rotation.x = PI / 2
	return n

func grp(ch: Array) -> Node3D:
	var g := Node3D.new()
	for c in ch:
		g.add_child(c)
	return g

# ---------------- setup ----------------
func _ready() -> void:
	randomize()
	_build_world()
	new_game()
	var args := OS.get_cmdline_user_args()
	if args.has("--smoke"):
		state = "play"
		smoke()
		get_tree().quit()
	elif args.has("--shot"):
		shot_path = args[args.find("--shot") + 1]
		shot_frames = 30
		state = "play"
		if args.has("debug"):
			start_debug()
		else:
			_shot_setup()
		if args.has("menu"):
			to_main_menu()
		elif args.has("pause"):
			toggle_pause()
	else:
		to_main_menu()

# ---------------- menus ----------------
func start_run() -> void:
	new_game()
	state = "play"
	menu.close()

func to_main_menu() -> void:
	state = "menu"
	menu.open("main")

func toggle_pause() -> void:
	if state == "play":
		state = "paused"
		menu.open("pause")
	elif state == "paused":
		resume()

func resume() -> void:
	state = "play"
	menu.close()

func quit_game() -> void:
	get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == "play" and shot_frames < 0:
		toggle_pause()

func _build_world() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0c0c10")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.5
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 25, 0)
	sun.shadow_enabled = true
	add_child(sun)
	cam = Camera3D.new()
	cam.fov = 45
	add_child(cam)
	cam.current = true
	cam.position = Vector3(0, 30, 19)
	cam.look_at(Vector3.ZERO)
	room_g = Node3D.new()
	add_child(room_g)
	pg = Node3D.new()
	add_child(pg)
	var layer := CanvasLayer.new()
	add_child(layer)
	var hw = Hud.new()
	hw.g = self
	hw.world = true
	vision = ColorRect.new()
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = VISION_SHADER
	sm.shader = sh
	vision.material = sm
	var hs = Hud.new()
	hs.g = self
	for c in [hw, vision, hs]:
		layer.add_child(c)
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu = Menu.new()
	menu.g = self
	layer.add_child(menu)

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.physical_keycode == KEY_ESCAPE:
			toggle_pause()
			return
		if state != "play":
			return
		if debug and debug_key(ev.physical_keycode):
			return
		match ev.physical_keycode:
			KEY_Q:
				interact("L")
			KEY_E:
				interact("R")
			KEY_SPACE:
				ability()
			KEY_R:
				if over:
					if debug:
						start_debug()
					else:
						new_game()

func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	if state == "play" and not over:
		update(dt)
	render()
	if shot_frames >= 0:
		shot_frames -= 1
		if shot_frames < 0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(shot_path)
			get_tree().quit()

# ---------------- small helpers ----------------
func say(m: String, t := 3.5) -> void:
	msg = m
	msg_t = t

func max_hp() -> int:
	return 6 + (2 if has_org("heart2") else 0) - (1 if has_org("tapeworm") else 0)

func missing() -> int:
	var n := 0
	for s in D.LIMBS:
		if P.parts[s] == null:
			n += 1
	return n

func haste() -> float:
	return 1.0 + 0.06 * missing() if has_org("adrenal") else 1.0

func eyes() -> int:
	var n := 0
	for s in ["le", "re"]:
		if sees(s):
			n += 1
	return n

func has_type(slots: Array, t: String) -> bool:
	for s in slots:
		if P.parts[s] != null and P.parts[s].type == t:
			return true
	return false

func legs() -> Array:
	var out := []
	for s in ["ll", "rl"]:
		if P.parts[s] != null:
			out.append(P.parts[s])
	return out

func leg_move() -> String:
	var ts := legs().map(func(l): return l.type)
	if ts.has("spring") and ts.has("rocket"):
		return "rocketleap"
	for t in ["bomb", "ghost", "rocket", "bird", "frog", "spring", "crate", "robot", "flesh", "squeaky", "wheel"]:
		if ts.has(t):
			return t
	return ""

func part_name(kind: String, type: String) -> String:
	return D.TYPES[kind][type].n

func d2(a, b) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func clamp_pos(o) -> void:
	var dash = o.get("dash")
	if not (dash != null and dash.get("fly", false)):  # leaps and glides carry you over obstacles
		var r: float = o.get("r", 0.55)
		for b in room.get("blocks", []):
			var nx := clampf(o.x, b.x - b.w / 2, b.x + b.w / 2)
			var nz := clampf(o.z, b.z - b.h / 2, b.z + b.h / 2)
			var dx: float = o.x - nx
			var dz: float = o.z - nz
			var d := sqrt(dx * dx + dz * dz)
			if d >= r:
				continue
			if d > 0.0001:
				o.x = nx + dx / d * r
				o.z = nz + dz / d * r
			else:  # centre is inside the block: leave through the nearest face
				var px: float = b.w / 2 + r - absf(o.x - b.x)
				var pz: float = b.h / 2 + r - absf(o.z - b.z)
				if px < pz:
					o.x += px * (1.0 if o.x >= b.x else -1.0)
				else:
					o.z += pz * (1.0 if o.z >= b.z else -1.0)
	o.x = clampf(o.x, -AW + 1, AW - 1)
	o.z = clampf(o.z, -AH + 1, AH - 1)

func in_block(x: float, z: float, margin: float) -> bool:
	for b in room.get("blocks", []):
		if absf(x - b.x) < b.w / 2 + margin and absf(z - b.z) < b.h / 2 + margin:
			return true
	return false

func ang_diff(a: float, b: float) -> float:
	return absf(angle_difference(a, b))

func add_item(d: Dictionary, x: float, z: float) -> Dictionary:
	d.x = x
	d.z = z
	d.m = null
	clamp_pos(d)
	items.append(d)
	return d

func nearest(list: Array, r: float):
	var best = null
	var bd := r
	for o in list:
		var d := d2(o, P)
		if d < bd:
			bd = d
			best = o
	return best

func prune(list: Array, keep: Callable, on = null) -> Array:
	var out := []
	for o in list:
		if keep.call(o):
			out.append(o)
		else:
			if o.get("m") != null:
				o.m.queue_free()
				o.m = null
			if on != null:
				on.call(o)
	return out

func side_name(side: String) -> String:
	return "left" if side == "L" else "right"

func hand_label(s: String) -> String:
	var h = P.parts[s]
	if h == null:
		return "-"
	var arm = P.parts[arm_of(s)]
	if arm.type == "boomerang":
		return "in the air" if arm.out else "throw arm"
	var t: String = part_name("hand", h.type)
	if can_grip(h):
		if h.held != null:
			t = D.GUNS[h.held].n
		elif h.type == "flesh":
			t = "jab"
	if arm.hand2 != null:
		t += " + " + part_name("hand", arm.hand2.type)
	return t

func space_label() -> String:
	return {
		"rocketleap": "rocket leap", "bomb": "DETONATE", "ghost": "phase", "rocket": "rocket dash", "bird": "glide",
		"frog": "hop (hold)", "spring": "leap", "crate": "stomp", "robot": "kick-dash", "flesh": "roll",
		"squeaky": "roll", "wheel": "roll", "": "-",
	}[leg_move()]

# ---------------- game flow ----------------
func new_game() -> void:
	P = {
		x = 0.0, z = AH - 2, y = 0.0, hp = 6, scrap = 0, keys = 0, inv = 0.0, cdL = 0.0, cdR = 0.0, cdSp = 0.0, cdJ = 0.0,
		dash = null, kx = 0.0, kz = 0.0, vx = 0.0, vz = 0.0, aim = -PI / 2,
		chL = 0.0, chR = 0.0, shL = 0.0, shR = 0.0, bashL = 0.0, bashR = 0.0,
		frog = 0.0, still = 0.0, drain = 0.0, frenzy = 0.0, laser = 3.0, plate = false, regrow = true,
		parts = {
			le = {type = "flesh"}, re = {type = "flesh"}, lr = {type = "flesh"}, rr = {type = "flesh"},
			jaw = {type = "flesh"}, skin = {type = "flesh"},
			la = new_part("arm", "flesh"), ra = new_part("arm", "flesh"),
			lh = new_hand("flesh"), rh = new_hand("flesh"),
			ll = {type = "flesh"}, rl = {type = "flesh"}, o1 = null, o2 = null, o3 = null,
		},
	}
	P.parts.rh.held = "pistol"
	floor_n = 0
	debug = false
	god = false
	over = false
	time = 0.0
	kills = 0
	slow_t = 0.0
	dirty = true
	pending_room = null
	won = false
	room = {}
	next_floor()
	say("Left click = left hand. Right click = right hand. Q / E grab things with that side. F = jaw.", 7.0)

func spawn(type: String, o := {}) -> Dictionary:
	var d = D.ENEMY[type]
	var elite: bool = o.get("elite", false)
	var hp: float = ceilf(d.hp * (1 + diff() * 0.06) * (2.4 if elite else 1.0))
	var e := {
		type = type, x = randf_range(-AW + 3, AW - 3), z = randf_range(-AH + 2, 0.0), hp = hp, maxhp = hp, spd = d.spd,
		r = d.r * (1.3 if elite else 1.0), sev = d.sev, kb = d.get("kb", 0.0), cd = randf_range(1, 2.5), st = "walk", t = 0.0,
		kx = 0.0, kz = 0.0, stun = 0.0, bleed = 0.0, burn = 0.0, acid = 0.0, spk = 0.0, limbs = d.limbs.duplicate(), ld = false, flash = 0.0, a = 0.0, la = 0.0, elite = elite, m = null,
	}
	for i in 12:  # do not spawn on top of the player
		if d2(e, P) > minf(9.0, AW * 0.6) and not in_block(e.x, e.z, 1.0):
			break
		e.x = randf_range(-AW + 3, AW - 3)
		e.z = randf_range(-AH + 2, AH - 2)
	e.merge(o, true)
	enemies.append(e)
	return e

func diff() -> float:
	# difficulty grows with the floor and with distance from the floor's start room
	return 1.0 + (floor_n - 1) * 2.5 + room.get("depth", 0) * 0.4

func make_room(type: String, gx := 0, gy := 0) -> Dictionary:
	return {
		idx = rooms.size(), gx = gx, gy = gy, type = type, links = {}, opened = {}, visited = false, cleared = false, depth = 0,
		items = [], chests = [], spikes = [], altar = null, stairs = null, hw = 20.0, hh = 13.0, blocks = [],
	}

# Room size and obstacles. Every layout keeps a clear cross through the middle,
# so all four doors always connect.
func gen_layout(r: Dictionary) -> void:
	var wall := "505068"
	var style: String = ["open", "pillars", "corners", "corners", "vbars", "hbars", "crates", "crates"].pick_random()
	if r.type == "start":
		r.hw = 12.0
		r.hh = 8.0
		style = "open"
	elif r.type == "surgeon":
		r.hw = 13.0
		r.hh = 9.0
		style = ["open", "pillars"].pick_random()
	elif r.type == "exit":
		style = "pillars"
	else:
		r.hw = float(randi_range(13, 20))
		r.hh = float(randi_range(9, 13))
	var hw: float = r.hw
	var hh: float = r.hh
	r.style = style
	match style:
		"pillars":
			var sz := randf_range(1.6, 2.6)
			for sx in [-1, 1]:
				for szn in [-1, 1]:
					r.blocks.append({x = sx * hw * 0.5, z = szn * hh * 0.5, w = sz, h = sz, ht = 2.4, c = wall})
		"corners":  # filled corners turn the box into an L, T or plus shape
			var n := 0
			for sx in [-1, 1]:
				for szn in [-1, 1]:
					if randf() < 0.65 or (n == 0 and sx == 1 and szn == 1):
						n += 1
						var w := randf_range(3, hw - 4)
						var h := randf_range(3, hh - 4)
						r.blocks.append({x = sx * (hw - w / 2), z = szn * (hh - h / 2), w = w, h = h, ht = 2.4, c = wall})
		"vbars":
			var l := hh * 0.6 - 2.8
			for sx in [-1, 1]:
				for szn in [-1, 1]:
					r.blocks.append({x = sx * hw * 0.5, z = szn * (2.8 + l / 2), w = 1.2, h = l, ht = 2.4, c = wall})
		"hbars":
			var l := hw * 0.6 - 3.0
			for sx in [-1, 1]:
				for szn in [-1, 1]:
					r.blocks.append({x = sx * (3.0 + l / 2), z = szn * hh * 0.5, w = l, h = 1.2, ht = 2.4, c = wall})
		"crates":
			for i in 60:
				if r.blocks.size() >= randi_range(5, 9):
					break
				var w := randf_range(1.5, 3)
				var h := randf_range(1.5, 3)
				var x := randf_range(-hw + 2.5 + w / 2, hw - 2.5 - w / 2)
				var z := randf_range(-hh + 2.5 + h / 2, hh - 2.5 - h / 2)
				if absf(x) - w / 2 < 2.6 or absf(z) - h / 2 < 2.6:
					continue
				var clash := false
				for b in r.blocks:
					if absf(x - b.x) < (w + b.w) / 2 + 2.2 and absf(z - b.z) < (h + b.h) / 2 + 2.2:
						clash = true
				if not clash:
					r.blocks.append({x = x, z = z, w = w, h = h, ht = 1.3, c = "6b5030"})

func build_room_mesh(floor_col: Color) -> void:
	floor_mesh = box(AW * 2, 0.2, AH * 2, floor_col, 0, -0.1, 0)
	room_g.add_child(floor_mesh)
	room_g.add_child(box(AW * 2 + 1, 2, 0.5, "44445a", 0, 1, -AH - 0.25))
	room_g.add_child(box(AW * 2 + 1, 2, 0.5, "44445a", 0, 1, AH + 0.25))
	room_g.add_child(box(0.5, 2, AH * 2, "44445a", -AW - 0.25, 1, 0))
	room_g.add_child(box(0.5, 2, AH * 2, "44445a", AW + 0.25, 1, 0))
	for b in room.blocks:
		b.m = box(b.w, b.ht, b.h, b.c, b.x, b.ht / 2, b.z)
		room_g.add_child(b.m)

# ---------------- pathfinding ----------------
func build_solid() -> void:
	ff_w = int(ceil(AW * 2))
	ff_h = int(ceil(AH * 2))
	solid = PackedByteArray()
	solid.resize(ff_w * ff_h)
	for cz in ff_h:
		for cx in ff_w:
			solid[cz * ff_w + cx] = 1 if in_block(-AW + cx + 0.5, -AH + cz + 0.5, 0.6) else 0
	ff = PackedInt32Array()
	ff_t = 0.0

func cell_of(x: float, z: float) -> int:
	return clampi(int(floor(z + AH)), 0, ff_h - 1) * ff_w + clampi(int(floor(x + AW)), 0, ff_w - 1)

func flood(from: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(ff_w * ff_h)
	out.fill(9999)
	out[from] = 0
	var queue := PackedInt32Array([from])
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var cx := c % ff_w
		var cz := c / ff_w
		for o in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = cx + o[0]
			var nz: int = cz + o[1]
			if nx < 0 or nz < 0 or nx >= ff_w or nz >= ff_h:
				continue
			var n := nz * ff_w + nx
			if solid[n] == 0 and out[n] > out[c] + 1:
				out[n] = out[c] + 1
				queue.append(n)
	return out

# Direction an enemy should walk to reach the player around obstacles.
func ff_dir(e: Dictionary, direct: float) -> float:
	if room.blocks.is_empty() or ff.size() != ff_w * ff_h:
		return direct
	var c := cell_of(e.x, e.z)
	if ff[c] <= 2:
		return direct
	var cx := c % ff_w
	var cz := c / ff_w
	var best := ff[c]
	var bx := 0
	var bz := 0
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var nx: int = cx + dx
			var nz: int = cz + dz
			if (dx == 0 and dz == 0) or nx < 0 or nz < 0 or nx >= ff_w or nz >= ff_h:
				continue
			if dx != 0 and dz != 0 and (solid[cz * ff_w + nx] == 1 or solid[nz * ff_w + cx] == 1):
				continue  # no cutting corners
			var v := ff[nz * ff_w + nx]
			if v < best:
				best = v
				bx = dx
				bz = dz
	if bx == 0 and bz == 0:
		return direct
	return atan2((-AH + cz + bz + 0.5) - e.z, (-AW + cx + bx + 0.5) - e.x)

func link_rooms(a: Dictionary, b: Dictionary, dir: String) -> void:
	a.links[dir] = b.idx
	b.links[OPP[dir]] = a.idx

func gen_floor() -> void:
	rooms = []
	var cells := {}
	var n := randi_range(10, 15)
	rooms.append(make_room("start"))
	cells[Vector2i.ZERO] = 0
	while rooms.size() < n:
		var parent: Dictionary = rooms.pick_random()
		var dir: String = DIRS.keys().pick_random()
		var c: Vector2i = Vector2i(parent.gx, parent.gy) + DIRS[dir]
		if cells.has(c):
			continue
		var nb := 0
		for d in DIRS.values():
			if cells.has(c + d):
				nb += 1
		if nb > 1 and randf() < 0.7:
			continue  # keep the map branchy rather than a blob
		var r := make_room("fight", c.x, c.y)
		rooms.append(r)
		cells[c] = r.idx
		link_rooms(parent, r, dir)
	for r in rooms:  # a few extra links so the map has loops
		for dir in ["E", "S"]:
			var c: Vector2i = Vector2i(r.gx, r.gy) + DIRS[dir]
			if cells.has(c) and not r.links.has(dir) and randf() < 0.15:
				link_rooms(r, rooms[cells[c]], dir)
	var queue := [rooms[0]]
	var seen := {0: true}
	while not queue.is_empty():
		var r: Dictionary = queue.pop_front()
		for dir in r.links:
			var o: Dictionary = rooms[r.links[dir]]
			if not seen.has(o.idx):
				seen[o.idx] = true
				o.depth = r.depth + 1
				queue.append(o)
	var exit_room: Dictionary = rooms[1]
	for r in rooms:
		if r.idx != 0 and r.depth + (0.5 if r.links.size() == 1 else 0.0) > exit_room.depth + (0.5 if exit_room.links.size() == 1 else 0.0):
			exit_room = r
	exit_room.type = "exit"
	var cands := rooms.filter(func(r): return r.type == "fight")
	cands.shuffle()
	cands.sort_custom(func(a, b): return a.links.size() < b.links.size())  # dead ends first
	cands[0].type = "treasure"
	cands[1].type = "surgeon"
	cands[2].type = "treasure"  # always two treasure rooms: scrap needs chests
	for r in cands:
		if r.type == "fight":
			var roll := randf()
			if roll < 0.15:
				r.type = "dark"
			elif roll < 0.25 and floor_n >= 2:
				r.type = "elite"
	for r in rooms:
		gen_layout(r)

func next_floor() -> void:
	floor_n += 1
	P.regrow = true  # lizard gland recharges
	room = {}
	gen_floor()
	enter_room(rooms[0], "")

func stash_room() -> void:
	if room.is_empty():
		return
	for list in [items, chests, spikes]:
		for o in list:
			o.m = null
	if altar != null:
		altar.m = null
	if stairs != null:
		stairs.m = null
	room.items = items
	room.chests = chests
	room.spikes = spikes
	room.altar = altar
	room.stairs = stairs

func near_door(x: float, z: float) -> bool:
	return (absf(x) < 4 and absf(z) > AH - 5) or (absf(z) < 4 and absf(x) > AW - 5)

func free_spot(mx: float, mz: float) -> Vector2:
	var v := Vector2.ZERO
	for i in 20:
		v = Vector2(randf_range(-AW + mx, AW - mx), randf_range(-AH + mz, AH - mz))
		if not near_door(v.x, v.y) and not in_block(v.x, v.y, 1.2) and Vector2(v.x - P.x, v.y - P.z).length() > 5:
			break
	return v

func enter_room(r: Dictionary, from_dir: String) -> void:
	stash_room()
	room = r
	AW = r.hw
	AH = r.hh
	for c in room_g.get_children():
		c.queue_free()
	enemies = []
	bullets = []
	fx = []
	spawn_q = []
	fires = []
	flyers = []
	for k in ["la", "ra"]:
		if P.parts[k] != null:
			P.parts[k].out = false
	P.frog = 0.0
	P.vx = 0.0
	P.vz = 0.0
	P.plate = skin_is("plated")
	dirty = true
	items = r.items
	chests = r.chests
	spikes = r.spikes
	altar = r.altar
	stairs = r.stairs
	P.x = 0.0
	P.z = 3.0
	match from_dir:  # the direction we walked: arrive at the opposite wall
		"N":
			P.z = AH - 2.5
		"S":
			P.z = -AH + 2.5
		"E":
			P.x = -AW + 2.5
			P.z = 0.0
		"W":
			P.x = AW - 2.5
			P.z = 0.0
	P.y = 0.0
	P.dash = null
	P.kx = 0.0
	P.kz = 0.0
	var dark: bool = r.type == "dark"
	build_room_mesh(Color("15151c") if dark else (Color("2c2430") if r.type == "surgeon" else Color("2a2a36")))
	build_solid()
	env.ambient_light_energy = 0.15 if dark else 0.5
	sun.light_energy = 0.25 if dark else 1.0
	doors = []
	for dir in r.links:
		var v: Vector2i = DIRS[dir]
		doors.append({x = v.x * AW, z = v.y * AH, dir = dir, to = rooms[r.links[dir]], m = null})
	if not r.visited:
		r.visited = true
		populate(r)
	if enemies.is_empty() and not r.cleared:
		clear_room()
	rescue_hand()

func populate(r: Dictionary) -> void:
	var type: String = r.type
	var df := diff()
	if type == "start" or type == "debug":
		return
	if type == "surgeon":
		altar = {x = 0.0, z = -2.0, used = false, m = null}
		return
	var budget := minf(11.0, 1.5 + df)
	if type == "treasure":
		budget = minf(6.0, 0.5 + df * 0.5)
	if type == "elite" or type == "exit":
		spawn("brute", {elite = true})
		budget = maxf(0.0, budget - 3)
	var pool := [["grunt", 1.0]]
	if df >= 2:
		pool.append(["spitter", 1.5])
	if df >= 3:
		pool.append(["slasher", 1.5])
	if df >= 4:
		pool.append(["leaper", 2.0])
	if df >= 6:
		pool.append(["brute", 3.0])
	while budget > 0:
		var pk = pool.pick_random()
		spawn(pk[0])
		budget -= pk[1]
	var n_ch := 0
	if type == "treasure":
		n_ch = 2
	elif type == "dark" or type == "elite":
		n_ch = 1
	elif type == "fight" and randf() < 0.25:
		n_ch = 1
	for i in n_ch:
		var ct := "normal"
		if type == "elite" or type == "dark":
			ct = "locked"
		elif df >= 3 and randf() < 0.22:
			ct = "mimic"
		elif randf() < 0.3:
			ct = "locked"
		var v := free_spot(4, 4)
		chests.append({x = v.x, z = v.y, type = ct, open = false, gone = false, hp = D.CHEST_HP, flash = 0.0, m = null})
	if df >= 2:
		for i in randi_range(0, 3):
			var v := free_spot(5, 5)
			spikes.append({x = v.x, z = v.y, w = randf_range(2, 4), h = randf_range(2, 4), m = null})

# Never leave the player with no way to get a hand back.
func rescue_hand() -> void:
	if P.parts.lh != null or P.parts.rh != null:
		return
	var has_arm: bool = P.parts.la != null or P.parts.ra != null
	for i in items:
		if i.get("pk") == "arm" and i.get("hand") != null:
			return
		if has_arm and i.get("pk") == "hand":
			return
	var x: float = P.x + randf_range(-3, 3)
	var z: float = P.z + randf_range(-3, 3)
	if has_arm:
		add_item({kind = "part", pk = "hand", type = "flesh", fingers = 4}, x, z)
		say("A stray hand twitches on the floor nearby...")
	else:
		add_item({kind = "part", pk = "arm", type = "flesh", hand = new_hand("flesh", 4), hand2 = null}, x, z)
		say("A stray arm twitches on the floor nearby...")

func clear_room() -> void:
	room.cleared = true
	if room.type in ["start", "surgeon", "debug"]:
		return
	var note := ""
	if has_org("liver") and P.hp < max_hp():
		P.hp += 1
	for s in ["lh", "rh"]:
		var h = P.parts[s]
		if h != null and h.type == "rotting":
			h.fingers -= 1
			if h.fingers <= 0:
				drop_held(s)
				lose_hand(s)
				note = " Your rotting hand fell apart."
			else:
				note = " Your rotting hand lost a finger."
			check_grip()
			dirty = true
	if has_org("marrow"):
		for s in ["lh", "rh"]:
			var h = P.parts[s]
			if h != null and h.type in ["flesh", "baby"] and h.fingers < h.maxf:
				h.fingers += 1
				note += " A finger grew back."
				dirty = true
				break
	if has_org("lizard") and P.regrow:
		var grown := regrow()
		if grown != "":
			note += " Your %s grew back." % grown
	if room.type == "exit":
		stairs = {x = 0.0, z = 0.0, m = null}
		say(("The guardian is down. The way out is open." if floor_n >= FLOORS else "The guardian is down. The stairs are open.") + note)
	else:
		say("Room clear. Doors unsealed." + note)
	rescue_hand()

func try_door(d: Dictionary) -> void:
	if not enemies.is_empty():
		if msg_t <= 0:
			say("The doors are sealed until the room is clear.", 1.5)
		return
	room.opened[d.dir] = true
	d.to.opened[OPP[d.dir]] = true
	pending_room = d

func descend() -> void:
	if floor_n >= FLOORS:
		won = true
		over = true
		return
	P.hp = mini(max_hp(), P.hp + 1)
	next_floor()
	say("Floor %d of %d." % [floor_n, FLOORS])

func room_label(r: Dictionary) -> String:
	if r.visited or r.type in ["treasure", "surgeon", "exit", "start"] or has_type(["le", "re"], "keyhole"):
		return D.ROOMS[r.type]
	return "?"

# ---------------- loot ----------------
func loot(x: float, z: float, rare := false) -> void:
	var r := randf()
	var px := x + randf_range(-1.2, 1.2)
	var pz := z + randf_range(0.8, 2.0)
	if r < 0.25:
		add_item({kind = "weapon", id = ["smg", "shotgun", "sniper", "knife", "pistol", "smg", "shotgun"].pick_random()}, px, pz)
	elif r < 0.7 or rare:
		var pk: String = ["hand", "hand", "leg", "leg", "arm", "eye", "ear", "jaw", "skin"].pick_random()
		add_item({kind = "part", pk = pk, type = roll_part(pk, rare)}, px, pz)
	elif r < 0.84:
		add_item({kind = "part", pk = "organ", type = roll_part("organ", rare)}, px, pz)
	elif r < 0.94:
		add_item({kind = "heart"}, px, pz)
	else:
		add_item({kind = "finger"}, px, pz)

func enemy_drop(e: Dictionary) -> void:
	kills += 1
	# parts now come off enemies while they are alive (see sever_enemy); only an elite brute still drops one on death
	if e.type == "brute" and e.elite:
		add_item({kind = "part", pk = "hand", type = "fist"}, e.x, e.z)
	elif randf() < (0.2 if has_org("tapeworm") else 0.08):
		add_item({kind = "heart"}, e.x, e.z)
	elif randf() < 0.06:
		add_item({kind = "finger"}, e.x, e.z)
	if e.type == "mimic" or e.elite:
		loot(e.x, e.z, true)
		loot(e.x, e.z)
	if e.type == "mimic" or e.elite or randf() < D.KEY_DROP:
		add_item({kind = "key"}, e.x + randf_range(-1, 1), e.z + randf_range(-1, 1))

# ---------------- body ----------------
func drop_held(s: String) -> void:
	var h = P.parts[s]
	if h == null or h.get("held") == null:
		return
	var id: String = h.held
	if D.GUNS[id].hands == 2:
		for k in ["lh", "rh"]:
			if P.parts[k] != null and P.parts[k].held == id:
				P.parts[k].held = null
	else:
		h.held = null
	add_item({kind = "weapon", id = id}, P.x + randf_range(-1.5, 1.5), P.z + randf_range(-1.5, 1.5))
	dirty = true

func check_grip() -> void:
	for s in ["lh", "rh"]:
		var h = P.parts[s]
		if h == null or h.held == null:
			continue
		var g = D.GUNS[h.held]
		var other = P.parts["rh" if s == "lh" else "lh"]
		if not can_grip(h) or not fingers_ok(h, g) or (g.hands == 2 and (other == null or other.held != h.held)):
			say("You fumble the %s!" % g.n)
			drop_held(s)

func sever(slot = null) -> void:
	var present := []
	for k in D.LIMBS:
		if P.parts[k] == null:
			continue
		var arm_slot := ""
		if k in ["la", "ra"]:
			arm_slot = k
		elif k in ["lh", "rh"]:
			arm_slot = arm_of(k)
		if arm_slot != "" and P.parts[arm_slot] != null and P.parts[arm_slot].out:
			continue  # a thrown arm is out of reach
		present.append(k)
	if present.is_empty():
		return
	var s: String = slot if slot != null else present.pick_random()
	if slot == null and s in ["la", "ra"] and P.parts[hand_of(s)] != null and randf() < 0.75:
		s = hand_of(s)  # the hand usually goes before the whole arm does
	var p = P.parts[s]
	if p == null:
		return
	var kind: String = D.SLOT[s][0]
	if kind == "hand":
		var arm = P.parts[arm_of(s)]
		if arm.hand2 != null:
			var h2: Dictionary = arm.hand2
			arm.hand2 = null
			drop_hand_item(h2, true)
			say("The second hand on your %s came off!" % D.SLOT[arm_of(s)][1])
			dirty = true
			lost_part()
			return
		if slot == null and p.type in ["flesh", "baby", "rotting"] and p.fingers > 0 and randf() < 0.5:
			var n: int = mini(p.fingers, 1 + randi() % 2)
			p.fingers -= n
			if randf() < 0.6:
				add_item({kind = "finger"}, P.x + randf_range(-2, 2), P.z + randf_range(-2, 2))
			say("Lost %d finger%s on your %s! Slower trigger." % [n, "s" if n > 1 else "", D.SLOT[s][1]])
			check_grip()
			dirty = true
			return
	if kind == "arm":
		var hs := hand_of(s)
		drop_held(hs)
		add_item({kind = "part", pk = "arm", type = p.type, hand = P.parts[hs], hand2 = p.hand2, rot = 25.0}, P.x + randf_range(-2.5, 2.5), P.z + randf_range(-2.5, 2.5))
		P.parts[hs] = null
		P.parts[s] = null
		say("Your whole %s came off! Grab it before it rots." % D.SLOT[s][1])
	elif kind == "hand":
		drop_held(s)
		drop_hand_item(p, true)
		P.parts[s] = null
		say("Your %s came off! Grab it before it rots." % D.SLOT[s][1])
	else:
		P.parts[s] = null
		add_item({kind = "part", pk = kind, type = p.type, rot = 25.0}, P.x + randf_range(-2.5, 2.5), P.z + randf_range(-2.5, 2.5))
		say("Your %s came off! Grab it before it rots." % D.SLOT[s][1])
	check_grip()
	dirty = true
	lost_part()

func hurt(dmg: int, sev_chance: float, src = null) -> void:
	if P.inv > 0 or P.dash != null or over or god:
		return
	var contact: bool = src != null and src.has("hp")
	if contact:
		var front: bool = ang_diff(atan2(src.z - P.z, src.x - P.x), P.aim) < 1.1
		if front and (P.shL > 0 or P.shR > 0):  # shield takes it
			var ba := atan2(P.z - src.z, P.x - src.x)
			P.kx += cos(ba) * 8
			P.kz += sin(ba) * 8
			P.inv = 0.4
			return
		var stilts: int = legs().filter(func(l): return l.type == "stilt").size()
		if randf() < 0.3 * stilts:  # swung under you
			P.inv = 0.4
			return
	if P.plate:
		P.plate = false
		P.inv = 0.9
		say("Your plating took the hit.", 1.5)
		return
	P.hp -= dmg * (2 if skin_is("glass") else 1)
	P.inv = 0.9
	P.still = 0.0
	var kb := 0.0
	if src != null:
		kb = src.get("kb", 0.0)
		if skin_is("rubber"):
			kb = maxf(kb, 8.0) * 2.0
	if kb > 0 and not has_type(["ll", "rl"], "peg") and not has_type(["ll", "rl"], "tread"):
		var a := atan2(P.z - src.z, P.x - src.x)
		P.kx += cos(a) * kb
		P.kz += sin(a) * kb
	if has_org("bile"):
		fx.append({k = "ring", x = P.x, z = P.z, r = 3.5, t = 0.25, life = 0.25, c = Color("a0e040")})
		for e in enemies:
			if d2(e, P) < 3.5 + e.r:
				hit(e, 1)
				status(e, "acid", 4.0)
	if skin_is("hive"):
		for i in 3:
			var fa := randf() * TAU
			bullets.append({x = P.x, z = P.z, vx = cos(fa) * 12, vz = sin(fa) * 12, mine = true, dmg = 1.0, pierce = false, life = 3.0, hits = [], explode = 0.0, big = false, dead = false, home = 8.0, fly = true, m = null})
	if has_org("pacemaker"):
		slow_t = 1.5
	for s in ["lh", "rh"]:
		var h = P.parts[s]
		if h != null and h.type == "skeleton" and h.held != null:
			say("Your skeleton hand lets go of the %s!" % D.GUNS[h.held].n)
			drop_held(s)
	for s in ["le", "re"]:
		if P.parts[s] != null and P.parts[s].type == "glass":
			P.parts[s] = null
			add_item({kind = "part", pk = "eye", type = "glass", decoy = 4.0}, P.x + randf_range(-4, 4), P.z + randf_range(-4, 4))
			say("Your glass eye pops out and rolls away. They chase it.")
			dirty = true
			break
	if randf() < sev_chance * (0.4 if skin_is("stitched") else 1.0):
		sever()
	if P.hp <= 0:
		for o in D.ORGS:
			if P.parts[o] != null and P.parts[o].type == "kidney":
				P.parts[o] = null
				P.hp = 1
				P.inv = 2.0
				dirty = true
				say("Your spare kidney gave out instead of you.", 5.0)
				return
		over = true
		msg = ""

# ---------------- interaction ----------------
func interact(side: String) -> void:
	if over or P.is_empty():
		return
	var hs: String = D.SIDE[side].hand
	var hand = P.parts[hs]
	var it = nearest(items, reach())
	if it != null:
		take_item(it, side)
		return
	var closed := chests.filter(func(c): return not c.open)
	var ch = nearest(closed, 2.8)
	if ch != null:
		if hand == null:
			say("No %s hand to open it with." % side_name(side))
		else:
			open_chest(ch, hs)
		return
	if altar != null and not altar.used and d2(altar, P) < 3.2:
		use_altar(side)
		return
	if stairs != null and d2(stairs, P) < 3.2:
		descend()
		return
	var dr = nearest(doors, 3.2)
	if dr != null:
		if hand == null:
			say("No %s hand for the door. (A robot leg dash can kick it down.)" % side_name(side))
		else:
			try_door(dr)

func take_item(it: Dictionary, side: String) -> void:
	var hs: String = D.SIDE[side].hand
	var h = P.parts[hs]
	if it.kind == "heart":
		if P.parts.jaw == null:
			say("No jaw to eat it with.")
			return
		if P.hp >= max_hp():
			say("Already at full health.")
			return
		P.hp = mini(max_hp(), P.hp + (4 if has_org("stomach") else 2))
	elif it.kind == "finger":
		if h == null or not (h.type in ["flesh", "baby"]):
			say("Fingers need a flesh hand on that side.")
			return
		if h.fingers >= h.maxf:
			say("That hand cannot take another finger. Try the other side.")
			return
		h.fingers += 1
		say("Finger reattached.")
	elif it.kind == "key":
		P.keys += 1
		say("Picked up a key.")
	elif it.kind == "scrap":
		P.scrap += 1
		if P.scrap >= D.SCRAP_NEEDED:
			P.scrap = 0
			var q = D.QUIRKY.pick_random()
			add_item({kind = "part", pk = q[0], type = q[1]}, P.x, P.z + 1.5)
			say("The scrap knits itself into a %s!" % part_name(q[0], q[1]), 5.0)
		else:
			say("Picked up scrap.")
	elif it.kind == "weapon":
		var g = D.GUNS[it.id]
		if g.hands == 2:
			for k in ["lh", "rh"]:
				var hk = P.parts[k]
				if not can_grip(hk) or not fingers_ok(hk, g):
					say("The %s needs two gripping hands with %d+ fingers each." % [g.n, g.fingers])
					return
			drop_held("lh")
			drop_held("rh")
			P.parts.lh.held = it.id
			P.parts.rh.held = it.id
		else:
			if h == null:
				say("No hand on that side. Try the other key.")
				return
			if not can_grip(h):
				say("A %s can't hold a weapon." % part_name("hand", h.type))
				return
			if not fingers_ok(h, g):
				say("The %s needs %d+ fingers." % [g.n, g.fingers])
				return
			drop_held(hs)
			h.held = it.id
		say("Equipped %s." % g.n)
	elif not attach(it, side):
		return
	items = prune(items, func(i): return not is_same(i, it))
	dirty = true
	if debug and it.get("stock", false):  # debug room stock comes straight back
		var again := it.duplicate()
		again.m = null
		add_item(again, it.sx, it.sz)

func open_chest(c: Dictionary, hs: String) -> void:
	var h = P.parts[hs]
	if h.type == "chainsaw":
		say("The chainsaw chews the chest apart.")
		if c.type == "mimic":
			wake(c)
		else:
			break_chest(c, true)
		return
	if c.type == "mimic":
		if h.type == "maw":
			say("MIMIC! Your maw bites back.")
		else:
			say("MIMIC! It bit your hand off!")
			sever(hs)
		wake(c)
		return
	if c.type == "locked":
		if h.type == "maw":
			say("Your maw chews through the lock.")
		elif h.type == "pincer":
			c.snipped = true
			say("Snipped the lock. Some of the loot got cut up with it.")
		elif P.keys > 0:
			P.keys -= 1
			say("Unlocked with a key.")
		elif h.type in ["flesh", "baby"] and h.fingers > 0:
			h.fingers -= 1
			h.maxf -= 1  # a finger the lock takes never grows back
			say("No key. The lock bites off a finger for good and opens.")
			check_grip()
			dirty = true
		else:
			say("Locked. Needs a key.")
			return
	pop_chest(c)

func pop_chest(c: Dictionary) -> void:
	c.open = true
	if c.m != null:
		c.m.get_child(1).visible = false
	var bonus: bool = c.type == "locked" and not c.get("snipped", false)
	loot(c.x, c.z, bonus)
	if bonus:
		loot(c.x, c.z)

func smash_chest(c: Dictionary) -> void:
	if c.open:
		return
	if c.type == "mimic":
		wake(c)
		return
	if randf() < 0.5:  # a smash is a gamble: loot or wreckage
		say("Smashed it open.")
		pop_chest(c)
	else:
		say("Smashed it to pieces. Only scrap left.")
		break_chest(c)

# Any hit from a bullet, melee swing or explosion. Chest hit points are never shown.
func damage_chest(c: Dictionary, saw := false) -> void:
	if c.open:
		return
	if c.type == "mimic":
		wake(c)
		return
	c.hp -= 1
	c.flash = 0.1
	if c.hp <= 0:
		break_chest(c, saw)

func break_chest(c: Dictionary, saw := false) -> void:
	c.open = true
	c.gone = true
	if saw and randf() >= D.SAW_SCRAP:
		return  # shredded too finely to leave scrap
	add_item({kind = "scrap"}, c.x, c.z)

func wake(c: Dictionary) -> void:
	c.open = true
	c.gone = true
	spawn_q.append({x = c.x, z = c.z, cd = 0.0})

func use_altar(side: String) -> void:
	var cands := []
	for s in (["le", "lr", "lh", "ll"] if side == "L" else ["re", "rr", "rh", "rl"]):
		if P.parts[s] != null and P.parts[s].type == "flesh":
			cands.append(s)
	if cands.is_empty():
		say("The surgeon wants flesh from your %s side. You have none there." % side_name(side))
		return
	var s: String = cands.pick_random()
	if s in ["lh", "rh"]:
		drop_held(s)
		lose_hand(s)
	else:
		P.parts[s] = null
	altar.used = true
	check_grip()
	dirty = true
	loot(altar.x, altar.z + 1, true)
	loot(altar.x, altar.z + 1, true)
	say("The surgeon takes your %s. Fair trade." % D.SLOT[s][1])

# ---------------- combat ----------------
func hit(e: Dictionary, dmg: float, a = null, kb := 0.0, sv := 1.0) -> void:
	e.hp -= dmg * (1.5 if e.acid > 0 else 1.0)
	e.flash = 0.12
	if a != null and kb > 0:
		e.kx += cos(a) * kb
		e.kz += sin(a) * kb
	# harder hits are more likely to take a limb off; sv scales it per weapon (99 = always)
	if sv > 0 and not e.limbs.is_empty():
		var chance := 1.0 if sv >= 99.0 else minf(0.6, 0.1 * dmg * sv) * (0.5 if e.elite else 1.0)
		if randf() < chance:
			sever_enemy(e)

# Takes one limb off an enemy. It bleeds, fights worse, and the limb may be usable.
func sever_enemy(e: Dictionary) -> void:
	if e.limbs.is_empty():
		return
	var l: String = e.limbs.pick_random()
	e.limbs.erase(l)
	e.ld = true
	fx.append({k = "ring", x = e.x, z = e.z, r = 1.2, t = 0.2, life = 0.2, c = Color("cc1111")})
	status(e, "bleed", 3.0)
	var arm: bool = l in ["la", "ra"]
	var it = null
	match e.type:
		"grunt":
			if randf() < 0.3:
				it = {kind = "part", pk = "arm", type = "flesh", hand = new_hand("flesh", randi_range(2, 5)), hand2 = null} if arm else {kind = "part", pk = "leg", type = "flesh"}
		"slasher":
			if arm and randf() < 0.35:
				it = {kind = "part", pk = "hand", type = "claw"}
			elif not arm and randf() < 0.15:
				it = {kind = "part", pk = "leg", type = "flesh"}
		"leaper":
			if randf() < 0.35:
				it = {kind = "part", pk = "leg", type = "spring"}
		"brute":
			if arm and randf() < 0.4:
				it = {kind = "part", pk = "hand", type = "fist"}
			elif not arm and randf() < 0.2:
				it = {kind = "part", pk = "leg", type = "flesh"}
		"spitter":
			if randf() < 0.4:
				it = {kind = "part", pk = "eye", type = ["cyber", "cat"].pick_random()}
	if it != null:
		add_item(it, e.x + randf_range(-1.5, 1.5), e.z + randf_range(-1.5, 1.5))

func melee(a: float, rng: float, arc: float, dmg: float, kb: float, o := {}) -> Array:
	var out := []
	fx.append({k = "arc", x = P.x, z = P.z, a = a, arc = arc, r = rng, t = 0.14, life = 0.14, c = o.get("c", Color.WHITE)})
	for e in enemies:
		var ea := atan2(e.z - P.z, e.x - P.x)
		if d2(e, P) < rng + e.r and ang_diff(ea, a) < arc:
			var dm := dmg
			var sv: float = o.get("sv", 1.0)
			if o.get("crit", false) and (e.stun > 0 or randf() < 0.3):
				dm *= 3.0
				sv = 99.0  # a pincer crit always snips a limb off
			hit(e, dm, ea, kb, sv)
			for k in ["bleed", "burn", "acid", "stun"]:
				if o.has(k):
					status(e, k, o[k])
			out.append(e)
	var smash: bool = o.get("smash", false)
	for c in chests:
		if c.open:
			continue
		var ca := atan2(c.z - P.z, c.x - P.x)
		if d2(c, P) < rng + 0.8 and ang_diff(ca, a) < arc:
			if smash:
				smash_chest(c)
			else:
				damage_chest(c, o.get("saw", false))
	if smash:
		for d in doors:
			if d2(d, P) < rng + 1.2:
				try_door(d)
	return out

func shoot(a: float, g: Dictionary, extra := {}, spread_add := 0.0) -> void:
	var spread: float = g.get("spread", 0.0) + [0.5, 0.07, 0.0][eyes()] + spread_add
	var home := 2.5 if both("le", "re", "cyber") else 0.0
	for i in g.get("pellets", 1):
		var b := a + randf_range(-spread, spread)
		var bl := {
			x = P.x + cos(a) * 0.2, z = P.z + sin(a) * 0.2, vx = cos(b) * g.spd, vz = sin(b) * g.spd, mine = true, dmg = g.dmg,
			pierce = g.get("pierce", false), life = g.get("life", 1.6), hits = [], explode = 0.0, big = false, dead = false,
			ox = P.x, oz = P.z, home = home, acid = 0.0, m = null,
		}
		bl.merge(extra, true)
		bullets.append(bl)
	if g.has("recoil") and not has_type(["la", "ra"], "robot"):
		P.kx -= cos(a) * g.recoil
		P.kz -= sin(a) * g.recoil

func hook_shot(a: float) -> void:
	var best = null
	var bd := 14.0
	for e in enemies:
		var d := d2(e, P)
		if d < bd and ang_diff(atan2(e.z - P.z, e.x - P.x), a) < 0.25:
			bd = d
			best = e
	if best == null:
		for i in items:
			var d := d2(i, P)
			if d < bd and d > 2 and ang_diff(atan2(i.z - P.z, i.x - P.x), a) < 0.25:
				bd = d
				best = i
	fx.append({k = "line", x = P.x, z = P.z, x2 = P.x + cos(a) * bd, z2 = P.z + sin(a) * bd, t = 0.18, life = 0.18, c = Color("ccccdd")})
	if best == null:
		return
	best.x = P.x + cos(a) * 1.9
	best.z = P.z + sin(a) * 1.9
	if best.has("hp"):
		best.stun = 1.2
		best.kx = 0.0
		best.kz = 0.0
		hit(best, 1)

func act(side: String, charge := 0.0) -> void:
	var s: String = D.SIDE[side].hand
	var h = P.parts[s]
	var arm = P.parts[D.SIDE[side].arm]
	var ck := "cdL" if side == "L" else "cdR"
	if h == null:
		if msg_t <= 0:
			say("No %s %s!" % [side_name(side), "arm" if arm == null else "hand"], 1.5)
		return
	if arm.out or P[ck] > 0 or P.dash != null:
		return
	P.still = 0.0
	if arm.type == "boomerang":
		throw_arm(side)
		P[ck] = 0.4
		return
	var cd := use_hand(h, s, side, arm, charge)
	if arm.hand2 != null:
		cd = maxf(cd, use_hand(arm.hand2, s, side, arm, charge))
	P[ck] = maxf(P[ck], cd / haste())

func move_input() -> Vector2:
	if t_move != null:
		return t_move
	return Vector2(
		(1 if Input.is_physical_key_pressed(KEY_D) else 0) - (1 if Input.is_physical_key_pressed(KEY_A) else 0),
		(1 if Input.is_physical_key_pressed(KEY_S) else 0) - (1 if Input.is_physical_key_pressed(KEY_W) else 0))

func ability() -> void:
	if over or P.is_empty() or P.cdSp > 0 or P.dash != null or P.frog > 0:
		return
	var L := legs()
	if L.is_empty():
		say("No legs, no dodge.")
		return
	var t := leg_move()
	if t == "":
		say("These legs cannot dodge.")
		return
	P.still = 0.0
	var lung := 0.6 if has_org("lungs") else 1.0
	if t == "crate":
		explode(P.x, P.z, 4.0, 2)
		P.cdSp = 1.4 * lung / haste()
		return
	if t == "frog":
		P.frog = 0.001  # charging; released in update()
		return
	var dir := move_input()
	if dir == Vector2.ZERO:
		dir = Vector2(cos(P.aim), sin(P.aim))
	dir = dir.normalized()
	var one := 0.65 if L.size() == 1 else 1.0
	var cd := 1.0
	match t:
		"bomb":
			for s in ["ll", "rl"]:
				if P.parts[s] != null and P.parts[s].type == "bomb":
					P.parts[s] = null
					break
			explode(P.x, P.z, 6.0, 6)
			dirty = true
			say("Your leg went off. So did you.")
			# the blast throws you across the room
			P.dash = {t = 0.55, dur = 0.55, vx = dir.x * 42, vz = dir.y * 42, type = "blast", fly = true, h = 4.0, hits = []}
			lost_part()
		"flesh", "squeaky", "wheel":
			P.dash = {t = 0.2, dur = 0.2, vx = dir.x * 24 * one, vz = dir.y * 24 * one, type = "flesh", hits = []}
		"robot":
			var pair := both("ll", "rl", "robot")
			P.dash = {t = 0.22, dur = 0.22, vx = dir.x * 38 * one, vz = dir.y * 38 * one, type = "robot", dmg = 4.0 if pair else 2.0, hits = []}
			cd = 0.6 if pair else 0.9
		"rocket":
			var far := 1.5 if has_type(["ll", "rl"], "wheel") else 1.0
			P.dash = {t = 0.35 * far, dur = 0.35 * far, vx = dir.x * 45 * one, vz = dir.y * 45 * one, type = "rocket", hits = []}
			cd = 1.4
		"bird":
			P.dash = {t = 0.9, dur = 0.9, vx = dir.x * 14, vz = dir.y * 14, type = "bird", fly = true, h = 2.4, hits = []}
			cd = 1.6
		"ghost":
			P.dash = {t = 0.35, dur = 0.35, vx = dir.x * 30, vz = dir.y * 30, type = "ghost", fly = true, hits = []}
			cd = 2.0
		"rocketleap":
			var far: float = minf(16.0, maxf(4, Vector2(aim_pt.x - P.x, aim_pt.y - P.z).length()))
			P.dash = {t = 0.6, dur = 0.6, vx = cos(P.aim) * far / 0.6, vz = sin(P.aim) * far / 0.6, type = "rocketleap", fly = true, h = 4.5, boom = [5.0, 4.0], hits = []}
			cd = 1.8
		_:  # spring
			var dist: float = minf(11 * one, maxf(3, Vector2(aim_pt.x - P.x, aim_pt.y - P.z).length()))
			P.dash = {t = 0.5, dur = 0.5, vx = cos(P.aim) * dist / 0.5, vz = sin(P.aim) * dist / 0.5, type = "spring", fly = true, h = 3.2, boom = [3.6, 2.0], hits = []}
			cd = 1.5
	P.cdSp = cd * lung / haste()

func explode(x: float, z: float, r: float, dmg: float) -> void:
	fx.append({k = "ring", x = x, z = z, r = r, t = 0.25, life = 0.25, c = Color("ffaa44")})
	var c := {x = x, z = z}
	for e in enemies:
		if d2(e, c) < r + e.r:
			hit(e, dmg, atan2(e.z - z, e.x - x), 8, 1.5)
	for ch in chests:
		if not ch.open and d2(ch, c) < r + 0.8:
			damage_chest(ch)

# ---------------- update ----------------
func update(dt: float) -> void:
	time += dt
	msg_t -= dt
	slow_t -= dt
	for k in ["inv", "cdL", "cdR", "cdSp", "cdJ", "shL", "shR", "bashL", "bashR", "laser"]:
		P[k] -= dt
	P.frenzy = maxf(0.0, P.frenzy - dt * 2)
	if t_aim != null:
		aim_pt = t_aim
	else:
		var mp := get_viewport().get_mouse_position()
		var o := cam.project_ray_origin(mp)
		var n := cam.project_ray_normal(mp)
		if absf(n.y) > 0.0001:
			var hp := o - n * (o.y / n.y)
			aim_pt = Vector2(hp.x, hp.z)
	var want_aim := atan2(aim_pt.y - P.z, aim_pt.x - P.x)
	P.aim = rotate_toward(P.aim, want_aim, 5.0 * dt) if has_type(["ll", "rl"], "stilt") else want_aim
	# movement
	var L := legs()
	var dir := move_input()
	if dir != Vector2.ZERO:
		dir = dir.normalized()
	if P.dash != null:
		var Dh = P.dash
		P.x += Dh.vx * dt
		P.z += Dh.vz * dt
		Dh.t -= dt
		P.y = sin(PI * (1 - Dh.t / Dh.dur)) * Dh.get("h", 0.0)
		if Dh.type == "robot":
			for e in enemies:
				if not Dh.hits.has(e) and d2(e, P) < e.r + 1.3:
					Dh.hits.append(e)
					hit(e, Dh.dmg, atan2(Dh.vz, Dh.vx), 14)
			for c in chests:
				if not c.open and d2(c, P) < 1.8:
					smash_chest(c)
			for d in doors:
				if d2(d, P) < 2.4:
					try_door(d)
		elif Dh.type == "rocket":
			if fires.is_empty() or d2(fires[-1], P) > 1.0:
				fires.append({x = P.x, z = P.z, t = 3.0})
		if Dh.t <= 0:
			P.dash = null
			P.y = 0.0
			P.inv = maxf(P.inv, 0.15)
			P.vx = 0.0
			P.vz = 0.0
			if Dh.has("boom"):
				explode(P.x, P.z, Dh.boom[0], Dh.boom[1])
	else:
		if P.frog > 0:
			if t_space or Input.is_physical_key_pressed(KEY_SPACE):
				P.frog = minf(1.0, P.frog + dt)
			else:  # released: the longer the charge, the further the hop
				var c: float = P.frog
				P.frog = 0.0
				var dist := 4.0 + 10.0 * c
				P.dash = {t = 0.45, dur = 0.45, vx = cos(P.aim) * dist / 0.45, vz = sin(P.aim) * dist / 0.45, type = "frog", fly = true, h = 2.0 + 2.0 * c, boom = [2.5 + 1.5 * c, 1.0 + 2.0 * c], hits = []}
				P.cdSp = (0.6 if has_org("lungs") else 1.0) / haste()
		var sp := 9.0 * haste()
		var hopping: bool = L.size() == 1 and L[0].type != "tentacle"
		if hopping:
			sp *= 0.15 + 0.75 * absf(sin(time * 7))
		elif L.is_empty():
			sp *= 0.22
		for l in L:
			sp *= D.LEG_SPD.get(l.type, 1.0)
		if P.shL > 0 or P.shR > 0:
			sp *= 0.6
		if P.frog > 0:
			sp *= 0.4
		if has_type(["ll", "rl"], "wheel"):  # wheels keep rolling
			var k := 1.0 - exp(-2.5 * dt)
			P.vx += (dir.x * sp - P.vx) * k
			P.vz += (dir.y * sp - P.vz) * k
		else:
			P.vx = dir.x * sp
			P.vz = dir.y * sp
		P.x += P.vx * dt
		P.z += P.vz * dt
		P.y = absf(sin(time * 7)) * 0.5 if hopping else 0.0
		P.still = P.still + dt if dir == Vector2.ZERO else 0.0
	P.x += P.kx * dt
	P.z += P.kz * dt
	var dec := exp(-8 * dt)
	P.kx *= dec
	P.kz *= dec
	var tread: bool = has_type(["ll", "rl"], "tread")
	if tread and P.dash == null:  # treads flatten crates
		for b in room.blocks.duplicate():
			if b.ht < 2 and absf(P.x - b.x) < b.w / 2 + 0.75 and absf(P.z - b.z) < b.h / 2 + 0.75:
				if b.get("m") != null:
					b.m.queue_free()
				room.blocks.erase(b)
				build_solid()
				fx.append({k = "ring", x = b.x, z = b.z, r = 1.5, t = 0.2, life = 0.2, c = Color("a9762f")})
	clamp_pos(P)
	if P.dash == null and enemies.is_empty() and pending_room == null:
		for d in doors:  # opened doors can simply be walked through
			if room.opened.get(d.dir, false) and d2(d, P) < 1.7 and dir.dot(Vector2(DIRS[d.dir])) > 0.5:
				pending_room = d
	# hands and jaw
	for side in ["L", "R"]:
		var down: bool = t_lmb or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if side == "R":
			down = t_rmb or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		var arm = P.parts[D.SIDE[side].arm]
		var ck: String = "ch" + side
		if arm != null and arm.type == "piston":  # hold to charge, release to hit
			if down:
				P[ck] = minf(1.0, P[ck] + dt)
			elif P[ck] > 0:
				act(side, P[ck])
				P[ck] = 0.0
		elif down:
			act(side)
	if t_f or Input.is_physical_key_pressed(KEY_F):
		jaw_act()
	if P.laser <= 0 and has_type(["le", "re"], "laser") and not enemies.is_empty():
		P.laser = 3.0
		var lx := cos(P.aim)
		var lz := sin(P.aim)
		fx.append({k = "line", x = P.x, z = P.z, x2 = P.x + lx * 40, z2 = P.z + lz * 40, t = 0.25, life = 0.25, c = Color("ff2020")})
		for e in enemies:
			var along: float = (e.x - P.x) * lx + (e.z - P.z) * lz
			var off: float = absf((e.x - P.x) * lz - (e.z - P.z) * lx)
			if along > 0 and off < e.r + 0.4:
				hit(e, 2 * power(), P.aim, 2)
	# thrown arms
	for f in flyers:
		f.t += dt
		if f.t < 0.35:
			f.x += cos(f.a) * 26 * dt
			f.z += sin(f.a) * 26 * dt
		else:
			if not f.back:
				f.back = true
				f.hits = []
			var ra := atan2(P.z - f.z, P.x - f.x)
			f.x += cos(ra) * 30 * dt
			f.z += sin(ra) * 30 * dt
			if d2(f, P) < 1.2 or f.t > 3.0:
				f.dead = true
				var arm = P.parts[D.SIDE[f.side].arm]
				if arm != null:
					arm.out = false
				dirty = true
		for e in enemies:
			if not f.hits.has(e) and d2(f, e) < e.r + 0.7:
				f.hits.append(e)
				hit(e, 3 * power(), f.a, 4)
				touch(e, P.parts[D.SIDE[f.side].hand])
	flyers = prune(flyers, func(f): return not f.dead)
	for f in fires:
		f.t -= dt
		for e in enemies:
			if d2(e, f) < e.r + 0.9:
				status(e, "burn", 1.5)
	fires = fires.filter(func(f): return f.t > 0)
	# bullets
	var slow := 0.35 if slow_t > 0 else 1.0
	var magnet: bool = has_type(["lh", "rh"], "magnet")
	var fly_eye: bool = has_type(["le", "re"], "fly")
	var sniper: bool = has_type(["le", "re"], "sniper")
	for b in bullets:
		var bdt := dt
		if not b.mine:
			bdt *= slow * (0.6 if fly_eye else 1.0)
			var bd := d2(b, P)
			if magnet and bd < 3.5 and bd > 0.01:  # pushed away from the magnet
				b.vx += (b.x - P.x) / bd * 40 * dt
				b.vz += (b.z - P.z) / bd * 40 * dt
		elif b.get("home", 0.0) > 0:
			var best = null
			var bd := 12.0
			for e in enemies:
				var d := d2(b, e)
				if d < bd:
					bd = d
					best = e
			if best != null:
				var na := rotate_toward(atan2(b.vz, b.vx), atan2(best.z - b.z, best.x - b.x), b.home * dt)
				var spd := Vector2(b.vx, b.vz).length()
				b.vx = cos(na) * spd
				b.vz = sin(na) * spd
		b.x += b.vx * bdt
		b.z += b.vz * bdt
		b.life -= bdt
		if b.mine:
			for e in enemies:
				if b.dead or b.hits.has(e):
					continue
				if d2(b, e) < e.r + 0.25:
					if b.explode > 0:
						b.dead = true
					else:
						var dm: float = b.dmg
						if sniper and b.has("ox"):
							dm *= 1.0 + minf(1.0, Vector2(b.x - b.ox, b.z - b.oz).length() / 18.0)
						hit(e, dm, atan2(b.vz, b.vx), 3)
						if b.get("acid", 0.0) > 0:
							status(e, "acid", b.acid)
						if b.pierce:
							b.hits.append(e)
						else:
							b.dead = true
			if not b.get("fly", false):
				for c in chests:
					if not b.dead and not c.open and d2(b, c) < 1:
						damage_chest(c)
						b.dead = true
		elif P.dash == null and d2(b, P) < 0.75:
			var front: bool = ang_diff(atan2(-b.vz, -b.vx), P.aim) < 1.1
			if front and (P.shL > 0 or P.shR > 0):
				b.dead = true
			elif skin_is("rubber") or (front and has_type(["le", "re"], "mirror")):
				reflect(b)
			else:
				b.dead = true
				hurt(1, 0.35)
		if absf(b.x) > AW or absf(b.z) > AH or b.life <= 0 or (in_block(b.x, b.z, 0.1) and not b.get("fly", false)):
			b.dead = true
		if b.dead and b.explode > 0:
			explode(b.x, b.z, b.explode, b.dmg)
	bullets = prune(bullets, func(b): return not b.dead)
	# enemies
	ff_t -= dt
	if ff_t <= 0 and not room.blocks.is_empty():
		ff_t = 0.2
		ff = flood(cell_of(P.x, P.z))
	var edt := dt * slow
	var decoy = null
	for i in items:
		if i.get("decoy", 0.0) > 0:
			i.decoy -= dt
			decoy = i
	var hidden: bool = decoy == null and skin_is("chameleon") and P.still > 1.0
	var evil: bool = has_type(["le", "re"], "evil")
	var squeak: bool = has_type(["ll", "rl"], "squeaky")
	var spiked: bool = skin_is("spiked")
	for e in enemies:
		e.flash -= dt
		e.spk -= dt
		if e.bleed > 0:
			e.bleed -= dt
			e.hp -= dt
		if e.burn > 0:
			e.burn -= dt
			e.hp -= dt * 0.8
		if e.acid > 0:
			e.acid -= dt
		e.x += e.kx * dt
		e.z += e.kz * dt
		e.kx *= dec
		e.kz *= dec
		var touching: bool = d2(e, P) < e.r + 0.7
		if touching and spiked and e.spk <= 0:
			e.spk = 0.5
			hit(e, 1)
		if e.stun > 0:
			e.stun -= dt
			clamp_pos(e)
			continue
		if hidden:  # lost track of you; they only hurt you if you are already touching
			if touching:
				hurt(1, e.sev, e)
			clamp_pos(e)
			continue
		var tgt = decoy if decoy != null else P
		var a := atan2(tgt.z - e.z, tgt.x - e.x)
		var d := d2(e, tgt)
		e.a = a
		var mv: float = e.spd * (1.2 if squeak else 1.0)
		# missing limbs: legs slow it down, arms weaken its attack
		var base: Array = D.ENEMY[e.type].limbs
		var legs_n: int = e.limbs.count("ll") + e.limbs.count("rl")
		var arms_n: int = e.limbs.count("la") + e.limbs.count("ra")
		var jawless: bool = base.has("jaw") and not e.limbs.has("jaw")
		if base.has("ll"):
			mv *= [0.2, 0.55, 1.0][legs_n]
		if jawless:
			mv *= 0.6
		if evil and ang_diff(atan2(e.z - P.z, e.x - P.x), P.aim) < 0.2:
			mv *= 0.5
		var mdir: float = a if decoy != null else ff_dir(e, a)
		if e.type == "spitter":
			if d < 6:
				mdir = a + PI
			elif d < 11:
				mv = 0
			e.cd -= edt
			if e.cd <= 0:
				e.cd = 1.9
				var sa: float = a if e.limbs.has("eye") else randf() * TAU  # blind: spits anywhere
				bullets.append({x = e.x, z = e.z, vx = cos(sa) * 11, vz = sin(sa) * 11, mine = false, dmg = 1.0, pierce = false, life = 4.0, hits = [], explode = 0.0, big = false, dead = false, m = null})
		elif e.type == "leaper":
			if e.st == "walk":
				e.cd -= edt
				if e.cd <= 0 and d < 13 and legs_n > 0:
					e.st = "wind"
					e.t = 0.5
					e.la = a
			elif e.st == "wind":
				mv = 0
				e.t -= edt
				if e.t <= 0:
					e.st = "leap"
					e.t = 0.45
			else:
				mv = 22.0 if legs_n == 2 else 12.0
				mdir = e.la
				e.a = e.la
				e.t -= edt
				if e.t <= 0:
					e.st = "walk"
					e.cd = 2.2
		e.x += cos(mdir) * mv * edt
		e.z += sin(mdir) * mv * edt
		var armless: bool = base.has("la") and arms_n == 0
		if d2(e, P) < e.r + (0.35 if armless else 0.7):  # no arms: it has to get right on top of you to bite
			var sv: float = e.sev
			if base.has("la"):
				sv *= [0.0, 0.5, 1.0][arms_n]
			if jawless:
				sv = 0.0
			hurt(1, sv, {x = e.x, z = e.z, hp = e.hp, kb = 0.0 if armless else e.kb})
		clamp_pos(e)
	for i in enemies.size():
		for j in range(i + 1, enemies.size()):
			var A = enemies[i]
			var B = enemies[j]
			var d := d2(A, B)
			var m: float = A.r + B.r
			if d < m and d > 0.001:
				var px: float = (A.x - B.x) / d * (m - d) / 2
				var pz: float = (A.z - B.z) / d * (m - d) / 2
				A.x += px
				A.z += pz
				B.x -= px
				B.z -= pz
	# hazards and rot
	if P.dash == null:
		var peg: bool = has_type(["ll", "rl"], "peg")
		for s in spikes:
			if absf(P.x - s.x) < s.w / 2 and absf(P.z - s.z) < s.h / 2:
				if tread:
					s.gone = true
				elif not peg:
					hurt(1, 0.2)
	spikes = prune(spikes, func(s): return not s.get("gone", false))
	for c in chests:
		c.flash -= dt
	for i in items:
		if magnet:
			var d := d2(i, P)
			if d < 6 and d > 1.2:
				i.x += (P.x - i.x) / d * 6 * dt
				i.z += (P.z - i.z) / d * 6 * dt
		if i.has("rot"):
			i.rot -= dt
			if i.rot <= 0:
				i.dead = true
				say("Your %s rotted away." % part_name(i.pk, i.type))
	items = prune(items, func(i): return not i.get("dead", false))
	chests = prune(chests, func(c): return not c.gone)
	enemies = prune(enemies, func(e): return e.hp > 0, enemy_drop)
	for q in spawn_q:
		spawn("mimic", q)
	spawn_q = []
	for f in fx:
		f.t -= dt
	fx = fx.filter(func(f): return f.t > 0)
	if enemies.is_empty() and not room.cleared:
		clear_room()
	if pending_room != null:
		var pd = pending_room
		pending_room = null
		enter_room(pd.to, pd.dir)

# ---------------- meshes ----------------
func build_player() -> void:
	for c in pg.get_children():
		c.queue_free()
	var flesh := "e9a98c"
	var p = P.parts
	var sk: String = p.skin.type
	pg.add_child(box(0.9, 1, 0.5, "3a4a7a" if sk == "flesh" else D.TYPES.skin[sk].c, 0, 1.5, 0))
	if sk == "spiked":
		for sx in [-0.3, 0.0, 0.3]:
			pg.add_child(cone(0.09, 0.35, "dddddd", sx, 2.1, -0.2))
	pg.add_child(ball(0.36, flesh, 0, 2.35, 0))
	if p.jaw != null:
		pg.add_child(box(0.42, 0.14, 0.34, "d99a80" if p.jaw.type == "flesh" else D.TYPES.jaw[p.jaw.type].c, 0, 2.1, 0.14))
	else:
		pg.add_child(box(0.3, 0.1, 0.2, "661111", 0, 2.1, 0.2))
	for sx in [["lr", 0.37], ["rr", -0.37]]:
		var ear = p[sx[0]]
		if ear != null:
			pg.add_child(box(0.08, 0.36 if ear.type == "bat" else 0.2, 0.14, flesh if ear.type == "flesh" else D.TYPES.ear[ear.type].c, sx[1], 2.42, 0))
	for sx in [["le", 0.15], ["re", -0.15]]:
		var e = p[sx[0]]
		pg.add_child(ball(0.09 if e != null else 0.07, D.TYPES.eye[e.type].c if e != null else "330000", sx[1], 2.42, 0.31))
	var two: bool = p.lh != null and p.lh.held != null and D.GUNS[p.lh.held].hands == 2
	for sx in [["la", "lh", 0.62], ["ra", "rh", -0.62]]:
		var arm = p[sx[0]]
		var h = p[sx[1]]
		var x: float = sx[2]
		if arm == null or arm.out:
			pg.add_child(box(0.24, 0.24, 0.2, "882222", x, 1.7, 0))
			continue
		var ln := 0.9
		if arm.type == "long":
			ln = 1.3
		elif arm.type == "noodle":
			ln = 1.8
		pg.add_child(box(0.14 if arm.type == "noodle" else 0.22, 0.22, ln, flesh if arm.type == "flesh" else D.TYPES.arm[arm.type].c, x, 1.6, ln / 2 - 0.1))
		var tip := ln - 0.1
		if h == null:
			pg.add_child(box(0.2, 0.2, 0.1, "882222", x, 1.6, tip))
			continue
		add_hand(h, x, tip, not two)
		if arm.hand2 != null:
			add_hand(arm.hand2, x + (0.42 if x > 0 else -0.42), tip - 0.15, false)
	if two:
		var g = D.GUNS[p.lh.held]
		pg.add_child(box(0.16, 0.22, g.len, "222222", 0, 1.6, 0.9 + g.len / 2))
	for sx in [["ll", 0.24], ["rl", -0.24]]:
		var l = p[sx[0]]
		if l == null:
			continue
		var c: String = D.TYPES.leg[l.type].c
		var x: float = sx[1]
		match l.type:
			"peg", "stilt":
				pg.add_child(cyl(0.08, 1, c, x, 0.5, 0))
			"spring", "frog":
				pg.add_child(cyl(0.16, 1, c, x, 0.5, 0))
			"bird", "tentacle":
				pg.add_child(cyl(0.14, 1, c, x, 0.5, 0, 0.06))
			"crate":
				pg.add_child(box(0.42, 0.7, 0.42, c, x, 0.35, 0))
				pg.add_child(box(0.14, 0.4, 0.14, "6b5030", x, 0.85, 0))
			"wheel":
				var w := cyl(0.32, 0.14, c, x, 0.32, 0)
				w.rotation.z = PI / 2
				pg.add_child(w)
				pg.add_child(box(0.1, 0.5, 0.1, "555555", x, 0.75, 0))
			"tread":
				pg.add_child(box(0.34, 0.4, 0.9, c, x, 0.2, 0))
				pg.add_child(box(0.2, 0.6, 0.2, "555555", x, 0.7, 0))
			"bomb":
				pg.add_child(ball(0.27, c, x, 0.3, 0))
				pg.add_child(box(0.12, 0.5, 0.12, "aa3333", x, 0.75, 0))
			_:
				pg.add_child(box(0.28, 1, 0.28, "2a3350" if l.type == "flesh" else c, x, 0.5, 0))
	var oi := 0
	for o in D.ORGS:
		if p[o] != null:
			pg.add_child(ball(0.11, D.TYPES.organ[p[o].type].c, 0.24 - oi * 0.24, 1.6, 0.27))
		oi += 1

func mk_enemy(e: Dictionary) -> Node3D:
	var c: String = D.ENEMY[e.type].c
	var skin := "e9a98c"
	var g: Node3D
	match e.type:
		"grunt":
			g = grp([
				box(1, 1.0, 0.7, c, 0, 1.2, 0), ball(0.3, skin, 0, 2.0, 0),
				limb(box(0.24, 0.24, 0.9, skin, 0.62, 1.3, 0.35), "la"), limb(box(0.24, 0.24, 0.9, skin, -0.62, 1.3, 0.35), "ra"),
				limb(box(0.3, 0.7, 0.3, "40304a", 0.25, 0.35, 0), "ll"), limb(box(0.3, 0.7, 0.3, "40304a", -0.25, 0.35, 0), "rl"),
			])
		"spitter":
			g = grp([ball(0.6, c, 0, 0.8, 0), limb(ball(0.16, "ff3355", 0, 1.05, 0.5), "eye"), cone(0.2, 0.6, c, 0, 1.6, 0)])
		"slasher":
			g = grp([
				box(0.6, 1.2, 0.5, c, 0, 1.3, 0),
				limb(fwd(cone(0.14, 0.9, "c0392b", 0.45, 1.3, 0.6)), "la"), limb(fwd(cone(0.14, 0.9, "c0392b", -0.45, 1.3, 0.6)), "ra"),
				limb(box(0.2, 0.7, 0.2, "8a4a20", 0.17, 0.35, 0), "ll"), limb(box(0.2, 0.7, 0.2, "8a4a20", -0.17, 0.35, 0), "rl"),
			])
		"leaper":
			g = grp([ball(0.6, c, 0, 1.1, 0), limb(cyl(0.14, 0.9, "6fd36f", 0.3, 0.45, 0), "ll"), limb(cyl(0.14, 0.9, "6fd36f", -0.3, 0.45, 0), "rl")])
		"brute":
			g = grp([
				box(1.9, 1.6, 1.3, c, 0, 1.6, 0), ball(0.35, skin, 0, 2.7, 0),
				limb(box(0.7, 0.7, 0.8, "5fb4e0", 1.2, 1.5, 0.7), "la"), limb(box(0.7, 0.7, 0.8, "5fb4e0", -1.2, 1.5, 0.7), "ra"),
				limb(box(0.6, 0.8, 0.6, "3a4660", 0.5, 0.4, 0), "ll"), limb(box(0.6, 0.8, 0.6, "3a4660", -0.5, 0.4, 0), "rl"),
			])
		_:
			g = grp([box(1.5, 0.9, 1.1, c, 0, 0.5, 0), limb(cone(0.12, 0.4, "ffffff", 0.4, 1.1, 0.4), "jaw"), limb(cone(0.12, 0.4, "ffffff", 0, 1.1, 0.4), "jaw"), limb(cone(0.12, 0.4, "ffffff", -0.4, 1.1, 0.4), "jaw")])
	g.set_meta("s", e.r / D.ENEMY[e.type].r)
	e.ld = true
	return g

# Marks a mesh as one of an enemy's limbs, so it disappears when that limb is cut off.
func limb(n: Node3D, name: String) -> Node3D:
	n.set_meta("limb", name)
	return n

func mk_item(i: Dictionary) -> Node3D:
	if i.kind == "heart":
		return grp([ball(0.3, "ee3344", 0, 0.5, 0)])
	if i.kind == "scrap":
		return grp([box(0.34, 0.2, 0.3, "8a6a3a", 0, 0.35, 0), box(0.2, 0.14, 0.26, "8888a0", 0.12, 0.5, 0.08)])
	if i.kind == "key":
		return grp([box(0.12, 0.08, 0.55, "ffd24a", 0, 0.5, 0), box(0.32, 0.08, 0.26, "ffd24a", 0, 0.5, -0.32)])
	if i.kind == "finger":
		return grp([box(0.12, 0.12, 0.4, "f3c4a8", 0, 0.4, 0)])
	if i.kind == "weapon":
		var g = D.GUNS[i.id]
		var is_melee: bool = g.get("melee", false)
		return grp([box(0.16, 0.06 if is_melee else 0.24, g.len + 0.3, "dddddd" if is_melee else "777788", 0, 0.5, 0)])
	var c: String = D.TYPES[i.pk][i.type].c
	match i.pk:
		"eye":
			return grp([ball(0.22, c, 0, 0.5, 0), ball(0.08, "111111", 0, 0.5, 0.19)])
		"organ":
			return grp([ball(0.3, c, 0, 0.5, 0)])
		"leg":
			return grp([box(0.26, 0.9, 0.26, c, 0, 0.55, 0)])
		"arm":
			var parts := [box(0.22, 0.22, 1.0, c, 0, 0.5, 0)]
			if i.get("hand") != null:
				parts.append(box(0.34, 0.34, 0.3, D.TYPES.hand[i.hand.type].c, 0, 0.5, 0.6))
			return grp(parts)
		"ear":
			return grp([box(0.1, 0.34, 0.26, c, 0, 0.5, 0)])
		"jaw":
			return grp([box(0.5, 0.16, 0.4, c, 0, 0.45, 0), cone(0.06, 0.18, "ffffff", 0.15, 0.6, 0.12), cone(0.06, 0.18, "ffffff", -0.15, 0.6, 0.12)])
		"skin":
			return grp([box(0.8, 0.06, 0.6, c, 0, 0.4, 0)])
	return grp([box(0.24, 0.24, 0.7, c, 0, 0.5, 0), box(0.34, 0.34, 0.3, c, 0, 0.5, 0.45)])

func mk_chest(c: Dictionary) -> Node3D:
	var locked: bool = c.type == "locked"
	return grp([box(1.5, 0.7, 1.1, "777799" if locked else "a9762f", 0, 0.35, 0), box(1.6, 0.35, 1.2, "555577" if locked else "8a5a1f", 0, 0.85, 0)])

func mk_bullet(b: Dictionary) -> Node3D:
	var c := "ff66ff"
	if b.mine:
		c = "ffaa33" if b.big else "ffee66"
	var m := ball(0.3 if b.big else 0.14, c, 0, 1.4, 0)
	m.mesh.material.emission_enabled = true
	m.mesh.material.emission = Color(c)
	return grp([m])

func mk_spike(s: Dictionary) -> Node3D:
	var g := grp([box(s.w, 0.06, s.h, "551c1c", 0, 0.03, 0)])
	for i in 8:
		g.add_child(cone(0.15, 0.5, "aa3333", randf_range(-s.w / 2 + 0.2, s.w / 2 - 0.2), 0.25, randf_range(-s.h / 2 + 0.2, s.h / 2 - 0.2)))
	return g

func mk_door(d: Dictionary) -> Node3D:
	var horiz: bool = d.dir == "N" or d.dir == "S"
	var off := Vector2(DIRS[d.dir]) * 0.3
	return grp([box(3.2 if horiz else 0.6, 3, 0.6 if horiz else 3.2, "333333", off.x, 1.5, off.y)])

func sync(list: Array, mk: Callable) -> void:
	for o in list:
		if o.get("m") == null:
			o.m = mk.call(o)
			room_g.add_child(o.m)
		o.m.position = Vector3(o.x, 0, o.z)

# ---------------- render ----------------
func render() -> void:
	if dirty:
		build_player()
		dirty = false
	sync(enemies, mk_enemy)
	sync(items, mk_item)
	sync(chests, mk_chest)
	sync(bullets, mk_bullet)
	sync(spikes, mk_spike)
	sync(doors, mk_door)
	sync(flyers, mk_flyer)
	for f in flyers:
		f.m.rotation.y = time * 22
	if altar != null and altar.m == null:
		altar.m = grp([box(2.4, 1, 1.4, "8a4a9a", 0, 0.5, 0), box(0.2, 1.4, 0.2, "ffffff", 0, 1.7, 0), box(0.9, 0.2, 0.2, "ffffff", 0, 1.9, 0)])
		room_g.add_child(altar.m)
		altar.m.position = Vector3(altar.x, 0, altar.z)
	for c in chests:
		var cs := 1.12 if c.flash > 0 else 1.0
		c.m.scale = Vector3(cs, cs, cs)
	for d in doors:
		var col: String = D.DOOR_COLOR[d.to.type]
		if not enemies.is_empty():
			col = "661111"
		elif room.opened.get(d.dir, false):
			col = "15151a"
		d.m.get_child(0).mesh.material.albedo_color = Color(col)
	if stairs != null and stairs.m == null:
		stairs.m = grp([box(3.4, 0.1, 3.4, "050505", 0, 0.05, 0), box(3.4, 0.5, 0.8, "8888aa", 0, 0.25, -1.3), box(3.4, 0.3, 0.8, "666688", 0, 0.15, -0.5)])
		room_g.add_child(stairs.m)
		stairs.m.position = Vector3(stairs.x, 0, stairs.z)
	for e in enemies:
		var s: float = e.m.get_meta("s") * (1.2 if e.flash > 0 else 1.0)
		e.m.scale = Vector3(s, s * (0.6 if e.st == "wind" else 1.0), s)
		e.m.rotation.y = -e.a + PI / 2 + (time * 12 if e.stun > 0 else 0.0)
		if e.ld:
			e.ld = false
			for ch in e.m.get_children():
				if ch.has_meta("limb"):
					ch.visible = e.limbs.has(ch.get_meta("limb"))
			# no legs left: it drags itself along the floor
			e.m.rotation.x = 1.1 if D.ENEMY[e.type].limbs.has("ll") and not (e.limbs.has("ll") or e.limbs.has("rl")) else 0.0
	for i in items:
		i.m.rotation.y = time * 1.5
		i.m.position.y = 0.15 + sin(time * 3 + i.x) * 0.12
	pg.position = Vector3(P.x, P.y, P.z)
	pg.rotation.y = -P.aim + PI / 2
	pg.rotation.x = 1.2 if legs().is_empty() else 0.0
	pg.visible = not (P.inv > 0 and int(time * 20) % 2 == 1)
	cam_t.x += (P.x * 0.85 - cam_t.x) * 0.1
	cam_t.y += (P.z * 0.85 - cam_t.y) * 0.1
	var far := 1.25 if has_type(["le", "re"], "sniper") else 1.0  # sniper eye pulls the camera back
	cam.position = Vector3(cam_t.x, 30 * far, cam_t.y + 19 * far)
	cam.look_at(Vector3(cam_t.x, 0, cam_t.y))
	# vision
	var sm: ShaderMaterial = vision.material
	vis_radius = -1.0
	vis_side = 0.0
	if eyes() == 0:
		vis_radius = 150.0
	else:
		if room.type == "dark" and not has_type(["le", "re"], "cat") and not has_type(["lh", "rh"], "torch"):
			vis_radius = 300.0
		if eyes() == 1:
			vis_side = -1.0 if not sees("le") else 1.0
	sm.set_shader_parameter("center", cam.unproject_position(Vector3(P.x, 1.5, P.z)))
	sm.set_shader_parameter("vsize", get_viewport().get_visible_rect().size)
	sm.set_shader_parameter("radius", vis_radius)
	sm.set_shader_parameter("side", vis_side)

# ---------------- expanded body: helpers and new part logic ----------------
func sees(s: String) -> bool:
	return P.parts[s] != null and P.parts[s].type != "glass"

func has_org(t: String) -> bool:
	return has_type(D.ORGS, t)

func both(a: String, b: String, t: String) -> bool:
	return has_type([a], t) and has_type([b], t)

func skin_is(t: String) -> bool:
	return P.parts.skin.type == t

func hand_of(arm_slot: String) -> String:
	return "lh" if arm_slot == "la" else "rh"

func arm_of(hand_slot: String) -> String:
	return "la" if hand_slot == "lh" else "ra"

func can_grip(h) -> bool:
	return h != null and h.type in D.GRIP

func fingers_ok(h, g) -> bool:
	if h.type == "skeleton":
		return true
	if h.type == "baby":
		return g.hands == 1
	return h.fingers >= g.fingers

func new_hand(type: String, fingers := -1) -> Dictionary:
	var top := 2 if type == "baby" else 5
	var f := 0
	if type in D.GRIP:
		f = top
		if fingers >= 0 and type != "skeleton":
			f = mini(top, fingers)
	return {type = type, fingers = f, maxf = top, held = null}

func new_part(kind: String, type: String) -> Dictionary:
	if kind == "hand":
		return new_hand(type)
	if kind == "arm":
		return {type = type, hand2 = null, out = false}
	return {type = type}

# How far away things can be picked up.
func reach() -> float:
	return 3.8 if has_type(["la", "ra"], "long") else 2.2

# Damage multiplier from the whole body.
func power() -> float:
	var m := 1.0
	if skin_is("glass"):
		m *= 2.0
	if has_org("blackheart"):
		m *= 1.0 + 0.75 * (1.0 - clampf(float(P.hp) / max_hp(), 0.0, 1.0))
	return m

# Drained blood turns into health: 6 points per HP.
func feed(amount: float) -> void:
	P.drain += amount
	while P.drain >= 6.0:
		P.drain -= 6.0
		if P.hp < max_hp():
			P.hp += 1
			say("Drained. +1 HP.", 1.5)

func item_name(i: Dictionary) -> String:
	if i.kind == "weapon":
		return D.GUNS[i.id].n
	if i.kind != "part":
		return i.kind
	var n: String = part_name(i.pk, i.type)
	if i.pk == "hand" and i.type in ["flesh", "baby", "rotting"]:
		n += " (%df)" % i.get("fingers", 2 if i.type == "baby" else 5)
	if i.pk == "arm" and i.get("hand") != null:
		n += " + " + part_name("hand", i.hand.type)
	return n

func jaw_label() -> String:
	var j = P.parts.jaw
	if j == null:
		return "-"
	return {"flesh": "bite", "shark": "lunge bite", "howler": "howl", "spitter": "acid spit", "fangs": "drain bite"}[j.type]

# Lizard gland: one missing limb grows back as plain flesh. Returns its label, or "".
func regrow() -> String:
	for s in ["la", "ra", "lh", "rh", "ll", "rl", "le", "re", "jaw", "lr", "rr"]:
		if P.parts[s] != null:
			continue
		var kind: String = D.SLOT[s][0]
		if kind == "hand" and P.parts[arm_of(s)] == null:
			continue
		P.parts[s] = new_part(kind, "flesh")
		P.regrow = false
		dirty = true
		return D.SLOT[s][1]
	return ""

# Picks a part type of the given kind. Rarer tiers are less likely; never plain flesh or a scrap-only part.
func roll_part(pk: String, rare: bool) -> String:
	var pool := []
	for t in D.TYPES[pk]:
		if t == "flesh" or (t in D.QUIRKY_TYPES):
			continue
		var w: int = (D.TIER_W_RARE if rare else D.TIER_W)[D.TYPES[pk][t].t - 1]
		for i in w:
			pool.append(t)
	return pool.pick_random()

# Removes the hand in a slot. A forked arm's second hand moves up to take its place.
func lose_hand(s: String) -> void:
	var arm = P.parts[arm_of(s)]
	P.parts[s] = null
	if arm != null and arm.hand2 != null:
		P.parts[s] = arm.hand2
		arm.hand2 = null
	dirty = true

func drop_hand_item(h: Dictionary, rot := false) -> void:
	var it := {kind = "part", pk = "hand", type = h.type, fingers = h.fingers, maxf = h.maxf}
	if rot:
		it.rot = 25.0
	add_item(it, P.x + randf_range(-2.5, 2.5), P.z + randf_range(-2.5, 2.5))

func lost_part() -> void:
	if has_org("bombheart"):
		explode(P.x, P.z, 4.0, 3)

# Puts a part item onto the body. Returns false (with a message) when it cannot go there.
func attach(it: Dictionary, side: String) -> bool:
	var pk: String = it.pk
	var verb := "Attached"
	var dx: float = P.x + randf_range(-2, 2)
	if pk == "organ":
		if has_org(it.type):
			say("You already have a %s." % part_name(pk, it.type))
			return false
		var s := ""
		for o in D.ORGS:
			if P.parts[o] == null:
				s = o
				break
		if s == "":  # all three slots full: the oldest organ is pushed out
			add_item({kind = "part", pk = "organ", type = P.parts.o1.type}, dx, P.z + 2)
			P.parts.o1 = P.parts.o2
			P.parts.o2 = P.parts.o3
			s = "o3"
			verb = "Swapped in"
		P.parts[s] = {type = it.type}
	elif pk == "hand":
		var s: String = D.SIDE[side].hand
		var arm = P.parts[arm_of(s)]
		if arm == null:
			say("No %s arm to attach a hand to." % side_name(side))
			return false
		if arm.out:
			say("That arm is still in the air.")
			return false
		var nh := new_hand(it.type, it.get("fingers", -1))
		if it.has("maxf"):
			nh.maxf = it.maxf
			nh.fingers = mini(nh.fingers, nh.maxf)
		var cur = P.parts[s]
		if cur != null and arm.type == "forked" and arm.hand2 == null and not (it.type in D.GRIP):
			arm.hand2 = nh
			verb = "Mounted on the fork:"
		else:
			if cur != null:
				if cur.type == "gunhand":
					say("The gun hand is fused on. Only losing it or swapping the arm removes it.")
					return false
				drop_held(s)
				drop_hand_item(cur)
				verb = "Swapped in"
			P.parts[s] = nh
	elif pk == "arm":
		var s: String = D.SIDE[side].arm
		var hs := hand_of(s)
		var cur = P.parts[s]
		var spare = null  # second hand from a forked arm
		if cur != null:
			if cur.out:
				say("That arm is still in the air.")
				return false
			spare = cur.hand2
			add_item({kind = "part", pk = "arm", type = cur.type, hand = null, hand2 = null}, dx, P.z + 2)
			verb = "Swapped in"
		if it.get("hand") != null:  # the new arm brings its own hand
			if P.parts[hs] != null:
				drop_held(hs)
				drop_hand_item(P.parts[hs])
			P.parts[hs] = it.hand
		if it.get("hand2") != null:
			if spare != null:
				drop_hand_item(spare)
			spare = it.hand2
		var na := new_part("arm", it.type)
		if it.type == "forked" and P.parts[hs] != null:
			na.hand2 = spare
		elif spare != null:
			drop_hand_item(spare)
		P.parts[s] = na
	else:
		var s: String = D.SIDE[side][pk]
		var cur = P.parts[s]
		if cur != null:
			verb = "Swapped in"
			if not (pk == "skin" and cur.type == "flesh"):
				add_item({kind = "part", pk = pk, type = cur.type}, dx, P.z + 2)
		P.parts[s] = {type = it.type}
		if pk == "skin":
			P.plate = it.type == "plated"
	P.hp = mini(P.hp, max_hp())
	check_grip()
	var tip: String = D.TYPES[pk][it.type].get("tip", "")
	say("%s %s%s." % [verb, part_name(pk, it.type), (" - " + tip) if tip != "" else ""], 5.0)
	return true

# Status effects on enemies: bleed, burn, acid, stun. Fire and acid together blow up.
func status(e: Dictionary, kind: String, t: float) -> void:
	e[kind] = maxf(e[kind], t)
	if e.burn > 0 and e.acid > 0:
		e.burn = 0.0
		e.acid = 0.0
		explode(e.x, e.z, 3.0, 3)

# What a hand does to an enemy just by touching it (used by the thrown boomerang arm).
func touch(e: Dictionary, h) -> void:
	if h == null:
		return
	match h.type:
		"claw", "chainsaw":
			status(e, "bleed", 3.0)
		"torch":
			status(e, "burn", 3.0)
		"fist", "tentacle", "pincer":
			status(e, "stun", 0.6)
		"syringe":
			feed(2.0)

# Turns an enemy shot into one of yours, flying back the way it came.
func reflect(b: Dictionary) -> void:
	b.mine = true
	b.vx = -b.vx
	b.vz = -b.vz
	b.life = 2.0
	b.hits = []
	if b.m != null:
		b.m.queue_free()
		b.m = null

# How the arm changes what its hand does.
func arm_mod(arm: Dictionary) -> Dictionary:
	var m := {rng = 0.0, dmg = 1.0, kb = 1.0, spread = 0.0}
	match arm.type:
		"robot":
			m.kb = 1.5
		"long":
			m.rng = 0.8
		"noodle":
			m.rng = 2.0
			m.dmg = 0.6
			m.spread = 0.12
	return m

# One hand's action. Returns its cooldown in seconds.
func use_hand(h: Dictionary, s: String, side: String, arm: Dictionary, charge: float) -> float:
	var a: float = P.aim
	var am := arm_mod(arm)
	var m: float = power() * am.dmg * (1.0 + 2.0 * charge)
	var kbm: float = am.kb * (1.0 + charge)
	var rng: float = am.rng
	match h.type:
		"flesh", "skeleton", "baby", "rotting":
			var fast := 0.7 if h.type == "baby" else 1.0
			if h.type == "baby":
				m *= 0.7
			elif h.type == "rotting":
				m *= 3.0
			if h.held == null:
				melee(a, 1.9 + rng, 0.9, 1 * m, 3 * kbm)
				return 0.4 * fast
			var g = D.GUNS[h.held]
			var slow: float = 1.0 + (5 - h.fingers) * 0.15 if h.type in ["flesh", "rotting"] else 1.0
			if g.get("melee", false):
				melee(a, g.range + rng, g.arc, g.dmg * m, 4 * kbm, {sv = 2.0})
				return g.cd * slow * fast
			var gg: Dictionary = g.duplicate()
			gg.dmg = g.dmg * m
			shoot(a, gg, {}, am.spread + (0.1 if h.type == "baby" else 0.0))
			if g.hands == 2:
				P.cdL = g.cd * slow / haste()
				P.cdR = P.cdL
			return g.cd * slow * fast
		"fist":
			melee(a, 2.7 + rng, 0.9, 4 * m, 16 * kbm, {smash = true, c = Color("77ccff")})
			return 0.6
		"claw":
			var hits := melee(a, 2.4 + rng, 1.3, 1.1 * m, 1, {bleed = 3.0, sv = 1.5, c = Color("ff6666")})
			if both("lh", "rh", "claw") and not hits.is_empty():
				P.frenzy = minf(8.0, P.frenzy + 1.0)  # a pair of claws speeds up with every hit
			return 0.17 / (1.0 + 0.1 * P.frenzy)
		"hook":
			hook_shot(a)
			return 1.1
		"cannon":
			shoot(a, {spd = 20.0, dmg = 3.0 * m, spread = am.spread}, {explode = 3.2, big = true})
			return 1.3
		"maw":
			bite(a, 2.2 + rng, 0.8, 3 * m, 2, Color("d9a441"))
			return 0.45
		"chainsaw":
			melee(a, 2.2 + rng, 0.6, 0.7 * m, 0.5, {bleed = 2.0, saw = true, sv = 1.5, c = Color("d0d040")})
			return 0.07
		"tentacle":
			for e in melee(a, 4.5 + rng, 0.5, 1.5 * m, 0, {stun = 0.8, c = Color("b080e0")}):
				e.kx += cos(a) * 22
				e.kz += sin(a) * 22
			return 0.5
		"pincer":
			melee(a, 2.0 + rng, 0.6, 2.5 * m, 2 * kbm, {crit = true, c = Color("e06030")})
			return 0.5
		"shield":
			P["sh" + side] = 0.12
			if P["bash" + side] <= 0:
				P["bash" + side] = 0.8
				melee(a, 1.8 + rng, 1.0, 1 * m, 10 * kbm, {c = Color("7f8fa6")})
			return 0.0
		"syringe":
			for e in melee(a, 2.2 + rng, 0.5, 1.5 * m, 1, {c = Color("9fe0c0")}):
				feed(3.0 if e.bleed > 0 else 1.5)
			return 0.6
		"torch":
			melee(a, 2.3 + rng, 0.9, 0.8 * m, 1, {burn = 3.0, c = Color("ff8a20")})
			return 0.35
		"magnet":
			fx.append({k = "ring", x = P.x, z = P.z, r = 5.0, t = 0.25, life = 0.25, c = Color("d04040")})
			for i in items:
				i.x = P.x + randf_range(-1.5, 1.5)
				i.z = P.z + randf_range(-1.5, 1.5)
				clamp_pos(i)
			for b in bullets:
				if not b.mine and d2(b, P) < 6:
					reflect(b)
			for e in enemies:
				if d2(e, P) < 3 + e.r:
					hit(e, 0.5 * m, atan2(e.z - P.z, e.x - P.x), 8 * kbm)
			return 1.5
		"gunhand":
			var pg2: Dictionary = D.GUNS.pistol.duplicate()
			pg2.dmg *= m
			shoot(a, pg2, {}, am.spread)
			return 0.32
		"grenade":
			shoot(a, {spd = 18.0, dmg = 5.0 * m, spread = am.spread}, {explode = 4.5, big = true})
			if arm.hand2 != null and is_same(arm.hand2, h):
				arm.hand2 = null
			else:
				lose_hand(s)
			dirty = true
			say("You threw your hand. It will not be coming back.")
			return 0.5
	return 0.4

func throw_arm(side: String) -> void:
	var arm = P.parts[D.SIDE[side].arm]
	arm.out = true
	flyers.append({x = P.x, z = P.z, a = P.aim, t = 0.0, side = side, back = false, hits = [], dead = false, m = null})
	dirty = true

# A melee bite that heals 1 HP when it kills. Returns the enemies it hit.
func bite(a: float, rng: float, arc: float, dmg: float, kb: float, c: Color) -> Array:
	var hits := melee(a, rng, arc, dmg, kb, {c = c})
	for e in hits:
		if e.hp <= 0 and P.hp < max_hp():
			P.hp += 1
			say("Swallowed. +1 HP.", 1.5)
			break
	return hits

# F: the jaw's action.
func jaw_act() -> void:
	if over or P.cdJ > 0 or P.dash != null:
		return
	var j = P.parts.jaw
	if j == null:
		if msg_t <= 0:
			say("No jaw!", 1.5)
		return
	var a: float = P.aim
	var m := power()
	P.still = 0.0
	match j.type:
		"flesh":
			melee(a, 1.6, 0.7, 1 * m, 1, {c = Color("f3c4a8")})
			P.cdJ = 0.8
		"shark":
			melee(a, 4.4, 0.5, 4 * m, 6, {c = Color("90a0b0")})
			P.dash = {t = 0.12, dur = 0.12, vx = cos(a) * 28, vz = sin(a) * 28, type = "bite", hits = []}
			P.cdJ = 1.2
		"howler":
			fx.append({k = "ring", x = P.x, z = P.z, r = 7.0, t = 0.3, life = 0.3, c = Color("c0a0e0")})
			for e in enemies:
				if d2(e, P) < 7 + e.r:
					status(e, "stun", 1.5)
			P.cdJ = 4.0
		"spitter":
			shoot(a, {spd = 22.0, dmg = 1.5 * m, spread = 0.04}, {acid = 4.0})
			P.cdJ = 0.55
		"fangs":
			for e in bite(a, 1.9, 0.7, 2 * m, 1, Color("f0f0f0")):
				if e.bleed > 0:
					feed(2.0)
			P.cdJ = 0.6
	P.cdJ /= haste()

# Adds one hand's shape at the end of an arm (x = side offset, z = arm tip).
func add_hand(h: Dictionary, x: float, z: float, show_gun: bool) -> void:
	var c: String = D.TYPES.hand[h.type].c
	match h.type:
		"flesh", "baby", "rotting", "skeleton":
			var s := 0.16 if h.type == "baby" else 0.24
			pg.add_child(box(s, s, 0.1 + 0.04 * h.fingers, "f3c4a8" if h.type == "flesh" else c, x, 1.6, z + 0.1))
		"fist":
			pg.add_child(box(0.5, 0.5, 0.55, c, x, 1.6, z + 0.2))
		"claw":
			pg.add_child(fwd(cone(0.16, 0.8, c, x, 1.6, z + 0.35)))
		"hook":
			pg.add_child(fwd(cone(0.08, 0.7, c, x, 1.6, z + 0.3)))
		"maw":
			pg.add_child(box(0.5, 0.2, 0.6, c, x, 1.45, z + 0.25))
			pg.add_child(box(0.5, 0.2, 0.6, c, x, 1.8, z + 0.25))
			pg.add_child(fwd(cone(0.07, 0.25, "ffffff", x - 0.12, 1.62, z + 0.5)))
			pg.add_child(fwd(cone(0.07, 0.25, "ffffff", x + 0.12, 1.62, z + 0.5)))
		"chainsaw":
			pg.add_child(box(0.14, 0.32, 1.1, c, x, 1.6, z + 0.5))
		"tentacle":
			pg.add_child(fwd(cyl(0.11, 1.4, c, x, 1.6, z + 0.6, 0.03)))
		"pincer":
			pg.add_child(box(0.1, 0.14, 0.6, c, x - 0.13, 1.6, z + 0.3))
			pg.add_child(box(0.1, 0.14, 0.6, c, x + 0.13, 1.6, z + 0.3))
		"shield":
			pg.add_child(box(0.95, 0.95, 0.1, c, x, 1.6, z + 0.2))
		"grenade":
			pg.add_child(ball(0.26, c, x, 1.6, z + 0.2))
		"torch":
			pg.add_child(fwd(cyl(0.07, 0.6, "6b5030", x, 1.6, z + 0.25)))
			pg.add_child(ball(0.17, c, x, 1.6, z + 0.6))
		"gunhand":
			pg.add_child(box(0.2, 0.26, 0.7, c, x, 1.6, z + 0.3))
		_:
			pg.add_child(fwd(cyl(0.2, 0.8, c, x, 1.6, z + 0.25)))
	if h.held != null and show_gun:
		var g = D.GUNS[h.held]
		var is_melee: bool = g.get("melee", false)
		pg.add_child(box(0.12, 0.06 if is_melee else 0.2, g.len, "dddddd" if is_melee else "222222", x, 1.62, z + 0.2 + g.len / 2))

func mk_flyer(_f: Dictionary) -> Node3D:
	return grp([box(0.22, 0.22, 1.2, "c08a3a", 0, 1.4, 0)])

# ---------------- debug room ----------------
# One big empty room with every part, weapon and pickup laid out. Stock comes back when taken.
const DEBUG_ENEMIES := ["grunt", "spitter", "slasher", "leaper", "brute", "mimic"]
const DEBUG_HELP := [
	"DEBUG ROOM",
	"1-6  spawn grunt, spitter, slasher, leaper, brute, mimic",
	"7  spawn elite brute",
	"0  remove all enemies",
	"H  heal        G  god mode",
	"B  reset body  T  restock items and chests",
	"C  count as a cleared room (liver, marrow, rotting hand...)",
]

func start_debug() -> void:
	new_game()
	debug = true
	rooms = []
	var r := make_room("debug")
	r.hw = 30.0
	r.hh = 20.0
	rooms.append(r)
	enter_room(r, "")
	P.x = 0.0
	P.z = 15.0
	stock_debug()
	state = "play"
	menu.close()
	say("Debug room. Everything on the floor comes back when you take it.", 6.0)

func debug_item(d: Dictionary, x: float, z: float) -> void:
	d.stock = true
	d.sx = x
	d.sz = z
	add_item(d, x, z)

func stock_debug() -> void:
	items = prune(items, func(_i): return false)
	chests = prune(chests, func(_c): return false)
	var z := -17.5
	for kinds in [["hand"], ["arm"], ["leg"], ["eye"], ["ear", "jaw"], ["skin"], ["organ"]]:
		var col := 0
		for pk in kinds:
			for t in D.TYPES[pk]:
				if col == 12:
					col = 0
					z += 2.3
				debug_item({kind = "part", pk = pk, type = t}, -24.2 + col * 4.4, z)
				col += 1
		z += 2.3
	var col2 := 0
	for id in D.GUNS:
		debug_item({kind = "weapon", id = id}, -24.2 + col2 * 4.4, z)
		col2 += 1
	for k in ["heart", "finger", "key", "scrap"]:
		debug_item({kind = k}, -24.2 + col2 * 4.4, z)
		col2 += 1
	var cx := 12.0
	for ct in ["normal", "locked", "mimic"]:
		chests.append({x = cx, z = 11.0, type = ct, open = false, gone = false, hp = D.CHEST_HP, flash = 0.0, m = null})
		cx += 5.0

func reset_body() -> void:
	P.parts = {
		le = {type = "flesh"}, re = {type = "flesh"}, lr = {type = "flesh"}, rr = {type = "flesh"},
		jaw = {type = "flesh"}, skin = {type = "flesh"},
		la = new_part("arm", "flesh"), ra = new_part("arm", "flesh"),
		lh = new_hand("flesh"), rh = new_hand("flesh"),
		ll = {type = "flesh"}, rl = {type = "flesh"}, o1 = null, o2 = null, o3 = null,
	}
	P.parts.rh.held = "pistol"
	P.plate = false
	P.hp = max_hp()
	dirty = true

# Returns true when the key was a debug command.
func debug_key(code: int) -> bool:
	var n: int = code - KEY_1
	if n >= 0 and n < DEBUG_ENEMIES.size():
		spawn(DEBUG_ENEMIES[n])
		return true
	match code:
		KEY_7:
			spawn("brute", {elite = true})
		KEY_0:
			enemies = prune(enemies, func(_e): return false)
			bullets = prune(bullets, func(_b): return false)
		KEY_H:
			P.hp = max_hp()
			over = false
		KEY_G:
			god = not god
			say("God mode %s." % ("on" if god else "off"), 2.0)
		KEY_B:
			reset_body()
			say("Body reset.", 2.0)
		KEY_T:
			stock_debug()
			say("Restocked.", 2.0)
		KEY_C:
			room.type = "fight"
			clear_room()
			room.type = "debug"
		_:
			return false
	return true

# ---------------- automated checks (run with: -- --smoke / -- --shot <png>) ----------------
func _shot_setup() -> void:
	floor_n = 2
	var sr: Dictionary = rooms[rooms[0].links.values()[0]]
	sr.type = "fight"
	for style in ["pillars", "corners", "vbars", "hbars", "crates"]:
		if OS.get_cmdline_user_args().has(style):
			for i in 300:
				sr.blocks = []
				gen_layout(sr)
				if sr.style == style:
					break
	enter_room(sr, rooms[0].links.keys()[0])
	chests.append({x = -6.0, z = -4.0, type = "mimic", open = false, gone = false, hp = D.CHEST_HP, flash = 0.0, m = null})
	P.parts.lh = new_hand("fist")
	P.parts.ll = {type = "spring"}
	P.parts.re = null
	P.parts.le = {type = "cyber"}
	if OS.get_cmdline_user_args().has("quirky"):
		P.parts.lh = new_hand("maw")
		P.parts.ll = {type = "crate"}
		P.parts.re = {type = "keyhole"}
		P.scrap = 3
		P.keys = 2
		add_item({kind = "scrap"}, 2, 3)
		add_item({kind = "key"}, -2, 3)
	dirty = true
	spawn("brute")
	spawn("leaper")
	add_item({kind = "part", pk = "hand", type = "claw", fingers = 0}, 3, 8)
	add_item({kind = "weapon", id = "shotgun"}, -4, 7)
	P.inv = 99.0

func _run(n: int) -> void:
	for i in n:
		P.hp = 50
		P.inv = 1.0
		over = false
		if not enemies.is_empty():
			t_aim = Vector2(enemies[0].x, enemies[0].z)
		update(1.0 / 60)
	render()

func _enemy_hp() -> float:
	var s := 0.0
	for e in enemies:
		s += e.hp
	return s

func smoke() -> void:
	t_move = Vector2.ZERO
	t_aim = Vector2.ZERO
	# pistol clears a fight room
	test_room("fight")
	t_rmb = true
	var n0 := enemies.size()
	for i in 900:
		if enemies.is_empty():
			break
		_run(1)
	t_rmb = false
	print("pistol: %d -> %d, cleared %s" % [n0, enemies.size(), room.cleared])
	for t in D.TYPES.hand.keys():
		test_room("fight")
		for et in ["brute", "leaper", "spitter", "slasher"]:
			spawn(et)
		P.parts.lh = new_hand(t)
		dirty = true
		var hp0 := _enemy_hp()
		n0 = enemies.size()
		t_lmb = true
		for i in 240:
			if enemies.is_empty():
				break
			P.x = enemies[0].x
			P.z = enemies[0].z + 2
			clamp_pos(P)
			_run(1)
		t_lmb = false
		print("hand %s: %d -> %d, hp %.0f -> %.1f" % [t, n0, enemies.size(), hp0, _enemy_hp()])
	P.parts.lh = new_hand("flesh")
	P.parts.rh = new_hand("flesh")
	for id in D.GUNS.keys():
		test_room("fight")
		take_item(add_item({kind = "weapon", id = id}, P.x, P.z), "R")
		spawn("grunt")
		n0 = enemies.size()
		t_rmb = true
		for i in 400:
			if enemies.is_empty():
				break
			_run(1)
		t_rmb = false
		print("gun %s: held %s, %d -> %d" % [id, P.parts.rh.held, n0, enemies.size()])
	for t in D.TYPES.leg.keys():
		test_room("fight")
		P.parts.ll = {type = t}
		P.parts.rl = {type = t}
		dirty = true
		P.cdSp = 0.0
		var x0: float = P.x
		var z0: float = P.z
		ability()
		var dashed: bool = P.dash != null
		_run(40)
		print("leg %s: dash %s, moved %.1f" % [t, dashed, Vector2(P.x - x0, P.z - z0).length()])
	P.parts.ll = {type = "flesh"}
	P.parts.rl = {type = "flesh"}
	test_room("dark")
	P.parts.le = null
	_run(5)
	P.parts.re = null
	_run(5)
	P.parts.le = {type = "cyber"}
	P.parts.re = {type = "cat"}
	_run(5)
	print("eyes: ok")
	for t in D.TYPES.organ.keys():
		take_item(add_item({kind = "part", pk = "organ", type = t, fingers = 0}, P.x, P.z), "L")
		_run(5)
		print("organ %s: max hp %d, haste %.1f" % [t, max_hp(), haste()])
	test_room("fight")
	enemies = prune(enemies, func(_e): return false)
	for i in 120:
		sever()
	_run(10)
	var miss := missing()
	for i in items:
		if i.has("rot"):
			i.rot = 0.01
	_run(5)
	print("sever: missing %d, items left %d" % [miss, items.size()])
	for k in D.LIMBS:
		P.parts[k] = null
	dirty = true
	test_room("fight")
	var hand_item = null
	for i in items:
		if i.get("pk") in ["hand", "arm"]:
			hand_item = i
	P.x = hand_item.x
	P.z = hand_item.z
	interact("R")
	_run(5)
	print("reattach: rh %s" % [P.parts.rh])
	test_room("treasure")
	enemies = prune(enemies, func(_e): return false)
	chests = prune(chests, func(_c): return false)
	P.parts.la = new_part("arm", "flesh")
	P.parts.ra = new_part("arm", "flesh")
	P.parts.lh = new_hand("flesh")
	P.parts.rh = new_hand("fist")
	for c in [[0.0, "normal"], [5.0, "locked"], [-5.0, "locked"], [9.0, "mimic"]]:
		chests.append({x = c[0], z = 0.0, type = c[1], open = false, gone = false, hp = D.CHEST_HP, flash = 0.0, m = null})
	render()
	P.z = 1.5
	P.x = 0.0
	interact("L")
	var r1: bool = chests[0].open
	P.x = 5.0
	interact("L")
	var r2: bool = chests[1].open
	var f2: int = P.parts.lh.fingers
	P.x = -5.0
	P.keys = 1
	interact("R")
	var r3: bool = chests[2].open
	P.x = 9.0
	interact("L")
	_run(3)
	print("chests: normal %s | locked+finger %s (fingers %d) | locked+key %s | mimic took lh: %s, enemies %s" % [r1, r2, f2, r3, P.parts.lh == null, enemies.map(func(e): return e.type)])
	test_room("surgeon")
	P.parts.ll = {type = "flesh"}
	P.x = 0.0
	P.z = 0.0
	var ni := items.size()
	interact("L")
	_run(3)
	print("altar: used %s, items +%d" % [altar.used, items.size() - ni])
	# destructible chests, scrap, keys
	new_game()
	test_room("treasure")
	enemies = prune(enemies, func(_e): return false)
	chests = prune(chests, func(_c): return false)
	items = prune(items, func(_i): return false)
	spikes = prune(spikes, func(_s): return false)
	var tc := _test_chest(6.0, "normal")
	for i in 4:
		damage_chest(tc)
	var alive4: bool = not tc.open
	damage_chest(tc)
	_run(2)
	print("chest hits: alive after 4 %s, broken after 5 %s, left behind %s" % [alive4, tc.gone, items.map(func(i): return i.kind)])
	items = prune(items, func(_i): return false)
	var pc := _test_chest(5.0, "normal")
	P.x = 0.0
	P.z = 0.0
	t_aim = Vector2(5, 0)
	var shots := 0
	while not pc.gone and shots < 20:
		P.cdR = 0.0
		P.aim = 0.0
		act("R")
		shots += 1
		_run(30)
	print("pistol shots to destroy a chest: %d" % shots)
	items = prune(items, func(_i): return false)
	var sc := _test_chest(1.5, "normal")
	take_item(add_item({kind = "weapon", id = "shotgun"}, P.x, P.z), "R")
	t_aim = Vector2(1.5, 0)
	P.cdR = 0.0
	P.cdL = 0.0
	P.aim = 0.0
	act("R")
	P.kx = 0.0
	_run(20)
	print("one shotgun blast destroys a chest: %s" % sc.gone)
	items = prune(items, func(_i): return false)
	var mc := _test_chest(6.0, "mimic")
	damage_chest(mc)
	_run(2)
	print("mimic wakes on first hit: %s" % [enemies.map(func(e): return e.type)])
	enemies = prune(enemies, func(_e): return false)
	items = prune(items, func(_i): return false)
	var opened := 0
	var broken := 0
	for i in 200:
		var fc := _test_chest(6.0, "normal")
		smash_chest(fc)
		if fc.gone:
			broken += 1
		else:
			opened += 1
	print("200 fist smashes: opened %d, destroyed %d" % [opened, broken])
	chests = []
	items = []
	var lc := _test_chest(0.0, "locked")
	P.x = 0.0
	P.z = 1.5
	P.keys = 0
	P.parts.lh = new_hand("flesh", 0)
	interact("L")
	var refused: bool = not lc.open
	P.keys = 1
	interact("L")
	print("locked chest: refused without key %s, opened with key %s, keys left %d" % [refused, lc.open, P.keys])
	chests = []
	items = []
	for i in 2000:
		enemy_drop({type = "slasher", elite = false, x = 0.0, z = 0.0})
	var key_n := items.filter(func(i): return i.kind == "key").size()
	items = []
	enemy_drop({type = "brute", elite = true, x = 0.0, z = 0.0})
	print("key drops: %.1f%% over 2000 kills, elite drops key %s" % [key_n / 20.0, items.any(func(i): return i.kind == "key")])
	items = []
	P.scrap = 0
	for i in 4:
		take_item(add_item({kind = "scrap"}, P.x, P.z), "L")
	var q4 := items.filter(func(i): return i.kind == "part").size()
	take_item(add_item({kind = "scrap"}, P.x, P.z), "L")
	var q5 := items.filter(func(i): return i.kind == "part" and i.type in D.QUIRKY_TYPES).size()
	print("scrap: quirky parts after 4 = %d, after 5 = %d, counter %d" % [q4, q5, P.scrap])
	items = []
	for q in D.QUIRKY:
		take_item(add_item({kind = "part", pk = q[0], type = q[1], fingers = 0}, P.x, P.z), "L")
	items = []
	P.hp = 3
	var g1 := spawn("grunt", {x = P.x + 1.2, z = P.z})
	g1.hp = 1.0
	P.aim = 0.0
	P.cdL = 0.0
	act("L")
	var bite_hp: int = P.hp
	P.cdSp = 0.0
	var g2 := spawn("grunt", {x = P.x + 2.0, z = P.z})
	var hp_before: float = g2.hp
	ability()
	var hidden := make_room("dark")
	print("quirky: maw bite heals %s, stomp hits %s, keyhole label '%s', loot never quirky %s" % [bite_hp == 4, g2.hp < hp_before, room_label(hidden), _loot_never_quirky()])
	enemies = []
	items = []
	# floor generation
	var ok := true
	for i in 200:
		room = {}
		gen_floor()
		var types := rooms.map(func(r): return r.type)
		if rooms.size() < 10 or rooms.size() > 15 or types.count("exit") != 1 or types.count("start") != 1 or types.count("treasure") != 2 or not types.has("surgeon"):
			ok = false
		for r in rooms:
			if r.idx != 0 and r.depth == 0:
				ok = false
	print("floor gen x200 valid: %s" % ok)
	# room layouts: every open cell reachable, doors connected, fights still resolve
	var lay_ok := true
	var styles := {}
	for i in 300:
		var r := make_room(["fight", "dark", "treasure", "elite", "exit", "surgeon"].pick_random())
		gen_layout(r)
		styles[r.style] = true
		enter_room(r, "")
		var reach := flood(cell_of(0, 0))
		for c in ff_w * ff_h:
			if solid[c] == 0 and reach[c] == 9999:
				lay_ok = false
		for dv in DIRS.values():
			if reach[cell_of(dv.x * (AW - 1.5), dv.y * (AH - 1.5))] == 9999:
				lay_ok = false
		for o in chests + spikes + enemies:
			if in_block(o.x, o.z, 0.0):
				lay_ok = false
	print("layouts x300 valid: %s, styles %s" % [lay_ok, styles.keys()])
	var stuck := 0
	for i in 12:
		var r := make_room("fight")
		r.depth = 8
		gen_layout(r)
		enter_room(r, ["N", "S", "E", "W"].pick_random())
		for k in 600:  # enemies must path around obstacles to reach a standing player
			_run(1)
		for e in enemies:
			if e.type in ["grunt", "slasher", "brute"] and d2(e, P) > 4:
				stuck += 1
	print("chasers failing to reach player in 12 rooms: %d" % stuck)
	# play through a whole run by the shortest path
	new_game()
	var first_dir := _path_dir()
	var steps := 0
	var back_ok := false
	while not won and steps < 300:
		steps += 1
		enemies = prune(enemies, func(_e): return false)
		_run(2)
		if stairs != null:
			P.x = 0.0
			P.z = 1.0
			interact("R")
			continue
		var dir := _path_dir()
		var d = doors.filter(func(x): return x.dir == dir)[0]
		P.x = d.x
		P.z = d.z
		clamp_pos(P)
		interact("R")
		_run(2)
		if steps == 1:  # walk back through the opened door, then forward again
			enemies = prune(enemies, func(_e): return false)
			_run(2)
			var bd = doors.filter(func(x): return x.dir == OPP[first_dir])[0]
			P.x = bd.x
			P.z = bd.z
			clamp_pos(P)
			t_move = Vector2(DIRS[OPP[first_dir]])
			_run(3)
			t_move = Vector2.ZERO
			back_ok = room.idx == 0
	print("walk back through opened door: %s" % back_ok)
	print("full run: won %s, floor %d, steps %d" % [won, floor_n, steps])
	floor_n = 5
	test_room("elite", 6)
	_run(300)
	test_room("fight", 6)
	_run(300)
	print("late rooms: %s" % [enemies.map(func(e): return e.type)])
	smoke_parts()
	smoke_limbs()
	start_debug()
	var stock := items.size()
	var first: Dictionary = items[0]
	P.x = first.x
	P.z = first.z
	interact("L")
	for code in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7]:
		debug_key(code)
	var spawned := enemies.size()
	_run(120)
	debug_key(KEY_0)
	debug_key(KEY_C)
	debug_key(KEY_B)
	debug_key(KEY_T)
	print("debug room: %d items stocked, %d after taking one, spawned %d enemies, %d after clearing, chests %d" % [stock, items.filter(func(i): return i.get("stock", false)).size(), spawned, enemies.size(), chests.size()])
	print("SMOKE DONE")

func _test_chest(x: float, type: String) -> Dictionary:
	var c := {x = x, z = 0.0, type = type, open = false, gone = false, hp = D.CHEST_HP, flash = 0.0, m = null}
	chests.append(c)
	return c

func _loot_never_quirky() -> bool:
	items = []
	for i in 500:
		loot(0, 0, true)
	var ok := not items.any(func(i): return i.kind == "part" and i.type in D.QUIRKY_TYPES)
	items = []
	return ok

func test_room(type: String, depth := 0) -> void:
	var r := make_room(type)
	r.depth = depth
	enter_room(r, "")

func _path_dir() -> String:
	var q := [[room.idx, ""]]
	var seen := {room.idx: true}
	while not q.is_empty():
		var cur = q.pop_front()
		var r: Dictionary = rooms[cur[0]]
		if r.type == "exit":
			return cur[1]
		for dir in r.links:
			var o: int = r.links[dir]
			if not seen.has(o):
				seen[o] = true
				q.append([o, dir if cur[1] == "" else cur[1]])
	return ""

# Checks for the expanded body: every part, arms, nerfs and the stranger parts.
func smoke_parts() -> void:
	t_move = Vector2.ZERO
	var n := 0
	for pk in D.TYPES:
		for t in D.TYPES[pk]:
			new_game()
			test_room("fight", 4)
			spawn("grunt")
			spawn("spitter")
			take_item(add_item({kind = "part", pk = pk, type = t}, P.x, P.z), "L")
			t_lmb = true
			t_f = true
			_run(20)
			P.cdSp = 0.0
			ability()
			_run(60)
			t_lmb = false
			t_f = false
			P.inv = 0.0
			P.dash = null
			hurt(1, 1.0, enemies[0] if not enemies.is_empty() else null)
			_run(10)
			n += 1
	print("parts: %d types attached, used and hurt without errors" % n)
	# arms carry hands
	new_game()
	test_room("fight")
	enemies = prune(enemies, func(_e): return false)
	items = prune(items, func(_i): return false)
	sever("la")
	var arm_item = items[0]
	var gone: bool = P.parts.la == null and P.parts.lh == null
	take_item(add_item({kind = "part", pk = "hand", type = "claw"}, P.x, P.z), "L")
	var refused: bool = P.parts.lh == null
	take_item(arm_item, "L")
	print("arm: severed with hand %s, hand refused without arm %s, reattached arm %s + hand %s" % [gone, refused, P.parts.la.type, P.parts.lh.type])
	take_item(add_item({kind = "part", pk = "arm", type = "forked"}, P.x, P.z), "L")
	take_item(add_item({kind = "part", pk = "hand", type = "claw"}, P.x, P.z), "L")
	take_item(add_item({kind = "part", pk = "hand", type = "torch"}, P.x, P.z), "L")
	print("forked arm: hand %s, second hand %s, label '%s'" % [P.parts.lh.type, P.parts.la.hand2.type if P.parts.la.hand2 != null else "none", hand_label("lh")])
	take_item(add_item({kind = "part", pk = "arm", type = "boomerang"}, P.x, P.z), "R")
	var far_e := spawn("grunt", {x = P.x + 6.0, z = P.z})
	far_e.hp = 50.0
	far_e.stun = 99.0
	P.aim = 0.0
	t_aim = Vector2(P.x + 6.0, P.z)
	P.cdR = 0.0
	act("R")
	var was_out: bool = P.parts.ra.out
	for i in 200:
		update(1.0 / 60)
	print("boomerang arm: thrown %s, back %s, hit for %.0f" % [was_out, not P.parts.ra.out, 50.0 - far_e.hp])
	# finger economy: a finger paid to a lock never grows back
	new_game()
	test_room("fight")
	enemies = prune(enemies, func(_e): return false)
	items = prune(items, func(_i): return false)
	chests = prune(chests, func(_c): return false)
	var fc := _test_chest(P.x, "locked")
	fc.z = P.z - 1.5
	interact("L")
	var paid: int = P.parts.lh.fingers
	items = prune(items, func(_i): return false)
	P.parts.o1 = {type = "marrow"}
	for i in 3:
		clear_room()
	var after_lock: int = P.parts.lh.fingers
	P.parts.lh.fingers = 2
	clear_room()
	print("fingers: paid lock -> %d, marrow after 3 rooms -> %d (max %d), combat loss regrows 2 -> %d" % [paid, after_lock, P.parts.lh.maxf, P.parts.lh.fingers])
	# chest hunter
	var scraps := 0
	for i in 400:
		items = []
		break_chest(_test_chest(0.0, "normal"), true)
		scraps += items.size()
	chests = []
	items = []
	P.parts.lh = new_hand("pincer")
	P.keys = 0
	var lc := _test_chest(P.x, "locked")
	lc.z = P.z - 1.5
	interact("L")
	print("chest hunter: chainsaw scrap %.0f%%, pincer on a locked chest gives %d item(s)" % [scraps / 4.0, items.size()])
	chests = []
	items = []
	# bomb leg throws you across the room
	test_room("fight")
	enemies = prune(enemies, func(_e): return false)
	P.x = -AW + 2
	P.z = 0.0
	P.parts.ll = {type = "bomb"}
	t_move = Vector2(1, 0)
	P.cdSp = 0.0
	ability()
	t_move = Vector2.ZERO
	var x0: float = P.x
	_run(50)
	print("bomb leg: leg gone %s, thrown %.1f units" % [P.parts.ll == null, P.x - x0])
	# statuses and survival
	var se := spawn("grunt")
	se.hp = 50.0
	status(se, "burn", 3.0)
	status(se, "acid", 3.0)
	print("burn + acid: exploded for %.1f, statuses cleared %s" % [50.0 - se.hp, se.burn == 0.0 and se.acid == 0.0])
	enemies = prune(enemies, func(_e): return false)
	P.parts.o2 = {type = "kidney"}
	P.hp = 1
	P.inv = 0.0
	P.dash = null
	over = false
	hurt(1, 0.0)
	print("kidney: alive %s, hp %d, kidney left %s" % [not over, P.hp, has_org("kidney")])
	P.parts.jaw = null
	P.hp = 3
	take_item(add_item({kind = "heart"}, P.x, P.z), "L")
	print("no jaw: heart refused %s" % (P.hp == 3))
	items = []
	var seen := {}
	var bad := 0
	for i in 4000:
		loot(0, 0, i % 2 == 0)
	for i in items:
		if i.kind == "part":
			seen[i.pk + ":" + i.type] = true
			if i.type == "flesh" or (i.type in D.QUIRKY_TYPES):
				bad += 1
	items = []
	print("loot: %d different parts seen in 4000 rolls, flesh or scrap-only %d" % [seen.size(), bad])

# Checks for enemy dismemberment.
func smoke_limbs() -> void:
	new_game()
	test_room("fight")
	enemies = prune(enemies, func(_e): return false)
	items = prune(items, func(_i): return false)
	room.blocks = []
	t_move = Vector2.ZERO
	P.x = 0.0
	P.z = AH - 2
	var whole := spawn("grunt", {x = -3.0, z = -AH + 2})
	var cut := spawn("grunt", {x = 3.0, z = -AH + 2})
	for e in [whole, cut]:
		e.hp = 500.0
		e.maxhp = 500.0
	sever_enemy(cut)
	var limbs_after_one: int = cut.limbs.size()
	for l in ["ll", "rl"]:
		cut.limbs.erase(l)
	cut.ld = true
	var z0: float = whole.z
	var z1: float = cut.z
	_run(60)
	print("enemy limbs: 4 -> %d after one sever, legless moved %.1f vs whole %.1f" % [limbs_after_one, absf(cut.z - z1), absf(whole.z - z0)])
	var hits := 0
	while not whole.limbs.is_empty() and hits < 500:
		hit(whole, 2.0, null, 0.0, 2.0)
		hits += 1
	var drops := 0
	for i in 300:
		var g := spawn("grunt")
		sever_enemy(g)
	drops = items.size()
	enemies = prune(enemies, func(e): return is_same(e, whole))
	whole.x = P.x
	whole.z = P.z - 0.9
	whole.stun = 0.0
	P.inv = 0.0
	P.hp = 6
	var lost0 := missing()
	for i in 600:
		P.inv = minf(P.inv, 0.0)
		update(1.0 / 60)
		over = false
		P.hp = 6
	print("knife hits to strip a grunt: %d; armless grunt severed %d of your parts in 600 frames; limb drops %d of 300 severs" % [hits, missing() - lost0, drops])
	for t in D.ENEMY:
		test_room("fight")
		enemies = prune(enemies, func(_e): return false)
		var e := spawn(t)
		e.hp = 500.0
		while not e.limbs.is_empty():
			sever_enemy(e)
		_run(120)
	print("every enemy type runs with all limbs gone: ok")
	enemies = prune(enemies, func(_e): return false)
	items = prune(items, func(_i): return false)
