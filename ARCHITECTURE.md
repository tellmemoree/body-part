# Spare Parts: architecture

How the Godot prototype is put together, for anyone (person or agent) about to change it.
What the game is and what is planned lives in [PLAN.md](PLAN.md); this file covers how the code works.

## At a glance

- Godot 4.7, GDScript, Forward+ renderer, 1280×720 window that stretches.
- No art assets and no hand-built scenes: every mesh is a box, sphere, cylinder or cone built in code,
  and every UI element is drawn or created in code.
- Game state is plain dictionaries and arrays, not nodes. 3D nodes are only a view of that state and are
  rebuilt from it.
- One scene (`main.tscn`) holding one node (`Main`, a `Node3D` running `src/game.gd`). That node owns
  all state; the rest of the logic is split into modules that work on it.

## Files

| File | Lines | What it holds |
|---|---|---|
| `src/game.gd` | ~420 | The game node: all shared state, setup, input, menus, `new_game()` and the frame loop `update()`. Small helpers used everywhere (`say`, `d2`, `nearest`, `prune`, `add_item`, `clamp_pos`, `in_block`) |
| `src/player.gd` | ~530 | What the player does: walking, dashes and leg abilities (`ability`), hand actions (`act`, `use_hand`), jaw, picking things up (`interact`, `take_item`, the loot picker: `in_reach`, `picked`, `cycle_pick`) |
| `src/body.gd` | ~470 | The body: part queries (`has_type`, `has_org`, `legs`, `power`, `reach`…), losing parts (`sever`, `hurt`), attaching parts (`attach`), new parts, labels for the HUD and Tab screen |
| `src/guns.gd` | ~110 | Held weapons: `give_gun`, `drop_held`, ammo, magazines, reloading |
| `src/combat.gd` | ~280 | Damage to enemies: `hit`, `melee`, `shoot`, `explode`, status effects, cutting enemy limbs, bullets and thrown arms every frame |
| `src/enemies.gd` | ~210 | Enemies: `spawn`, pathfinding, their behaviour every frame |
| `src/loot.gd` | ~200 | Loot rolls, enemy drops, opening / smashing / breaking chests, mimics, the surgeon, the stray-hand rescue |
| `src/world.gd` | ~500 | Floors and rooms: generation, layouts, floor geometry (rooms, corridors, fog), entering rooms, walking between them, populating, clearing, doors, stairs, floor hazards |
| `src/view.gd` | ~370 | Meshes for the player and everything in the room, doors, the camera, the vision overlay |
| `src/shapes.gd` | ~50 | Static mesh helpers: `box`, `ball`, `cyl`, `cone`, `grp`, `mat` |
| `src/debug_room.gd` | ~120 | The debug room and its keys |
| `src/data.gd` | ~200 | Content and tuning tables only (parts, guns, enemies, rooms, drop rates). No logic |
| `src/hud.gd` | ~320 | Immediate-mode drawing: labels over the 3D world, the HUD, the minimap, the Tab screen |
| `src/menu.gd` | ~80 | Main menu and pause menu (real `Control` buttons) |
| `tests/smoke.gd` | ~650 | Automated checks (`--smoke`) and the screenshot scenes (`--shot`) |
| `tests/smoke_parts.gd` | ~200 | Automated checks for every part type and for enemy limbs |
| `main.tscn` | 6 | The single root node with `src/game.gd` attached |
| `index.html` | ~500 | The original browser prototype, kept for reference. Not used by the Godot project |

## How modules fit together

```
src/game.gd  (the node, owns the state)
 ├── var player     := Player.new(self)
 ├── var body       := Body.new(self)
 ├── var guns       := Guns.new(self)
 ├── var combat     := Combat.new(self)
 ├── var ai         := Enemies.new(self)
 ├── var loot       := Loot.new(self)
 ├── var world      := World.new(self)
 ├── var view       := View.new(self)
 ├── var debug_room := DebugRoom.new(self)
 └── var tests, tests_parts
```

Every module is a `RefCounted` with the same header:

```gdscript
const D = preload("res://src/data.gd")
const Game = preload("res://src/game.gd")
var g: Game

func _init(game: Game) -> void:
	g = game
```

- **State** is always reached through `g`: `g.P`, `g.enemies`, `g.room`, `g.floor_n`.
- **Calls into another module** go through `g` and the module's name: `g.body.sever("lh")`,
  `g.combat.hit(e, 2.0)`, `g.loot.loot(x, z)`. Calls inside the same module are plain: `sever("lh")`.
