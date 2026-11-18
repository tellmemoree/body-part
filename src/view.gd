extends RefCounted
# 3D meshes for everything in the room, the player model, the camera and the vision overlay.

const D = preload("res://src/data.gd")
const Game = preload("res://src/game.gd")
const Shapes = preload("res://src/shapes.gd")

var g: Game
var near_g: Node3D  # loot of the rooms next to the current one (show_near)

func _init(game: Game) -> void:
	g = game

func build_player() -> void:
	for c in g.pg.get_children():
		c.queue_free()
	var flesh := "e9a98c"
	var p = g.P.parts
	var sk: String = p.skin.type
	g.pg.add_child(Shapes.box(0.9, 1, 0.5, "3a4a7a" if sk == "flesh" else D.TYPES.skin[sk].c, 0, 1.5, 0))
	if sk == "spiked":
		for sx in [-0.3, 0.0, 0.3]:
			g.pg.add_child(Shapes.cone(0.09, 0.35, "dddddd", sx, 2.1, -0.2))
	g.pg.add_child(Shapes.ball(0.36, flesh, 0, 2.35, 0))
	if p.jaw != null:
		g.pg.add_child(Shapes.box(0.42, 0.14, 0.34, "d99a80" if p.jaw.type == "flesh" else D.TYPES.jaw[p.jaw.type].c, 0, 2.1, 0.14))
	else:
		g.pg.add_child(Shapes.box(0.3, 0.1, 0.2, "661111", 0, 2.1, 0.2))
	for sx in [["lr", 0.37], ["rr", -0.37]]:
		var ear = p[sx[0]]
		if ear != null:
			g.pg.add_child(Shapes.box(0.08, 0.36 if ear.type == "bat" else 0.2, 0.14, flesh if ear.type == "flesh" else D.TYPES.ear[ear.type].c, sx[1], 2.42, 0))
	for sx in [["le", 0.15], ["re", -0.15]]:
		var e = p[sx[0]]
		g.pg.add_child(Shapes.ball(0.09 if e != null else 0.07, D.TYPES.eye[e.type].c if e != null else "330000", sx[1], 2.42, 0.31))
	var two: bool = p.lh != null and p.lh.held != null and D.GUNS[p.lh.held].hands == 2
	for sx in [["la", "lh", 0.62], ["ra", "rh", -0.62]]:
		var arm = p[sx[0]]
		var h = p[sx[1]]
		var x: float = sx[2]
		if arm == null or arm.out:
			g.pg.add_child(Shapes.box(0.24, 0.24, 0.2, "882222", x, 1.7, 0))
			continue
		var ln := 0.9
		if arm.type == "long":
			ln = 1.3
		elif arm.type == "noodle":
			ln = 1.8
		if h == null:
			ln *= 0.55  # no hand: a clearly shorter arm that ends in a raw stump
		g.pg.add_child(Shapes.box(0.14 if arm.type == "noodle" else 0.22, 0.22, ln, flesh if arm.type == "flesh" else D.TYPES.arm[arm.type].c, x, 1.6, ln / 2 - 0.1))
		var tip := ln - 0.1
		if h == null:
			g.pg.add_child(Shapes.box(0.28, 0.28, 0.08, "e01818", x, 1.6, tip))
			continue
		add_hand(h, x, tip, not two, sx[1])
		if arm.hand2 != null:
			add_hand(arm.hand2, x + (0.42 if x > 0 else -0.42), tip - 0.15, false, sx[1] + "2")
	if two:
		var gun = D.GUNS[p.lh.held]
		g.pg.add_child(Shapes.box(0.16, 0.22, gun.len, "222222", 0, 1.6, 0.9 + gun.len / 2))
	for sx in [["ll", 0.24], ["rl", -0.24]]:
		var l = p[sx[0]]
		if l == null:
			continue
		var c: String = D.TYPES.leg[l.type].c
		var x: float = sx[1]
		match l.type:
			"peg", "stilt":
				g.pg.add_child(Shapes.cyl(0.08, 1, c, x, 0.5, 0))
			"spring", "frog":
				g.pg.add_child(Shapes.cyl(0.16, 1, c, x, 0.5, 0))
			"bird", "tentacle":
				g.pg.add_child(Shapes.cyl(0.14, 1, c, x, 0.5, 0, 0.06))
			"crate":
				g.pg.add_child(Shapes.box(0.42, 0.7, 0.42, c, x, 0.35, 0))
				g.pg.add_child(Shapes.box(0.14, 0.4, 0.14, "6b5030", x, 0.85, 0))
			"wheel":
				var w := Shapes.cyl(0.32, 0.14, c, x, 0.32, 0)
				w.rotation.z = PI / 2
				g.pg.add_child(w)
				g.pg.add_child(Shapes.box(0.1, 0.5, 0.1, "555555", x, 0.75, 0))
			"tread":
				g.pg.add_child(Shapes.box(0.34, 0.4, 0.9, c, x, 0.2, 0))
				g.pg.add_child(Shapes.box(0.2, 0.6, 0.2, "555555", x, 0.7, 0))
			"bomb":
				g.pg.add_child(Shapes.ball(0.27, c, x, 0.3, 0))
				g.pg.add_child(Shapes.box(0.12, 0.5, 0.12, "aa3333", x, 0.75, 0))
			_:
				g.pg.add_child(Shapes.box(0.28, 1, 0.28, "2a3350" if l.type == "flesh" else c, x, 0.5, 0))
	var oi := 0
	for o in D.ORGS:
		if p[o] != null:
			g.pg.add_child(Shapes.ball(0.11, D.TYPES.organ[p[o].type].c, 0.24 - oi * 0.24, 1.6, 0.27))
		oi += 1

