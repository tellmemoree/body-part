# Spare Parts — demo plan

Roguelite where you lose, find and swap body parts. Godot 4.7, tilted top-down 3D.
Goal: a demo run with a realistic, gory look.

**Run structure:** 5 floors. Each floor is a randomised map of 10–15 connected rooms,
explored freely like Enter the Gungeon. A guarded exit room leads down; clearing floor 5 wins.

**Design rule:** your body is your control scheme. Left/right click = left/right hand,
Q/E = use left/right side, F = jaw, Space = legs. Easy to learn, hard to master.

Status key: `[x]` done · `[~]` in progress · `[ ]` not started

## Done

- [x] Browser prototype (kept as `index.html` for reference)
- [x] Port to Godot with all prototype content
  - Parts: hands (flesh, robot fist, claw, hook, wrist cannon), legs (flesh, robot, spring, peg),
    eyes (flesh, cyber, cat), organs (second heart, adrenal gland, regen liver)
  - Weapons: pistol, SMG, shotgun, sniper, knife
  - Enemies: grunt, spitter, slasher, leaper, brute, mimic
  - Rooms: fight, treasure, surgeon, dark, elite
  - Chests (normal, locked, mimic), spike traps, severed parts rot after 25 s
- [x] Main menu, pause (Esc), pause menu (resume, restart run, main menu, quit)
- [x] Floor maps (replaces the two-door choice)
  - 10–15 rooms per floor on a grid, branching with a few loops, doors on N/S/E/W
  - Start room is safe; each floor has two treasure rooms and one surgeon
  - Doors seal while enemies are alive; a door needs a hand (or robot kick / fist) the first
    time, then stays open and can be walked through
  - Rooms remember their loot, chests and traps when you come back
  - Minimap (bottom right) shows visited rooms and their neighbours
  - Exit room at the far end, guarded by an elite brute; stairs lead to the next floor
  - 5 floors, win screen after the last; difficulty rises per floor and with distance from start
- [x] Room layouts (no more plain box)
  - Random room size; start and surgeon rooms are small, the exit room is large
  - Six styles: open, pillars, filled corners (L / T / plus shapes), vertical bars,
    horizontal bars, scattered crates
  - Walls and crates block the player, enemies and bullets; a spring-leg leap clears them
  - Enemies path around obstacles; every layout keeps a clear cross so all doors connect
- [x] Destructible chests, scrap, keys
  - Every chest has 5 hidden hit points; each bullet, pellet, melee swing or explosion is one hit
    (a shotgun blast or SMG burst destroys it at once, a pistol needs 5 shots)
  - A destroyed chest drops one scrap and no loot; a mimic still wakes on the first hit
  - 5 scrap fuse into a random quirky part, only obtainable this way (the scrap count is
    hidden: not on the HUD and not in the pickup message):
    mimic maw (hand: bite heals on a kill, eats locks, mimics cannot bite it),
    crate leg (slow, Space = stomp shockwave),
    keyhole eye (reveals mimics and what is behind every door)
  - Robot fist punch or robot-leg dash on a chest is 50/50: opens with loot, or destroyed for scrap
  - Locked chests need a key. Every floor gives out exactly 1-2 keys (`KEYS_PER_FLOOR`): 4% of
    kills and every elite drop one until the floor's keys are used up, and the exit guardian drops
    whatever is left. Mimics drop no key. With no key, a flesh hand can still pay a finger
  - Two treasure rooms per floor, so there are enough chests to collect scrap

