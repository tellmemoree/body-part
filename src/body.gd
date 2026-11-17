extends RefCounted
# The player's body: questions about parts, losing parts (sever, hurt), attaching new ones,
# and the labels the HUD shows for them.

const D = preload("res://src/data.gd")
const Game = preload("res://src/game.gd")

var g: Game

func _init(game: Game) -> void:
	g = game

func max_hp() -> int:
	return 6 + (2 if has_org("heart2") else 0) - (1 if has_org("tapeworm") else 0)

func missing() -> int:
	var n := 0
	for s in D.LIMBS:
		if g.P.parts[s] == null:
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
		if g.P.parts[s] != null and g.P.parts[s].type == t:
			return true
	return false

func legs() -> Array:
	var out := []
	for s in ["ll", "rl"]:
		if g.P.parts[s] != null:
			out.append(g.P.parts[s])
	return out

func leg_move() -> String:
	var ts := legs().map(func(l): return l.type)
	if ts.size() == 1 and not D.ONE_LEG.has(ts[0]):
		return ""  # this leg cannot do its move alone
	if ts.has("spring") and ts.has("rocket"):
		return "rocketleap"
	for t in ["bomb", "ghost", "rocket", "bird", "frog", "spring", "crate", "robot", "flesh", "squeaky", "wheel"]:
		if ts.has(t):
			return t
	return ""

func hand_label(s: String) -> String:
	var h = g.P.parts[s]
	if h == null:
		return "-"
	var arm = g.P.parts[arm_of(s)]
	if arm.type == "boomerang":
		return "in the air" if arm.out else "throw arm"
	var t: String = g.part_name("hand", h.type)
	if can_grip(h):
		if h.held != null:
			t = D.GUNS[h.held].n
			if D.GUNS[h.held].has("mag"):
				t = "reloading" if g.P["rl" + g.guns.side_of(s)] > 0 else "%s %d/%d" % [t, h.mag, h.res]
		elif h.type == "flesh":
			t = "jab"
	if arm.hand2 != null:
		t += " + " + g.part_name("hand", arm.hand2.type)
	return t

func space_label() -> String:
	return {
		"rocketleap": "rocket leap", "bomb": "DETONATE", "ghost": "phase", "rocket": "rocket dash", "bird": "glide",
		"frog": "hop (hold)", "spring": "leap", "crate": "stomp", "robot": "kick-dash", "flesh": "roll",
		"squeaky": "roll", "wheel": "roll", "": "-",
	}[leg_move()]

func check_grip() -> void:
	for s in ["lh", "rh"]:
		var h = g.P.parts[s]
		if h == null or h.held == null:
			continue
		var gun = D.GUNS[h.held]
		var other = g.P.parts["rh" if s == "lh" else "lh"]
		if not can_grip(h) or not fingers_ok(h, gun) or (gun.hands == 2 and (other == null or other.held != h.held)):
			g.say("You fumble the %s!" % gun.n)
			g.guns.drop_held(s)

func sever(slot = null) -> void:
	var present := []
	for k in D.LIMBS:
		if g.P.parts[k] == null:
			continue
		var arm_slot := ""
		if k in ["la", "ra"]:
			arm_slot = k
		elif k in ["lh", "rh"]:
			arm_slot = arm_of(k)
		if arm_slot != "" and g.P.parts[arm_slot] != null and g.P.parts[arm_slot].out:
			continue  # a thrown arm is out of reach
		present.append(k)
	if present.is_empty():
		return
	var s: String = slot if slot != null else present.pick_random()
	if slot == null and s in ["la", "ra"] and g.P.parts[hand_of(s)] != null and randf() < 0.75:
		s = hand_of(s)  # the hand usually goes before the whole arm does
	var p = g.P.parts[s]
	if p == null:
		return
	var kind: String = D.SLOT[s][0]
	if kind == "hand":
		var arm = g.P.parts[arm_of(s)]
		if arm.hand2 != null:
			var h2: Dictionary = arm.hand2
			arm.hand2 = null
			drop_hand_item(h2, true)
			g.say("The second hand on your %s came off!" % D.SLOT[arm_of(s)][1])
			g.dirty = true
			lost_part()
			return
		if slot == null and p.type in ["flesh", "baby", "rotting"] and p.fingers > 0 and randf() < 0.5:
			var n: int = mini(p.fingers, 1 + randi() % 2)
			p.fingers -= n
			if randf() < 0.6:
				g.add_item({kind = "finger"}, g.P.x + randf_range(-2, 2), g.P.z + randf_range(-2, 2))
			g.say("Lost %d finger%s on your %s! Slower trigger." % [n, "s" if n > 1 else "", D.SLOT[s][1]])
			check_grip()
			g.dirty = true
			return
	if kind == "arm":
		var hs := hand_of(s)
		g.guns.drop_held(hs)
		g.add_item({kind = "part", pk = "arm", type = p.type, hand = g.P.parts[hs], hand2 = p.hand2, rot = 25.0}, g.P.x + randf_range(-2.5, 2.5), g.P.z + randf_range(-2.5, 2.5))
		g.P.parts[hs] = null
		g.P.parts[s] = null
		g.say("Your whole %s came off! Grab it before it rots." % D.SLOT[s][1])
	elif kind == "hand":
		g.guns.drop_held(s)
		drop_hand_item(p, true)
		g.P.parts[s] = null
		g.say("Your %s came off! Grab it before it rots." % D.SLOT[s][1])
	else:
		g.P.parts[s] = null
		g.add_item({kind = "part", pk = kind, type = p.type, rot = 25.0}, g.P.x + randf_range(-2.5, 2.5), g.P.z + randf_range(-2.5, 2.5))
		g.say("Your %s came off! Grab it before it rots." % D.SLOT[s][1])
	check_grip()
	g.dirty = true
	lost_part()