func mk_enemy(e: Dictionary) -> Node3D:
	var c: String = D.ENEMY[e.type].c
	var skin := "e9a98c"
	var node: Node3D
	match e.type:
		"grunt":
			node = Shapes.grp([
				Shapes.box(1, 1.0, 0.7, c, 0, 1.2, 0), Shapes.ball(0.3, skin, 0, 2.0, 0),
				limb(Shapes.box(0.24, 0.24, 0.9, skin, 0.62, 1.3, 0.35), "la"), limb(Shapes.box(0.24, 0.24, 0.9, skin, -0.62, 1.3, 0.35), "ra"),
				limb(Shapes.box(0.3, 0.7, 0.3, "40304a", 0.25, 0.35, 0), "ll"), limb(Shapes.box(0.3, 0.7, 0.3, "40304a", -0.25, 0.35, 0), "rl"),
			])
		"spitter":
			node = Shapes.grp([Shapes.ball(0.6, c, 0, 0.8, 0), limb(Shapes.ball(0.16, "ff3355", 0, 1.05, 0.5), "eye"), Shapes.cone(0.2, 0.6, c, 0, 1.6, 0)])
		"slasher":
			node = Shapes.grp([
				Shapes.box(0.6, 1.2, 0.5, c, 0, 1.3, 0),
				limb(Shapes.fwd(Shapes.cone(0.14, 0.9, "c0392b", 0.45, 1.3, 0.6)), "la"), limb(Shapes.fwd(Shapes.cone(0.14, 0.9, "c0392b", -0.45, 1.3, 0.6)), "ra"),
				limb(Shapes.box(0.2, 0.7, 0.2, "8a4a20", 0.17, 0.35, 0), "ll"), limb(Shapes.box(0.2, 0.7, 0.2, "8a4a20", -0.17, 0.35, 0), "rl"),
			])
		"leaper":
			node = Shapes.grp([Shapes.ball(0.6, c, 0, 1.1, 0), limb(Shapes.cyl(0.14, 0.9, "6fd36f", 0.3, 0.45, 0), "ll"), limb(Shapes.cyl(0.14, 0.9, "6fd36f", -0.3, 0.45, 0), "rl")])
		"brute":
			node = Shapes.grp([
				Shapes.box(1.9, 1.6, 1.3, c, 0, 1.6, 0), Shapes.ball(0.35, skin, 0, 2.7, 0),
				limb(Shapes.box(0.7, 0.7, 0.8, "5fb4e0", 1.2, 1.5, 0.7), "la"), limb(Shapes.box(0.7, 0.7, 0.8, "5fb4e0", -1.2, 1.5, 0.7), "ra"),
				limb(Shapes.box(0.6, 0.8, 0.6, "3a4660", 0.5, 0.4, 0), "ll"), limb(Shapes.box(0.6, 0.8, 0.6, "3a4660", -0.5, 0.4, 0), "rl"),
			])
		_:
			node = Shapes.grp([Shapes.box(1.5, 0.9, 1.1, c, 0, 0.5, 0), limb(Shapes.cone(0.12, 0.4, "ffffff", 0.4, 1.1, 0.4), "jaw"), limb(Shapes.cone(0.12, 0.4, "ffffff", 0, 1.1, 0.4), "jaw"), limb(Shapes.cone(0.12, 0.4, "ffffff", -0.4, 1.1, 0.4), "jaw")])
	node.set_meta("s", e.r / D.ENEMY[e.type].r)
	e.ld = true
	return node

