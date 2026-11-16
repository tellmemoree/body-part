extends RefCounted
# All game content lives here: part types, weapons, enemies, rooms.
# Part fields: n = name, c = colour, t = tier (1 common, 2 rare, 3 legendary), tip = shown on pickup.

const TYPES := {
	"hand": {
		"flesh": {n = "hand", c = "e9a98c", t = 1},
		"fist": {n = "robot fist", c = "5fb4e0", t = 2, tip = "huge punch, smashes chests & doors, no guns"},
		"claw": {n = "claw", c = "c0392b", t = 1, tip = "very fast slashes, bleed; a pair goes into a frenzy"},
		"hook": {n = "hook hand", c = "c9c9d6", t = 1, tip = "yanks enemies & items to you"},
		"cannon": {n = "wrist cannon", c = "e0a030", t = 3, tip = "explosive shots, needs no fingers"},
		"maw": {n = "mimic maw", c = "b8862f", t = 3, tip = "bite heals on a kill, eats locks, mimics can't bite it"},
		"chainsaw": {n = "chainsaw hand", c = "d0d040", t = 3, tip = "hold to grind; shreds any chest it touches"},
		"tentacle": {n = "tentacle", c = "8a5ab0", t = 2, tip = "long whip that throws enemies away"},
		"pincer": {n = "crab pincer", c = "e06030", t = 1, tip = "snips limbs off enemies (always when they are stunned), snips locks"},
		"shield": {n = "shield arm", c = "7f8fa6", t = 1, tip = "hold to block bullets and hits from the front"},
		"syringe": {n = "syringe hand", c = "9fe0c0", t = 2, tip = "drains enemies to heal you, more from bleeding ones"},
		"torch": {n = "torch hand", c = "ff8a20", t = 1, tip = "sets enemies on fire, lights dark rooms"},
		"magnet": {n = "magnet hand", c = "d04040", t = 1, tip = "pulls items, bends enemy bullets away; click = pulse"},
		"gunhand": {n = "gun hand", c = "444455", t = 2, tip = "built-in pistol; fused on, cannot be swapped out"},
		"skeleton": {n = "skeleton hand", c = "e8e4d0", t = 1, tip = "fingers can't be lost, but it drops its gun when you are hit"},
		"baby": {n = "baby hand", c = "f6c8b8", t = 1, tip = "2 fingers, fires fast and weak, one-handed weapons only"},
		"grenade": {n = "grenade hand", c = "4a7a3a", t = 1, tip = "click throws the hand itself: big blast, hand gone"},
		"rotting": {n = "rotting hand", c = "7a8a4a", t = 2, tip = "triple damage, loses a finger every room"},
	},
	"arm": {
		"flesh": {n = "arm", c = "e9a98c", t = 1},
		"robot": {n = "robot arm", c = "5fb4e0", t = 1, tip = "no recoil, stronger knockback"},
		"long": {n = "long arm", c = "d9b99c", t = 1, tip = "more melee reach, picks things up from further away"},
		"piston": {n = "piston arm", c = "b0b0c0", t = 2, tip = "hold the click to charge a heavy hit"},
		"noodle": {n = "noodle arm", c = "f0d080", t = 2, tip = "huge reach, weak hits, shaky aim"},
		"forked": {n = "forked arm", c = "a070c0", t = 3, tip = "takes a second, artificial hand; one click uses both"},
		"boomerang": {n = "boomerang arm", c = "c08a3a", t = 2, tip = "click throws the whole arm; it comes back with its hand"},
	},
	"leg": {
		"flesh": {n = "leg", c = "e9a98c", t = 1},
		"robot": {n = "robot leg", c = "5fb4e0", t = 1, tip = "SPACE: damaging dash, kicks doors open; a pair hits twice as hard"},
		"spring": {n = "spring leg", c = "6fd36f", t = 1, tip = "SPACE: leap + shockwave"},
		"peg": {n = "peg leg", c = "8a5a2b", t = 1, tip = "slow, immune to spikes & knockback"},
		"crate": {n = "crate leg", c = "a9762f", t = 3, tip = "slow, SPACE: stomp shockwave"},
		"wheel": {n = "wheel", c = "303038", t = 1, tip = "fast, but slides when turning or stopping"},
		"tread": {n = "tank tread", c = "5a6a4a", t = 2, tip = "slow, no knockback, crushes spikes and crates"},
		"bird": {n = "bird leg", c = "e0c040", t = 2, tip = "SPACE: glide over obstacles"},
		"rocket": {n = "rocket leg", c = "e05030", t = 2, tip = "SPACE: long dash that leaves fire; with a spring leg: rocket leap"},
		"frog": {n = "frog leg", c = "3fae5f", t = 1, tip = "hold SPACE to charge a hop"},
		"ghost": {n = "ghost leg", c = "bfd8ff", t = 3, tip = "SPACE: phase through walls and enemies"},
		"stilt": {n = "stilt", c = "9a7a4a", t = 1, tip = "enemy melee often misses, but you turn slowly"},
		"tentacle": {n = "tentacle leg", c = "8a5ab0", t = 1, tip = "no hopping penalty when it is your only leg; no dodge"},
		"bomb": {n = "bomb leg", c = "303030", t = 1, tip = "SPACE: detonate it; huge blast, leg gone, you fly across the room"},
		"squeaky": {n = "squeaky leg", c = "ff80c0", t = 1, tip = "very fast, but enemies home in on the noise and move faster"},
	},
	"eye": {
		"flesh": {n = "eye", c = "ffffff", t = 1},
		"cyber": {n = "cyber eye", c = "ff3355", t = 1, tip = "shows enemy HP, mimics, laser sight; a pair makes bullets home"},
		"cat": {n = "cat eye", c = "d7f03c", t = 1, tip = "see in dark rooms"},
		"keyhole": {n = "keyhole eye", c = "ffd24a", t = 3, tip = "reveals nearby mimics and what is behind every door"},
		"thermal": {n = "thermal eye", c = "ff7030", t = 1, tip = "shows enemies in the dark and on your blind side"},
		"sniper": {n = "sniper eye", c = "70c0ff", t = 2, tip = "camera pulls back; bullets hit harder at range"},
		"fly": {n = "fly eye", c = "90a040", t = 1, tip = "enemy bullets move slower"},
		"evil": {n = "evil eye", c = "a020c0", t = 2, tip = "enemies in your line of aim are slowed"},
		"laser": {n = "laser eye", c = "ff2020", t = 3, tip = "fires a beam along your aim every few seconds"},
		"glass": {n = "glass eye", c = "c0e8f0", t = 1, tip = "sees nothing; pops out when you are hit and distracts enemies"},
		"mirror": {n = "mirror eye", c = "e0e0f0", t = 2, tip = "enemy shots at your front bounce back"},
	},
	"ear": {
		"flesh": {n = "ear", c = "e9a98c", t = 1},
		"bat": {n = "bat ear", c = "5a4a6a", t = 2, tip = "echo pulses show enemies you cannot see"},
		"cat": {n = "cat ear", c = "d0a060", t = 1, tip = "hears a mimic growl when you stand close"},
		"radar": {n = "radar dish", c = "a0b0c0", t = 2, tip = "shows where enemy shots are heading"},
	},
	"jaw": {
		"flesh": {n = "jaw", c = "e9a98c", t = 1},
		"shark": {n = "shark jaw", c = "90a0b0", t = 2, tip = "F: lunging bite"},
		"howler": {n = "howler", c = "c0a0e0", t = 2, tip = "F: shout that stuns everything near you"},
		"spitter": {n = "acid spitter", c = "a0e040", t = 2, tip = "F: acid spit; a weapon that needs no hands"},
		"fangs": {n = "vampire fangs", c = "f0f0f0", t = 2, tip = "F: bite; kills heal you, bleeding prey feeds you"},
	},
	"skin": {
		"flesh": {n = "skin", c = "e9a98c", t = 1},
		"plated": {n = "plated skin", c = "8090a0", t = 1, tip = "blocks the first hit in every room"},
		"spiked": {n = "spiked skin", c = "707070", t = 1, tip = "hurts enemies that touch you"},
		"rubber": {n = "rubber skin", c = "e060a0", t = 2, tip = "enemy shots bounce off; you get knocked around more"},
		"stitched": {n = "stitched skin", c = "b08a6a", t = 1, tip = "parts are much harder to sever"},
		"glass": {n = "glass skin", c = "c0f0ff", t = 3, tip = "double damage dealt and taken"},
		"hive": {n = "hive skin", c = "c0a020", t = 2, tip = "releases biting flies when you are hit"},
		"chameleon": {n = "chameleon skin", c = "40a080", t = 2, tip = "stand still and enemies lose track of you"},
	},
	"organ": {
		"heart2": {n = "second heart", c = "e0406a", t = 1, tip = "+2 max HP"},
		"adrenal": {n = "adrenal gland", c = "ff8a2a", t = 2, tip = "faster for every missing part"},
		"liver": {n = "regen liver", c = "9a4a6a", t = 1, tip = "heal 1 HP per cleared room"},
		"lungs": {n = "iron lungs", c = "8090b0", t = 1, tip = "SPACE recharges faster"},
		"stomach": {n = "second stomach", c = "d08080", t = 1, tip = "hearts heal double"},
		"bile": {n = "bile sac", c = "a0c030", t = 1, tip = "sprays acid around you when you are hit"},
		"kidney": {n = "spare kidney", c = "a04040", t = 2, tip = "survives one lethal hit, then it is gone"},
		"blackheart": {n = "black heart", c = "301020", t = 2, tip = "more damage the lower your health"},
		"marrow": {n = "marrow", c = "f0e0c0", t = 1, tip = "regrows one lost finger per cleared room"},
		"pacemaker": {n = "pacemaker", c = "60d0d0", t = 2, tip = "brief slow motion when you are hit"},
		"tapeworm": {n = "tapeworm", c = "e0d0a0", t = 1, tip = "-1 max HP; enemies drop more hearts"},
		"lizard": {n = "lizard gland", c = "40c040", t = 3, tip = "regrows one lost limb per floor"},
		"bombheart": {n = "bomb heart", c = "ff5020", t = 2, tip = "every part you lose explodes"},
	},
}

