extends RefCounted
# Automated checks. Run with: Godot --headless --path . -- --smoke [--seed N]
# Also sets up the --shot screenshot scenes.

const D = preload("res://src/data.gd")
const Game = preload("res://src/game.gd")

var g: Game

func _init(game: Game) -> void:
	g = game

func _shot_setup() -> void:
	g.floor_n = 2
	var sr: Dictionary = g.rooms[g.rooms[0].links.values()[0]]
	sr.type = "fight"
	for style in ["pillars", "corners", "vbars", "hbars", "crates"]:
		if OS.get_cmdline_user_args().has(style):
			for i in 300:
				sr.blocks = []
				g.world.gen_layout(sr)
				if sr.style == style:
					break
	g.world.enter_room(sr, g.rooms[0].links.keys()[0])
	g.chests.append({x = -6.0, z = -4.0, type = "mimic", open = false, gone = false, hp = D.CHEST_HP, flash = 0.0, m = null})
	g.P.parts.lh = g.body.new_hand("fist")
	g.P.parts.ll = {type = "spring"}
	g.P.parts.re = null
	g.P.parts.le = {type = "cyber"}
	if OS.get_cmdline_user_args().has("quirky"):
		g.P.parts.lh = g.body.new_hand("maw")
		g.P.parts.ll = {type = "crate"}
		g.P.parts.re = {type = "keyhole"}
		g.P.scrap = 3
		g.P.keys = 2
		g.add_item({kind = "scrap"}, 2, 3)
		g.add_item({kind = "key"}, -2, 3)
	if OS.get_cmdline_user_args().has("chests"):  # one closed and one opened chest of each kind, no enemies
		g.enemies.clear()
		g.chests.clear()
		var cx := -6.0
		for ct in ["normal", "normal", "locked", "locked"]:
			g.chests.append({x = cx, z = 2.0, type = ct, open = cx == -2.0 or cx == 6.0, gone = false, hp = D.CHEST_HP, flash = 0.0, m = null})
			cx += 4.0
	if OS.get_cmdline_user_args().has("stump"):  # right hand gone, left arm gone
		g.guns.drop_held("rh")
		g.P.parts.rh = null
		g.P.parts.lh = null
		g.P.parts.la = null
	g.dirty = true
	g.ai.spawn("brute")
	g.ai.spawn("leaper")
	g.add_item({kind = "part", pk = "hand", type = "claw", fingers = 0}, 3, 8)
	g.add_item({kind = "weapon", id = "shotgun"}, -4, 7)
	g.P.inv = 99.0
	if OS.get_cmdline_user_args().has("picker"):  # a pile of loot at the player's feet, second item chosen
		for it in [{kind = "weapon", id = "pistol"}, {kind = "part", pk = "eye", type = "cat"}, {kind = "heart"}, {kind = "scrap"}]:
			g.add_item(it, g.P.x + randf_range(-0.6, 0.6), g.P.z + randf_range(-0.6, 0.6))
		g.player.cycle_pick(1)
	if OS.get_cmdline_user_args().has("corridor"):  # room cleared, every door open, halfway down a corridor
		g.enemies.clear()
		g.room.cleared = true
		for d in g.doors:
			g.world.try_door(d)
		var cd: Dictionary = g.doors[0]
		for d in g.doors:  # prefer a corridor that leads to a room not yet seen, to show its fog
			if not d.to.visited:
				cd = d
		var v: Vector2i = Game.DIRS[cd.dir]
		g.P.x = v.x * (g.AW + cd.len * 0.6)
		g.P.z = v.y * (g.AH + cd.len * 0.6)
		g.clamp_pos(g.P)
		g.cam_t = Vector2(g.P.x, g.P.z)
	if OS.get_cmdline_user_args().has("surgeon"):  # standing at the altar, no enemies
		g.enemies.clear()
		g.items.clear()
		g.altar = {x = g.P.x, z = g.P.z - 2.5, used = false, m = null}

