extends Control
# Draws either the in-world overlay (labels, effects; world = true)
# or the screen HUD (health, body panel, action bar; world = false).

const D = preload("res://src/data.gd")
var g
var world := false
var font: Font

func _ready() -> void:
	font = ThemeDB.fallback_font

func _process(_dt: float) -> void:
	queue_redraw()

func pr(x: float, y: float, z: float) -> Vector2:
	return g.cam.unproject_position(Vector3(x, y, z))

func text(t: String, pos: Vector2, col: Color = Color.WHITE, size: int = 14, center: bool = false) -> void:
	var p := pos
	if center:
		p.x -= font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x / 2.0
	draw_string(font, p + Vector2(1, 1), t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.7))
	draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func ground_ring(x: float, z: float, r: float, col: Color, width := 3.0) -> void:
	var pts := PackedVector2Array()
	for i in 17:
		var a := TAU * i / 16.0
		pts.append(pr(x + cos(a) * r, 0.2, z + sin(a) * r))
	draw_polyline(pts, col, width)

func _draw() -> void:
	if g == null or g.P.is_empty():
		return
	if world:
		_draw_world()
	else:
		_draw_hud()

func _draw_world() -> void:
	var P = g.P
	for f in g.fires:
		ground_ring(f.x, f.z, 0.9, Color(1.0, 0.45, 0.1, minf(1.0, f.t)), 4.0)
	for f in g.fx:
		var col: Color = f.c
		col.a = f.t / f.life
		if f.k == "line":
			draw_line(pr(f.x, 1.4, f.z), pr(f.x2, 1.4, f.z2), col, 3.0)
			continue
		var a0: float = 0.0 if f.k == "ring" else f.a - f.arc
		var a1: float = TAU if f.k == "ring" else f.a + f.arc
		var r: float = f.r * (1.0 - f.t / f.life * 0.6) if f.k == "ring" else f.r
		var pts := PackedVector2Array()
		for i in 17:
			var a := a0 + (a1 - a0) * i / 16.0
			pts.append(pr(f.x + cos(a) * r, 0.6, f.z + sin(a) * r))
		draw_polyline(pts, col, 3.0)
	var cyber: bool = g.body.has_type(["le", "re"], "cyber")
	if cyber:
		draw_line(pr(P.x, 1.5, P.z), pr(P.x + cos(P.aim) * 30, 1.5, P.z + sin(P.aim) * 30), Color(1, 0.2, 0.33, 0.4), 1.0)
	for e in g.enemies:
		var p := pr(e.x, 3, e.z)
		if cyber:
			draw_rect(Rect2(p.x - 20, p.y, 40, 5), Color.BLACK)
			draw_rect(Rect2(p.x - 20, p.y, 40 * maxf(0.0, e.hp / e.maxhp), 5), Color("ff3355"))
		# status marks: bleed, burn, acid
		var sx := p.x - 12
		for st in [["bleed", "ff3030"], ["burn", "ff9020"], ["acid", "a0e040"]]:
			if e[st[0]] > 0:
				draw_circle(Vector2(sx, p.y - 7), 4, Color(st[1]))
				sx += 12
	for i in g.items:
		var n: String = g.body.item_name(i)
		var col := Color.WHITE
		if i.has("rot"):
			n += " %ds" % ceili(i.rot)
			if i.rot < 8:
				col = Color("ff6666")
		text(n, pr(i.x, 1.6, i.z), col, 13, true)
	var keyhole: bool = g.body.has_type(["le", "re"], "keyhole")
	var cat_ear: bool = g.body.has_type(["lr", "rr"], "cat")
	for c in g.chests:
		if c.open:
			continue
		var dist: float = g.d2(c, P)
		var label := "locked chest" if c.type == "locked" else "chest"
		var col := Color("ffdd88")
		if c.type == "mimic":
			if cyber or (keyhole and dist < D.MIMIC_SENSE.keyhole):
				label = "MIMIC!"
				col = Color("ff3355")
			elif cat_ear and dist < D.MIMIC_SENSE.cat:
				label = "chest... it is growling"
				col = Color("ff9955")
		text(label, pr(c.x, 2, c.z), col, 13, true)
	if g.enemies.is_empty():
		for d in g.doors:
			text(g.world.room_label(d.to), pr(d.x, 4.2, d.z), Color.WHITE, 15, true)
	if g.stairs != null:
		text("Q / E: " + ("escape" if g.floor_n >= g.FLOORS else "descend"), pr(g.stairs.x, 2.5, g.stairs.z), Color("aaddff"), 16, true)
	if g.altar != null and not g.altar.used:
		text("SURGEON - Q: offer left flesh / E: offer right flesh", pr(g.altar.x, 3.2, g.altar.z), Color("ee99ff"), 14, true)
	var near = g.nearest(g.items, g.body.reach())
	if near != null:
		var t := "Q / E: take"
		if near.kind == "part":
			t = "Q / E: attach" if near.pk in ["organ", "jaw", "skin"] else "Q: attach left / E: attach right"
		elif near.kind == "weapon" and D.GUNS[near.id].hands == 1:
			t = "Q: left hand / E: right hand"
		text(t, pr(P.x, 4, P.z), Color("ffff88"), 14, true)

