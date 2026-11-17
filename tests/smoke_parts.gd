extends RefCounted
# Automated checks for every part type and for enemy limbs. Called from smoke().

const D = preload("res://src/data.gd")
const Game = preload("res://src/game.gd")

var g: Game

func _init(game: Game) -> void:
	g = game

# Checks for the expanded body: every part, arms, nerfs and the stranger parts.
func smoke_parts() -> void:
	g.t_move = Vector2.ZERO
	var n := 0
	for pk in D.TYPES:
		for t in D.TYPES[pk]:
			g.new_game()
			g.tests.test_room("fight", 4)
			g.ai.spawn("grunt")
			g.ai.spawn("spitter")
			g.player.take_item(g.add_item({kind = "part", pk = pk, type = t}, g.P.x, g.P.z), "L")
			g.t_lmb = true
			g.t_f = true
			g.tests._run(20)
			g.P.cdSp = 0.0
			g.player.ability()
			g.tests._run(60)
			g.t_lmb = false
			g.t_f = false
			g.P.inv = 0.0
			g.P.dash = null
			g.body.hurt(1, 1.0, g.enemies[0] if not g.enemies.is_empty() else null)
			g.tests._run(10)
			n += 1
	print("parts: %d types attached, used and hurt without errors" % n)
	# arms carry hands
	g.new_game()
	g.tests.test_room("fight")
	g.enemies = g.prune(g.enemies, func(_e): return false)
	g.items = g.prune(g.items, func(_i): return false)
	g.body.sever("la")
	var arm_item = g.items[0]
	var gone: bool = g.P.parts.la == null and g.P.parts.lh == null
	g.player.take_item(g.add_item({kind = "part", pk = "hand", type = "claw"}, g.P.x, g.P.z), "L")
	var refused: bool = g.P.parts.lh == null
	g.player.take_item(arm_item, "L")
	print("arm: severed with hand %s, hand refused without arm %s, reattached arm %s + hand %s" % [gone, refused, g.P.parts.la.type, g.P.parts.lh.type])
	g.player.take_item(g.add_item({kind = "part", pk = "arm", type = "forked"}, g.P.x, g.P.z), "L")
	g.player.take_item(g.add_item({kind = "part", pk = "hand", type = "claw"}, g.P.x, g.P.z), "L")
	g.player.take_item(g.add_item({kind = "part", pk = "hand", type = "torch"}, g.P.x, g.P.z), "L")
	print("forked arm: hand %s, second hand %s, label '%s'" % [g.P.parts.lh.type, g.P.parts.la.hand2.type if g.P.parts.la.hand2 != null else "none", g.body.hand_label("lh")])
	g.player.take_item(g.add_item({kind = "part", pk = "arm", type = "boomerang"}, g.P.x, g.P.z), "R")
	var far_e := g.ai.spawn("grunt", {x = g.P.x + 6.0, z = g.P.z})
	far_e.hp = 50.0
	far_e.stun = 99.0
	g.P.aim = 0.0
	g.t_aim = Vector2(g.P.x + 6.0, g.P.z)
	g.P.cdR = 0.0
	g.player.act("R")
	var was_out: bool = g.P.parts.ra.out
	for i in 200:
		g.update(1.0 / 60)
	print("boomerang arm: thrown %s, back %s, hit for %.0f" % [was_out, not g.P.parts.ra.out, 50.0 - far_e.hp])
	# finger economy: a finger paid to a lock never grows back
	g.new_game()
	g.tests.test_room("fight")
	g.enemies = g.prune(g.enemies, func(_e): return false)
	g.items = g.prune(g.items, func(_i): return false)
	g.chests = g.prune(g.chests, func(_c): return false)
	var fc := g.tests._test_chest(g.P.x, "locked")
	fc.z = g.P.z - 1.5
	g.player.interact("L")
	var paid: int = g.P.parts.lh.fingers
	g.items = g.prune(g.items, func(_i): return false)
	g.P.parts.o1 = {type = "marrow"}
	for i in 3:
		g.world.clear_room()
	var after_lock: int = g.P.parts.lh.fingers
	g.P.parts.lh.fingers = 2
	g.world.clear_room()
	print("fingers: paid lock -> %d, marrow after 3 rooms -> %d (max %d), combat loss regrows 2 -> %d" % [paid, after_lock, g.P.parts.lh.maxf, g.P.parts.lh.fingers])
	# chest hunter
	var scraps := 0
	for i in 400:
		g.items = []
		g.loot.break_chest(g.tests._test_chest(0.0, "normal"), true)
		scraps += g.items.size()
	g.chests = []
	g.items = []
	g.P.parts.lh = g.body.new_hand("pincer")
	g.P.keys = 0
	var lc := g.tests._test_chest(g.P.x, "locked")
	lc.z = g.P.z - 1.5
	g.player.interact("L")
	print("chest hunter: chainsaw scrap %.0f%%, pincer on a locked chest gives %d item(s)" % [scraps / 4.0, g.items.size()])
	g.chests = []
	g.items = []
	# bomb leg throws you across the room
	g.tests.test_room("fight")
	g.enemies = g.prune(g.enemies, func(_e): return false)
	g.P.x = -g.AW + 2
	g.P.z = 0.0
	g.P.parts.ll = {type = "bomb"}
	g.t_move = Vector2(1, 0)
	g.P.cdSp = 0.0
	g.player.ability()
	g.t_move = Vector2.ZERO
	var x0: float = g.P.x
	g.tests._run(50)
	print("bomb leg: leg gone %s, thrown %.1f units" % [g.P.parts.ll == null, g.P.x - x0])
	# statuses and survival
	var se := g.ai.spawn("grunt")
	se.hp = 50.0
	g.combat.status(se, "burn", 3.0)
	g.combat.status(se, "acid", 3.0)
	print("burn + acid: exploded for %.1f, statuses cleared %s" % [50.0 - se.hp, se.burn == 0.0 and se.acid == 0.0])
	g.enemies = g.prune(g.enemies, func(_e): return false)
	g.P.parts.o2 = {type = "kidney"}
	g.P.hp = 1
	g.P.inv = 0.0
	g.P.dash = null
	g.over = false
	g.body.hurt(1, 0.0)
	print("kidney: alive %s, hp %d, kidney left %s" % [not g.over, g.P.hp, g.body.has_org("kidney")])
	g.P.parts.jaw = null
	g.P.hp = 3
	g.player.take_item(g.add_item({kind = "heart"}, g.P.x, g.P.z), "L")
	print("no jaw: heart refused %s" % (g.P.hp == 3))
	g.items = []
	var seen := {}
	var bad := 0
	for i in 4000:
		g.loot.loot(0, 0, i % 2 == 0)
	for i in g.items:
		if i.kind == "part":
			seen[i.pk + ":" + i.type] = true
			if i.type == "flesh" or (i.type in D.QUIRKY_TYPES):
				bad += 1
	g.items = []
	print("loot: %d different parts seen in 4000 rolls, flesh or scrap-only %d" % [seen.size(), bad])

