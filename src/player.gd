extends RefCounted
# What the player does: walking and leg abilities, hand and jaw actions, picking things up.

const D = preload("res://src/data.gd")
const Game = preload("res://src/game.gd")

var g: Game

func _init(game: Game) -> void:
	g = game

func interact(side: String) -> void:
	if g.over or g.P.is_empty():
		return
	var hs: String = D.SIDE[side].hand
	var hand = g.P.parts[hs]
	# nearest first; something this side cannot use does not block what lies under it
	var near := g.items.filter(func(i): return g.d2(i, g.P) < g.body.reach())
	near.sort_custom(func(a, b): return g.d2(a, g.P) < g.d2(b, g.P))
	if not near.is_empty():
		var why := ""
		for it in near:
			if take_item(it, side):
				return
			if why == "":
				why = g.msg
		g.say(why)
		return
	var closed := g.chests.filter(func(c): return not c.open)
	var ch = g.nearest(closed, 2.8)
	if ch != null:
		if hand == null:
			g.say("No %s hand to open it with." % g.side_name(side))
		else:
			g.loot.open_chest(ch, hs)
		return
	if g.altar != null and not g.altar.used and g.d2(g.altar, g.P) < 3.2:
		g.loot.use_altar(side)
		return
	if g.stairs != null and g.d2(g.stairs, g.P) < 3.2:
		g.world.descend()
		return
	var dr = g.nearest(g.doors, 3.2)
	if dr != null:
		if hand == null:
			g.say("No %s hand for the door. (A robot leg dash can kick it down.)" % g.side_name(side))
		else:
			g.world.try_door(dr)

func take_item(it: Dictionary, side: String) -> bool:
	var hs: String = D.SIDE[side].hand
	var h = g.P.parts[hs]
	if it.kind == "heart":
		if g.P.parts.jaw == null:
			g.say("No jaw to eat it with.")
			return false
		if g.P.hp >= g.body.max_hp():
			g.say("Already at full health.")
			return false
		g.P.hp = mini(g.body.max_hp(), g.P.hp + (4 if g.body.has_org("stomach") else 2))
	elif it.kind == "finger":
		if h == null or not (h.type in ["flesh", "baby"]):
			g.say("Fingers need a flesh hand on that side.")
			return false
		if h.fingers >= h.maxf:
			g.say("That hand cannot take another finger. Try the other side.")
			return false
		h.fingers += 1
		g.say("Finger reattached.")
	elif it.kind == "key":
		g.P.keys += 1
		g.say("Picked up a key.")
	elif it.kind == "scrap":
		g.P.scrap += 1
		if g.P.scrap >= D.SCRAP_NEEDED:
			g.P.scrap = 0
			var q = D.QUIRKY.pick_random()
			g.add_item({kind = "part", pk = q[0], type = q[1]}, g.P.x, g.P.z + 1.5)
			g.say("The scrap knits itself into a %s!" % g.part_name(q[0], q[1]), 5.0)
		else:
			g.say("Picked up scrap.")
	elif it.kind == "weapon":
		var gun = D.GUNS[it.id]
		if gun.hands == 2:
			for k in ["lh", "rh"]:
				var hk = g.P.parts[k]
				if not g.body.can_grip(hk) or not g.body.fingers_ok(hk, gun):
					g.say("The %s needs two gripping hands with %d+ fingers each." % [gun.n, gun.fingers])
					return false
			g.guns.drop_held("lh")
			g.guns.drop_held("rh")
			g.guns.give_gun("lh", it.id, it.get("mag", -1), it.get("res", -1))
		else:
			if h == null:
				g.say("No hand on that side. Try the other key.")
				return false
			if not g.body.can_grip(h):
				g.say("A %s can't hold a weapon." % g.part_name("hand", h.type))
				return false
			if not g.body.fingers_ok(h, gun):
				g.say("The %s needs %d+ fingers." % [gun.n, gun.fingers])
				return false
			g.guns.drop_held(hs)
			g.guns.give_gun(hs, it.id, it.get("mag", -1), it.get("res", -1))
		g.say("Equipped %s." % gun.n)
	elif not g.body.attach(it, side):
		return false
	g.items = g.prune(g.items, func(i): return not is_same(i, it))
	g.dirty = true
	if g.debug and it.get("stock", false):  # debug room stock comes straight back
		var again := it.duplicate()
		again.m = null
		g.add_item(again, it.sx, it.sz)
	return true

