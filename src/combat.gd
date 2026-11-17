extends RefCounted
# Damage to enemies: hits, melee swings, bullets, explosions, status effects, cutting enemy limbs.

const D = preload("res://src/data.gd")
const Game = preload("res://src/game.gd")

var g: Game

func _init(game: Game) -> void:
	g = game

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
	g.fx.append({k = "ring", x = e.x, z = e.z, r = 1.2, t = 0.2, life = 0.2, c = Color("cc1111")})
	status(e, "bleed", 3.0)
	var arm: bool = l in ["la", "ra"]
	var it = null
	match e.type:
		"grunt":
			if randf() < 0.3:
				it = {kind = "part", pk = "arm", type = "flesh", hand = g.body.new_hand("flesh", randi_range(2, 5)), hand2 = null} if arm else {kind = "part", pk = "leg", type = "flesh"}
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
		g.add_item(it, e.x + randf_range(-1.5, 1.5), e.z + randf_range(-1.5, 1.5))

func melee(a: float, rng: float, arc: float, dmg: float, kb: float, o := {}) -> Array:
	var out := []
	g.fx.append({k = "arc", x = g.P.x, z = g.P.z, a = a, arc = arc, r = rng, t = 0.14, life = 0.14, c = o.get("c", Color.WHITE)})
	for e in g.enemies:
		var ea := atan2(e.z - g.P.z, e.x - g.P.x)
		if g.d2(e, g.P) < rng + e.r and g.ang_diff(ea, a) < arc:
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
	for c in g.chests:
		if c.open:
			continue
		var ca := atan2(c.z - g.P.z, c.x - g.P.x)
		if g.d2(c, g.P) < rng + 0.8 and g.ang_diff(ca, a) < arc:
			if smash:
				g.loot.smash_chest(c)
			else:
				g.loot.damage_chest(c, o.get("saw", false))
	if smash:
		for d in g.doors:
			if g.d2(d, g.P) < rng + 1.2:
				g.world.try_door(d)
	return out

func shoot(a: float, gun: Dictionary, extra := {}, spread_add := 0.0) -> void:
	var spread: float = gun.get("spread", 0.0) + [0.5, 0.07, 0.0][g.body.eyes()] + spread_add
	var home := 2.5 if g.body.both("le", "re", "cyber") else 0.0
	for i in gun.get("pellets", 1):
		var b := a + randf_range(-spread, spread)
		var bl := {
			x = g.P.x + cos(a) * 0.2, z = g.P.z + sin(a) * 0.2, vx = cos(b) * gun.spd, vz = sin(b) * gun.spd, mine = true, dmg = gun.dmg,
			pierce = gun.get("pierce", false), life = gun.get("life", 1.6), hits = [], explode = 0.0, big = false, dead = false,
			ox = g.P.x, oz = g.P.z, home = home, acid = 0.0, m = null,
		}
		bl.merge(extra, true)
		g.bullets.append(bl)
	if gun.has("recoil") and not g.body.has_type(["la", "ra"], "robot"):
		g.P.kx -= cos(a) * gun.recoil
		g.P.kz -= sin(a) * gun.recoil

func hook_shot(a: float) -> void:
	var best = null
	var bd := 14.0
	for e in g.enemies:
		var d := g.d2(e, g.P)
		if d < bd and g.ang_diff(atan2(e.z - g.P.z, e.x - g.P.x), a) < 0.25:
			bd = d
			best = e
	if best == null:
		for i in g.items:
			var d := g.d2(i, g.P)
			if d < bd and d > 2 and g.ang_diff(atan2(i.z - g.P.z, i.x - g.P.x), a) < 0.25:
				bd = d
				best = i
	g.fx.append({k = "line", x = g.P.x, z = g.P.z, x2 = g.P.x + cos(a) * bd, z2 = g.P.z + sin(a) * bd, t = 0.18, life = 0.18, c = Color("ccccdd")})
	if best == null:
		return
	best.x = g.P.x + cos(a) * 1.9
	best.z = g.P.z + sin(a) * 1.9
	if best.has("hp"):
		best.stun = 1.2
		best.kx = 0.0
		best.kz = 0.0
		hit(best, 1)