# Marks a mesh as one of an enemy's limbs, so it disappears when that limb is cut off.
func limb(n: Node3D, name: String) -> Node3D:
	n.set_meta("limb", name)
	return n

func mk_item(i: Dictionary) -> Node3D:
	if i.kind == "heart":
		return Shapes.grp([Shapes.ball(0.3, "ee3344", 0, 0.5, 0)])
	if i.kind == "scrap":
		return Shapes.grp([Shapes.box(0.34, 0.2, 0.3, "8a6a3a", 0, 0.35, 0), Shapes.box(0.2, 0.14, 0.26, "8888a0", 0.12, 0.5, 0.08)])
	if i.kind == "key":
		return Shapes.grp([Shapes.box(0.12, 0.08, 0.55, "ffd24a", 0, 0.5, 0), Shapes.box(0.32, 0.08, 0.26, "ffd24a", 0, 0.5, -0.32)])
	if i.kind == "finger":
		return Shapes.grp([Shapes.box(0.12, 0.12, 0.4, "f3c4a8", 0, 0.4, 0)])
	if i.kind == "weapon":
		var gun = D.GUNS[i.id]
		var is_melee: bool = gun.get("melee", false)
		return Shapes.grp([Shapes.box(0.16, 0.06 if is_melee else 0.24, gun.len + 0.3, "dddddd" if is_melee else "777788", 0, 0.5, 0)])
	var c: String = D.TYPES[i.pk][i.type].c
	match i.pk:
		"eye":
			return Shapes.grp([Shapes.ball(0.22, c, 0, 0.5, 0), Shapes.ball(0.08, "111111", 0, 0.5, 0.19)])
		"organ":
			return Shapes.grp([Shapes.ball(0.3, c, 0, 0.5, 0)])
		"leg":
			return Shapes.grp([Shapes.box(0.26, 0.9, 0.26, c, 0, 0.55, 0)])
		"arm":
			var parts := [Shapes.box(0.22, 0.22, 1.0, c, 0, 0.5, 0)]
			if i.get("hand") != null:
				parts.append(Shapes.box(0.34, 0.34, 0.3, D.TYPES.hand[i.hand.type].c, 0, 0.5, 0.6))
			return Shapes.grp(parts)
		"ear":
			return Shapes.grp([Shapes.box(0.1, 0.34, 0.26, c, 0, 0.5, 0)])
		"jaw":
			return Shapes.grp([Shapes.box(0.5, 0.16, 0.4, c, 0, 0.45, 0), Shapes.cone(0.06, 0.18, "ffffff", 0.15, 0.6, 0.12), Shapes.cone(0.06, 0.18, "ffffff", -0.15, 0.6, 0.12)])
		"skin":
			return Shapes.grp([Shapes.box(0.8, 0.06, 0.6, c, 0, 0.4, 0)])
	return Shapes.grp([Shapes.box(0.24, 0.24, 0.7, c, 0, 0.5, 0), Shapes.box(0.34, 0.34, 0.3, c, 0, 0.5, 0.45)])

func mk_chest(c: Dictionary) -> Node3D:
	var locked: bool = c.type == "locked"
	return Shapes.grp([Shapes.box(1.5, 0.7, 1.1, "777799" if locked else "a9762f", 0, 0.35, 0), Shapes.box(1.6, 0.35, 1.2, "555577" if locked else "8a5a1f", 0, 0.85, 0), Shapes.box(1.3, 0.04, 0.9, "08080a", 0, 0.71, 0)])

func mk_bullet(b: Dictionary) -> Node3D:
	var c := "ff66ff"
	if b.mine:
		c = "ffaa33" if b.big else "ffee66"
	var m := Shapes.ball(0.3 if b.big else 0.14, c, 0, 1.4, 0)
	m.mesh.material.emission_enabled = true
	m.mesh.material.emission = Color(c)
	return Shapes.grp([m])

func mk_spike(s: Dictionary) -> Node3D:
	var node := Shapes.grp([Shapes.box(s.w, 0.06, s.h, "551c1c", 0, 0.03, 0)])
	for i in 8:
		node.add_child(Shapes.cone(0.15, 0.5, "aa3333", randf_range(-s.w / 2 + 0.2, s.w / 2 - 0.2), 0.25, randf_range(-s.h / 2 + 0.2, s.h / 2 - 0.2)))
	return node

