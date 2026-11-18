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
		r.hw = 16.0
		r.hh = 10.0
		style = "open"
	elif r.type == "surgeon":
		r.hw = 16.0
		r.hh = 11.0
		style = ["open", "pillars"].pick_random()
	elif r.type == "exit":
		r.hw = float(D.ROOM_HW[1]) - 2
		r.hh = float(D.ROOM_HH[1]) - 2
		style = "pillars"
	else:
		r.hw = float(randi_range(D.ROOM_HW[0], D.ROOM_HW[1]))
		r.hh = float(randi_range(D.ROOM_HH[0], D.ROOM_HH[1]))
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
			for i in 200:
				if r.blocks.size() >= roundi(randi_range(5, 9) * area_k(r)):
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

# How much bigger a room's floor is than the size the numbers were tuned for (1 = same).
func area_k(r: Dictionary) -> float:
	return maxf(1.0, r.hw * r.hh / (D.ROOM_REF.x * D.ROOM_REF.y))

# Where a room's centre sits in the floor's world (set by place_rooms; rooms made outside a floor sit at 0, 0).
func room_off(r: Dictionary) -> Vector2:
	return Vector2(r.get("ox", 0.0), r.get("oz", 0.0))

# Lays the floor's grid out in the world. Each column is as wide as its widest room and each row as deep
# as its deepest, a random CORRIDOR_MIN-CORRIDOR_MAX apart; a smaller room leans toward its links inside
# its column / row (_lean). Retried until no corridor is longer than CORRIDOR_LONG. Then every link gets a doorway somewhere both rooms' walls overlap (door_at: the door's
# offset along the wall, in each room's own coordinates) and a corridor record in g.corridors.
func place_rooms() -> void:
	var col := {}
	var row := {}
	for r in g.rooms:
		col[r.gx] = maxf(col.get(r.gx, 0.0), r.hw)
		row[r.gy] = maxf(row.get(r.gy, 0.0), r.hh)
	var cx := _centres(col)
	var cz := _centres(row)
	var room_m := D.DOOR_W / 2 + 1.5  # keep doorways this far from a room's corners
	var best := {}
	var best_len := INF
	for tries in 200:
		var jig := tries > 0  # first try: every room centred in its cell, which always has a doorway
		for r in g.rooms:
			r.ox = cx[r.gx] + (_lean(r, "W", "E") * (col[r.gx] - r.hw) if jig else 0.0)
			r.oz = cz[r.gy] + (_lean(r, "N", "S") * (row[r.gy] - r.hh) if jig else 0.0)
		var longest := _longest(room_m)
		if longest < best_len:
			best_len = longest
			for r in g.rooms:
				best[r.idx] = Vector2(r.ox, r.oz)
		if longest <= D.CORRIDOR_LONG:
			break
	for r in g.rooms:  # the try with the shortest longest corridor (some floors cannot keep all under the cap)
		r.ox = best[r.idx].x
		r.oz = best[r.idx].y
	g.corridors = []
	for r in g.rooms:
		r.door_at = {}
		r.corr = {}
	for r in g.rooms:
		for dir in ["E", "S"]:
			if not r.links.has(dir):
				continue
			var o: Dictionary = g.rooms[r.links[dir]]
			var ov := _overlap(r, o, dir, room_m)
			var w := randf_range(ov.x, ov.x + ov.y)  # world coordinate across the corridor
			var ew: bool = dir == "E"
			r.door_at[dir] = w - (r.oz if ew else r.ox)
			o.door_at[Game.OPP[dir]] = w - (o.oz if ew else o.ox)
			var s0: float = (r.ox + r.hw) if ew else (r.oz + r.hh)
			var s1: float = (o.ox - o.hw) if ew else (o.oz - o.hh)
			var c := {a = r.idx, b = o.idx, ew = ew, w = w, s0 = s0, s1 = s1, props = []}
			g.corridors.append(c)
			r.corr[dir] = c
			o.corr[Game.OPP[dir]] = c

# Where a room sits in the spare room of its column (or row), from -1 (lo side) to 1 (hi side):
# toward its only link on that axis, so the corridor is short; anywhere when it links both ways or neither.
func _lean(r: Dictionary, lo: String, hi: String) -> float:
	var l: bool = r.links.has(lo)
	var h: bool = r.links.has(hi)
	if l == h:
		return randf_range(-1, 1)
	return randf_range(0.4, 1.0) * (1.0 if h else -1.0)