func explode(x: float, z: float, r: float, dmg: float) -> void:
	g.fx.append({k = "ring", x = x, z = z, r = r, t = 0.25, life = 0.25, c = Color("ffaa44")})
	var c := {x = x, z = z}
	for e in g.enemies:
		if g.d2(e, c) < r + e.r:
			hit(e, dmg, atan2(e.z - z, e.x - x), 8, 1.5)
	for ch in g.chests:
		if not ch.open and g.d2(ch, c) < r + 0.8:
			g.loot.damage_chest(ch)

# Thrown boomerang arms and burning ground from a rocket leg.
func update_flyers(dt: float) -> void:
	for f in g.flyers:
		f.t += dt
		if f.t < 0.35:
			f.x += cos(f.a) * 26 * dt
			f.z += sin(f.a) * 26 * dt
		else:
			if not f.back:
				f.back = true
				f.hits = []
			var ra := atan2(g.P.z - f.z, g.P.x - f.x)
			f.x += cos(ra) * 30 * dt
			f.z += sin(ra) * 30 * dt
			if g.d2(f, g.P) < 1.2 or f.t > 3.0:
				f.dead = true
				var arm = g.P.parts[D.SIDE[f.side].arm]
				if arm != null:
					arm.out = false
				g.dirty = true
		for e in g.enemies:
			if not f.hits.has(e) and g.d2(f, e) < e.r + 0.7:
				f.hits.append(e)
				hit(e, 3 * g.body.power(), f.a, 4)
				touch(e, g.P.parts[D.SIDE[f.side].hand])
	g.flyers = g.prune(g.flyers, func(f): return not f.dead)
	for f in g.fires:
		f.t -= dt
		for e in g.enemies:
			if g.d2(e, f) < e.r + 0.9:
				status(e, "burn", 1.5)
	g.fires = g.fires.filter(func(f): return f.t > 0)

func update_bullets(dt: float) -> void:
	var slow := 0.35 if g.slow_t > 0 else 1.0
	var magnet: bool = g.body.has_type(["lh", "rh"], "magnet")
	var fly_eye: bool = g.body.has_type(["le", "re"], "fly")
	var sniper: bool = g.body.has_type(["le", "re"], "sniper")
	for b in g.bullets:
		var bdt := dt
		if not b.mine:
			bdt *= slow * (0.6 if fly_eye else 1.0)
			var bd := g.d2(b, g.P)
			if magnet and bd < 3.5 and bd > 0.01:  # pushed away from the magnet
				b.vx += (b.x - g.P.x) / bd * 40 * dt
				b.vz += (b.z - g.P.z) / bd * 40 * dt
		elif b.get("home", 0.0) > 0:
			var best = null
			var bd := 12.0
			for e in g.enemies:
				var d := g.d2(b, e)
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
			for e in g.enemies:
				if b.dead or b.hits.has(e):
					continue
				if g.d2(b, e) < e.r + 0.25:
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
				for c in g.chests:
					if not b.dead and not c.open and g.d2(b, c) < 1:
						g.loot.damage_chest(c)
						b.dead = true
		elif g.P.dash == null and g.d2(b, g.P) < 0.75:
			var front: bool = g.ang_diff(atan2(-b.vz, -b.vx), g.P.aim) < 1.1
			if front and (g.P.shL > 0 or g.P.shR > 0):
				b.dead = true
			elif g.body.skin_is("rubber") or (front and g.body.has_type(["le", "re"], "mirror")):
				reflect(b)
			else:
				b.dead = true
				g.body.hurt(1, 0.35)
		if absf(b.x) > g.AW or absf(b.z) > g.AH or b.life <= 0 or (g.in_block(b.x, b.z, 0.1) and not b.get("fly", false)):
			b.dead = true
		if b.dead and b.explode > 0:
			explode(b.x, b.z, b.explode, b.dmg)
	g.bullets = g.prune(g.bullets, func(b): return not b.dead)

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
			g.body.feed(2.0)

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

# A melee bite that heals 1 HP when it kills. Returns the enemies it hit.
func bite(a: float, rng: float, arc: float, dmg: float, kb: float, c: Color) -> Array:
	var hits := melee(a, rng, arc, dmg, kb, {c = c})
	for e in hits:
		if e.hp <= 0 and g.P.hp < g.body.max_hp():
			g.P.hp += 1
			g.say("Swallowed. +1 HP.", 1.5)
			break
	return hits
