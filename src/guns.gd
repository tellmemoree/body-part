extends RefCounted
# Held weapons: giving, dropping, ammo, magazines and reloading.

const D = preload("res://src/data.gd")
const Game = preload("res://src/game.gd")

var g: Game

func _init(game: Game) -> void:
	g = game

# Bare hands only: at least one hand that could hold a weapon, and nothing to fight with but punches.
func unarmed() -> bool:
	var grip := false
	for k in ["lh", "rh"]:
		var h = g.P.parts[k]
		if h == null:
			continue
		if h.held != null or not g.body.can_grip(h):
			return false
		grip = true
	return grip

func side_of(hand_slot: String) -> String:
	return "L" if hand_slot == "lh" else "R"

# The hand slots holding the weapon in slot s: both for a two-handed gun.
func gun_slots(s: String) -> Array:
	var h = g.P.parts[s]
	if h != null and h.held != null and D.GUNS[h.held].hands == 2:
		return ["lh", "rh"]
	return [s]

# Puts a weapon in a hand (both hands if it is two-handed). mag / res < 0 means a fresh, full gun.
func give_gun(s: String, id: String, mag := -1, res := -1) -> void:
	var gun = D.GUNS[id]
	if mag < 0:
		mag = gun.get("mag", 0)
		res = gun.get("ammo", 0) - mag
	for k in (["lh", "rh"] if gun.hands == 2 else [s]):
		g.P.parts[k].held = id
		g.P.parts[k].mag = mag
		g.P.parts[k].res = res

# Missing fingers make the trigger and the reload slower.
func finger_slow(h: Dictionary) -> float:
	return 1.0 + (5 - h.fingers) * 0.15 if h.type in ["flesh", "rotting"] else 1.0

func start_reload(s: String) -> bool:
	var h = g.P.parts[s]
	if h == null or h.held == null or g.P["rl" + side_of(s)] > 0:
		return false
	var gun = D.GUNS[h.held]
	if not gun.has("mag") or h.mag >= gun.mag or h.res <= 0:
		return false
	for k in gun_slots(s):
		g.P["rl" + side_of(k)] = gun.reload * finger_slow(h) / g.body.haste()
	return true

func finish_reload(s: String) -> void:
	var h = g.P.parts[s]
	if h == null or h.held == null or not D.GUNS[h.held].has("mag"):
		return
	var n: int = mini(D.GUNS[h.held].mag - h.mag, h.res)
	h.mag += n
	h.res -= n

# One shot leaves the magazine. An empty magazine reloads by itself; a gun with nothing left is thrown away.
func spend_shot(s: String) -> void:
	var h = g.P.parts[s]
	var gun = D.GUNS[h.held]
	var slots := gun_slots(s)
	for k in slots:
		g.P.parts[k].mag -= 1
	if h.mag > 0:
		return
	if h.res > 0:
		start_reload(s)
		return
	for k in slots:
		g.P.parts[k].held = null
	g.say("The %s is empty. You toss it." % gun.n)
	g.dirty = true

func drop_held(s: String) -> void:
	var h = g.P.parts[s]
	if h == null or h.get("held") == null:
		return
	var id: String = h.held
	var it := {kind = "weapon", id = id}
	if D.GUNS[id].has("mag"):  # a dropped gun keeps its count
		it.mag = h.mag
		it.res = h.res
	if D.GUNS[id].hands == 2:
		for k in ["lh", "rh"]:
			if g.P.parts[k] != null and g.P.parts[k].held == id:
				g.P.parts[k].held = null
		g.P.rlL = 0.0
		g.P.rlR = 0.0
	else:
		h.held = null
		g.P["rl" + side_of(s)] = 0.0
	g.add_item(it, g.P.x + randf_range(-1.5, 1.5), g.P.z + randf_range(-1.5, 1.5))
	g.dirty = true

# R: reload every gun whose magazine is not full.
func reload_all() -> void:
	if g.over or g.P.is_empty():
		return
	for s in ["lh", "rh"]:
		start_reload(s)