# Shown on the Tab screen for plain flesh parts and for empty slots.
const BASE_TIP := {
	"eye": "sees its side of the screen; two eyes aim straight",
	"ear": "points at enemies you cannot see on its side",
	"jaw": "F: weak bite; eats hearts",
	"skin": "nothing special",
	"arm": "carries a hand",
	"hand": "jab; holds weapons, opens chests and doors; fewer fingers = slower trigger and reload",
	"leg": "walk; SPACE: roll (needs both legs)",
}
const MISSING_TIP := {
	"eye": "blind on that side, shots spread; no eyes: nearly blind",
	"ear": "cannot hear unseen enemies on that side",
	"jaw": "cannot bite or eat hearts",
	"arm": "no arm, so no hand on that side",
	"hand": "that click does nothing; cannot open chests or doors with that side",
	"leg": "hopping, slower, most SPACE moves fail; no legs: crawling",
	"organ": "empty organ slot",
}

# slot -> [kind, label]
const SLOT := {
	"le": ["eye", "L eye"], "re": ["eye", "R eye"],
	"lr": ["ear", "L ear"], "rr": ["ear", "R ear"],
	"jaw": ["jaw", "jaw"], "skin": ["skin", "skin"],
	"la": ["arm", "L arm"], "ra": ["arm", "R arm"],
	"lh": ["hand", "L hand"], "rh": ["hand", "R hand"],
	"ll": ["leg", "L leg"], "rl": ["leg", "R leg"],
	"o1": ["organ", "organ 1"], "o2": ["organ", "organ 2"], "o3": ["organ", "organ 3"],
}
# Quirky parts are only made by combining scrap from destroyed chests.
const QUIRKY := [["hand", "maw"], ["leg", "crate"], ["eye", "keyhole"]]
const QUIRKY_TYPES := ["maw", "crate", "keyhole"]
const SCRAP_NEEDED := 5
const CHEST_HP := 5
const KEYS_PER_FLOOR := [1, 2]  # every floor gives out this many keys in total (min, max)
const KEY_CHANCE := 0.04  # chance a normal kill drops one of them; elites always do, the exit guardian drops the rest
const SAW_SCRAP := 0.5  # chance a chainsawed chest still leaves scrap
const MIMIC_SENSE := {"keyhole": 6.0, "cat": 4.0}  # how close these parts must be to notice a mimic