# Checks for enemy dismemberment.
func smoke_limbs() -> void:
	g.new_game()
	g.tests.test_room("fight")
	g.enemies = g.prune(g.enemies, func(_e): return false)
	g.items = g.prune(g.items, func(_i): return false)
	g.room.blocks = []
	g.t_move = Vector2.ZERO
	g.P.x = 0.0
	g.P.z = g.AH - 2
	var whole := g.ai.spawn("grunt", {x = -3.0, z = -g.AH + 2})
	var cut := g.ai.spawn("grunt", {x = 3.0, z = -g.AH + 2})
	for e in [whole, cut]:
		e.hp = 500.0
		e.maxhp = 500.0
	g.combat.sever_enemy(cut)
	var limbs_after_one: int = cut.limbs.size()
	for l in ["ll", "rl"]:
		cut.limbs.erase(l)
	cut.ld = true
	var z0: float = whole.z
	var z1: float = cut.z
	g.tests._run(60)
	print("enemy limbs: 4 -> %d after one sever, legless moved %.1f vs whole %.1f" % [limbs_after_one, absf(cut.z - z1), absf(whole.z - z0)])
	var hits := 0
	while not whole.limbs.is_empty() and hits < 500:
		g.combat.hit(whole, 2.0, null, 0.0, 2.0)
		hits += 1
	var drops := 0
	for i in 300:
		var node := g.ai.spawn("grunt")
		g.combat.sever_enemy(node)
	drops = g.items.size()
	g.enemies = g.prune(g.enemies, func(e): return is_same(e, whole))
	whole.x = g.P.x
	whole.z = g.P.z - 0.9
	whole.stun = 0.0
	g.P.inv = 0.0
	g.P.hp = 6
	var lost0 := g.body.missing()
	for i in 600:
		g.P.inv = minf(g.P.inv, 0.0)
		g.update(1.0 / 60)
		g.over = false
		g.P.hp = 6
	print("knife hits to strip a grunt: %d; armless grunt severed %d of your parts in 600 frames; limb drops %d of 300 severs" % [hits, g.body.missing() - lost0, drops])
	for t in D.ENEMY:
		g.tests.test_room("fight")
		g.enemies = g.prune(g.enemies, func(_e): return false)
		var e := g.ai.spawn(t)
		e.hp = 500.0
		while not e.limbs.is_empty():
			g.combat.sever_enemy(e)
		g.tests._run(120)
	print("every enemy type runs with all limbs gone: ok")
	g.enemies = g.prune(g.enemies, func(_e): return false)
	g.items = g.prune(g.items, func(_i): return false)