- **Helpers on the game node** are `g.say(...)`, `g.d2(a, b)`, `g.nearest(...)`, `g.prune(...)`.
- **Constants** of the game node: `Game.FLOORS`, `Game.DIRS`, `Game.OPP`. Content tables: `D.GUNS` and so on.
- `g` is typed (`Game`), so the editor autocompletes and checks names, and `:=` keeps working.
- `hud.gd` and `menu.gd` are UI nodes; they also hold the game node as `g` (untyped) and call into
  modules the same way: `g.body.hand_label("rh")`, `g.world.room_label(d.to)`.

The game node and the modules preload each other. Godot 4.7 handles that cycle; no `class_name` is used,
so nothing depends on the editor's global class cache.

## Scene tree (built in `_build_world()`)

```
Main (Node3D, src/game.gd)
├── WorldEnvironment        background colour, ambient light (dimmed in dark rooms)
├── DirectionalLight3D sun  shadows; dimmed in dark rooms
├── Camera3D cam            fixed tilted top-down view; follows the player, kept inside the room during a fight
├── Node3D floor_g          the whole floor: every room's floor, walls, obstacles, doors, fog, and the corridors.
│                           Built in world coordinates, shifted so the current room's centre is at the origin
├── Node3D room_g           every enemy, item, chest, bullet, spike patch of the current room
├── Node3D pg               the player's body, rebuilt whenever a part changes
└── CanvasLayer
    ├── Hud (world = true)  labels and effects projected onto the 3D world
    ├── ColorRect vision    shader that blacks out what the eyes cannot see
    ├── Hud (world = false) screen HUD: health, keys, body panel, action bar, minimap, Tab screen
    └── Menu                main and pause menus
```

`hud.gd` is used twice: the `world` flag picks whether it draws in-world overlays or the screen HUD.
The vision overlay sits between them, so labels on things you cannot see are darkened while the HUD is not.
Modules are not nodes and do not appear in the tree.

## Frame loop

```
_process(dt)                       src/game.gd
├── dt capped at 0.05 s
├── update(dt)                     only when state == "play" and the run is not over
│   ├── timers, aim (mouse ray onto the ground plane)
│   ├── player.update_movement     walking, dashes, leg abilities, knockback, treads, corridors (world.check_transit)
│   ├── player.update_hands        held clicks and piston charge, reload timers, jaw, laser eye
│   ├── combat.update_flyers       thrown boomerang arms, burning ground
│   ├── combat.update_bullets      both sides' bullets, homing, reflection, hits
│   ├── ai.update_enemies          status effects, movement and attacks, pushing apart
│   ├── world.update_hazards       spikes, magnet pull, parts rotting on the floor
│   └── prune the dead, drops, queued mimics, room cleared?
├── view.render()                  every frame, also when paused (keeps meshes in sync)
└── screenshot                     only in --shot mode: save the frame after 30 frames and quit
```

The order of the steps matters (and random numbers are drawn in this order, which the seeded test
relies on). Discrete input (Q, E, Space, R, Tab, Esc, debug keys) arrives in `_unhandled_input()`; held
input (mouse buttons, WASD, F) is polled inside the steps.

### Game states

`state` is one of `"menu"`, `"play"`, `"paused"`, `"info"` (Tab screen). Only `"play"` runs `update()`,
so pausing and the Tab screen freeze the game simply by not updating it. `over` (and `won`) mark the
end of a run on top of `"play"`.

## State model

All mutable state is in `src/game.gd` member variables. Everything is a `Dictionary` with an `m` field
that holds its mesh (or `null` when it has none yet).

| Variable | What it is |
|---|---|
| `P` | The player: position, velocity, hp, keys, scrap, cooldown timers (`cdL`, `cdR`, `cdSp`, `cdJ`), charge (`chL`/`chR`), reload (`rlL`/`rlR`), and `parts` |
| `P.parts` | 15 body slots keyed by short names (below). `null` means the part is missing |
| `enemies`, `bullets`, `items`, `chests`, `spikes`, `doors`, `fx`, `fires`, `flyers` | Everything in the current room |
| `room` | The current room dictionary; `rooms` is every room on the floor |
| `floor_n`, `keys_left`, `kills`, `time` | Run progress |
| `dirty` | Set to `true` whenever the body changes; the next `render()` rebuilds the player model |
| `msg`, `msg_t` | The one message line on screen; set with `say(text, seconds)` |
| `t_move`, `t_aim`, `t_lmb`, `t_rmb`, `t_f`, `t_space` | Fake input for the tests; `null` / `false` in normal play |