# The longest corridor of the current placement, or INF if some link has no room for a doorway.
func _longest(m: float) -> float:
	var out := 0.0
	for a in g.rooms:
		for dir in ["E", "S"]:
			if not a.links.has(dir):
				continue
			var b: Dictionary = g.rooms[a.links[dir]]
			if _overlap(a, b, dir, m).y <= 0:
				return INF
			out = maxf(out, (b.ox - a.ox - a.hw - b.hw) if dir == "E" else (b.oz - a.oz - a.hh - b.hh))
	return out

# Where a doorway between a and its neighbour b (in direction dir) may go, as (start, length) of the
# world coordinate across the corridor; length <= 0 when the two walls do not overlap enough.
func _overlap(a: Dictionary, b: Dictionary, dir: String, m: float) -> Vector2:
	var ew: bool = Game.DIRS[dir].x != 0
	var ac: float = a.oz if ew else a.ox
	var bc: float = b.oz if ew else b.ox
	var ah: float = a.hh if ew else a.hw
	var bh: float = b.hh if ew else b.hw
	var lo := maxf(ac - ah + m, bc - bh + m)
	var hi := minf(ac + ah - m, bc + bh - m)
	return Vector2(lo, hi - lo)

# Centre of each grid line, given the half size of each: neighbours sit half + gap + half apart.
func _centres(half: Dictionary) -> Dictionary:
	var ks := half.keys()
	ks.sort()
	var out := {}
	var at := 0.0
	for i in ks.size():
		if i > 0:
			at += half[ks[i - 1]] + randf_range(D.CORRIDOR_MIN, D.CORRIDOR_MAX) + half[ks[i]]
		out[ks[i]] = at
	return out

# Obstacles that stand in front of a doorway are removed, so every door reaches the room's clear cross.
func clear_door_lanes(r: Dictionary) -> void:
	var keep := []
	for b in r.blocks:
		var hit := false
		for dir in r.links:
			var v: Vector2i = Game.DIRS[dir]
			var at: float = r.door_at[dir]
			var lane := D.DOOR_W / 2 + 1.2
			if v.x != 0:  # strip from the E / W wall to the room's centre line, at z = at
				hit = hit or (absf(b.z - at) < b.h / 2 + lane and b.x * v.x + b.w / 2 > 0)
			else:
				hit = hit or (absf(b.x - at) < b.w / 2 + lane and b.z * v.y + b.h / 2 > 0)
		if not hit:
			keep.append(b)
	r.blocks = keep

# Fills a corridor with breakables (world coordinates): a spot every PROP_STEP along two lanes,
# each filled with chance PROP_FILL, leaving the two ends clear.
func fill_corridor(c: Dictionary) -> void:
	var along: float = c.s0 + 1.6
	while along < c.s1 - 1.6:
		for lane in [-0.9, 0.9]:
			if randf() < D.PROP_FILL:
				var a := along + randf_range(-0.2, 0.2)
				var across: float = c.w + lane + randf_range(-0.15, 0.15)
				c.props.append(_prop(a if c.ew else across, across if c.ew else a))
		along += D.PROP_STEP

func _prop(wx: float, wz: float) -> Dictionary:
	return {type = D.PROPS.keys().pick_random(), broken = false, m = null, wx = wx, wz = wz}

# Clusters of breakables against a room's walls and in its corners (world coordinates in r.props),
# clear of obstacles and doorways. More clusters in bigger rooms.
func fill_room(r: Dictionary) -> void:
	r.props = []
	if r.type == "debug":
		return
	var o := room_off(r)
	var hw: float = r.hw
	var hh: float = r.hh
	var doors := []
	for dir in r.links:
		var v: Vector2i = Game.DIRS[dir]
		var at: float = r.door_at[dir]
		doors.append(Vector2(v.x * hw if v.x != 0 else at, v.y * hh if v.y != 0 else at))
	var placed := []
	for i in roundi(randi_range(D.PROP_CLUSTERS[0], D.PROP_CLUSTERS[1]) * sqrt(area_k(r))):
		var cx := randf_range(-hw + 1, hw - 1)
		var cz := randf_range(-hh + 1, hh - 1)
		match randi() % 4:  # against one of the four walls (corners come up on their own)
			0:
				cz = -hh + 1
			1:
				cz = hh - 1
			2:
				cx = -hw + 1
			3:
				cx = hw - 1
		var want := randi_range(D.PROP_CLUSTER[0], D.PROP_CLUSTER[1])
		var got := 0
		for t in want * 4:
			if got >= want:
				break
			var p := Vector2(clampf(cx + randf_range(-2.5, 2.5), -hw + 0.7, hw - 0.7), clampf(cz + randf_range(-2.5, 2.5), -hh + 0.7, hh - 0.7))
			if doors.any(func(d): return d.distance_to(p) < 4.0) or placed.any(func(q): return q.distance_to(p) < 0.95):
				continue
			if r.blocks.any(func(b): return absf(p.x - b.x) < b.w / 2 + 0.6 and absf(p.y - b.z) < b.h / 2 + 0.6):
				continue
			placed.append(p)
			r.props.append(_prop(o.x + p.x, o.y + p.y))
			got += 1