func mk_altar() -> Node3D:
	return Shapes.grp([Shapes.box(2.4, 1, 1.4, "8a4a9a", 0, 0.5, 0), Shapes.box(0.2, 1.4, 0.2, "ffffff", 0, 1.7, 0), Shapes.box(0.9, 0.2, 0.2, "ffffff", 0, 1.9, 0)])

func mk_stairs() -> Node3D:
	return Shapes.grp([Shapes.box(3.4, 0.1, 3.4, "050505", 0, 0.05, 0), Shapes.box(3.4, 0.5, 0.8, "8888aa", 0, 0.25, -1.3), Shapes.box(3.4, 0.3, 0.8, "666688", 0, 0.15, -0.5)])

# Chest lid: thrown back with a dark inside once opened.
func set_lid(c: Dictionary) -> void:
	var lid: Node3D = c.m.get_child(1)
	lid.position = Vector3(0, 1.05, -0.75) if c.open else Vector3(0, 0.85, 0)
	lid.rotation.x = 1.25 if c.open else 0.0
	c.m.get_child(2).visible = c.open

# Loads the loot of every visited room next to the current one into the world, so it is there to see
# as you walk up (still meshes, in world coordinates; only the current room's loot is live).
# Rooms further away are unloaded; the map marks what they still hold.
func show_near() -> void:
	if near_g != null and is_instance_valid(near_g):
		near_g.queue_free()
	near_g = Node3D.new()
	g.floor_g.add_child(near_g)
	for dir in g.room.links:
		var r: Dictionary = g.rooms[g.room.links[dir]]
		if not r.visited:
			continue
		var o := g.world.room_off(r)
		var put := func(n: Node3D, x: float, z: float) -> void:
			n.position = Vector3(o.x + x, n.position.y, o.y + z)
			near_g.add_child(n)
		for i in r.items:
			var n := mk_item(i)
			n.position.y = 0.15
			put.call(n, i.x, i.z)
		for c in r.chests:
			var n := mk_chest(c)
			set_lid({m = n, open = c.open})
			put.call(n, c.x, c.z)
		for sp in r.spikes:
			put.call(mk_spike(sp), sp.x, sp.z)
		if r.altar != null and not r.altar.used:
			put.call(mk_altar(), r.altar.x, r.altar.z)
		if r.stairs != null:
			put.call(mk_stairs(), r.stairs.x, r.stairs.z)

# A corridor breakable: clay pot, barrel or small crate.
func mk_prop(p: Dictionary) -> Node3D:
	var c: String = D.PROPS[p.type]
	match p.type:
		"pot":
			return Shapes.grp([Shapes.ball(0.42, c, 0, 0.42, 0), Shapes.cyl(0.2, 0.25, c, 0, 0.9, 0)])
		"barrel":
			return Shapes.grp([Shapes.cyl(0.42, 1.1, c, 0, 0.55, 0), Shapes.cyl(0.44, 0.08, "3a3a3a", 0, 0.3, 0), Shapes.cyl(0.44, 0.08, "3a3a3a", 0, 0.8, 0)])
	return Shapes.grp([Shapes.box(0.8, 0.8, 0.8, c, 0, 0.4, 0)])

func sync(list: Array, mk: Callable) -> void:
	for o in list:
		if o.get("m") == null:
			o.m = mk.call(o)
			g.room_g.add_child(o.m)
		o.m.position = Vector3(o.x, 0, o.z)

