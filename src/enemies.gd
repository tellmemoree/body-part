extends RefCounted
# Enemies: spawning, pathfinding around obstacles, and their behaviour every frame.

const D = preload("res://src/data.gd")
const Game = preload("res://src/game.gd")

var g: Game

func _init(game: Game) -> void:
	g = game

func spawn(type: String, o := {}) -> Dictionary:
	var d = D.ENEMY[type]
	var elite: bool = o.get("elite", false)
	var hp: float = ceilf(d.hp * (1 + g.world.diff() * 0.06) * (2.4 if elite else 1.0))
	var e := {
		type = type, x = randf_range(-g.AW + 3, g.AW - 3), z = randf_range(-g.AH + 2, 0.0), hp = hp, maxhp = hp, spd = d.spd,
		r = d.r * (1.3 if elite else 1.0), sev = d.sev, kb = d.get("kb", 0.0), cd = randf_range(1, 2.5), st = "walk", t = 0.0,
		kx = 0.0, kz = 0.0, stun = 0.0, bleed = 0.0, burn = 0.0, acid = 0.0, spk = 0.0, limbs = d.limbs.duplicate(), ld = false, flash = 0.0, a = 0.0, la = 0.0, elite = elite, m = null,
	}
	for i in 12:  # do not spawn on top of the player
		if g.d2(e, g.P) > minf(9.0, g.AW * 0.6) and not g.in_block(e.x, e.z, 1.0):
			break
		e.x = randf_range(-g.AW + 3, g.AW - 3)
		e.z = randf_range(-g.AH + 2, g.AH - 2)
	e.merge(o, true)
	g.enemies.append(e)
	return e

func build_solid() -> void:
	g.ff_w = int(ceil(g.AW * 2))
	g.ff_h = int(ceil(g.AH * 2))
	g.solid = PackedByteArray()
	g.solid.resize(g.ff_w * g.ff_h)
	for cz in g.ff_h:
		for cx in g.ff_w:
			g.solid[cz * g.ff_w + cx] = 1 if g.in_block(-g.AW + cx + 0.5, -g.AH + cz + 0.5, 0.6) else 0
	g.ff = PackedInt32Array()
	g.ff_t = 0.0

func cell_of(x: float, z: float) -> int:
	return clampi(int(floor(z + g.AH)), 0, g.ff_h - 1) * g.ff_w + clampi(int(floor(x + g.AW)), 0, g.ff_w - 1)

func flood(from: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(g.ff_w * g.ff_h)
	out.fill(9999)
	out[from] = 0
	var queue := PackedInt32Array([from])
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var cx := c % g.ff_w
		var cz := c / g.ff_w
		for o in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = cx + o[0]
			var nz: int = cz + o[1]
			if nx < 0 or nz < 0 or nx >= g.ff_w or nz >= g.ff_h:
				continue
			var n := nz * g.ff_w + nx
			if g.solid[n] == 0 and out[n] > out[c] + 1:
				out[n] = out[c] + 1
				queue.append(n)
	return out

# Direction an enemy should walk to reach the player around obstacles.
func ff_dir(e: Dictionary, direct: float) -> float:
	if g.room.blocks.is_empty() or g.ff.size() != g.ff_w * g.ff_h:
		return direct
	var c := cell_of(e.x, e.z)
	if g.ff[c] <= 2:
		return direct
	var cx := c % g.ff_w
	var cz := c / g.ff_w
	var best := g.ff[c]
	var bx := 0
	var bz := 0
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var nx: int = cx + dx
			var nz: int = cz + dz
			if (dx == 0 and dz == 0) or nx < 0 or nz < 0 or nx >= g.ff_w or nz >= g.ff_h:
				continue
			if dx != 0 and dz != 0 and (g.solid[cz * g.ff_w + nx] == 1 or g.solid[nz * g.ff_w + cx] == 1):
				continue  # no cutting corners
			var v := g.ff[nz * g.ff_w + nx]
			if v < best:
				best = v
				bx = dx
				bz = dz
	if bx == 0 and bz == 0:
		return direct
	return atan2((-g.AH + cz + bz + 0.5) - e.z, (-g.AW + cx + bx + 0.5) - e.x)

# Enemy status effects, movement and attacks, then push overlapping enemies apart.
func update_enemies(dt: float) -> void:
	g.ff_t -= dt
	if g.ff_t <= 0 and not g.room.blocks.is_empty():
		g.ff_t = 0.2
		g.ff = flood(cell_of(g.P.x, g.P.z))
	var slow := 0.35 if g.slow_t > 0 else 1.0  # pacemaker slow motion
	var edt := dt * slow
	var dec := exp(-8 * dt)
	var decoy = null
	for i in g.items:
		if i.get("decoy", 0.0) > 0:
			i.decoy -= dt
			decoy = i
	var hidden: bool = decoy == null and g.body.skin_is("chameleon") and g.P.still > 1.0
	var evil: bool = g.body.has_type(["le", "re"], "evil")
	var squeak: bool = g.body.has_type(["ll", "rl"], "squeaky")
	var spiked: bool = g.body.skin_is("spiked")
	for e in g.enemies:
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
		var touching: bool = g.d2(e, g.P) < e.r + 0.7
		if touching and spiked and e.spk <= 0:
			e.spk = 0.5
			g.combat.hit(e, 1)
		if e.stun > 0:
			e.stun -= dt
			g.clamp_pos(e)
			continue
		if hidden:  # lost track of you; they only hurt you if you are already touching
			if touching:
				g.body.hurt(1, e.sev, e)
			g.clamp_pos(e)
			continue
		var tgt = decoy if decoy != null else g.P
		var a := atan2(tgt.z - e.z, tgt.x - e.x)
		var d := g.d2(e, tgt)
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
		if evil and g.ang_diff(atan2(e.z - g.P.z, e.x - g.P.x), g.P.aim) < 0.2:
			mv *= 0.5
		var mdir: float = a if decoy != null else ff_dir(e, a)
		if e.type == "spitter":
			if d < 6:
				mdir = a + PI
			elif d < 11:
				mv = 0
			e.cd -= edt
			if e.cd <= 0 and d < D.SPIT_RANGE:
				e.cd = 1.9
				var sa: float = a if e.limbs.has("eye") else randf() * TAU  # blind: spits anywhere
				g.bullets.append({x = e.x, z = e.z, vx = cos(sa) * 11, vz = sin(sa) * 11, mine = false, dmg = 1.0, pierce = false, life = 4.0, hits = [], explode = 0.0, big = false, dead = false, m = null})
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
		if g.d2(e, g.P) < e.r + (0.35 if armless else 0.7):  # no arms: it has to get right on top of you to bite
			var sv: float = e.sev
			if base.has("la"):
				sv *= [0.0, 0.5, 1.0][arms_n]
			if jawless:
				sv = 0.0
			g.body.hurt(1, sv, {x = e.x, z = e.z, hp = e.hp, kb = 0.0 if armless else e.kb})
		g.clamp_pos(e)
	for i in g.enemies.size():
		for j in range(i + 1, g.enemies.size()):
			var A = g.enemies[i]
			var B = g.enemies[j]
			var d := g.d2(A, B)
			var m: float = A.r + B.r
			if d < m and d > 0.001:
				var px: float = (A.x - B.x) / d * (m - d) / 2
				var pz: float = (A.z - B.z) / d * (m - d) / 2
				A.x += px
				A.z += pz
				B.x -= px
				B.z -= pz