func floor_color(r: Dictionary) -> Color:
	if r.type == "dark":
		return Color("15151c")
	return Color("2c2430") if r.type == "surgeon" else Color("2a2a36")

# Builds the whole floor at once: every room (floor, walls with doorways, obstacles, doors, fog)
# and the corridors between them. All of it hangs under g.floor_g in world coordinates.
func build_floor() -> void:
	for c in g.floor_g.get_children():
		c.queue_free()
	place_rooms()
	for r in g.rooms:
		clear_door_lanes(r)
		fill_room(r)
		r.erase("geo")
		build_room_geo(r)
	for c in g.corridors:
		fill_corridor(c)
		build_corridor(c)
	g.view.near_g = null  # it was freed with the rest of the floor

func build_room_geo(r: Dictionary) -> void:
	r.geo = true
	var o := room_off(r)
	var hw: float = r.hw
	var hh: float = r.hh
	var wall := "44445a"
	g.floor_g.add_child(Shapes.box(hw * 2, 0.2, hh * 2, floor_color(r), o.x, -0.1, o.y))
	var gap := D.DOOR_W / 2
	for dir in ["N", "S", "E", "W"]:
		var v: Vector2i = Game.DIRS[dir]
		var horiz := v.y != 0  # N / S walls run along x
		var half: float = hw if horiz else hh
		var wx: float = o.x + v.x * (hw + 0.25)
		var wz: float = o.y + v.y * (hh + 0.25)
		var spans := [[-half - 0.5, half + 0.5]]
		if r.links.has(dir):
			var at: float = r.door_at[dir]
			spans = [[-half - 0.5, at - gap], [at + gap, half + 0.5]]
		for sp in spans:
			var ln: float = sp[1] - sp[0]
			var mid: float = (sp[0] + sp[1]) / 2
			if horiz:
				g.floor_g.add_child(Shapes.box(ln, 2, 0.5, wall, o.x + mid, 1, wz))
			else:
				g.floor_g.add_child(Shapes.box(0.5, 2, ln, wall, wx, 1, o.y + mid))
	r.door_m = {}
	for dir in r.links:
		var v: Vector2i = Game.DIRS[dir]
		var horiz := v.y != 0
		var at: float = r.door_at[dir]
		var dm := Shapes.box(D.DOOR_W if horiz else 0.5, 2.6, 0.5 if horiz else D.DOOR_W, "333333",
			o.x + (v.x * (hw + 0.25) if v.x != 0 else at), 1.3, o.y + (v.y * (hh + 0.25) if v.y != 0 else at))
		g.floor_g.add_child(dm)
		r.door_m[dir] = dm
	for b in r.blocks:
		b.m = Shapes.box(b.w, b.ht, b.h, b.c, o.x + b.x, b.ht / 2, o.y + b.z)
		b.m.visible = r.visited
		g.floor_g.add_child(b.m)
	for p in r.get("props", []):
		p.m = g.view.mk_prop(p)
		p.m.position = Vector3(p.wx, 0, p.wz)
		g.floor_g.add_child(p.m)
	var fog := Shapes.box(hw * 2, 2.05, hh * 2, D.FOG, o.x, 1.025, o.y)
	fog.mesh.material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fog.visible = not r.visited
	g.floor_g.add_child(fog)
	r.fog_m = fog

# A straight corridor (floor, two side walls, its breakables) between two doorways.
func build_corridor(c: Dictionary) -> void:
	var ln: float = c.s1 - c.s0
	var mid: float = (c.s0 + c.s1) / 2
	var wall := "44445a"
	var gap := D.DOOR_W / 2 + 0.25
	if c.ew:
		g.floor_g.add_child(Shapes.box(ln, 0.2, D.DOOR_W, "24242e", mid, -0.1, c.w))
		for sd in [-1, 1]:
			g.floor_g.add_child(Shapes.box(ln - 1.0, 2, 0.5, wall, mid, 1, c.w + sd * gap))
	else:
		g.floor_g.add_child(Shapes.box(D.DOOR_W, 0.2, ln, "24242e", c.w, -0.1, mid))
		for sd in [-1, 1]:
			g.floor_g.add_child(Shapes.box(0.5, 2, ln - 1.0, wall, c.w + sd * gap, 1, mid))
	for p in c.props:
		p.m = g.view.mk_prop(p)
		p.m.position = Vector3(p.wx, 0, p.wz)
		g.floor_g.add_child(p.m)