func hurt(dmg: int, sev_chance: float, src = null) -> void:
	if g.P.inv > 0 or g.P.dash != null or g.over or g.god:
		return
	var contact: bool = src != null and src.has("hp")
	if contact:
		var front: bool = g.ang_diff(atan2(src.z - g.P.z, src.x - g.P.x), g.P.aim) < 1.1
		if front and (g.P.shL > 0 or g.P.shR > 0):  # shield takes it
			var ba := atan2(g.P.z - src.z, g.P.x - src.x)
			g.P.kx += cos(ba) * 8
			g.P.kz += sin(ba) * 8
			g.P.inv = 0.4
			return
		var stilts: int = legs().filter(func(l): return l.type == "stilt").size()
		if randf() < 0.3 * stilts:  # swung under you
			g.P.inv = 0.4
			return
	if g.P.plate:
		g.P.plate = false
		g.P.inv = 0.9
		g.say("Your plating took the hit.", 1.5)
		return
	g.P.hp -= dmg * (2 if skin_is("glass") else 1)
	g.P.inv = 0.9
	g.P.still = 0.0
	var kb := 0.0
	if src != null:
		kb = src.get("kb", 0.0)
		if skin_is("rubber"):
			kb = maxf(kb, 8.0) * 2.0
	if kb > 0 and not has_type(["ll", "rl"], "peg") and not has_type(["ll", "rl"], "tread"):
		var a := atan2(g.P.z - src.z, g.P.x - src.x)
		g.P.kx += cos(a) * kb
		g.P.kz += sin(a) * kb
	if has_org("bile"):
		g.fx.append({k = "ring", x = g.P.x, z = g.P.z, r = 3.5, t = 0.25, life = 0.25, c = Color("a0e040")})
		for e in g.enemies:
			if g.d2(e, g.P) < 3.5 + e.r:
				g.combat.hit(e, 1)
				g.combat.status(e, "acid", 4.0)
	if skin_is("hive"):
		for i in 3:
			var fa := randf() * TAU
			g.bullets.append({x = g.P.x, z = g.P.z, vx = cos(fa) * 12, vz = sin(fa) * 12, mine = true, dmg = 1.0, pierce = false, life = 3.0, hits = [], explode = 0.0, big = false, dead = false, home = 8.0, fly = true, m = null})
	if has_org("pacemaker"):
		g.slow_t = 1.5
	for s in ["lh", "rh"]:
		var h = g.P.parts[s]
		if h != null and h.type == "skeleton" and h.held != null:
			g.say("Your skeleton hand lets go of the %s!" % D.GUNS[h.held].n)
			g.guns.drop_held(s)
	for s in ["le", "re"]:
		if g.P.parts[s] != null and g.P.parts[s].type == "glass":
			g.P.parts[s] = null
			g.add_item({kind = "part", pk = "eye", type = "glass", decoy = 4.0}, g.P.x + randf_range(-4, 4), g.P.z + randf_range(-4, 4))
			g.say("Your glass eye pops out and rolls away. They chase it.")
			g.dirty = true
			break
	if randf() < sev_chance * (0.4 if skin_is("stitched") else 1.0):
		sever()
	if g.P.hp <= 0:
		for o in D.ORGS:
			if g.P.parts[o] != null and g.P.parts[o].type == "kidney":
				g.P.parts[o] = null
				g.P.hp = 1
				g.P.inv = 2.0
				g.dirty = true
				g.say("Your spare kidney gave out instead of you.", 5.0)
				return
		g.over = true
		g.msg = ""

func sees(s: String) -> bool:
	return g.P.parts[s] != null and g.P.parts[s].type != "glass"

func has_org(t: String) -> bool:
	return has_type(D.ORGS, t)

func both(a: String, b: String, t: String) -> bool:
	return has_type([a], t) and has_type([b], t)