func act(side: String, charge := 0.0) -> void:
	var s: String = D.SIDE[side].hand
	var h = g.P.parts[s]
	var arm = g.P.parts[D.SIDE[side].arm]
	var ck := "cdL" if side == "L" else "cdR"
	if h == null:
		if g.msg_t <= 0:
			g.say("No %s %s!" % [g.side_name(side), "arm" if arm == null else "hand"], 1.5)
		return
	if arm.out or g.P[ck] > 0 or g.P.dash != null or g.P["rl" + side] > 0:
		return
	g.P.still = 0.0
	if arm.type == "boomerang":
		throw_arm(side)
		g.P[ck] = 0.4
		return
	var cd := use_hand(h, s, side, arm, charge)
	if arm.hand2 != null:
		cd = maxf(cd, use_hand(arm.hand2, s, side, arm, charge))
	g.P[ck] = maxf(g.P[ck], cd / g.body.haste())

func move_input() -> Vector2:
	if g.t_move != null:
		return g.t_move
	return Vector2(
		(1 if Input.is_physical_key_pressed(KEY_D) else 0) - (1 if Input.is_physical_key_pressed(KEY_A) else 0),
		(1 if Input.is_physical_key_pressed(KEY_S) else 0) - (1 if Input.is_physical_key_pressed(KEY_W) else 0))

func ability() -> void:
	if g.over or g.P.is_empty() or g.P.cdSp > 0 or g.P.dash != null or g.P.frog > 0:
		return
	var L := g.body.legs()
	if L.is_empty():
		g.say("No legs, no dodge.")
		return
	var t := g.body.leg_move()
	if t == "":
		g.say("You cannot roll on one leg." if L.size() == 1 else "These legs cannot dodge.")
		return
	g.P.still = 0.0
	var lung := 0.6 if g.body.has_org("lungs") else 1.0
	if t == "crate":
		g.combat.explode(g.P.x, g.P.z, 4.0, 2)
		g.P.cdSp = 1.4 * lung / g.body.haste()
		return
	if t == "frog":
		g.P.frog = 0.001  # charging; released in update()
		return
	var dir := move_input()
	if dir == Vector2.ZERO:
		dir = Vector2(cos(g.P.aim), sin(g.P.aim))
	dir = dir.normalized()
	var one: float = D.ONE_LEG[t] if L.size() == 1 else 1.0
	var cd := 1.0
	match t:
		"bomb":
			for s in ["ll", "rl"]:
				if g.P.parts[s] != null and g.P.parts[s].type == "bomb":
					g.P.parts[s] = null
					break
			g.combat.explode(g.P.x, g.P.z, 6.0, 6)
			g.dirty = true
			g.say("Your leg went off. So did you.")
			# the blast throws you across the room
			g.P.dash = {t = 0.55, dur = 0.55, vx = dir.x * 42, vz = dir.y * 42, type = "blast", fly = true, h = 4.0, hits = []}
			g.body.lost_part()
		"flesh", "squeaky", "wheel":
			g.P.dash = {t = 0.2, dur = 0.2, vx = dir.x * 24 * one, vz = dir.y * 24 * one, type = "flesh", hits = []}
		"robot":
			var pair := g.body.both("ll", "rl", "robot")
			g.P.dash = {t = 0.22, dur = 0.22, vx = dir.x * 38 * one, vz = dir.y * 38 * one, type = "robot", dmg = 4.0 if pair else 2.0, hits = []}
			cd = 0.6 if pair else 0.9
		"rocket":
			var far := 1.5 if g.body.has_type(["ll", "rl"], "wheel") else 1.0
			g.P.dash = {t = 0.35 * far, dur = 0.35 * far, vx = dir.x * 45 * one, vz = dir.y * 45 * one, type = "rocket", hits = []}
			cd = 1.4
		"bird":
			g.P.dash = {t = 0.9, dur = 0.9, vx = dir.x * 14 * one, vz = dir.y * 14 * one, type = "bird", fly = true, h = 2.4, hits = []}
			cd = 1.6
		"ghost":
			g.P.dash = {t = 0.35, dur = 0.35, vx = dir.x * 30, vz = dir.y * 30, type = "ghost", fly = true, hits = []}
			cd = 2.0
		"rocketleap":
			var far: float = minf(16.0, maxf(4, Vector2(g.aim_pt.x - g.P.x, g.aim_pt.y - g.P.z).length()))
			g.P.dash = {t = 0.6, dur = 0.6, vx = cos(g.P.aim) * far / 0.6, vz = sin(g.P.aim) * far / 0.6, type = "rocketleap", fly = true, h = 4.5, boom = [5.0, 4.0], hits = []}
			cd = 1.8
		_:  # spring
			var dist: float = minf(11 * one, maxf(3, Vector2(g.aim_pt.x - g.P.x, g.aim_pt.y - g.P.z).length()))
			g.P.dash = {t = 0.5, dur = 0.5, vx = cos(g.P.aim) * dist / 0.5, vz = sin(g.P.aim) * dist / 0.5, type = "spring", fly = true, h = 3.2, boom = [3.6, 2.0], hits = []}
			cd = 1.5
	g.P.cdSp = cd * lung / g.body.haste()