# Parts that can come off (skin and organs cannot).
const LIMBS := ["le", "re", "lr", "rr", "jaw", "la", "ra", "lh", "rh", "ll", "rl"]
const ORDER := ["le", "re", "lr", "rr", "jaw", "skin", "la", "lh", "ra", "rh", "ll", "rl", "o1", "o2", "o3"]
const ORGS := ["o1", "o2", "o3"]
const SIDE := {
	"L": {"eye": "le", "ear": "lr", "arm": "la", "hand": "lh", "leg": "ll", "jaw": "jaw", "skin": "skin"},
	"R": {"eye": "re", "ear": "rr", "arm": "ra", "hand": "rh", "leg": "rl", "jaw": "jaw", "skin": "skin"},
}
# Hands that can hold weapons.
const GRIP := ["flesh", "skeleton", "baby", "rotting"]
# What SPACE does on a single leg: speed / distance multiplier. A leg type not listed cannot do its move alone.
const ONE_LEG := {"wheel": 0.5, "rocket": 0.5, "spring": 0.5, "frog": 0.5, "ghost": 1.0, "bomb": 1.0, "crate": 1.0}
const LEG_SPD := {"robot": 1.1, "peg": 0.9, "crate": 0.9, "wheel": 1.3, "tread": 0.75, "squeaky": 1.35, "bomb": 0.95}
# Loot weight per tier: [common, rare, legendary]
const TIER_W := [6, 3, 1]
const TIER_W_RARE := [3, 3, 2]

