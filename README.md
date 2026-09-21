# Missile Command x PIT

A Godot 4 two-screen roguelite prototype: explore and automate a rugged factory map, then defend five cities with the ammunition that factory produced.

Open `project.godot` in Godot 4.7 or later and run the main scene.

## Prototype loop

Runs begin on a separate top-down Factory screen. Explore persistent fog with the engineer, harvest Wood/Stone/Ore, excavate finite mountain grids, expose hidden veins, and construct drills, directional belts, ammunition factories, missile factories, and storage. Meaningful work consumes a 100-point stamina budget; walking and planning are free.

Ending preparation manually or reaching zero stamina triggers a short incoming-attack warning and switches to the existing Defense screen. Factory production is frozen during preparation and advances only during active combat, even while its scene is hidden. Clearing a wave immediately returns to the persistent Factory map with full stamina. The Basic MG starts unlocked with 1000 rounds; the Missile Launcher is a 60-Credit early unlock with only three missiles and slow 25-second combat-time production.

The northern edge of the Factory map is the strategic Defense Front. Its five city markers and two weapon nodes reference the exact city and weapon objects used by the Defense view, so health, shields, unlocks, selection, placement, upgrades, and ammunition remain synchronized. Ammo and missile factories emit physical colored packets: route their output belts directly, or through a rotated Storage buffer and splitter, into the matching Basic MG depot or Missile node. Ammunition becomes usable in combat only after the correct packet reaches that live node.

Every belt has two independent physical lanes. Lightweight transported items move continuously, retain ordering and minimum spacing, follow automatic curved corner paths, and back up without disappearing when a machine, storage, splitter, or depot cannot accept them. Straight connections preserve lanes; a side feed entering from the destination belt's left maps both incoming lanes to lane 0, while a feed from its right maps to lane 1. Splitters balance A/B by deterministic alternation and can be cycled through A priority, B priority, strict Ore filtering, and Ore-filter overflow modes by interacting beside them.

The existing five cities, manual aiming, enemies, shields, upgrades, Missile Carrier boss, victory, defeat, and persistent Components remain intact. The mandatory milestone reward modal is bypassed in normal progression.

Credits and combat upgrades reset on a new run. Generic Components are saved under `user://` and persist across victory, defeat, and relaunch.

## Controls

- Factory: `WASD` move, `E` interact/dig/harvest/Command Center
- Factory front: `E` beside an unlocked weapon node selects that same combat weapon
- Factory: choose a toolbar building, left click to place, `R` rotate
- Factory: hover an empty belt and press `R` to rotate it; occupied belts cannot be rotated or removed
- Factory: right click removes a belt or cancels placement; `Esc` cancels placement
- Factory: `E` beside a splitter cycles its prototype routing mode; `V` toggles lane/port diagnostics
- Preparation: `Tab` switches between Factory and Command inspection without starting combat
- Defense: mouse aims; left mouse fires (hold for Basic MG)
- Defense: `1` / `2` selects Basic MG / Missile Launcher
- Command preparation: drag emplacements and click cities for repair or shielding
- `Esc`: pause

Debug builds support `F1` +20 Wood, `F2` +20 Stone, `F3` +20 Ore, `F4` +300 MG rounds, `F5` +100 Credits, `F6` clear wave, `F8` destroy current enemies, `F9` reveal fog, `F10` refill stamina, `F11` return to preparation, and `F12` start defense.

## Project layout

- `game/Main.gd`: explicit run phases, waves, economy, UI, saving, and orchestration
- `game/Balance.gd`: centralized tuning and ten data-driven wave definitions
- `game/RunInventory.gd`: shared run-only materials and ammunition inventory
- `game/FactoryWorld.gd`: persistent exploration map plus machine ports, finite buffers, production, storage, front depots, and logistics rendering
- `game/LogisticsNetwork.gd`: deterministic fixed-step two-lane movement, spacing, topology, side-loading, merging, backpressure, and splitters
- `game/TransportResources.gd`: stable transported-resource IDs and replaceable item texture hooks
- `game/BeltVisualSet.gd`: replaceable straight/corner/splitter texture slots independent of transport geometry
- `assets/stranded/`: focused copies of the STRANDED sprites actually used by the Factory screen
- `game/City.gd`: city health states and shield damage routing
- `game/Weapon.gd`: runtime weapon state, heat, and behavioral upgrades
- `game/Enemy.gd`: reusable Basic, Fast, MIRV, child, and boss threat behavior
- `game/Projectile.gd`: interception missiles, bullets, explosions, clusters, and ricochets
- `tests/logistics_test.gd`: focused lane, order, congestion, corner, side-load, splitter, filter, and future-speed-hook coverage
- `tests/smoke_test.gd`: end-to-end exploration, complete weapon supply chains, off-screen resupply, combat, boss, and reset coverage

No audio assets are bundled. `Main.gd` emits `audio_cue_requested` hooks for launches, firing, explosions, destruction, purchases, wave starts, and run results.