func skin_is(t: String) -> bool:
	return g.P.parts.skin.type == t

func hand_of(arm_slot: String) -> String:
	return "lh" if arm_slot == "la" else "rh"

func arm_of(hand_slot: String) -> String:
	return "la" if hand_slot == "lh" else "ra"

func can_grip(h) -> bool:
	return h != null and h.type in D.GRIP

func fingers_ok(h, gun) -> bool:
	if h.type == "skeleton":
		return true
	if h.type == "baby":
		return gun.hands == 1
	return h.fingers >= gun.fingers

func new_hand(type: String, fingers := -1) -> Dictionary:
	var top := 2 if type == "baby" else 5
	var f := 0
	if type in D.GRIP:
		f = top
		if fingers >= 0 and type != "skeleton":
			f = mini(top, fingers)
	return {type = type, fingers = f, maxf = top, held = null, mag = 0, res = 0}

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
		m *= 1.0 + 0.75 * (1.0 - clampf(float(g.P.hp) / max_hp(), 0.0, 1.0))
	return m

# Drained blood turns into health: 6 points per HP.
func feed(amount: float) -> void:
	g.P.drain += amount
	while g.P.drain >= 6.0:
		g.P.drain -= 6.0
		if g.P.hp < max_hp():
			g.P.hp += 1
			g.say("Drained. +1 HP.", 1.5)

func item_name(i: Dictionary) -> String:
	if i.kind == "weapon":
		var gun = D.GUNS[i.id]
		return "%s (%d)" % [gun.n, i.get("mag", 0) + i.get("res", gun.ammo)] if gun.has("mag") else gun.n
	if i.kind != "part":
		return i.kind
	var n: String = g.part_name(i.pk, i.type)
	if i.pk == "hand" and i.type in ["flesh", "baby", "rotting"]:
		n += " (%df)" % i.get("fingers", 2 if i.type == "baby" else 5)
	if i.pk == "arm" and i.get("hand") != null:
		n += " + " + g.part_name("hand", i.hand.type)
	return n

# Tab screen: [name, what it does or what its absence costs, colour] for one body slot.
func part_info(s: String) -> Array:
	var kind: String = D.SLOT[s][0]
	var p = g.P.parts[s]
	if p == null:
		if kind == "organ":
			return ["none", D.MISSING_TIP.organ, Color("666666")]
		var why: String = D.MISSING_TIP[kind]
		if kind == "hand" and g.P.parts[arm_of(s)] == null:
			why = "gone with the arm"
		return ["MISSING", why, Color("ee4444")]
	var n: String = g.part_name(kind, p.type)
	var txt: String = D.TYPES[kind][p.type].get("tip", D.BASE_TIP.get(kind, ""))
	var col := Color("d8b8a8") if p.type == "flesh" else Color(D.TYPES[kind][p.type].c).lightened(0.25)
	if kind == "hand":
		if p.type in ["flesh", "baby", "rotting"]:
			n += ", %d finger%s" % [p.fingers, "" if p.fingers == 1 else "s"]
			if g.guns.finger_slow(p) > 1.0:
				txt += "  |  %d%% slower trigger and reload" % roundi((g.guns.finger_slow(p) - 1.0) * 100)
		if p.held != null:
			var gun = D.GUNS[p.held]
			txt += "  |  holding %s" % gun.n
			if gun.has("mag"):
				txt += ": %d in the magazine, %d spare (R reloads, thrown away when empty)" % [p.mag, p.res]
		var arm = g.P.parts[arm_of(s)]
		if arm != null and arm.hand2 != null:
			txt += "  |  second hand: %s - %s" % [g.part_name("hand", arm.hand2.type), D.TYPES.hand[arm.hand2.type].get("tip", "")]
	elif kind == "arm" and p.out:
		n += " (thrown)"
	elif kind == "leg" and legs().size() == 1:
		var f: float = D.ONE_LEG.get(p.type, 0.0)
		if p.type in ["peg", "tread", "stilt", "tentacle"]:
			txt += "  |  your only leg"
		elif f <= 0:
			txt += "  |  your only leg: SPACE does not work"
		elif f < 1:
			txt += "  |  your only leg: SPACE at half strength"
		else:
			txt += "  |  your only leg: SPACE still works"
	return [n, txt, col]

func jaw_label() -> String:
	var j = g.P.parts.jaw
	if j == null:
		return "-"
	return {"flesh": "bite", "shark": "lunge bite", "howler": "howl", "spitter": "acid spit", "fangs": "drain bite"}[j.type]