func _run(n: int) -> void:
	for i in n:
		g.P.hp = 50
		g.P.inv = 1.0
		g.over = false
		if not g.enemies.is_empty():
			g.t_aim = Vector2(g.enemies[0].x, g.enemies[0].z)
		g.update(1.0 / 60)
	g.view.render()

func _enemy_hp() -> float:
	var s := 0.0
	for e in g.enemies:
		s += e.hp
	return s

func smoke() -> void:
	g.t_move = Vector2.ZERO
	g.t_aim = Vector2.ZERO
	# pistol clears a fight room
	test_room("fight")
	g.t_rmb = true
	var n0 := g.enemies.size()
	for i in 900:
		if g.enemies.is_empty():
			break
		_run(1)
	g.t_rmb = false
	print("pistol: %d -> %d, cleared %s" % [n0, g.enemies.size(), g.room.cleared])
	for t in D.TYPES.hand.keys():
		test_room("fight")
		for et in ["brute", "leaper", "spitter", "slasher"]:
			g.ai.spawn(et)
		g.P.parts.lh = g.body.new_hand(t)
		g.dirty = true
		var hp0 := _enemy_hp()
		n0 = g.enemies.size()
		g.t_lmb = true
		for i in 240:
			if g.enemies.is_empty():
				break
			g.P.x = g.enemies[0].x
			g.P.z = g.enemies[0].z + 2
			g.clamp_pos(g.P)
			_run(1)
		g.t_lmb = false
		print("hand %s: %d -> %d, hp %.0f -> %.1f" % [t, n0, g.enemies.size(), hp0, _enemy_hp()])
	g.P.parts.lh = g.body.new_hand("flesh")
	g.P.parts.rh = g.body.new_hand("flesh")
	for id in D.GUNS.keys():
		test_room("fight")
		g.player.take_item(g.add_item({kind = "weapon", id = id}, g.P.x, g.P.z), "R")
		g.ai.spawn("grunt")
		n0 = g.enemies.size()
		g.t_rmb = true
		for i in 400:
			if g.enemies.is_empty():
				break
			_run(1)
		g.t_rmb = false
		print("gun %s: held %s, %d -> %d" % [id, g.P.parts.rh.held, n0, g.enemies.size()])
	for t in D.TYPES.leg.keys():
		test_room("fight")
		g.P.parts.ll = {type = t}
		g.P.parts.rl = {type = t}
		g.dirty = true
		g.P.cdSp = 0.0
		var x0: float = g.P.x
		var z0: float = g.P.z
		g.player.ability()
		var dashed: bool = g.P.dash != null
		_run(40)
		print("leg %s: dash %s, moved %.1f" % [t, dashed, Vector2(g.P.x - x0, g.P.z - z0).length()])
	g.P.parts.ll = {type = "flesh"}
	g.P.parts.rl = {type = "flesh"}
	test_room("dark")
	g.P.parts.le = null
	_run(5)
	g.P.parts.re = null
	_run(5)
	g.P.parts.le = {type = "cyber"}
	g.P.parts.re = {type = "cat"}
	_run(5)
	print("eyes: ok")
	for t in D.TYPES.organ.keys():
		g.player.take_item(g.add_item({kind = "part", pk = "organ", type = t, fingers = 0}, g.P.x, g.P.z), "L")
		_run(5)
		print("organ %s: max hp %d, haste %.1f" % [t, g.body.max_hp(), g.body.haste()])
	test_room("fight")
	g.enemies = g.prune(g.enemies, func(_e): return false)
	for i in 120:
		g.body.sever()
	_run(10)
	var miss := g.body.missing()
	for i in g.items:
		if i.has("rot"):
			i.rot = 0.01
	_run(5)
	print("sever: missing %d, items left %d" % [miss, g.items.size()])
	for k in D.LIMBS:
		g.P.parts[k] = null
	g.dirty = true
	test_room("fight")
	var hand_item = null
	for i in g.items:
		if i.get("pk") in ["hand", "arm"]:
			hand_item = i
	g.P.x = hand_item.x
	g.P.z = hand_item.z
	g.player.interact("R")
	_run(5)
	print("reattach: rh %s" % [g.P.parts.rh])
	test_room("treasure")
	g.enemies = g.prune(g.enemies, func(_e): return false)
	g.chests = g.prune(g.chests, func(_c): return false)
	g.P.parts.la = g.body.new_part("arm", "flesh")
	g.P.parts.ra = g.body.new_part("arm", "flesh")
	g.P.parts.lh = g.body.new_hand("flesh")
	g.P.parts.rh = g.body.new_hand("fist")
	for c in [[0.0, "normal"], [5.0, "locked"], [-5.0, "locked"], [9.0, "mimic"]]:
		g.chests.append({x = c[0], z = 0.0, type = c[1], open = false, gone = false, hp = D.CHEST_HP, flash = 0.0, m = null})
	g.view.render()
	g.P.z = 1.5
	g.P.x = 0.0
	g.player.interact("L")
	var r1: bool = g.chests[0].open
	g.P.x = 5.0
	g.player.interact("L")
	var r2: bool = g.chests[1].open
	var f2: int = g.P.parts.lh.fingers
	g.P.x = -5.0
	g.P.keys = 1
	g.player.interact("R")
	var r3: bool = g.chests[2].open
	g.P.x = 9.0
	g.player.interact("L")
	_run(3)
	print("chests: normal %s | locked+finger %s (fingers %d) | locked+key %s | mimic took lh: %s, enemies %s" % [r1, r2, f2, r3, g.P.parts.lh == null, g.enemies.map(func(e): return e.type)])
	test_room("surgeon")
	g.P.parts.ll = {type = "flesh"}
	g.P.x = 0.0
	g.P.z = 0.0
	var ni := g.items.size()
	g.player.interact("L")
	_run(3)
	print("altar: used %s, items +%d" % [g.altar.used, g.items.size() - ni])
	# destructible chests, scrap, keys
	g.new_game()
	test_room("treasure")
	g.enemies = g.prune(g.enemies, func(_e): return false)
	g.chests = g.prune(g.chests, func(_c): return false)
	g.items = g.prune(g.items, func(_i): return false)
	g.spikes = g.prune(g.spikes, func(_s): return false)
	var tc := _test_chest(6.0, "normal")
	for i in 4:
		g.loot.damage_chest(tc)
	var alive4: bool = not tc.open
	g.loot.damage_chest(tc)
	_run(2)
	print("chest hits: alive after 4 %s, broken after 5 %s, left behind %s" % [alive4, tc.gone, g.items.map(func(i): return i.kind)])
	g.items = g.prune(g.items, func(_i): return false)
	var pc := _test_chest(5.0, "normal")
	g.P.x = 0.0
	g.P.z = 0.0
	g.t_aim = Vector2(5, 0)
	var shots := 0
	while not pc.gone and shots < 20:
		g.P.cdR = 0.0
		g.P.aim = 0.0
		g.player.act("R")
		shots += 1
		_run(30)
	print("pistol shots to destroy a chest: %d" % shots)
	g.items = g.prune(g.items, func(_i): return false)
	var sc := _test_chest(1.5, "normal")
	g.player.take_item(g.add_item({kind = "weapon", id = "shotgun"}, g.P.x, g.P.z), "R")
	g.t_aim = Vector2(1.5, 0)
	g.P.cdR = 0.0
	g.P.cdL = 0.0
	g.P.aim = 0.0
	g.player.act("R")
	g.P.kx = 0.0
	_run(20)
	print("one shotgun blast destroys a chest: %s" % sc.gone)
	g.items = g.prune(g.items, func(_i): return false)
	var mc := _test_chest(6.0, "mimic")
	g.loot.damage_chest(mc)
	_run(2)
	print("mimic wakes on first hit: %s" % [g.enemies.map(func(e): return e.type)])
	g.enemies = g.prune(g.enemies, func(_e): return false)
	g.items = g.prune(g.items, func(_i): return false)
	var opened := 0
	var broken := 0
	for i in 200:
		var fc := _test_chest(6.0, "normal")
		g.loot.smash_chest(fc)
		if fc.gone:
			broken += 1
		else:
			opened += 1
	print("200 fist smashes: opened %d, destroyed %d" % [opened, broken])
	g.chests = []
	g.items = []
	var lc := _test_chest(0.0, "locked")
	g.P.x = 0.0
	g.P.z = 1.5
	g.P.keys = 0
	g.P.parts.lh = g.body.new_hand("flesh", 0)
	g.player.interact("L")
	var refused: bool = not lc.open
	g.P.keys = 1
	g.player.interact("L")
	print("locked chest: refused without key %s, opened with key %s, keys left %d" % [refused, lc.open, g.P.keys])
	g.chests = []
	g.items = []
	var is_key := func(i): return i.kind == "key"
	var per_floor := []
	for f in 20:  # every floor gives 1-2 keys, however many things die on it
		g.world.gen_floor()
		g.items = []
		g.room = {type = "fight"}
		for i in 300:
			g.loot.enemy_drop({type = "slasher", elite = false, x = 0.0, z = 0.0})
		g.loot.enemy_drop({type = "brute", elite = true, x = 0.0, z = 0.0})
		g.room = {type = "exit"}
		g.loot.enemy_drop({type = "brute", elite = true, x = 0.0, z = 0.0})
		per_floor.append(g.items.filter(is_key).size())
	g.world.gen_floor()
	g.items = []
	g.room = {type = "exit"}
	g.loot.enemy_drop({type = "brute", elite = true, x = 0.0, z = 0.0})
	var guardian: int = g.items.filter(is_key).size()
	print("keys per floor over 20 floors: min %d, max %d; exit guardian alone gives %d (1-2)" % [per_floor.min(), per_floor.max(), guardian])
	var mimic_ok := true
	var m_scrap := 0
	for i in 200:
		g.keys_left = 2
		g.items = []
		g.loot.enemy_drop({type = "mimic", elite = false, x = 0.0, z = 0.0})
		if g.items.size() != 1 or g.items[0].kind == "key" or g.items[0].kind == "heart" or g.items[0].kind == "finger":
			mimic_ok = false
		if g.items[0].kind == "scrap":
			m_scrap += 1
	print("mimic drops exactly one item or scrap, never a key: %s (scrap %d / 200)" % [mimic_ok, m_scrap])
	g.items = []
	g.new_game()
	test_room("fight")
	g.enemies = g.prune(g.enemies, func(_e): return false)
	# ammo: magazine, reload, thrown away when empty, a dropped gun keeps its count
	var gh = g.P.parts.rh
	g.t_aim = Vector2(0, -50)
	var fired := 0
	var reloads := 0
	var was_rl := false
	g.t_rmb = true
	for i in 6000:
		if gh.held == null:
			break
		var before: int = gh.mag + gh.res
		_run(1)
		if gh.held == null or gh.mag + gh.res < before:
			fired += 1
		if g.P.rlR > 0 and not was_rl:
			reloads += 1
		was_rl = g.P.rlR > 0
	g.t_rmb = false
	print("pistol: fired %d of %d, reloads %d, tossed when empty %s, label '%s'" % [fired, D.GUNS.pistol.ammo, reloads, gh.held == null, g.body.hand_label("rh")])
	g.guns.give_gun("rh", "smg")
	g.P.cdR = 0.0
	g.player.act("R")
	g.player.act("R")
	g.guns.drop_held("rh")
	var dropped = g.items.filter(func(i): return i.kind == "weapon")[0]
	var dn: String = g.body.item_name(dropped)
	g.player.take_item(dropped, "R")
	var back := "%d/%d" % [gh.mag, gh.res]
	g.P.cdR = 0.0
	gh.mag = 3
	var rl_ok: bool = g.guns.start_reload("rh") and g.P.rlR > 0
	g.player.act("R")
	var blocked: bool = gh.mag == 3
	_run(120)
	print("smg: dropped as '%s', picked up with %s, manual reload %s, no firing while reloading %s, after reload %d/%d" % [dn, back, rl_ok, blocked, gh.mag, gh.res])
	g.items = []
	g.player.take_item(g.add_item({kind = "weapon", id = "shotgun"}, g.P.x, g.P.z), "R")
	g.P.cdL = 0.0
	g.P.cdR = 0.0
	g.player.act("L")
	print("shotgun shares one magazine across both hands: %d/%d and %d/%d" % [g.P.parts.lh.mag, g.P.parts.lh.res, g.P.parts.rh.mag, g.P.parts.rh.res])
	g.items = []
	# one leg: only legs that can move you alone still work, at half strength
	var one_leg := []
	for t in D.TYPES.leg.keys():
		var dist := []
		for both_legs in [true, false]:
			test_room("fight")
			g.enemies = g.prune(g.enemies, func(_e): return false)
			g.P.parts.ll = {type = t}
			g.P.parts.rl = {type = t} if both_legs else null
			g.P.cdSp = 0.0
			g.P.frog = 0.0
			g.t_aim = Vector2(g.P.x, g.P.z - 30)
			var x0: float = g.P.x
			var z0: float = g.P.z
			g.player.ability()
			_run(70)
			dist.append(Vector2(g.P.x - x0, g.P.z - z0).length())
		one_leg.append("%s %.0f>%.0f" % [t, dist[0], dist[1]])
	print("SPACE distance with two legs > one leg: " + ", ".join(one_leg))
	g.P.parts.ll = {type = "flesh"}
	g.P.parts.rl = null
	print("one flesh leg: label '%s', info '%s'" % [g.body.space_label(), g.body.part_info("ll")[1]])
	g.P.parts.rl = {type = "flesh"}
	# a lost hand must be gone from the model, however it was lost
	var hand_gone := []
	var count_hand := func(slot): return g.pg.get_children().filter(func(n): return not n.is_queued_for_deletion() and n.get_meta("hand", "") == slot).size()
	for how in ["sever", "mimic", "surgeon", "enemy hit"]:
		g.new_game()
		test_room("fight")
		g.enemies = g.prune(g.enemies, func(_e): return false)
		g.chests = []
		g.view.render()
		var had: int = count_hand.call("lh")
		match how:
			"sever":
				g.body.sever("lh")
			"mimic":
				_test_chest(g.P.x, "mimic")
				g.chests[0].z = g.P.z - 1.5
				g.player.interact("L")
			"surgeon":
				g.altar = {x = g.P.x, z = g.P.z, used = false, m = null}
				for i in 50:
					if g.P.parts.lh == null:
						break
					g.altar.used = false
					g.P.parts.le = null
					g.P.parts.lr = null
					g.P.parts.ll = null
					g.loot.use_altar("L")
				g.altar = null
			"enemy hit":
				for i in 400:
					if g.P.parts.lh == null:
						break
					g.P.inv = 0.0
					g.P.hp = 50
					g.body.hurt(1, 1.0, {x = g.P.x, z = g.P.z - 1, hp = 3.0, kb = 0.0})
		g.enemies = g.prune(g.enemies, func(_e): return false)
		g.view.render()
		hand_gone.append("%s: lost %s, meshes %d>%d" % [how, g.P.parts.lh == null, had, count_hand.call("lh")])
	print("lost hand leaves the model - " + " | ".join(hand_gone))
	g.state = "play"
	g.toggle_info()
	var frozen: bool = g.state == "info"
	g.toggle_info()
	print("tab screen: opens %s, closes %s, rows %s" % [frozen, g.state == "play", D.ORDER.map(func(s): return g.body.part_info(s)[0])])
	g.new_game()
	test_room("treasure")
	g.enemies = g.prune(g.enemies, func(_e): return false)
	g.chests = g.prune(g.chests, func(_c): return false)
	g.items = g.prune(g.items, func(_i): return false)
	g.spikes = g.prune(g.spikes, func(_s): return false)
	g.P.parts.lh = g.body.new_hand("flesh", 0)
	g.P.parts.rh = g.body.new_hand("fist")
	g.P.scrap = 0
	for i in 4:
		g.player.take_item(g.add_item({kind = "scrap"}, g.P.x, g.P.z), "L")
	var q4 := g.items.filter(func(i): return i.kind == "part").size()
	g.player.take_item(g.add_item({kind = "scrap"}, g.P.x, g.P.z), "L")
	var q5 := g.items.filter(func(i): return i.kind == "part" and i.type in D.QUIRKY_TYPES).size()
	print("scrap: quirky parts after 4 = %d, after 5 = %d, counter %d" % [q4, q5, g.P.scrap])
	g.items = []
	for q in D.QUIRKY:
		g.player.take_item(g.add_item({kind = "part", pk = q[0], type = q[1], fingers = 0}, g.P.x, g.P.z), "L")
	g.items = []
	g.P.hp = 3
	var g1 := g.ai.spawn("grunt", {x = g.P.x + 1.2, z = g.P.z})
	g1.hp = 1.0
	g.P.aim = 0.0
	g.P.cdL = 0.0
	g.player.act("L")
	var bite_hp: int = g.P.hp
	g.P.cdSp = 0.0
	var g2 := g.ai.spawn("grunt", {x = g.P.x + 2.0, z = g.P.z})
	var hp_before: float = g2.hp
	g.player.ability()
	var hidden := g.world.make_room("dark")
	print("quirky: maw bite heals %s, stomp hits %s, keyhole label '%s', loot never quirky %s" % [bite_hp == 4, g2.hp < hp_before, g.world.room_label(hidden), _loot_never_quirky()])
	g.enemies = []
	g.items = []
	# floor generation
	var ok := true
	for i in 200:
		g.room = {}
		g.world.gen_floor()
		var types := g.rooms.map(func(r): return r.type)
		if g.rooms.size() < 10 or g.rooms.size() > 15 or types.count("exit") != 1 or types.count("start") != 1 or types.count("treasure") != 2 or not types.has("surgeon"):
			ok = false
		for r in g.rooms:
			if r.idx != 0 and r.depth == 0:
				ok = false
	print("floor gen x200 valid: %s" % ok)
	# room layouts: every open cell reachable, doors connected, fights still resolve
	var lay_ok := true
	var styles := {}
	for i in 300:
		var r := g.world.make_room(["fight", "dark", "treasure", "elite", "exit", "surgeon"].pick_random())
		g.world.gen_layout(r)
		styles[r.style] = true
		g.world.enter_room(r, "")
		var reach := g.ai.flood(g.ai.cell_of(0, 0))
		for c in g.ff_w * g.ff_h:
			if g.solid[c] == 0 and reach[c] == 9999:
				lay_ok = false
		for dv in Game.DIRS.values():
			if reach[g.ai.cell_of(dv.x * (g.AW - 1.5), dv.y * (g.AH - 1.5))] == 9999:
				lay_ok = false
		for o in g.chests + g.spikes + g.enemies:
			if g.in_block(o.x, o.z, 0.0):
				lay_ok = false
	print("layouts x300 valid: %s, styles %s" % [lay_ok, styles.keys()])
	var stuck := 0
	for i in 12:
		var r := g.world.make_room("fight")
		r.depth = 8
		g.world.gen_layout(r)
		g.world.enter_room(r, ["N", "S", "E", "W"].pick_random())
		for k in 1500:  # enemies must path around obstacles to reach a standing player (25 s: rooms are big)
			_run(1)
		for e in g.enemies:
			if e.type in ["grunt", "slasher", "brute"] and g.d2(e, g.P) > 4:
				stuck += 1
	print("chasers failing to reach player in 12 rooms: %d" % stuck)
	# play through a whole run by the shortest path
	g.new_game()
	var first_dir := _path_dir()
	var steps := 0
	var back_ok := false
	var walk_fail := 0
	var prev_room := -1
	while not g.won and steps < 300:
		steps += 1
		g.enemies = g.prune(g.enemies, func(_e): return false)
		_run(2)
		if g.stairs != null:
			g.P.x = 0.0
			g.P.z = 1.0
			g.player.interact("R")
			continue
		var dir := _path_dir()
		var d = g.doors.filter(func(x): return x.dir == dir)[0]
		g.P.x = d.x
		g.P.z = d.z
		g.clamp_pos(g.P)
		g.player.interact("R")  # opens the door; then walk down the corridor
		prev_room = g.room.idx
		if not _walk(dir):
			walk_fail += 1
		if steps == 1 and g.room.idx != prev_room:  # walk back through the corridor, then forward again
			g.enemies = g.prune(g.enemies, func(_e): return false)
			_run(2)
			var bd = g.doors.filter(func(x): return x.dir == Game.OPP[first_dir])[0]
			g.P.x = bd.x
			g.P.z = bd.z
			g.clamp_pos(g.P)
			back_ok = _walk(Game.OPP[first_dir]) and g.room.idx == 0
	print("seamless run: won %s in %d steps, corridor walks that failed %d" % [g.won, steps, walk_fail])
	print("walk back through opened door: %s" % back_ok)
	# out of ammo: bare-handed kills drop a weapon often, armed kills never do
	g.new_game()
	var wd := [0, 0]
	for armed in [0, 1]:
		g.P.parts.rh.held = "pistol" if armed == 1 else null
		for i in 200:
			g.items.clear()
			g.loot.enemy_drop({type = "grunt", elite = false, x = 0.0, z = 0.0})
			if g.items.any(func(i2): return i2.kind == "weapon"):
				wd[armed] += 1
	print("weapon drops per 200 kills - unarmed: %d (about 50), armed: %d (0)" % [wd[0], wd[1]])
	# piston arm: a gun fires while held, a bare hand still charges
	g.new_game()
	g.P.parts.ra = {type = "piston", hand2 = null}
	g.guns.give_gun("rh", "smg")
	var smg_ok: bool = not g.player.piston_charges("R")
	g.guns.drop_held("rh")
	g.items.clear()
	print("piston arm: smg fires normally %s, bare hand charges %s" % [smg_ok, g.player.piston_charges("R")])
	# a finger that cannot be used does not block the pistol under it
	g.new_game()
	g.guns.drop_held("rh")
	g.items.clear()
	g.add_item({kind = "finger"}, g.P.x, g.P.z)
	g.add_item({kind = "weapon", id = "pistol"}, g.P.x + 0.3, g.P.z)
	g.player.interact("R")
	print("pistol under a useless finger: picked up %s, finger left %s" % [g.P.parts.rh.held == "pistol", g.items.size() == 1 and g.items[0].kind == "finger"])
	# chest mix per floor
	for fl in [1, 5]:
		var cnt := {normal = 0, locked = 0, mimic = 0}
		g.floor_n = 0
		for i in fl:
			g.world.next_floor()
		for i in 30:
			g.world.gen_floor()
			for r in g.rooms:
				g.chests.clear()
				g.enemies.clear()
				g.room = r
				g.world.populate(r)
				for c in g.chests:
					cnt[c.type] += 1
		print("floor %d chests per floor: normal %.1f, locked %.1f, mimic %.1f" % [fl, cnt.normal / 30.0, cnt.locked / 30.0, cnt.mimic / 30.0])
	# surgeon never takes the last hand; losing both hands in a quiet room brings a stray one
	g.new_game()
	g.enemies.clear()
	g.P.parts.lh = null
	g.P.parts.le = null
	g.P.parts.lr = null
	g.P.parts.ll = null
	var last_ok := true
	for i in 40:
		g.altar = {x = g.P.x, z = g.P.z, used = false, m = null}
		for k in ["re", "rr", "rl"]:
			if g.P.parts[k] == null:
				g.P.parts[k] = {type = "flesh"}
		g.loot.use_altar("R")
		if g.P.parts.rh == null:
			last_ok = false
	g.P.parts.re = null
	g.P.parts.rr = null
	g.P.parts.rl = null
	g.altar.used = false
	g.loot.use_altar("R")
	print("surgeon leaves the last hand: %s (refused when only the hand is left: %s)" % [last_ok, g.P.parts.rh != null and not g.altar.used])
	print("surgeon offer with only the last hand: '%s'" % g.loot.altar_offer("R"))
	g.altar = null
	g.items.clear()
	g.body.lose_hand("rh")
	g.update(0.016)
	print("no hands in a quiet room -> stray hand appears: %s" % (g.items.any(func(i): return i.get("pk") in ["hand", "arm"])))
	print("full run: won %s, floor %d, steps %d" % [g.won, g.floor_n, steps])
	g.floor_n = 5
	test_room("elite", 6)
	_run(300)
	test_room("fight", 6)
	_run(300)
	print("late rooms: %s" % [g.enemies.map(func(e): return e.type)])
	# loot picker: the wheel chooses which of several items Q / E takes
	g.new_game()
	test_room("start")
	g.items.clear()
	for k in ["key", "scrap", "key"]:
		g.add_item({kind = k}, g.P.x + 0.3, g.P.z)
	var auto_pick = g.player.picked()
	g.player.cycle_pick(1)
	g.player.cycle_pick(1)
	var chosen = g.player.picked()
	var keys0: int = g.P.keys
	var scrap0: int = g.P.scrap
	g.player.interact("L")
	print("picker: %d in reach, wheel moved the pick %s, took the picked one %s, %d left" % [
		3, not is_same(auto_pick, chosen), not g.items.any(func(i): return is_same(i, chosen)),
		g.items.size()])
	print("picker: keys +%d scrap +%d" % [g.P.keys - keys0, g.P.scrap - scrap0])
	g.items.clear()
	# spikes never land in front of a door, where the player arrives
	g.floor_n = 4
	var spiked := 0
	var in_lane := 0
	for i in 200:
		test_room("fight", 6)
		spiked += g.spikes.size()
		for s in g.spikes:
			if g.world.in_door_lane(s.x, s.z, s.w, s.h):
				in_lane += 1
	print("spikes: %d placed in 200 rooms, %d in a door lane" % [spiked, in_lane])
	g.tests_parts.smoke_parts()
	g.tests_parts.smoke_limbs()
	g.debug_room.start_debug()
	var stock := g.items.size()
	var first: Dictionary = g.items[0]
	g.P.x = first.x
	g.P.z = first.z
	g.player.interact("L")
	for code in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7]:
		g.debug_room.debug_key(code)
	var spawned := g.enemies.size()
	_run(120)
	g.debug_room.debug_key(KEY_0)
	g.debug_room.debug_key(KEY_C)
	g.debug_room.debug_key(KEY_B)
	g.debug_room.debug_key(KEY_T)
	print("debug room: %d items stocked, %d after taking one, spawned %d enemies, %d after clearing, chests %d" % [stock, g.items.filter(func(i): return i.get("stock", false)).size(), spawned, g.enemies.size(), g.chests.size()])
	print("SMOKE DONE")

