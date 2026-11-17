extends RefCounted
# Loot: what chests, enemies and the surgeon give, and how chests open, break or bite.

const D = preload("res://src/data.gd")
const Game = preload("res://src/game.gd")

var g: Game

func _init(game: Game) -> void:
	g = game

# Never leave the player with no way to get a hand back.
func rescue_hand() -> void:
	if g.P.parts.lh != null or g.P.parts.rh != null:
		return
	var has_arm: bool = g.P.parts.la != null or g.P.parts.ra != null
	for i in g.items:
		if i.get("pk") == "arm" and i.get("hand") != null:
			return
		if has_arm and i.get("pk") == "hand":
			return
	var x: float = g.P.x + randf_range(-3, 3)
	var z: float = g.P.z + randf_range(-3, 3)
	if has_arm:
		g.add_item({kind = "part", pk = "hand", type = "flesh", fingers = 4}, x, z)
		g.say("A stray hand twitches on the floor nearby...")
	else:
		g.add_item({kind = "part", pk = "arm", type = "flesh", hand = g.body.new_hand("flesh", 4), hand2 = null}, x, z)
		g.say("A stray arm twitches on the floor nearby...")

func loot(x: float, z: float, rare := false) -> void:
	var r := randf()
	var px := x + randf_range(-1.2, 1.2)
	var pz := z + randf_range(0.8, 2.0)
	if r < 0.25:
		g.add_item({kind = "weapon", id = ["smg", "shotgun", "sniper", "knife", "pistol", "smg", "shotgun"].pick_random()}, px, pz)
	elif r < 0.7 or rare:
		var pk: String = ["hand", "hand", "leg", "leg", "arm", "eye", "ear", "jaw", "skin"].pick_random()
		g.add_item({kind = "part", pk = pk, type = roll_part(pk, rare)}, px, pz)
	elif r < 0.84:
		g.add_item({kind = "part", pk = "organ", type = roll_part("organ", rare)}, px, pz)
	elif r < 0.94:
		g.add_item({kind = "heart"}, px, pz)
	else:
		g.add_item({kind = "finger"}, px, pz)

func enemy_drop(e: Dictionary) -> void:
	g.kills += 1
	if e.type == "mimic":  # exactly one thing: a weapon or part, or just scrap
		if randf() < 0.5:
			loot(e.x, e.z, true)
		else:
			g.add_item({kind = "scrap"}, e.x, e.z)
		return
	# parts now come off enemies while they are alive (see sever_enemy); only an elite brute still drops one on death
	if e.type == "brute" and e.elite:
		g.add_item({kind = "part", pk = "hand", type = "fist"}, e.x, e.z)
	elif randf() < (0.2 if g.body.has_org("tapeworm") else 0.08):
		g.add_item({kind = "heart"}, e.x, e.z)
	elif randf() < 0.06:
		g.add_item({kind = "finger"}, e.x, e.z)
	if e.elite:
		loot(e.x, e.z, true)
		loot(e.x, e.z)
	elif g.guns.unarmed() and randf() < D.UNARMED_DROP and not g.items.any(func(i): return i.kind == "weapon"):
		g.add_item({kind = "weapon", id = D.UNARMED_GUNS.pick_random()}, e.x, e.z)
	# each floor hands out a fixed number of keys; the exit guardian drops whatever is left
	var n := 0
	if g.keys_left > 0:
		if e.elite and g.room.get("type", "") == "exit":
			n = g.keys_left
		elif e.elite or randf() < D.KEY_CHANCE:
			n = 1
	g.keys_left -= n
	for i in n:
		g.add_item({kind = "key"}, e.x + randf_range(-1, 1), e.z + randf_range(-1, 1))

func open_chest(c: Dictionary, hs: String) -> void:
	var h = g.P.parts[hs]
	if h.type == "chainsaw":
		g.say("The chainsaw chews the chest apart.")
		if c.type == "mimic":
			wake(c)
		else:
			break_chest(c, true)
		return
	if c.type == "mimic":
		if h.type == "maw":
			g.say("MIMIC! Your maw bites back.")
		else:
			g.say("MIMIC! It bit your hand off!")
			g.body.sever(hs)
		wake(c)
		return
	if c.type == "locked":
		if h.type == "maw":
			g.say("Your maw chews through the lock.")
		elif h.type == "pincer":
			c.snipped = true
			g.say("Snipped the lock. Some of the loot got cut up with it.")
		elif g.P.keys > 0:
			g.P.keys -= 1
			g.say("Unlocked with a key.")
		elif h.type in ["flesh", "baby"] and h.fingers > 0:
			h.fingers -= 1
			h.maxf -= 1  # a finger the lock takes never grows back
			g.say("No key. The lock bites off a finger for good and opens.")
			g.body.check_grip()
			g.dirty = true
		else:
			g.say("Locked. Needs a key.")
			return
	pop_chest(c)

func pop_chest(c: Dictionary) -> void:
	c.open = true
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
		g.say("Smashed it open.")
		pop_chest(c)
	else:
		g.say("Smashed it to pieces. Only scrap left.")
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
	g.add_item({kind = "scrap"}, c.x, c.z)

func wake(c: Dictionary) -> void:
	c.open = true
	c.gone = true
	g.spawn_q.append({x = c.x, z = c.z, cd = 0.0})

func use_altar(side: String) -> void:
	var cands := []
	for s in (["le", "lr", "lh", "ll"] if side == "L" else ["re", "rr", "rh", "rl"]):
		if g.P.parts[s] != null and g.P.parts[s].type == "flesh":
			cands.append(s)
	# never the last hand: without one you cannot open doors
	var hs: String = D.SIDE[side].hand
	if cands.has(hs) and g.P.parts["rh" if hs == "lh" else "lh"] == null:
		cands.erase(hs)
		if cands.is_empty():
			g.say("The surgeon will not take your last hand.")
			return
	if cands.is_empty():
		g.say("The surgeon wants flesh from your %s side. You have none there." % g.side_name(side))
		return
	var s: String = cands.pick_random()
	if s in ["lh", "rh"]:
		g.guns.drop_held(s)
		g.body.lose_hand(s)
	else:
		g.P.parts[s] = null
	g.altar.used = true
	g.body.check_grip()
	g.dirty = true
	loot(g.altar.x, g.altar.z + 1, true)
	loot(g.altar.x, g.altar.z + 1, true)
	g.say("The surgeon takes your %s. Fair trade." % D.SLOT[s][1])

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