# Lizard gland: one missing limb grows back as plain flesh. Returns its label, or "".
func regrow() -> String:
	for s in ["la", "ra", "lh", "rh", "ll", "rl", "le", "re", "jaw", "lr", "rr"]:
		if g.P.parts[s] != null:
			continue
		var kind: String = D.SLOT[s][0]
		if kind == "hand" and g.P.parts[arm_of(s)] == null:
			continue
		g.P.parts[s] = new_part(kind, "flesh")
		g.P.regrow = false
		g.dirty = true
		return D.SLOT[s][1]
	return ""

# Removes the hand in a slot. A forked arm's second hand moves up to take its place.
func lose_hand(s: String) -> void:
	var arm = g.P.parts[arm_of(s)]
	g.P.parts[s] = null
	if arm != null and arm.hand2 != null:
		g.P.parts[s] = arm.hand2
		arm.hand2 = null
	g.dirty = true

func drop_hand_item(h: Dictionary, rot := false) -> void:
	var it := {kind = "part", pk = "hand", type = h.type, fingers = h.fingers, maxf = h.maxf}
	if rot:
		it.rot = 25.0
	g.add_item(it, g.P.x + randf_range(-2.5, 2.5), g.P.z + randf_range(-2.5, 2.5))

func lost_part() -> void:
	if has_org("bombheart"):
		g.combat.explode(g.P.x, g.P.z, 4.0, 3)

# Puts a part item onto the body. Returns false (with a message) when it cannot go there.
func attach(it: Dictionary, side: String) -> bool:
	var pk: String = it.pk
	var verb := "Attached"
	var dx: float = g.P.x + randf_range(-2, 2)
	if pk == "organ":
		if has_org(it.type):
			g.say("You already have a %s." % g.part_name(pk, it.type))
			return false
		var s := ""
		for o in D.ORGS:
			if g.P.parts[o] == null:
				s = o
				break
		if s == "":  # all three slots full: the oldest organ is pushed out
			g.add_item({kind = "part", pk = "organ", type = g.P.parts.o1.type}, dx, g.P.z + 2)
			g.P.parts.o1 = g.P.parts.o2
			g.P.parts.o2 = g.P.parts.o3
			s = "o3"
			verb = "Swapped in"
		g.P.parts[s] = {type = it.type}
	elif pk == "hand":
		var s: String = D.SIDE[side].hand
		var arm = g.P.parts[arm_of(s)]
		if arm == null:
			g.say("No %s arm to attach a hand to." % g.side_name(side))
			return false
		if arm.out:
			g.say("That arm is still in the air.")
			return false
		var nh := new_hand(it.type, it.get("fingers", -1))
		if it.has("maxf"):
			nh.maxf = it.maxf
			nh.fingers = mini(nh.fingers, nh.maxf)
		var cur = g.P.parts[s]
		if cur != null and arm.type == "forked" and arm.hand2 == null and not (it.type in D.GRIP):
			arm.hand2 = nh
			verb = "Mounted on the fork:"
		else:
			if cur != null:
				if cur.type == "gunhand":
					g.say("The gun hand is fused on. Only losing it or swapping the arm removes it.")
					return false
				g.guns.drop_held(s)
				drop_hand_item(cur)
				verb = "Swapped in"
			g.P.parts[s] = nh
	elif pk == "arm":
		var s: String = D.SIDE[side].arm
		var hs := hand_of(s)
		var cur = g.P.parts[s]
		var spare = null  # second hand from a forked arm
		if cur != null:
			if cur.out:
				g.say("That arm is still in the air.")
				return false
			spare = cur.hand2
			g.add_item({kind = "part", pk = "arm", type = cur.type, hand = null, hand2 = null}, dx, g.P.z + 2)
			verb = "Swapped in"
		if it.get("hand") != null:  # the new arm brings its own hand
			if g.P.parts[hs] != null:
				g.guns.drop_held(hs)
				drop_hand_item(g.P.parts[hs])
			g.P.parts[hs] = it.hand
		if it.get("hand2") != null:
			if spare != null:
				drop_hand_item(spare)
			spare = it.hand2
		var na := new_part("arm", it.type)
		if it.type == "forked" and g.P.parts[hs] != null:
			na.hand2 = spare
		elif spare != null:
			drop_hand_item(spare)
		g.P.parts[s] = na
	else:
		var s: String = D.SIDE[side][pk]
		var cur = g.P.parts[s]
		if cur != null:
			verb = "Swapped in"
			if not (pk == "skin" and cur.type == "flesh"):
				g.add_item({kind = "part", pk = pk, type = cur.type}, dx, g.P.z + 2)
		g.P.parts[s] = {type = it.type}
		if pk == "skin":
			g.P.plate = it.type == "plated"
	g.P.hp = mini(g.P.hp, max_hp())
	check_grip()
	var tip: String = D.TYPES[pk][it.type].get("tip", "")
	g.say("%s %s%s." % [verb, g.part_name(pk, it.type), (" - " + tip) if tip != "" else ""], 5.0)
	return true