# Walking, dashes and leg abilities, knockback, treads, walking through open doors.
func update_movement(dt: float) -> void:
	var L := g.body.legs()
	var dir := move_input()
	if dir != Vector2.ZERO:
		dir = dir.normalized()
	if g.P.dash != null:
		var Dh = g.P.dash
		g.P.x += Dh.vx * dt
		g.P.z += Dh.vz * dt
		Dh.t -= dt
		g.P.y = sin(PI * (1 - Dh.t / Dh.dur)) * Dh.get("h", 0.0)
		if Dh.type == "robot":
			for e in g.enemies:
				if not Dh.hits.has(e) and g.d2(e, g.P) < e.r + 1.3:
					Dh.hits.append(e)
					g.combat.hit(e, Dh.dmg, atan2(Dh.vz, Dh.vx), 14)
			for c in g.chests:
				if not c.open and g.d2(c, g.P) < 1.8:
					g.loot.smash_chest(c)
			for d in g.doors:
				if g.d2(d, g.P) < 2.4:
					g.world.try_door(d)
		elif Dh.type == "rocket":
			if g.fires.is_empty() or g.d2(g.fires[-1], g.P) > 1.0:
				g.fires.append({x = g.P.x, z = g.P.z, t = 3.0})
		if Dh.t <= 0:
			g.P.dash = null
			g.P.y = 0.0
			g.P.inv = maxf(g.P.inv, 0.15)
			g.P.vx = 0.0
			g.P.vz = 0.0
			if Dh.has("boom"):
				g.combat.explode(g.P.x, g.P.z, Dh.boom[0], Dh.boom[1])
	else:
		if g.P.frog > 0:
			if g.t_space or Input.is_physical_key_pressed(KEY_SPACE):
				g.P.frog = minf(1.0, g.P.frog + dt)
			else:  # released: the longer the charge, the further the hop
				var c: float = g.P.frog
				g.P.frog = 0.0
				var dist := (4.0 + 10.0 * c) * (D.ONE_LEG.frog if L.size() == 1 else 1.0)
				g.P.dash = {t = 0.45, dur = 0.45, vx = cos(g.P.aim) * dist / 0.45, vz = sin(g.P.aim) * dist / 0.45, type = "frog", fly = true, h = 2.0 + 2.0 * c, boom = [2.5 + 1.5 * c, 1.0 + 2.0 * c], hits = []}
				g.P.cdSp = (0.6 if g.body.has_org("lungs") else 1.0) / g.body.haste()
		var sp := 9.0 * g.body.haste()
		var hopping: bool = L.size() == 1 and L[0].type != "tentacle"
		if hopping:
			sp *= 0.15 + 0.75 * absf(sin(g.time * 7))
		elif L.is_empty():
			sp *= 0.22
		for l in L:
			sp *= D.LEG_SPD.get(l.type, 1.0)
		if g.P.shL > 0 or g.P.shR > 0:
			sp *= 0.6
		if g.P.frog > 0:
			sp *= 0.4
		if g.body.has_type(["ll", "rl"], "wheel"):  # wheels keep rolling
			var k := 1.0 - exp(-2.5 * dt)
			g.P.vx += (dir.x * sp - g.P.vx) * k
			g.P.vz += (dir.y * sp - g.P.vz) * k
		else:
			g.P.vx = dir.x * sp
			g.P.vz = dir.y * sp
		g.P.x += g.P.vx * dt
		g.P.z += g.P.vz * dt
		g.P.y = absf(sin(g.time * 7)) * 0.5 if hopping else 0.0
		g.P.still = g.P.still + dt if dir == Vector2.ZERO else 0.0
	g.P.x += g.P.kx * dt
	g.P.z += g.P.kz * dt
	var dec := exp(-8 * dt)
	g.P.kx *= dec
	g.P.kz *= dec
	var tread: bool = g.body.has_type(["ll", "rl"], "tread")
	if tread and g.P.dash == null:  # treads flatten crates
		for b in g.room.blocks.duplicate():
			if b.ht < 2 and absf(g.P.x - b.x) < b.w / 2 + 0.75 and absf(g.P.z - b.z) < b.h / 2 + 0.75:
				if b.get("m") != null:
					b.m.queue_free()
				g.room.blocks.erase(b)
				g.ai.build_solid()
				g.fx.append({k = "ring", x = b.x, z = b.z, r = 1.5, t = 0.2, life = 0.2, c = Color("a9762f")})
	g.clamp_pos(g.P)
	if g.enemies.is_empty() and not g.debug:
		g.loot.rescue_hand()  # no hands outside a fight (grenade, rot, trap): never leave the player stuck
	if g.P.dash == null and g.enemies.is_empty() and g.pending_room == null:
		for d in g.doors:  # opened doors can simply be walked through
			if g.room.opened.get(d.dir, false) and g.d2(d, g.P) < 1.7 and dir.dot(Vector2(Game.DIRS[d.dir])) > 0.5:
				g.pending_room = d