# Distance from room r's inner wall line to the next room's inner wall line through the door in dir.
func corridor_len(r: Dictionary, dir: String) -> float:
	var c: Dictionary = r.corr[dir]
	return c.s1 - c.s0

# Shows a room's obstacles and lifts its fog once it has been visited.
func reveal(r: Dictionary) -> void:
	if r.get("fog_m") != null:
		r.fog_m.visible = false
	for b in r.blocks:
		if b.get("m") != null:
			b.m.visible = true

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
	build_floor()
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
	return g.doors.any(func(d): return Vector2(x - d.x, z - d.z).length() < 5)

func free_spot(mx: float, mz: float) -> Vector2:
	var v := Vector2.ZERO
	for i in 20:
		v = Vector2(randf_range(-g.AW + mx, g.AW - mx), randf_range(-g.AH + mz, g.AH - mz))
		if not near_door(v.x, v.y) and not g.in_block(v.x, v.y, 1.2) and Vector2(v.x - g.P.x, v.y - g.P.z).length() > 5 \
				and not g.props.any(func(p): return Vector2(p.x - v.x, p.z - v.y).length() < 1.6):
			break
	return v

# Makes r the current room. Game logic runs in the current room's own coordinates (its centre is 0, 0);
# the floor's geometry is shifted so the room sits at the origin.
# walked = true: the player came through a corridor, so they keep their place in the world
# (their position and the camera are shifted by the same amount and nothing visibly jumps).
# Otherwise the player is put just inside the wall opposite from_dir (or in the middle).
func enter_room(r: Dictionary, from_dir: String, walked := false) -> void:
	var shift := Vector2.ZERO
	if walked and not g.room.is_empty():
		shift = room_off(g.room) - room_off(r)
	stash_room()
	g.room = r
	g.AW = r.hw
	g.AH = r.hh
	for c in g.room_g.get_children():
		c.queue_free()
	if not r.has("geo"):  # a room made outside a floor (tests): build it on the spot
		build_room_geo(r)
	var o := room_off(r)
	g.floor_g.position = Vector3(-o.x, 0, -o.y)
	g.enemies = []
	g.bullets = []
	g.fx = []
	g.spawn_q = []
	g.fires = []
	g.flyers = []
	for k in ["la", "ra"]:
		if g.P.parts[k] != null:
			g.P.parts[k].out = false
	g.P.plate = g.body.skin_is("plated")
	g.dirty = true
	g.items = r.items
	g.chests = r.chests
	g.spikes = r.spikes
	g.altar = r.altar
	g.stairs = r.stairs
	if walked:
		g.P.x += shift.x
		g.P.z += shift.y
		g.cam_t += shift
	else:
		g.P.frog = 0.0
		g.P.vx = 0.0
		g.P.vz = 0.0
		g.P.x = 0.0
		g.P.z = 3.0
		var at: float = r.get("door_at", {}).get(Game.OPP.get(from_dir, ""), 0.0)  # the doorway we came in by
		match from_dir:  # the direction we walked: arrive at the opposite wall
			"N":
				g.P.x = at
				g.P.z = g.AH - 2.5
			"S":
				g.P.x = at
				g.P.z = -g.AH + 2.5
			"E":
				g.P.x = -g.AW + 2.5
				g.P.z = at
			"W":
				g.P.x = g.AW - 2.5
				g.P.z = at
		g.P.y = 0.0
		g.P.dash = null
		g.P.kx = 0.0
		g.P.kz = 0.0
		g.cam_t = Vector2(g.P.x, g.P.z)
	var dark: bool = r.type == "dark"
	g.ai.build_solid()
	g.env.ambient_light_energy = 0.15 if dark else 0.5
	g.sun.light_energy = 0.25 if dark else 1.0
	g.doors = []
	for dir in r.links:
		var v: Vector2i = Game.DIRS[dir]
		var at: float = r.door_at[dir]
		g.doors.append({x = v.x * g.AW if v.x != 0 else at, z = v.y * g.AH if v.y != 0 else at, at = at,
			dir = dir, to = g.rooms[r.links[dir]], len = corridor_len(r, dir)})
	load_corridors(r)
	if not r.visited:
		r.visited = true
		populate(r)
	reveal(r)
	g.view.show_near()
	if g.enemies.is_empty() and not r.cleared:
		clear_room()
	g.loot.rescue_hand()

