extends RefCounted
# The debug room: every part and weapon on the floor, restocking, and debug keys.

const D = preload("res://src/data.gd")
const Game = preload("res://src/game.gd")

var g: Game

func _init(game: Game) -> void:
	g = game

# One big empty room with every part, weapon and pickup laid out. Stock comes back when taken.
const DEBUG_ENEMIES := ["grunt", "spitter", "slasher", "leaper", "brute", "mimic"]

const DEBUG_HELP := [
	"DEBUG ROOM",
	"1-6  spawn grunt, spitter, slasher, leaper, brute, mimic",
	"7  spawn elite brute",
	"0  remove all enemies",
	"H  heal        G  god mode",
	"B  reset body  T  restock items and chests",
	"C  count as a cleared room (liver, marrow, rotting hand...)",
]

func start_debug() -> void:
	g.new_game()
	g.debug = true
	g.rooms = []
	var r := g.world.make_room("debug")
	r.hw = 30.0
	r.hh = 20.0
	g.rooms.append(r)
	g.world.build_floor()
	g.world.enter_room(r, "")
	g.P.x = 0.0
	g.P.z = 15.0
	stock_debug()
	g.state = "play"
	g.menu.close()
	g.say("Debug room. Everything on the floor comes back when you take it.", 6.0)

func debug_item(d: Dictionary, x: float, z: float) -> void:
	d.stock = true
	d.sx = x
	d.sz = z
	g.add_item(d, x, z)

func stock_debug() -> void:
	g.items = g.prune(g.items, func(_i): return false)
	g.chests = g.prune(g.chests, func(_c): return false)
	var z := -17.5
	for kinds in [["hand"], ["arm"], ["leg"], ["eye"], ["ear", "jaw"], ["skin"], ["organ"]]:
		var col := 0
		for pk in kinds:
			for t in D.TYPES[pk]:
				if col == 12:
					col = 0
					z += 2.3
				debug_item({kind = "part", pk = pk, type = t}, -24.2 + col * 4.4, z)
				col += 1
		z += 2.3
	var col2 := 0
	for id in D.GUNS:
		debug_item({kind = "weapon", id = id}, -24.2 + col2 * 4.4, z)
		col2 += 1
	for k in ["heart", "finger", "key", "scrap", "ammo"]:
		debug_item({kind = k}, -24.2 + col2 * 4.4, z)
		col2 += 1
	var cx := 12.0
	for ct in ["normal", "locked", "mimic"]:
		g.chests.append({x = cx, z = 11.0, type = ct, open = false, gone = false, hp = D.CHEST_HP, flash = 0.0, m = null})
		cx += 5.0

func reset_body() -> void:
	g.P.parts = {
		le = {type = "flesh"}, re = {type = "flesh"}, lr = {type = "flesh"}, rr = {type = "flesh"},
		jaw = {type = "flesh"}, skin = {type = "flesh"},
		la = g.body.new_part("arm", "flesh"), ra = g.body.new_part("arm", "flesh"),
		lh = g.body.new_hand("flesh"), rh = g.body.new_hand("flesh"),
		ll = {type = "flesh"}, rl = {type = "flesh"}, o1 = null, o2 = null, o3 = null,
	}
	g.guns.give_gun("rh", "pistol")
	g.P.plate = false
	g.P.hp = g.body.max_hp()
	g.dirty = true

# Returns true when the key was a debug command.
func debug_key(code: int) -> bool:
	var n: int = code - KEY_1
	if n >= 0 and n < DEBUG_ENEMIES.size():
		g.ai.spawn(DEBUG_ENEMIES[n])
		return true
	match code:
		KEY_7:
			g.ai.spawn("brute", {elite = true})
		KEY_0:
			g.enemies = g.prune(g.enemies, func(_e): return false)
			g.bullets = g.prune(g.bullets, func(_b): return false)
		KEY_H:
			g.P.hp = g.body.max_hp()
			g.over = false
		KEY_G:
			g.god = not g.god
			g.say("God mode %s." % ("on" if g.god else "off"), 2.0)
		KEY_B:
			reset_body()
			g.say("Body reset.", 2.0)
		KEY_T:
			stock_debug()
			g.say("Restocked.", 2.0)
		KEY_C:
			g.room.type = "fight"
			g.world.clear_room()
			g.room.type = "debug"
		_:
			return false
	return true