# Held clicks (with piston charge), reload timers, jaw, laser eye.
func update_hands(dt: float) -> void:
	for side in ["L", "R"]:
		if g.P["rl" + side] > 0:
			g.P["rl" + side] -= dt
			if g.P["rl" + side] <= 0:
				g.guns.finish_reload(D.SIDE[side].hand)
		var down: bool = g.t_lmb or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if side == "R":
			down = g.t_rmb or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		var arm = g.P.parts[D.SIDE[side].arm]
		var ck: String = "ch" + side
		if piston_charges(side):  # hold to charge, release to hit
			if down:
				g.P[ck] = minf(1.0, g.P[ck] + dt)
			elif g.P[ck] > 0:
				act(side, g.P[ck])
				g.P[ck] = 0.0
		else:
			g.P[ck] = 0.0
			if down:
				act(side)
	if g.t_f or Input.is_physical_key_pressed(KEY_F):
		jaw_act()
	if g.P.laser <= 0 and g.body.has_type(["le", "re"], "laser") and not g.enemies.is_empty():
		g.P.laser = 3.0
		var lx := cos(g.P.aim)
		var lz := sin(g.P.aim)
		g.fx.append({k = "line", x = g.P.x, z = g.P.z, x2 = g.P.x + lx * 40, z2 = g.P.z + lz * 40, t = 0.25, life = 0.25, c = Color("ff2020")})
		for e in g.enemies:
			var along: float = (e.x - g.P.x) * lx + (e.z - g.P.z) * lz
			var off: float = absf((e.x - g.P.x) * lz - (e.z - g.P.z) * lx)
			if along > 0 and off < e.r + 0.4:
				g.combat.hit(e, 2 * g.body.power(), g.P.aim, 2)

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