func render() -> void:
	if g.dirty:
		build_player()
		g.dirty = false
	sync(g.enemies, mk_enemy)
	sync(g.items, mk_item)
	sync(g.chests, mk_chest)
	sync(g.bullets, mk_bullet)
	sync(g.spikes, mk_spike)
	sync(g.flyers, mk_flyer)
	for f in g.flyers:
		f.m.rotation.y = g.time * 22
	if g.altar != null and g.altar.m == null:
		g.altar.m = mk_altar()
		g.room_g.add_child(g.altar.m)
		g.altar.m.position = Vector3(g.altar.x, 0, g.altar.z)
	for c in g.chests:
		var cs := 1.12 if c.flash > 0 else 1.0
		c.m.scale = Vector3(cs, cs, cs)
		set_lid(c)  # an opened chest: lid thrown back, dark and empty inside
	update_doors()
	if g.stairs != null and g.stairs.m == null:
		g.stairs.m = mk_stairs()
		g.room_g.add_child(g.stairs.m)
		g.stairs.m.position = Vector3(g.stairs.x, 0, g.stairs.z)
	for e in g.enemies:
		var s: float = e.m.get_meta("s") * (1.2 if e.flash > 0 else 1.0)
		e.m.scale = Vector3(s, s * (0.6 if e.st == "wind" else 1.0), s)
		e.m.rotation.y = -e.a + PI / 2 + (g.time * 12 if e.stun > 0 else 0.0)
		if e.ld:
			e.ld = false
			for ch in e.m.get_children():
				if ch.has_meta("limb"):
					ch.visible = e.limbs.has(ch.get_meta("limb"))
			# no legs left: it drags itself along the floor
			e.m.rotation.x = 1.1 if D.ENEMY[e.type].limbs.has("ll") and not (e.limbs.has("ll") or e.limbs.has("rl")) else 0.0
	for i in g.items:
		i.m.rotation.y = g.time * 1.5
		i.m.position.y = 0.15 + sin(g.time * 3 + i.x) * 0.12
	g.pg.position = Vector3(g.P.x, g.P.y, g.P.z)
	g.pg.rotation.y = -g.P.aim + PI / 2
	g.pg.rotation.x = 1.2 if g.body.legs().is_empty() else 0.0
	g.pg.visible = not (g.P.inv > 0 and int(g.time * 20) % 2 == 1)
	update_camera()
	# vision
	var sm: ShaderMaterial = g.vision.material
	g.vis_radius = -1.0
	g.vis_side = 0.0
	if g.body.eyes() == 0:
		g.vis_radius = 150.0
	else:
		if g.room.type == "dark" and not g.body.has_type(["le", "re"], "cat") and not g.body.has_type(["lh", "rh"], "torch"):
			g.vis_radius = 300.0
		if g.body.eyes() == 1:
			g.vis_side = -1.0 if not g.body.sees("le") else 1.0
	sm.set_shader_parameter("center", g.cam.unproject_position(Vector3(g.P.x, 1.5, g.P.z)))
	sm.set_shader_parameter("vsize", g.get_viewport().get_visible_rect().size)
	sm.set_shader_parameter("radius", g.vis_radius)
	sm.set_shader_parameter("side", g.vis_side)

# Doors of every room on the floor. Open ones vanish (the doorway is a gap in the wall).
# Closed doors of the current room: the colour of the room behind them, red while sealed.
func update_doors() -> void:
	for r in g.rooms + ([g.room] if not g.rooms.has(g.room) else []):
		for dir in r.get("door_m", {}):
			var dm: MeshInstance3D = r.door_m[dir]
			dm.visible = not r.opened.get(dir, false)
			if not dm.visible:
				continue
			var to: Dictionary = g.rooms[r.links[dir]]
			var col: String = D.DOOR_COLOR[to.type] if g.world.room_known(to) else D.DOOR_UNKNOWN
			if r != g.room:
				col = "333333"
			elif not g.enemies.is_empty():
				col = "661111"
			dm.mesh.material.albedo_color = Color(col)

# Follows the player. During a fight the view stays inside the room: it only moves as far as it can
# without showing what lies past the walls (a room smaller than the view stays centred).
func update_camera() -> void:
	var far := 1.25 if g.body.has_type(["le", "re"], "sniper") else 1.0  # sniper eye pulls the camera back
	var want := Vector2(g.P.x, g.P.z)
	if not g.enemies.is_empty():
		var ext := view_extent(far)  # ground visible around the look point: x min, x max, z min, z max
		want.x = _fit(want.x, -g.AW - 0.5 - ext[0], g.AW + 0.5 - ext[1])
		want.y = _fit(want.y, -g.AH - 0.5 - ext[2], g.AH + 0.5 - ext[3])
	g.cam_t += (want - g.cam_t) * 0.1
	g.cam.position = Vector3(g.cam_t.x, 30 * far, g.cam_t.y + 19 * far)
	g.cam.look_at(Vector3(g.cam_t.x, 0, g.cam_t.y))

func _fit(v: float, lo: float, hi: float) -> float:
	return (lo + hi) / 2 if lo > hi else clampf(v, lo, hi)

