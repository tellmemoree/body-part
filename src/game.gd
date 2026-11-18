extends Node3D
# The game node: all shared state, setup, input, menus and the frame loop.
# Everything else lives in the modules below; each gets this node as `g` and reads and changes
# the state through it. Entities are plain Dictionaries with an "m" field for their mesh.
# See ARCHITECTURE.md.

const D = preload("res://src/data.gd")
const Hud = preload("res://src/hud.gd")
const Menu = preload("res://src/menu.gd")
const Shapes = preload("res://src/shapes.gd")
const World = preload("res://src/world.gd")
const Enemies = preload("res://src/enemies.gd")
const Loot = preload("res://src/loot.gd")
const Body = preload("res://src/body.gd")
const Guns = preload("res://src/guns.gd")
const Combat = preload("res://src/combat.gd")
const Player = preload("res://src/player.gd")
const View = preload("res://src/view.gd")
const DebugRoom = preload("res://src/debug_room.gd")
const Smoke = preload("res://tests/smoke.gd")
const SmokeParts = preload("res://tests/smoke_parts.gd")

const FLOORS := 5
const DIRS := {"N": Vector2i(0, -1), "S": Vector2i(0, 1), "E": Vector2i(1, 0), "W": Vector2i(-1, 0)}
const OPP := {"N": "S", "S": "N", "E": "W", "W": "E"}

# Modules, in roughly the order a frame uses them.
var player := Player.new(self)  # walking, leg abilities, hand and jaw actions, picking things up
var body := Body.new(self)  # parts: queries, losing and attaching them, labels
var guns := Guns.new(self)  # held weapons and ammo
var combat := Combat.new(self)  # hits, bullets, explosions, status effects
var ai := Enemies.new(self)  # enemy spawning, pathfinding, behaviour
var loot := Loot.new(self)  # drops, chests, the surgeon
var world := World.new(self)  # floors, rooms, doors, hazards
var view := View.new(self)  # meshes, camera, vision overlay
var debug_room := DebugRoom.new(self)
var tests := Smoke.new(self)
var tests_parts := SmokeParts.new(self)

# ---------------- state ----------------
var AW := 20.0  # current room half width
var AH := 13.0  # current room half depth

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
var pick = null  # the item Q / E takes when several are in reach (mouse wheel changes it)
var pick_chosen := false  # true once the wheel moved it: then Q / E takes exactly that one
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
var corridors: Array = []  # one per link: {a, b, ew, w, s0, s1, props}, world coordinates (world.place_rooms)
var props: Array = []  # unbroken breakables in the current room's corridors, with local x / z
var solid := PackedByteArray()  # grid of cells blocked by walls, for pathfinding
var ff := PackedInt32Array()  # steps to the player from each cell
var ff_w := 0
var ff_h := 0
var ff_t := 0.0
var stairs = null
var keys_left := 0  # keys this floor will still give out
var won := false
var state := "menu"  # "menu" (main menu), "play", "paused", "info" (Tab screen)
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
var floor_g: Node3D  # the whole floor's rooms and corridors, shifted so the current room is at the origin
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

# ---------------- setup ----------------
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--seed"):  # same seed, same run: used to check that refactors change nothing
		seed(int(args[args.find("--seed") + 1]))
	else:
		randomize()
	_build_world()
	new_game()
	if args.has("--smoke"):
		state = "play"
		tests.smoke()
		get_tree().quit()
	elif args.has("--shot"):
		shot_path = args[args.find("--shot") + 1]
		shot_frames = 30
		state = "play"
		if args.has("debug"):
			debug_room.start_debug()
		else:
			tests._shot_setup()
		if args.has("menu"):
			to_main_menu()
		elif args.has("pause"):
			toggle_pause()
		elif args.has("info"):  # the Tab screen, opened through the real key path
			var ev := InputEventKey.new()
			ev.physical_keycode = KEY_TAB
			ev.pressed = true
			Input.parse_input_event(ev)
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

# Tab: body and map screen. The game stands still while it is open.
func toggle_info() -> void:
	if state == "play" and not over:
		state = "info"
	elif state == "info":
		state = "play"

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
	floor_g = Node3D.new()
	add_child(floor_g)
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
	if ev is InputEventMouseButton and ev.pressed and state == "play" and not over:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			player.cycle_pick(-1)
			return
		if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			player.cycle_pick(1)
			return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.physical_keycode == KEY_ESCAPE:
			if state == "info":
				state = "play"
			else:
				toggle_pause()
			return
		if ev.physical_keycode == KEY_TAB:
			toggle_info()
			return
		if state != "play":
			return
		if debug and debug_room.debug_key(ev.physical_keycode):
			return
		match ev.physical_keycode:
			KEY_Q:
				player.interact("L")
			KEY_E:
				player.interact("R")
			KEY_SPACE:
				player.ability()
			KEY_R:
				if over:
					if debug:
						debug_room.start_debug()
					else:
						new_game()
				else:
					guns.reload_all()