# A piston arm charges punches and swings. A gun in that hand fires normally while held down.
func piston_charges(side: String) -> bool:
	var arm = g.P.parts[D.SIDE[side].arm]
	if arm == null or arm.type != "piston":
		return false
	var h = g.P.parts[D.SIDE[side].hand]
	if h == null:
		return true
	if h.type == "gunhand":
		return false
	return h.get("held") == null or D.GUNS[h.held].get("melee", false)

# One hand's action. Returns its cooldown in seconds.
func use_hand(h: Dictionary, s: String, side: String, arm: Dictionary, charge: float) -> float:
	var a: float = g.P.aim
	var am := arm_mod(arm)
	var m: float = g.body.power() * am.dmg * (1.0 + 2.0 * charge)
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
				g.combat.melee(a, 1.9 + rng, 0.9, 1 * m, 3 * kbm)
				return 0.4 * fast
			var gun = D.GUNS[h.held]
			var slow := g.guns.finger_slow(h)
			if gun.get("melee", false):
				g.combat.melee(a, gun.range + rng, gun.arc, gun.dmg * m, 4 * kbm, {sv = 2.0})
				return gun.cd * slow * fast
			if h.mag <= 0:  # only happens if a reload was interrupted
				g.guns.start_reload(s)
				return 0.1
			var gg: Dictionary = gun.duplicate()
			gg.dmg = gun.dmg * m
			g.combat.shoot(a, gg, {}, am.spread + (0.1 if h.type == "baby" else 0.0))
			g.guns.spend_shot(s)
			if gun.hands == 2:
				g.P.cdL = gun.cd * slow / g.body.haste()
				g.P.cdR = g.P.cdL
			return gun.cd * slow * fast
		"fist":
			g.combat.melee(a, 2.7 + rng, 0.9, 4 * m, 16 * kbm, {smash = true, c = Color("77ccff")})
			return 0.6
		"claw":
			var hits := g.combat.melee(a, 2.4 + rng, 1.3, 1.1 * m, 1, {bleed = 3.0, sv = 1.5, c = Color("ff6666")})
			if g.body.both("lh", "rh", "claw") and not hits.is_empty():
				g.P.frenzy = minf(8.0, g.P.frenzy + 1.0)  # a pair of claws speeds up with every hit
			return 0.17 / (1.0 + 0.1 * g.P.frenzy)
		"hook":
			g.combat.hook_shot(a)
			return 1.1
		"cannon":
			g.combat.shoot(a, {spd = 20.0, dmg = 3.0 * m, spread = am.spread}, {explode = 3.2, big = true})
			return 1.3
		"maw":
			g.combat.bite(a, 2.2 + rng, 0.8, 3 * m, 2, Color("d9a441"))
			return 0.45
		"chainsaw":
			g.combat.melee(a, 2.2 + rng, 0.6, 0.7 * m, 0.5, {bleed = 2.0, saw = true, sv = 1.5, c = Color("d0d040")})
			return 0.07
		"tentacle":
			for e in g.combat.melee(a, 4.5 + rng, 0.5, 1.5 * m, 0, {stun = 0.8, c = Color("b080e0")}):
				e.kx += cos(a) * 22
				e.kz += sin(a) * 22
			return 0.5
		"pincer":
			g.combat.melee(a, 2.0 + rng, 0.6, 2.5 * m, 2 * kbm, {crit = true, c = Color("e06030")})
			return 0.5
		"shield":
			g.P["sh" + side] = 0.12
			if g.P["bash" + side] <= 0:
				g.P["bash" + side] = 0.8
				g.combat.melee(a, 1.8 + rng, 1.0, 1 * m, 10 * kbm, {c = Color("7f8fa6")})
			return 0.0
		"syringe":
			for e in g.combat.melee(a, 2.2 + rng, 0.5, 1.5 * m, 1, {c = Color("9fe0c0")}):
				g.body.feed(3.0 if e.bleed > 0 else 1.5)
			return 0.6
		"torch":
			g.combat.melee(a, 2.3 + rng, 0.9, 0.8 * m, 1, {burn = 3.0, c = Color("ff8a20")})
			return 0.35
		"magnet":
			g.fx.append({k = "ring", x = g.P.x, z = g.P.z, r = 5.0, t = 0.25, life = 0.25, c = Color("d04040")})
			for i in g.items:
				i.x = g.P.x + randf_range(-1.5, 1.5)
				i.z = g.P.z + randf_range(-1.5, 1.5)
				g.clamp_pos(i)
			for b in g.bullets:
				if not b.mine and g.d2(b, g.P) < 6:
					g.combat.reflect(b)
			for e in g.enemies:
				if g.d2(e, g.P) < 3 + e.r:
					g.combat.hit(e, 0.5 * m, atan2(e.z - g.P.z, e.x - g.P.x), 8 * kbm)
			return 1.5
		"gunhand":
			var pg2: Dictionary = D.GUNS.pistol.duplicate()
			pg2.dmg *= m
			g.combat.shoot(a, pg2, {}, am.spread)
			return 0.32
		"grenade":
			g.combat.shoot(a, {spd = 18.0, dmg = 5.0 * m, spread = am.spread}, {explode = 4.5, big = true})
			if arm.hand2 != null and is_same(arm.hand2, h):
				arm.hand2 = null
			else:
				g.body.lose_hand(s)
			g.dirty = true
			g.say("You threw your hand. It will not be coming back.")
			return 0.5
	return 0.4