# True when the vision shader is hiding this screen position.
func hidden_at(p: Vector2, center: Vector2, W: float) -> bool:
	if g.vis_radius > 0 and p.distance_to(center) > g.vis_radius * 0.75:
		return true
	if g.vis_side < -0.5 and p.x < W * 0.3:
		return true
	return g.vis_side > 0.5 and p.x > W * 0.7

# Senses that work where the eyes do not: thermal eye, bat ear echo, ears pointing at unseen enemies.
func _draw_senses(W: float) -> void:
	var P = g.P
	var center: Vector2 = pr(P.x, 1.5, P.z)
	var thermal: bool = g.body.has_type(["le", "re"], "thermal")
	var echo: bool = g.body.has_type(["lr", "rr"], "bat") and fmod(g.time, 2.0) < 0.6
	for e in g.enemies:
		var p := pr(e.x, 1.0, e.z)
		if not hidden_at(p, center, W):
			continue
		if thermal or echo:
			draw_circle(p, 9 if thermal else 7, Color(1.0, 0.35, 0.15, 0.85) if thermal else Color(0.7, 0.6, 1.0, 0.8))
			continue
		# an ear only hears its own side
		var rel := angle_difference(P.aim, atan2(e.z - P.z, e.x - P.x))
		if P.parts["rr" if rel > 0 else "lr"] == null:
			continue
		var dirv := (p - center).normalized()
		var tip := center + dirv * 78
		var side := Vector2(-dirv.y, dirv.x)
		draw_colored_polygon(PackedVector2Array([tip, tip - dirv * 16 + side * 8, tip - dirv * 16 - side * 8]), Color(1, 0.3, 0.3, 0.85))
	if g.body.has_type(["lr", "rr"], "radar"):
		for b in g.bullets:
			if not b.mine:
				draw_line(pr(b.x, 1.4, b.z), pr(b.x + b.vx * 0.7, 1.4, b.z + b.vz * 0.7), Color(1, 0.4, 1, 0.6), 2.0)