# How much floor the camera shows around the point it looks at, as [x min, x max, z min, z max].
# Found by casting the four screen corners onto the floor from a camera looking at the origin.
func view_extent(far: float) -> Array:
	var sz := g.get_viewport().get_visible_rect().size
	var asp := sz.x / maxf(1.0, sz.y)
	var pos := Vector3(0, 30 * far, 19 * far)
	var fwd := -pos.normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var up := right.cross(fwd)
	var ty := tan(deg_to_rad(g.cam.fov) / 2)
	var ext := [INF, -INF, INF, -INF]
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var ray: Vector3 = (fwd + right * sx * ty * asp + up * sy * ty).normalized()
			var t: float = -pos.y / ray.y
			var hit: Vector3 = pos + ray * t
			ext[0] = minf(ext[0], hit.x)
			ext[1] = maxf(ext[1], hit.x)
			ext[2] = minf(ext[2], hit.z)
			ext[3] = maxf(ext[3], hit.z)
	return ext

# Adds one hand's shape at the end of an arm (x = side offset, z = arm tip).
func add_hand(h: Dictionary, x: float, z: float, show_gun: bool, slot := "") -> void:
	var c: String = D.TYPES.hand[h.type].c
	var first := g.pg.get_child_count()
	match h.type:
		"flesh", "baby", "rotting", "skeleton":
			var s := 0.2 if h.type == "baby" else 0.32  # wider than the arm, so a hand reads as a hand
			g.pg.add_child(Shapes.box(s, s, 0.1 + 0.04 * h.fingers, "f3c4a8" if h.type == "flesh" else c, x, 1.6, z + 0.1))
		"fist":
			g.pg.add_child(Shapes.box(0.5, 0.5, 0.55, c, x, 1.6, z + 0.2))
		"claw":
			g.pg.add_child(Shapes.fwd(Shapes.cone(0.16, 0.8, c, x, 1.6, z + 0.35)))
		"hook":
			g.pg.add_child(Shapes.fwd(Shapes.cone(0.08, 0.7, c, x, 1.6, z + 0.3)))
		"maw":
			g.pg.add_child(Shapes.box(0.5, 0.2, 0.6, c, x, 1.45, z + 0.25))
			g.pg.add_child(Shapes.box(0.5, 0.2, 0.6, c, x, 1.8, z + 0.25))
			g.pg.add_child(Shapes.fwd(Shapes.cone(0.07, 0.25, "ffffff", x - 0.12, 1.62, z + 0.5)))
			g.pg.add_child(Shapes.fwd(Shapes.cone(0.07, 0.25, "ffffff", x + 0.12, 1.62, z + 0.5)))
		"chainsaw":
			g.pg.add_child(Shapes.box(0.14, 0.32, 1.1, c, x, 1.6, z + 0.5))
		"tentacle":
			g.pg.add_child(Shapes.fwd(Shapes.cyl(0.11, 1.4, c, x, 1.6, z + 0.6, 0.03)))
		"pincer":
			g.pg.add_child(Shapes.box(0.1, 0.14, 0.6, c, x - 0.13, 1.6, z + 0.3))
			g.pg.add_child(Shapes.box(0.1, 0.14, 0.6, c, x + 0.13, 1.6, z + 0.3))
		"shield":
			g.pg.add_child(Shapes.box(0.95, 0.95, 0.1, c, x, 1.6, z + 0.2))
		"grenade":
			g.pg.add_child(Shapes.ball(0.26, c, x, 1.6, z + 0.2))
		"torch":
			g.pg.add_child(Shapes.fwd(Shapes.cyl(0.07, 0.6, "6b5030", x, 1.6, z + 0.25)))
			g.pg.add_child(Shapes.ball(0.17, c, x, 1.6, z + 0.6))
		"gunhand":
			g.pg.add_child(Shapes.box(0.2, 0.26, 0.7, c, x, 1.6, z + 0.3))
		_:
			g.pg.add_child(Shapes.fwd(Shapes.cyl(0.2, 0.8, c, x, 1.6, z + 0.25)))
	if h.held != null and show_gun:
		var gun = D.GUNS[h.held]
		var is_melee: bool = gun.get("melee", false)
		g.pg.add_child(Shapes.box(0.12, 0.06 if is_melee else 0.2, gun.len, "dddddd" if is_melee else "222222", x, 1.62, z + 0.2 + gun.len / 2))
	for i in range(first, g.pg.get_child_count()):  # lets the smoke test check that a lost hand is gone from the model
		g.pg.get_child(i).set_meta("hand", slot)

func mk_flyer(_f: Dictionary) -> Node3D:
	return Shapes.grp([Shapes.box(0.22, 0.22, 1.2, "c08a3a", 0, 1.4, 0)])