func throw_arm(side: String) -> void:
	var arm = g.P.parts[D.SIDE[side].arm]
	arm.out = true
	g.flyers.append({x = g.P.x, z = g.P.z, a = g.P.aim, t = 0.0, side = side, back = false, hits = [], dead = false, m = null})
	g.dirty = true

# F: the jaw's action.
func jaw_act() -> void:
	if g.over or g.P.cdJ > 0 or g.P.dash != null:
		return
	var j = g.P.parts.jaw
	if j == null:
		if g.msg_t <= 0:
			g.say("No jaw!", 1.5)
		return
	var a: float = g.P.aim
	var m := g.body.power()
	g.P.still = 0.0
	match j.type:
		"flesh":
			g.combat.melee(a, 1.6, 0.7, 1 * m, 1, {c = Color("f3c4a8")})
			g.P.cdJ = 0.8
		"shark":
			g.combat.melee(a, 4.4, 0.5, 4 * m, 6, {c = Color("90a0b0")})
			g.P.dash = {t = 0.12, dur = 0.12, vx = cos(a) * 28, vz = sin(a) * 28, type = "bite", hits = []}
			g.P.cdJ = 1.2
		"howler":
			g.fx.append({k = "ring", x = g.P.x, z = g.P.z, r = 7.0, t = 0.3, life = 0.3, c = Color("c0a0e0")})
			for e in g.enemies:
				if g.d2(e, g.P) < 7 + e.r:
					g.combat.status(e, "stun", 1.5)
			g.P.cdJ = 4.0
		"spitter":
			g.combat.shoot(a, {spd = 22.0, dmg = 1.5 * m, spread = 0.04}, {acid = 4.0})
			g.P.cdJ = 0.55
		"fangs":
			for e in g.combat.bite(a, 1.9, 0.7, 2 * m, 1, Color("f0f0f0")):
				if e.bleed > 0:
					g.body.feed(2.0)
			g.P.cdJ = 0.6
	g.P.cdJ /= g.body.haste()