- [x] Expanded body: 15 slots, 81 parts (all in `data.gd`, each tagged with a tier for rarity later)
  - Slots: 2 eyes, 2 ears, jaw, skin, 2 arms, 2 hands, 2 legs, 3 organs
  - Arms are the base for hands: no arm, no hand. A heavy hit takes the whole arm with its hand;
    the severed arm keeps its hand and reattaches as one piece. Arm sets reach, damage, knockback,
    recoil; hand sets the action
    - Arms: robot, long, piston (hold to charge), noodle, forked (second artificial hand),
      boomerang (click throws the arm, it returns)
  - Ears point at enemies the eyes cannot see (dark rooms, blind side); each ear hears its own side
  - Jaw (F): bite; no jaw means hearts cannot be eaten. Shark jaw, howler, acid spitter, vampire fangs
  - Skin (never severed): plated, spiked, rubber, stitched, glass, hive, chameleon
  - New hands: chainsaw, tentacle, crab pincer, shield, syringe, torch, magnet, gun hand, skeleton,
    baby, grenade (thrown, gone), rotting (triple damage, loses a finger per room)
  - New legs: wheel, tank tread, bird, rocket, frog (hold Space), ghost, stilt, tentacle,
    bomb (detonate: leg gone, you are thrown across the room), squeaky
  - New eyes: thermal, sniper, fly, evil, laser, glass (pops out as a decoy when hit), mirror
  - New ears: bat, cat, radar dish
  - New organs: iron lungs, second stomach, bile sac, spare kidney, black heart, marrow, pacemaker,
    tapeworm, lizard gland, bomb heart. No duplicates; a fourth organ pushes out the oldest
  - Status effects on enemies: bleed, burn, acid (+50% damage taken), stun. Burn + acid explodes
  - Pair bonuses: two claws frenzy, two cyber eyes home bullets, two robot legs hit twice as hard,
    spring + rocket leg = rocket leap, wheel + rocket leg = longer dash
  - Loot rolls by tier weight (common 6, rare 3, legendary 1; locked chests and elites 3/3/2)
  - Nerfs: a finger paid to a lock never grows back (hand's max fingers drops), so marrow cannot
    make locked chests free; chainsawed chests leave scrap only half the time; a pincer-snipped
    locked chest gives one item instead of two; keyhole eye spots mimics only within 6 units,
    cat ear within 4
- [x] Enemies can be dismembered
  - Limbs per enemy: grunt, slasher and brute have 2 arms and 2 legs; leaper 2 legs; spitter an eye;
    mimic a jaw (set in `data.gd`)
  - Every hit can take a limb off: chance is 10% per point of damage (max 60%, halved on elites),
    doubled for the knife, x1.5 for claws, chainsaw and explosions. A crab pincer crit always
    snips one, and it always crits on stunned enemies
  - A severed limb makes the enemy bleed and fight worse: one leg = 55% speed, no legs = 20% (it
    crawls) and leapers cannot leap; one arm = half the chance to sever your parts, no arms = it
    cannot sever yours, has no knockback and must be right on top of you to hurt; a blind spitter
    spits in random directions; a jawless mimic is slower and cannot bite parts off
  - Usable parts now come from cutting them off live enemies instead of from kills: grunt arm
    (with hand) or leg, slasher claw, leaper spring leg, brute fist, spitter eye. Only an elite
    brute still drops a fist on death
  - Missing limbs disappear from the enemy model
- [x] Playtest fixes, round 1
  - Ammo: guns have a magazine and a fixed total (pistol 8/80, SMG 30/120, shotgun 4/16,
    sniper 3/9, in `data.gd`). An empty magazine reloads by itself, R reloads early, missing
    fingers slow the reload; a gun with nothing left is thrown away. A dropped gun keeps its count.
    Knife, gun hand, wrist cannon and acid jaw are unlimited
  - One leg: Space only works if that leg can move you alone (`ONE_LEG` in `data.gd`). Wheel,
    rocket, spring and frog work at half strength; ghost, bomb and crate are unchanged; flesh,
    squeaky, robot and bird do nothing
  - A killed mimic drops exactly one thing: a weapon or part (50%) or one scrap
  - A missing hand is now obvious on the model: shorter arm with a red stump; flesh hands are wider
  - Tab: body and map screen (game stands still). Enlarged floor map with a legend, and one row
    per body slot saying what the part does or what its absence costs
  - Out of ammo: while you have only bare hands, 25% of kills drop a pistol or knife
    (`UNARMED_DROP`, `UNARMED_GUNS` in `data.gd`); armed kills still drop no weapons
  - Door colour no longer gives away unknown rooms: a "?" door is plain grey; the room's colour
    shows only when its name does (treasure, surgeon, exit, visited, or with a keyhole eye)
  - No more getting stuck without hands: the surgeon never takes your last hand, and whenever
    you have no hands in a room without enemies a stray hand (or arm) appears on the floor
- [x] Playtest fixes, round 2
  - Piston arm only charges punches and melee swings; a gun (or gun hand) on it fires normally
  - Q / E takes the nearest thing that side can use, so a finger you cannot attach no longer
    blocks the weapon lying under it
  - Fewer locked chests early: ordinary chests are locked 10% on floor 1 rising to 35% on floor 5
    (`LOCK_CHANCE`), dark room chests 30% rising to 100% (`DARK_LOCK`), elite rooms always.
    Fight rooms have a chest 35% of the time (`FIGHT_CHEST`, was 25%)
  - Opened chests stay visibly open (lid thrown back, black inside), also after leaving the room
- [x] Debug room (main menu > Debug room)
  - One large empty room with every part, weapon and pickup on the floor; anything taken comes
    straight back. Three chests: normal, locked, mimic
  - Keys: 1-6 spawn grunt, spitter, slasher, leaper, brute, mimic; 7 elite brute; 0 remove enemies;
    H heal; G god mode; B reset body; T restock; C count as a cleared room

## Next up

- [ ] Playtest round 3 (first outside playtester)
  - [x] Spikes no longer land in the strip in front of a door (`DOOR_LANE`, `DOOR_LANE_DEPTH`):
        walking back into a room could drop you straight onto spikes
  - [ ] Loot picker: when several things lie together (a big drop from a kill), list them and
        let the mouse wheel choose which one Q / E takes
  - [ ] Camera: free inside cleared rooms; in a fight it stays inside the room. Unentered rooms
        are hidden under fog until you walk in. Rooms bigger than the screen. Belongs with
        "Seamless floors" below
  - [ ] Surgeon is unclear: say what it takes and what you get before you offer
  - [ ] Upgrade gamble (idea): try to improve an item, 4 tries at 80 / 55 / 35 / 20%; success
        upgrades it and allows the next try, failure breaks it
- [ ] Chests and rarity (designed, not built)
  - Tiers (working names): common, rare, legendary; the rarer the chest, the better the items
  - Rarity is visible on the chest (for example wood, steel, gold); odds improve on deeper floors
  - To decide: loot table per tier; whether rarer chests give more scrap when destroyed;
    how locks and mimics relate to rarity (for example legendary always locked, mimics copy any tier)
  - Tuning left open: keys per floor (`KEYS_PER_FLOOR`, `KEY_CHANCE`), ammo per gun (`GUNS`), scrap per part (`SCRAP_NEEDED`),
    chest hit points (`CHEST_HP`), all in `data.gd`; more quirky parts
- [ ] Game feel and gore: hit reactions, screen shake, limbs physically flying off, blood
- [ ] More room variety: hand-made room templates, pits, destructible cover, props
- [ ] Ranged enemies should check line of sight before shooting; melee and hook reach through
      walls and should not
- [ ] Door collision (from playtest, screenshot of a side door): the door block sticks out of the
      wall at an angle and the player can stand inside it. Doors need to sit flush in the wall
      and block the player like walls do until they are opened
- [ ] Seamless floors: corridors between rooms and a scrolling camera, instead of the current
      one-room-per-screen transitions
- [ ] Real bosses, one per floor, replacing the elite brute guardian
- [ ] Shop room and a currency
- [ ] Sound: weapons, hits, flesh, footsteps, ambience, music

## Later

- [ ] More parts and pair bonuses (next batch to be chosen)
- [ ] Throwing spare or own limbs
- [ ] Realistic art: modular human cut into limbs (MakeHuman + Mixamo), enemies, environment set
- [ ] Animation: walk, hop, crawl, attacks per limb setup
- [ ] Settings menu (volume, fullscreen, key rebinding), controller support
- [ ] Tutorial room
- [ ] Balance pass from playtests
- [ ] Desktop builds (Windows, Mac)

## Open questions

- Do the surgeon and the rot timer stay as is? (added without being asked)
- Parts that were reinterpreted to fit the game (say if any should work differently): squeaky leg
  makes enemies 20% faster instead of waking them; glass eye pops out by itself when you are hit;
  crab pincer crits instead of severing enemy limbs; forked arm's second hand must be artificial;
  two robot legs double dash damage (dashes already pass through enemies)
- Keep the finger payment as a fallback for locked chests, or make a key the only way?
- Should unvisited neighbour rooms stay hidden as "?" (only treasure, surgeon and exit are shown)?
- Which asset sources for the realistic look?

## Playtest notes

_Add what feels off here after each session._

- None of the 81 parts has been balanced or played by hand yet; numbers are first guesses.

## How to run

- Source: private repo `tellmemoree/body-part` on GitHub, branch `main`.

- Play: open the project in Godot, press F5.
- Mechanics test: `Godot --headless --path . -- --smoke [--seed N]` (same seed, same output)
- Screenshot: `Godot --path . -- --shot <file.png> [menu|pause|info|quirky|debug|stump|chests] [pillars|corners|vbars|hbars|crates]`
- Content tables (parts, guns, enemies, rooms) are in `src/data.gd`. How the code is organised: `ARCHITECTURE.md`.