func _process(dt: float) -> void:
	dt = minf(dt, 0.05)
	if state == "play" and not over:
		update(dt)
	view.render()
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
	if (is_same(o, P) or o.has("kind")) and in_corridor(o):  # the player or loot
		return
	o.x = clampf(o.x, -AW + 1, AW - 1)
	o.z = clampf(o.z, -AH + 1, AH - 1)

# The player (once no enemies are left) and loot may be in an open doorway and its corridor.
# Keeps o inside the doorway and corridor it is in and returns true, or returns false when it is in none.
func in_corridor(o) -> bool:
	if is_same(o, P) and not enemies.is_empty():
		return false
	var lane: float = D.DOOR_W / 2 - (0.6 if is_same(o, P) else 0.4)
	for d in doors:
		if not room.opened.get(d.dir, false):
			continue
		var v: Vector2i = DIRS[d.dir]
		var across: float = (o.z if v.x != 0 else o.x) - d.at
		if world.past_wall(d, o) > -1.0 and absf(across) < lane + 0.3:
			across = d.at + clampf(across, -lane, lane)
			if v.x != 0:
				o.z = across
				o.x = clampf(o.x, -AW - d.len - 1, AW + d.len + 1)
			else:
				o.x = across
				o.z = clampf(o.z, -AH - d.len - 1, AH + d.len + 1)
			return true
	return false

# Whether a point is open floor: inside the room or inside an opened doorway's corridor (for bullets).
func in_space(x: float, z: float) -> bool:
	if absf(x) <= AW and absf(z) <= AH:
		return true
	for d in doors:
		if room.opened.get(d.dir, false):
			var v: Vector2i = DIRS[d.dir]
			var across: float = (z if v.x != 0 else x) - d.at
			var past: float = world.past_wall(d, {x = x, z = z})
			if absf(across) < D.DOOR_W / 2 and past > -0.5 and past < d.len:
				return true
	return false

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

# ---------------- run and frame loop ----------------
func new_game() -> void:
	P = {
		x = 0.0, z = AH - 2, y = 0.0, hp = 6, scrap = 0, keys = 0, inv = 0.0, cdL = 0.0, cdR = 0.0, cdSp = 0.0, cdJ = 0.0,
		dash = null, kx = 0.0, kz = 0.0, vx = 0.0, vz = 0.0, aim = -PI / 2,
		chL = 0.0, chR = 0.0, shL = 0.0, shR = 0.0, bashL = 0.0, bashR = 0.0,
		rlL = 0.0, rlR = 0.0, frog = 0.0, still = 0.0, drain = 0.0, frenzy = 0.0, laser = 3.0, plate = false, regrow = true,
		parts = {
			le = {type = "flesh"}, re = {type = "flesh"}, lr = {type = "flesh"}, rr = {type = "flesh"},
			jaw = {type = "flesh"}, skin = {type = "flesh"},
			la = body.new_part("arm", "flesh"), ra = body.new_part("arm", "flesh"),
			lh = body.new_hand("flesh"), rh = body.new_hand("flesh"),
			ll = {type = "flesh"}, rl = {type = "flesh"}, o1 = null, o2 = null, o3 = null,
		},
	}
	guns.give_gun("rh", "pistol")
	floor_n = 0
	debug = false
	god = false
	over = false
	time = 0.0
	kills = 0
	slow_t = 0.0
	dirty = true
	won = false
	room = {}
	world.next_floor()

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
	P.aim = rotate_toward(P.aim, want_aim, 5.0 * dt) if body.has_type(["ll", "rl"], "stilt") else want_aim
	# each step in its own module, in this order
	player.update_movement(dt)
	player.update_hands(dt)
	combat.update_flyers(dt)
	combat.update_bullets(dt)
	ai.update_enemies(dt)
	world.update_hazards(dt)
	chests = prune(chests, func(c): return not c.gone)
	enemies = prune(enemies, func(e): return e.hp > 0, loot.enemy_drop)
	for q in spawn_q:
		ai.spawn("mimic", q)
	spawn_q = []
	for f in fx:
		f.t -= dt
	fx = fx.filter(func(f): return f.t > 0)
	if enemies.is_empty() and not room.cleared:
		world.clear_room()