# mag = shots per magazine, ammo = total shots in a fresh gun (first magazine included), reload = seconds.
# A gun with nothing left is thrown away. The knife needs none.
# With no weapon and no weapon-like hand, each kill has this chance to drop one of these.
const UNARMED_DROP := 0.25
const UNARMED_GUNS := ["pistol", "knife"]

const GUNS := {
	"pistol": {n = "pistol", hands = 1, fingers = 3, cd = 0.32, dmg = 1.0, spd = 30.0, spread = 0.03, len = 0.5, mag = 8, ammo = 80, reload = 0.9},
	"smg": {n = "SMG", hands = 1, fingers = 4, cd = 0.085, dmg = 0.45, spd = 28.0, spread = 0.16, len = 0.7, mag = 30, ammo = 120, reload = 1.3},
	"shotgun": {n = "shotgun", hands = 2, fingers = 2, cd = 0.75, dmg = 1.0, spd = 26.0, spread = 0.45, pellets = 6, recoil = 11.0, life = 0.45, len = 1.1, mag = 4, ammo = 16, reload = 1.6},
	"sniper": {n = "sniper", hands = 2, fingers = 3, cd = 1.1, dmg = 5.0, spd = 70.0, spread = 0.0, pierce = true, len = 1.6, mag = 3, ammo = 9, reload = 1.8},
	"knife": {n = "knife", hands = 1, fingers = 1, melee = true, cd = 0.28, dmg = 2.0, range = 2.7, arc = 1.0, len = 0.6},
}

# limbs: what can be cut off. Legs slow it, arms weaken its attack, a spitter's eye is its aim, a mimic's jaw its bite.
const ENEMY := {
	"grunt": {hp = 3, spd = 4.3, r = 0.7, c = "cc4444", sev = 0.4, limbs = ["la", "ra", "ll", "rl"]},
	"spitter": {hp = 2, spd = 3.2, r = 0.6, c = "cc55aa", sev = 0.3, limbs = ["eye"]},
	"slasher": {hp = 2, spd = 7.2, r = 0.55, c = "dd7733", sev = 0.6, limbs = ["la", "ra", "ll", "rl"]},
	"leaper": {hp = 3, spd = 3.5, r = 0.65, c = "4fa34f", sev = 0.4, limbs = ["ll", "rl"]},
	"brute": {hp = 9, spd = 2.7, r = 1.2, c = "556688", sev = 0.75, kb = 16.0, limbs = ["la", "ra", "ll", "rl"]},
	"mimic": {hp = 7, spd = 6.3, r = 0.9, c = "9a6a2a", sev = 0.6, limbs = ["jaw"]},
}

const ROOMS := {
	"start": "START",
	"debug": "DEBUG ROOM",
	"exit": "EXIT - guarded",
	"fight": "FIGHT",
	"treasure": "TREASURE - chests",
	"surgeon": "SURGEON - trade flesh for parts",
	"dark": "DARK - better loot",
	"elite": "ELITE - big guy, big reward",
}
const DOOR_UNKNOWN := "707078"  # door to a room the player cannot identify yet ("?")
const DOOR_COLOR := {"start": "55556a", "debug": "55556a", "exit": "dd3333", "fight": "3a8a5a", "treasure": "b9892f", "surgeon": "8a4a9a", "dark": "2a2a44", "elite": "aa5522"}