func _draw_hud() -> void:
	var P = g.P
	var W := size.x
	var H := size.y
	_draw_senses(W)
	text("Floor %d/%d - %s   kills %d" % [g.floor_n, g.FLOORS, D.ROOMS[g.room.type].split(" -")[0], g.kills], Vector2(16, 26), Color("dddddd"), 16)
	text("Keys %d" % P.keys, Vector2(16, 76), Color("ccbb88"), 14)
	_draw_map(Vector2(W - 154, H - 100), 26.0, 18.0, Vector2(140, 84))
	if g.debug:
		draw_rect(Rect2(8, 92, 420, g.debug_room.DEBUG_HELP.size() * 18 + 34), Color(0, 0, 0, 0.75))
		var hy := 112.0
		for line in g.debug_room.DEBUG_HELP:
			text(line, Vector2(16, hy), Color("88ddff") if hy < 113 else Color("aaaaaa"), 13)
			hy += 18
		if g.god:
			text("GOD MODE", Vector2(16, hy + 4), Color("ffdd55"), 14)
	for i in g.body.max_hp():
		var c := Color("ee4444") if i < P.hp else Color(0.3, 0.1, 0.1)
		draw_rect(Rect2(16 + i * 20, 38, 16, 16), c)
	# body panel
	var row := 18.0
	draw_rect(Rect2(W - 300, 8, 292, D.ORDER.size() * row + 14), Color(0, 0, 0, 0.5))
	var y := 28.0
	for s in D.ORDER:
		var p = P.parts[s]
		var kind: String = D.SLOT[s][0]
		text(D.SLOT[s][1], Vector2(W - 290, y), Color("999999"), 13)
		if p == null:
			var optional: bool = kind == "organ"
			text("none" if optional else "MISSING", Vector2(W - 215, y), Color("666666") if optional else Color("ee4444"), 13)
		else:
			var t: String = g.part_name(kind, p.type)
			if kind == "hand":
				if p.type in ["flesh", "baby", "rotting"]:
					t += " %df" % p.fingers
				if p.held != null:
					t += " / " + D.GUNS[p.held].n
					if D.GUNS[p.held].has("mag"):
						t += " %d/%d" % [p.mag, p.res]
				var arm = P.parts[g.body.arm_of(s)]
				if arm != null and arm.hand2 != null:
					t += " + " + g.part_name("hand", arm.hand2.type)
			elif kind == "arm" and p.out:
				t += " (thrown)"
			var col := Color("d8b8a8") if p.type == "flesh" else Color(D.TYPES[kind][p.type].c).lightened(0.25)
			text(t, Vector2(W - 215, y), col, 13)
		y += row
	# action bar
	var bar := [
		["LMB", g.body.hand_label("lh"), maxf(P.rlL, maxf(P.cdL, P.chL))], ["RMB", g.body.hand_label("rh"), maxf(P.rlR, maxf(P.cdR, P.chR))],
		["F", g.body.jaw_label(), P.cdJ], ["SPACE", g.body.space_label(), maxf(P.cdSp, P.frog)],
	]
	for i in 4:
		var x := W / 2 - 330 + i * 165
		var by := H - 48
		draw_rect(Rect2(x, by, 155, 34), Color(0, 0, 0, 0.65))
		if bar[i][2] > 0:
			draw_rect(Rect2(x, by, 155 * minf(1.0, bar[i][2]), 34), Color(1, 1, 1, 0.15))
		text("%s: %s" % [bar[i][0], bar[i][1]], Vector2(x + 77, by + 23), Color("ee4444") if bar[i][1] == "-" else Color.WHITE, 13, true)
	text("WASD move / Q,E use left,right side / F jaw / R reload / Tab body & map", Vector2(16, H - 16), Color("777777"), 13)
	if g.msg_t > 0 and g.msg != "":
		var w := font.get_string_size(g.msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 24
		draw_rect(Rect2(W / 2 - w / 2, H - 98, w, 32), Color(0, 0, 0, 0.7))
		text(g.msg, Vector2(W / 2, H - 76), Color.WHITE, 17, true)
	if g.state == "info":
		_draw_info(W, H)
	if g.over:
		draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.8))
		if g.won:
			var left: int = D.LIMBS.size() - g.body.missing()
			text("You made it out with %d of your %d parts" % [left, D.LIMBS.size()], Vector2(W / 2, H / 2 - 10), Color("aaffaa"), 36, true)
			text("%d kills - press R for another run" % g.kills, Vector2(W / 2, H / 2 + 28), Color.WHITE, 18, true)
		else:
			text("You fell apart on floor %d" % g.floor_n, Vector2(W / 2, H / 2 - 10), Color.WHITE, 36, true)
			text("%d kills - press R to try again" % g.kills, Vector2(W / 2, H / 2 + 28), Color.WHITE, 18, true)

# Splits a text into lines no wider than w pixels.
func wrap_text(t: String, w: float, fs: int) -> Array:
	var out := []
	var line := ""
	for word in t.split(" "):
		var next: String = word if line == "" else line + " " + word
		if line != "" and font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w:
			out.append(line)
			line = word
		else:
			line = next
	out.append(line)
	return out