# The current room's and its corridors' unbroken breakables go into g.props (in this room's coordinates),
# and loot lying in a corridor that a neighbour room held is handed to this room, so it can be picked up here.
func load_corridors(r: Dictionary) -> void:
	var o := room_off(r)
	g.props = []
	var lists := [r.get("props", [])]
	for dir in r.get("corr", {}):
		lists.append(r.corr[dir].props)
	for list in lists:
		for p in list:
			if not p.broken:
				p.x = p.wx - o.x
				p.z = p.wz - o.y
				g.props.append(p)
	for dir in r.get("corr", {}):
		var c: Dictionary = r.corr[dir]
		var nb: Dictionary = g.rooms[r.links[dir]]
		var no := room_off(nb)
		var keep := []
		for i in nb.items:
			var wx: float = i.x + no.x
			var wz: float = i.z + no.y
			if in_corridor_rect(c, wx, wz):
				i.x = wx - o.x
				i.z = wz - o.y
				i.m = null
				g.items.append(i)
			else:
				keep.append(i)
		nb.items = keep

# Smashes a breakable: a puff of splinters and, sometimes, a small drop (PROP_DROP).
func break_prop(p: Dictionary) -> void:
	if p.broken:
		return
	p.broken = true
	if p.m != null:
		p.m.queue_free()
		p.m = null
	g.fx.append({k = "ring", x = p.x, z = p.z, r = 0.9, t = 0.2, life = 0.2, c = Color(D.PROPS[p.type])})
	var roll := randf()
	for dr in D.PROP_DROP:
		if roll < dr[1]:
			g.add_item({kind = dr[0]}, p.x, p.z)
			break
		roll -= dr[1]
	g.props = g.props.filter(func(o): return not o.broken)

# Whether a world position lies in corridor c (between its two wall lines, within its width).
func in_corridor_rect(c: Dictionary, wx: float, wz: float) -> bool:
	var along := wx if c.ew else wz
	var across := wz if c.ew else wx
	return along > c.s0 + 0.3 and along < c.s1 - 0.3 and absf(across - c.w) < D.DOOR_W / 2

# Walking through a corridor: once the player passes the far room's wall line, that room becomes current.
func check_transit() -> void:
	if not g.enemies.is_empty():
		return
	for d in g.doors:
		if g.room.opened.get(d.dir, false) and past_wall(d) > d.len:
			enter_room(d.to, d.dir, true)
			return

# How far o (the player by default) is beyond the wall that holds door d (negative while inside the room).
func past_wall(d: Dictionary, o = null) -> float:
	if o == null:
		o = g.P
	var v: Vector2i = Game.DIRS[d.dir]
	return (o.x * v.x - g.AW) if v.x != 0 else (o.z * v.y - g.AH)

func populate(r: Dictionary) -> void:
	var type: String = r.type
	var df := diff()
	if type == "start" or type == "debug":
		return
	if type == "surgeon":
		g.altar = {x = 0.0, z = -2.0, used = false, m = null}
		return
	var fill := pow(area_k(r), D.ROOM_FILL)  # bigger rooms hold more enemies, but not in proportion
	var budget := minf(11.0, 1.5 + df) * fill
	if type == "treasure":
		budget = minf(6.0, 0.5 + df * 0.5) * fill
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
		for i in roundi(randi_range(0, 3) * area_k(r)):
			var w := randf_range(2, 4)
			var h := randf_range(2, 4)
			for t in 20:
				var v := free_spot(5, 5)
				if not in_door_lane(v.x, v.y, w, h):
					g.spikes.append({x = v.x, z = v.y, w = w, h = h, m = null})
					break

# Whether a w x h rectangle centred at (x, z) touches the strip of floor in front of one of the
# current room's doors, where the player walks in (DOOR_LANE wide, DOOR_LANE_DEPTH deep).
func in_door_lane(x: float, z: float, w: float, h: float) -> bool:
	var lw: float = D.DOOR_LANE / 2
	var ld: float = D.DOOR_LANE_DEPTH
	for d in g.doors:
		var v: Vector2i = Game.DIRS[d.dir]
		if v.x != 0 and absf(z - d.at) - h / 2 < lw and x * v.x + w / 2 > g.AW - ld:
			return true
		if v.y != 0 and absf(x - d.at) - w / 2 < lw and z * v.y + h / 2 > g.AH - ld:
			return true
	return false

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
	if not g.room.opened.get(d.dir, false):
		g.say("The door swings open.", 1.5)
	g.room.opened[d.dir] = true
	d.to.opened[Game.OPP[d.dir]] = true

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