### Body slots

| Slot | Part | Slot | Part |
|---|---|---|---|
| `le`, `re` | left / right eye | `la`, `ra` | left / right arm |
| `lr`, `rr` | left / right ear | `lh`, `rh` | left / right hand |
| `jaw` | jaw | `ll`, `rl` | left / right leg |
| `skin` | skin (never severed) | `o1`, `o2`, `o3` | organs |

`src/data.gd` has the lookup tables around them: `SLOT` (slot → kind and label), `SIDE` (`"L"`/`"R"` →
that side's slots), `ORDER` (display order), `LIMBS` (what can be severed), `ORGS`.

A part is `{type = "..."}`, with extras by kind:

- Arm: `hand2` (the forked arm's second hand), `out` (a thrown boomerang arm is away).
- Hand: `fingers`, `maxf` (fingers lost to locks lower this for good), `held` (gun id or `null`),
  `mag` and `res` (bullets in the magazine and in reserve). Create hands with `body.new_hand()`, other
  parts with `body.new_part()`.
- A two-handed gun is stored on both hands with the same `held`, `mag` and `res`; `guns.gun_slots()`
  returns both slots and `guns.give_gun()` / `guns.spend_shot()` keep them in step.
- An arm is the base for its hand: no arm, no hand. Use `body.arm_of()` and `body.hand_of()`.

Items on the floor are `{kind, x, z, ...}` with `kind` one of `part`, `weapon`, `heart`, `finger`, `key`,
`scrap`. A dropped gun carries its `mag`/`res`; a severed part may carry `rot` (seconds until it rots
away). Always create them with `g.add_item()`.

## Floors and rooms (`src/world.gd`)

```
new_game() → world.next_floor() → world.gen_floor() → world.build_floor() → world.enter_room(start)
                                                                                 │
   player walks out of a corridor: world.check_transit() → enter_room(next, dir, walked = true)
```

- Seamless floors: every room has a fixed place in one world, `room_off(r)` (`r.ox`, `r.oz`), set by
  `place_rooms()`: each grid column is as wide as its widest room and each row as deep as its deepest,
  `CORRIDOR_MIN` apart (in `data.gd`). `build_floor()` builds all rooms (`build_room_geo()`: floor, walls
  with a `DOOR_W` gap per link, a door mesh per link in `r.door_m`, obstacles, a fog block in `r.fog_m`)
  and one corridor per link (`build_corridor()`) under `g.floor_g`.
- Game logic still runs in the current room's own coordinates (centre 0, 0; walls at `AW` / `AH`).
  `g.floor_g` is moved by minus the room's offset so the two line up. When the player walks into the
  next room, `enter_room(..., walked = true)` shifts the player and `g.cam_t` by the difference between
  the two rooms' offsets, so the screen does not jump.
- Doors: `try_door()` only opens a door (both sides). An open door is a gap; `g.in_corridor()` (called
  from `clamp_pos()` for the player only) lets the player into the doorway and its corridor while no
  enemies are left. Once past the far room's wall line (`past_wall(d) > d.len`), that room becomes current.
- Unvisited rooms are under a block of the background colour, their obstacles hidden; `reveal()` lifts it
  on the first visit.

- `gen_floor()`: grows 10–15 rooms on a grid from the start room, keeping it branchy, adds a few loops,
  measures each room's `depth` from the start (breadth-first), then assigns types: the deepest room
  (dead ends preferred) is the exit; two treasure rooms and a surgeon go to dead ends first; the rest
  roll for dark or elite. Each room then gets a size and obstacle style from `gen_layout()`.
- `enter_room()`: saves the old room's items, chests, spikes, altar and stairs back into its dictionary
  (`stash_room()`), clears the room's entity meshes, loads the new room's lists, shifts `floor_g`, keeps
  the player where they walked in (or places them at a wall when not walking, e.g. a new floor or tests),
  builds the pathfinding grid and creates the door dictionaries (with `len`, the corridor length).
  On the first visit it calls `populate()` to spawn enemies, chests, spikes or the surgeon's altar.
- Rooms remember their loot because the lists are stored in the room dictionary, not in nodes.
- `diff()` is the difficulty number: it grows by 2.5 per floor and 0.4 per room of depth, and feeds
  enemy count and hit points.
- Room size: fight-type rooms are `ROOM_HW` x `ROOM_HH` (half sizes), mostly bigger than the screen.
  `area_k(r)` is how much bigger than `ROOM_REF` (the size the numbers were tuned for) a room is; the
  enemy budget grows with `area_k ^ ROOM_FILL`, crates and spike patches with `area_k`.
- Room types and their labels are in `data.gd` `ROOMS`; door colours in `DOOR_COLOR`. `room_known()`
  decides whether a door shows its room's name and colour or a grey "?".

### Pathfinding (`src/enemies.gd`)

`build_solid()` turns the room into a 1×1 grid of blocked and open cells. `flood()` runs a breadth-first
search from the player's cell (refreshed every 0.2 s) and stores steps-to-player per cell; `ff_dir()`
lets an enemy walk downhill on that field. Rooms without obstacles skip it and enemies walk straight.

## The body as the control scheme

| Input | Code path |
|---|---|
| Left / right click | `player.update_hands()` → `player.act(side)` → `player.use_hand()` for that hand (and the forked arm's second hand). Every hand type is a `match` branch that returns its cooldown |
| Q / E | `player.interact(side)`: pick up the item chosen with the wheel, or the nearest usable one, else open a chest, use the altar, take the stairs, open a door |
| Mouse wheel | `player.cycle_pick(step)`: with several items in reach, choose which one Q / E takes (`g.pick`, `g.pick_chosen`) |
| F | `player.jaw_act()` |
| Space | `player.ability()`: what it does depends on the legs (`body.leg_move()`), and on one leg only if `ONE_LEG` allows it |
| R | `guns.reload_all()` (restart when the run is over) |

Losing parts goes through `body.sever()` (random or given slot, drops the part as an item) and
`body.hurt()` (damage, shields, stilts, severing chance). `body.lose_hand()`, `guns.drop_held()` and
`body.check_grip()` keep hands and guns consistent. After any change to `P.parts`, set `g.dirty = true`.

Passive effects are checked where they matter with small helpers in `body.gd`: `has_type(slots, type)`,
`has_org()`, `skin_is()`, `both()` (pair bonuses), `power()` (damage multiplier), `haste()`, `reach()`,
`eyes()`. There is no effect system to register with; to add a part, add it to `data.gd` `TYPES` and add
its behaviour at the place it affects (for example a new hand is a new branch in `player.use_hand()`).

## Rendering (`src/view.gd`, `src/shapes.gd`)

- The player model is rebuilt from scratch in `build_player()` whenever `g.dirty` is set.
- Everything else is created once per object by `sync(list, mk_fn)`: if an object's `m` is `null`, the
  `mk_*` function builds a mesh group for it; every frame the mesh is moved to the object's `x`/`z`.
  Per-frame changes (chest lid, enemy flash and scale) are applied in `render()` after sync.
- Doors of every room are updated in `update_doors()`: open ones are hidden, the current room's show the
  colour of the room behind them (red while sealed).
- Camera: `update_camera()` follows the player; while enemies are alive the target is clamped so the
  view stays inside the room (`view_extent()` measures how much floor the camera shows).
- Mesh helpers are static functions in `shapes.gd`: `Shapes.box()`, `Shapes.ball()`, `Shapes.cyl()`,
  `Shapes.cone()`, `Shapes.grp()`, `Shapes.mat()`.
- Text over the world (item names, chest labels, door labels) is drawn in 2D by `hud.gd` using
  `cam.unproject_position()`; it is not part of the 3D scene.
- Vision: `VISION_SHADER` (in `game.gd`) darkens a ring around the player (dark rooms, missing eyes) or
  one half of the screen (one eye missing); `render()` sets it from `vis_radius` and `vis_side`.

## Content and tuning (`src/data.gd`)

Every number a designer is likely to change is here, not in the logic:

| Table | Holds |
|---|---|
| `TYPES` | All 81 parts by kind: name, colour, tier (1 common, 2 rare, 3 legendary), pickup tip |
| `GUNS` | Weapons: hands needed, fingers needed, cooldown, damage, spread, magazine, total ammo, reload time |
| `ENEMY` | Enemy hit points, speed, size, chance to sever your parts, which limbs they have |
| `ROOMS`, `DOOR_COLOR`, `DOOR_UNKNOWN` | Room labels and door colours |
| `TIER_W`, `TIER_W_RARE` | Loot rarity weights |
| `KEYS_PER_FLOOR`, `KEY_CHANCE` | Keys per floor and how they drop |
| `LOCK_CHANCE`, `DARK_LOCK`, `FIGHT_CHEST` | Chest mix per floor |
| `SCRAP_NEEDED`, `CHEST_HP`, `SAW_SCRAP`, `QUIRKY` | Scrap and quirky parts |
| `ONE_LEG`, `LEG_SPD`, `GRIP` | Leg and hand rules |
| `UNARMED_DROP`, `UNARMED_GUNS` | Weapon drops when you are bare-handed |
| `BASE_TIP`, `MISSING_TIP` | Text for the Tab screen |

Every script loads it as `const D = preload("res://src/data.gd")` (`D.GUNS.pistol.mag` and so on).

## Debug room and testing

There is no test framework. The game can drive itself from command-line flags given after `--`:

```bash
/Users/vzwinner/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . -- --smoke
```

`--smoke` runs `tests/smoke.gd` `smoke()`, which ends with `tests/smoke_parts.gd` (`smoke_parts()`,
`smoke_limbs()`). They set up rooms, fake input through `t_move`, `t_aim`, `t_lmb`, `t_rmb`, `t_f`,
`t_space`, step the game with `_run(frames)` and print one line per check (around 100 lines). A GDScript
error, or a line whose numbers look wrong, is a failure; nothing asserts automatically, so read the output.

`--seed N` fixes the random numbers, so two runs with the same seed print exactly the same lines. Use it
to check that a refactor changes nothing: run the old and the new code with the same seed and `diff`
the output. (The split into modules was checked this way with seeds 3 and 7.)

```bash
/Users/vzwinner/Downloads/Godot.app/Contents/MacOS/Godot --path . -- --shot out.png [menu|pause|info|quirky|debug|stump|chests] [pillars|corners|vbars|hbars|crates]
```

`--shot` sets up a scene (`tests._shot_setup()`), waits 30 frames, saves a screenshot and quits. It needs
a window, so no `--headless`. Screenshots are not byte-for-byte repeatable even with a seed (frame
timing differs), so compare them by eye.

The debug room (main menu → Debug room, `debug_room.start_debug()`) lays out every part, weapon and chest
type, restocks whatever you take, and has keys to spawn enemies, heal, toggle god mode and reset the body
(`DEBUG_HELP` lists them).

## Conventions

- Warnings about inferred `Variant` types are errors in this project. `var x := dict.field` will not
  compile; write `var x: float = dict.field`.
- Never name a local variable or parameter `g` inside a module: it would hide the game node. (Guns used
  to be called `g`; they are `gun` now.)
- Do not name functions after GDScript built-ins (`wrap` was one).
- Sides are `"L"` / `"R"`; slots are the short names above. `D.SIDE[side].hand` turns a side into its
  hand slot.
- Remove objects by marking them (`dead`, `gone`, `hp <= 0`) and calling `g.prune()` once per frame,
  never by erasing from a list while looping over it. `prune()` also frees the mesh.
- New state goes on the game node, not in a module, so every module and the tests can reach it.
  Modules hold no state of their own beyond `g`.
- Comments explain game rules, not code mechanics. Player-facing text goes through `g.say()`.
- When a playtest note changes a rule, update `PLAN.md` too, and add a smoke check that prints the new
  behaviour.

## Where to look for…

| Task | Start at |
|---|---|
| A new part | `data.gd` `TYPES`, then `player.use_hand()` / `player.ability()` / `player.jaw_act()` or the `update_*` step it affects, `view.build_player()` or `view.add_hand()` for its look |
| A new weapon | `data.gd` `GUNS`; `player.use_hand()` flesh-hand branch fires it, `guns.gd` handles ammo |
| A new enemy | `data.gd` `ENEMY`, `world.populate()` for where it spawns, `ai.update_enemies()` for its behaviour, `view.mk_enemy()` for its mesh |
| A new room type | `world.gen_floor()` (assignment), `world.gen_layout()` (shape), `world.populate()` (contents), `ROOMS` and `DOOR_COLOR` |
| Loot and drops | `loot.gd`: `loot()`, `enemy_drop()`, `pop_chest()`, `roll_part()` |
| HUD or Tab screen | `hud.gd` `_draw_hud()`, `_draw_info()`, `_draw_map()` |
| Menus or controls text | `menu.gd`, plus the help line at the bottom of `hud.gd` `_draw_hud()` |
| A new automated check | `tests/smoke.gd` (or `smoke_parts.gd` for per-part checks) |