func _test_chest(x: float, type: String) -> Dictionary:
	var c := {x = x, z = 0.0, type = type, open = false, gone = false, hp = D.CHEST_HP, flash = 0.0, m = null}
	g.chests.append(c)
	return c

func _loot_never_quirky() -> bool:
	g.items = []
	for i in 500:
		g.loot.loot(0, 0, true)
	var ok := not g.items.any(func(i): return i.kind == "part" and i.type in D.QUIRKY_TYPES)
	g.items = []
	return ok

# Walks in direction dir until the room changes (through an open door and its corridor). True if it did.
func _walk(dir: String) -> bool:
	var from: int = g.room.idx
	g.t_move = Vector2(Game.DIRS[dir])
	for i in 400:
		_run(1)
		if g.room.idx != from:
			break
	g.t_move = Vector2.ZERO
	return g.room.idx != from

func test_room(type: String, depth := 0) -> void:
	var r := g.world.make_room(type)
	r.depth = depth
	g.world.enter_room(r, "")

func _path_dir() -> String:
	var q := [[g.room.idx, ""]]
	var seen := {g.room.idx: true}
	while not q.is_empty():
		var cur = q.pop_front()
		var r: Dictionary = g.rooms[cur[0]]
		if r.type == "exit":
			return cur[1]
		for dir in r.links:
			var o: int = r.links[dir]
			if not seen.has(o):
				seen[o] = true
				q.append([o, dir if cur[1] == "" else cur[1]])
	return ""