# Tab screen: the floor map enlarged, and what every attached (or missing) part does.
func _draw_info(W: float, H: float) -> void:
	var P = g.P
	draw_rect(Rect2(0, 0, W, H), Color(0.02, 0.02, 0.04, 0.93))
	var split := W * 0.42
	# map
	text("FLOOR %d of %d" % [g.floor_n, g.FLOORS], Vector2(32, 44), Color.WHITE, 22)
	text("HP %d/%d    keys %d    kills %d" % [P.hp, g.body.max_hp(), P.keys, g.kills], Vector2(32, 68), Color("ccbb88"), 14)
	var half := Vector2(split / 2 - 32, H / 2 - 120)
	_draw_map(Vector2(split / 2 + 8, H / 2), 62.0, 44.0, half)
	var lx := 32.0
	var ly := H / 2 + half.y + 26
	for l in [["you are here", Color.WHITE, true], ["cleared", Color("8a8aa0"), false], ["not cleared", Color("aa4444"), false], ["unvisited", Color("44445a"), false]]:
		draw_rect(Rect2(lx, ly - 11, 16, 12), l[1], not l[2], 2.0 if l[2] else -1.0)
		text(l[0], Vector2(lx + 22, ly), Color("aaaaaa"), 13)
		lx += 40 + font.get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	lx = 32.0
	ly += 22
	for k in ["treasure", "surgeon", "exit"]:
		draw_rect(Rect2(lx, ly - 11, 16, 12), Color(D.DOOR_COLOR[k]))
		text(k, Vector2(lx + 22, ly), Color("aaaaaa"), 13)
		lx += 40 + font.get_string_size(k, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	# body
	var x0 := split + 24
	var tw := W - x0 - 250
	text("YOUR BODY", Vector2(x0, 44), Color.WHITE, 22)
	var rows := []
	var total := 0.0
	for s in D.ORDER:
		var info: Array = g.body.part_info(s)
		var lines: Array = wrap_text(info[1], tw, 13)
		rows.append([s, info, lines])
		total += 6 + 16 * maxi(1, lines.size())
	var y := 76.0
	var gap := clampf((H - 120 - total) / D.ORDER.size(), 0.0, 14.0)  # spread out when there is room
	for r in rows:
		var info: Array = r[1]
		var gone: bool = info[0] == "MISSING"
		text(D.SLOT[r[0]][1], Vector2(x0, y), Color("999999"), 13)
		text(info[0], Vector2(x0 + 62, y), info[2], 13)
		var ty := y
		for line in r[2]:
			text(line, Vector2(x0 + 226, ty), Color("ee8888") if gone else Color("cccccc"), 13)
			ty += 16
		y += 6 + 16 * maxi(1, r[2].size()) + gap
	text("Tab / Esc: close", Vector2(W / 2, H - 18), Color("888899"), 14, true)

# Map of the current floor, centred on the current room. Shows visited rooms and their neighbours.
# cw / chh = size of one room cell, half = half the size of the panel.
func _draw_map(c: Vector2, cw: float, chh: float, half: Vector2) -> void:
	var k := cw / 26.0
	var panel := Rect2(c - half, half * 2)
	draw_rect(panel, Color(0, 0, 0, 0.55))
	var cur = g.room
	if not cur.has("gx") or g.rooms.is_empty():
		return
	for r in g.rooms:
		var known: bool = r.visited
		if not known:
			for dir in r.links:
				if g.rooms[r.links[dir]].visited:
					known = true
		if not known:
			continue
		var p := c + Vector2((r.gx - cur.gx) * cw, (r.gy - cur.gy) * chh)
		var rect := Rect2(p - Vector2(cw / 2 - 2 * k, chh / 2 - 2 * k), Vector2(cw - 4 * k, chh - 4 * k))
		if not panel.encloses(rect):
			continue
		for dir in ["E", "S"]:
			if r.links.has(dir):
				var o = g.rooms[r.links[dir]]
				if r.visited or o.visited:
					var v := Vector2(g.DIRS[dir])
					draw_line(p, p + Vector2(v.x * cw, v.y * chh), Color("777788"), 2.0 * k)
		var col := Color("44445a")
		if r.visited:
			col = Color("8a8aa0") if r.cleared else Color("aa4444")
		if r.type in ["treasure", "surgeon", "exit"] or (not r.visited and g.body.has_type(["le", "re"], "keyhole")):
			col = Color(D.DOOR_COLOR[r.type])
			if not r.visited:
				col = col.darkened(0.35)
		draw_rect(rect, col)
		if r.idx == cur.idx:
			draw_rect(rect.grow(2), Color.WHITE, false, 2.0)
