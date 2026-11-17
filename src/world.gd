extends RefCounted
# Floors and rooms: floor generation, room layouts, entering rooms, what each room holds,
# clearing rooms, doors and stairs, and hazards on the floor.

const D = preload("res://src/data.gd")
const Game = preload("res://src/game.gd")
const Shapes = preload("res://src/shapes.gd")

var g: Game

func _init(game: Game) -> void:
	g = game

func diff() -> float:
	# difficulty grows with the floor and with distance from the floor's start room
	return 1.0 + (g.floor_n - 1) * 2.5 + g.room.get("depth", 0) * 0.4

func make_room(type: String, gx := 0, gy := 0) -> Dictionary:
	return {
		idx = g.rooms.size(), gx = gx, gy = gy, type = type, links = {}, opened = {}, visited = false, cleared = false, depth = 0,
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
	g.floor_mesh = Shapes.box(g.AW * 2, 0.2, g.AH * 2, floor_col, 0, -0.1, 0)
	g.room_g.add_child(g.floor_mesh)
	g.room_g.add_child(Shapes.box(g.AW * 2 + 1, 2, 0.5, "44445a", 0, 1, -g.AH - 0.25))
	g.room_g.add_child(Shapes.box(g.AW * 2 + 1, 2, 0.5, "44445a", 0, 1, g.AH + 0.25))
	g.room_g.add_child(Shapes.box(0.5, 2, g.AH * 2, "44445a", -g.AW - 0.25, 1, 0))
	g.room_g.add_child(Shapes.box(0.5, 2, g.AH * 2, "44445a", g.AW + 0.25, 1, 0))
	for b in g.room.blocks:
		b.m = Shapes.box(b.w, b.ht, b.h, b.c, b.x, b.ht / 2, b.z)
		g.room_g.add_child(b.m)

func link_rooms(a: Dictionary, b: Dictionary, dir: String) -> void:
	a.links[dir] = b.idx
	b.links[Game.OPP[dir]] = a.idx

func gen_floor() -> void:
	g.rooms = []
	g.keys_left = randi_range(D.KEYS_PER_FLOOR[0], D.KEYS_PER_FLOOR[1])
	var cells := {}
	var n := randi_range(10, 15)
	g.rooms.append(make_room("start"))
	cells[Vector2i.ZERO] = 0
	while g.rooms.size() < n:
		var parent: Dictionary = g.rooms.pick_random()
		var dir: String = Game.DIRS.keys().pick_random()
		var c: Vector2i = Vector2i(parent.gx, parent.gy) + Game.DIRS[dir]
		if cells.has(c):
			continue
		var nb := 0
		for d in Game.DIRS.values():
			if cells.has(c + d):
				nb += 1
		if nb > 1 and randf() < 0.7:
			continue  # keep the map branchy rather than a blob
		var r := make_room("fight", c.x, c.y)
		g.rooms.append(r)
		cells[c] = r.idx
		link_rooms(parent, r, dir)
	for r in g.rooms:  # a few extra links so the map has loops
		for dir in ["E", "S"]:
			var c: Vector2i = Vector2i(r.gx, r.gy) + Game.DIRS[dir]
			if cells.has(c) and not r.links.has(dir) and randf() < 0.15:
				link_rooms(r, g.rooms[cells[c]], dir)
	var queue := [g.rooms[0]]
	var seen := {0: true}
	while not queue.is_empty():
		var r: Dictionary = queue.pop_front()
		for dir in r.links:
			var o: Dictionary = g.rooms[r.links[dir]]
			if not seen.has(o.idx):
				seen[o.idx] = true
				o.depth = r.depth + 1
				queue.append(o)
	var exit_room: Dictionary = g.rooms[1]
	for r in g.rooms:
		if r.idx != 0 and r.depth + (0.5 if r.links.size() == 1 else 0.0) > exit_room.depth + (0.5 if exit_room.links.size() == 1 else 0.0):
			exit_room = r
	exit_room.type = "exit"
	var cands := g.rooms.filter(func(r): return r.type == "fight")
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
			elif roll < 0.25 and g.floor_n >= 2:
				r.type = "elite"
	for r in g.rooms:
		gen_layout(r)

func next_floor() -> void:
	g.floor_n += 1
	g.P.regrow = true  # lizard gland recharges
	g.room = {}
	gen_floor()
	enter_room(g.rooms[0], "")

func stash_room() -> void:
	if g.room.is_empty():
		return
	for list in [g.items, g.chests, g.spikes]:
		for o in list:
			o.m = null
	if g.altar != null:
		g.altar.m = null
	if g.stairs != null:
		g.stairs.m = null
	g.room.items = g.items
	g.room.chests = g.chests
	g.room.spikes = g.spikes
	g.room.altar = g.altar
	g.room.stairs = g.stairs

func near_door(x: float, z: float) -> bool:
	return (absf(x) < 4 and absf(z) > g.AH - 5) or (absf(z) < 4 and absf(x) > g.AW - 5)

func free_spot(mx: float, mz: float) -> Vector2:
	var v := Vector2.ZERO
	for i in 20:
		v = Vector2(randf_range(-g.AW + mx, g.AW - mx), randf_range(-g.AH + mz, g.AH - mz))
		if not near_door(v.x, v.y) and not g.in_block(v.x, v.y, 1.2) and Vector2(v.x - g.P.x, v.y - g.P.z).length() > 5:
			break
	return v

func enter_room(r: Dictionary, from_dir: String) -> void:
	stash_room()
	g.room = r
	g.AW = r.hw
	g.AH = r.hh
	for c in g.room_g.get_children():
		c.queue_free()
	g.enemies = []
	g.bullets = []
	g.fx = []
	g.spawn_q = []
	g.fires = []
	g.flyers = []
	for k in ["la", "ra"]:
		if g.P.parts[k] != null:
			g.P.parts[k].out = false
	g.P.frog = 0.0
	g.P.vx = 0.0
	g.P.vz = 0.0
	g.P.plate = g.body.skin_is("plated")
	g.dirty = true
	g.items = r.items
	g.chests = r.chests
	g.spikes = r.spikes
	g.altar = r.altar
	g.stairs = r.stairs
	g.P.x = 0.0
	g.P.z = 3.0
	match from_dir:  # the direction we walked: arrive at the opposite wall
		"N":
			g.P.z = g.AH - 2.5
		"S":
			g.P.z = -g.AH + 2.5
		"E":
			g.P.x = -g.AW + 2.5
			g.P.z = 0.0
		"W":
			g.P.x = g.AW - 2.5
			g.P.z = 0.0
	g.P.y = 0.0
	g.P.dash = null
	g.P.kx = 0.0
	g.P.kz = 0.0
	var dark: bool = r.type == "dark"
	build_room_mesh(Color("15151c") if dark else (Color("2c2430") if r.type == "surgeon" else Color("2a2a36")))
	g.ai.build_solid()
	g.env.ambient_light_energy = 0.15 if dark else 0.5
	g.sun.light_energy = 0.25 if dark else 1.0
	g.doors = []
	for dir in r.links:
		var v: Vector2i = Game.DIRS[dir]
		g.doors.append({x = v.x * g.AW, z = v.y * g.AH, dir = dir, to = g.rooms[r.links[dir]], m = null})
	if not r.visited:
		r.visited = true
		populate(r)
	if g.enemies.is_empty() and not r.cleared:
		clear_room()
	g.loot.rescue_hand()

func populate(r: Dictionary) -> void:
	var type: String = r.type
	var df := diff()
	if type == "start" or type == "debug":
		return
	if type == "surgeon":
		g.altar = {x = 0.0, z = -2.0, used = false, m = null}
		return
	var budget := minf(11.0, 1.5 + df)
	if type == "treasure":
		budget = minf(6.0, 0.5 + df * 0.5)
	if type == "elite" or type == "exit":
		g.ai.spawn("brute", {elite = true})
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
		g.ai.spawn(pk[0])
		budget -= pk[1]
	var n_ch := 0
	if type == "treasure":
		n_ch = 2
	elif type == "dark" or type == "elite":
		n_ch = 1
	elif type == "fight" and randf() < D.FIGHT_CHEST:
		n_ch = 1
	for i in n_ch:
		var ct := "normal"
		var fi: int = clampi(g.floor_n, 1, D.LOCK_CHANCE.size()) - 1
		if type == "elite" or (type == "dark" and randf() < D.DARK_LOCK[fi]):
			ct = "locked"
		elif df >= 3 and randf() < 0.22:
			ct = "mimic"
		elif randf() < D.LOCK_CHANCE[fi]:
			ct = "locked"
		var v := free_spot(4, 4)
		g.chests.append({x = v.x, z = v.y, type = ct, open = false, gone = false, hp = D.CHEST_HP, flash = 0.0, m = null})
	if df >= 2:
		for i in randi_range(0, 3):
			var v := free_spot(5, 5)
			g.spikes.append({x = v.x, z = v.y, w = randf_range(2, 4), h = randf_range(2, 4), m = null})

func clear_room() -> void:
	g.room.cleared = true
	if g.room.type in ["start", "surgeon", "debug"]:
		return
	var note := ""
	if g.body.has_org("liver") and g.P.hp < g.body.max_hp():
		g.P.hp += 1
	for s in ["lh", "rh"]:
		var h = g.P.parts[s]
		if h != null and h.type == "rotting":
			h.fingers -= 1
			if h.fingers <= 0:
				g.guns.drop_held(s)
				g.body.lose_hand(s)
				note = " Your rotting hand fell apart."
			else:
				note = " Your rotting hand lost a finger."
			g.body.check_grip()
			g.dirty = true
	if g.body.has_org("marrow"):
		for s in ["lh", "rh"]:
			var h = g.P.parts[s]
			if h != null and h.type in ["flesh", "baby"] and h.fingers < h.maxf:
				h.fingers += 1
				note += " A finger grew back."
				g.dirty = true
				break
	if g.body.has_org("lizard") and g.P.regrow:
		var grown := g.body.regrow()
		if grown != "":
			note += " Your %s grew back." % grown
	if g.room.type == "exit":
		g.stairs = {x = 0.0, z = 0.0, m = null}
		g.say(("The guardian is down. The way out is open." if g.floor_n >= Game.FLOORS else "The guardian is down. The stairs are open.") + note)
	else:
		g.say("Room clear. Doors unsealed." + note)
	g.loot.rescue_hand()

func try_door(d: Dictionary) -> void:
	if not g.enemies.is_empty():
		if g.msg_t <= 0:
			g.say("The doors are sealed until the room is clear.", 1.5)
		return
	g.room.opened[d.dir] = true
	d.to.opened[Game.OPP[d.dir]] = true
	g.pending_room = d

func descend() -> void:
	if g.floor_n >= Game.FLOORS:
		g.won = true
		g.over = true
		return
	g.P.hp = mini(g.body.max_hp(), g.P.hp + 1)
	next_floor()
	g.say("Floor %d of %d." % [g.floor_n, Game.FLOORS])

# Whether the player can tell what a room is before entering: decides the door label and colour.
func room_known(r: Dictionary) -> bool:
	return r.visited or r.type in ["treasure", "surgeon", "exit", "start"] or g.body.has_type(["le", "re"], "keyhole")

func room_label(r: Dictionary) -> String:
	return D.ROOMS[r.type] if room_known(r) else "?"

# Spikes underfoot, chest flashes, magnet pull and rotting parts on the floor.
func update_hazards(dt: float) -> void:
	var tread: bool = g.body.has_type(["ll", "rl"], "tread")
	if g.P.dash == null:
		var peg: bool = g.body.has_type(["ll", "rl"], "peg")
		for s in g.spikes:
			if absf(g.P.x - s.x) < s.w / 2 and absf(g.P.z - s.z) < s.h / 2:
				if tread:
					s.gone = true
				elif not peg:
					g.body.hurt(1, 0.2)
	g.spikes = g.prune(g.spikes, func(s): return not s.get("gone", false))
	for c in g.chests:
		c.flash -= dt
	var magnet: bool = g.body.has_type(["lh", "rh"], "magnet")
	for i in g.items:
		if magnet:
			var d := g.d2(i, g.P)
			if d < 6 and d > 1.2:
				i.x += (g.P.x - i.x) / d * 6 * dt
				i.z += (g.P.z - i.z) / d * 6 * dt
		if i.has("rot"):
			i.rot -= dt
			if i.rot <= 0:
				i.dead = true
				g.say("Your %s rotted away." % g.part_name(i.pk, i.type))
	g.items = g.prune(g.items, func(i): return not i.get("dead", false))
