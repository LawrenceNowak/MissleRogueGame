# Missile Command x PIT

A Godot 4 arcade roguelite defense prototype built around manual aiming, weapon switching, city preservation, and between-wave buildcraft.

Open `project.godot` in Godot 4.7 or later and run the main scene.

## Prototype loop

Protect five independently damaged cities through ten waves. The missile launcher intercepts groups at a chosen detonation point; the unlockable Gatling gun answers fast individual targets with continuous fire and an overheat limit. Between waves, select cities to repair or shield, buy and upgrade the Gatling gun, collect three functional charms, and drag either emplacement to a new ground position. Free one-of-three upgrade choices appear after waves 2, 5, and 8. Wave 10 is the Missile Carrier boss.

Credits and combat upgrades reset on a new run. Generic Components are saved under `user://` and persist across victory, defeat, and relaunch.

## Controls

- Mouse: aim
- Left mouse button: fire (hold for Gatling)
- `1` / `2`: switch weapon
- Drag emplacements during defense phase: reposition
- Click a city during defense phase: select it for repair or shielding
- `Esc`: pause

Debug builds also support `F5` for 100 Credits, `F6` to clear the current wave, `F7` to damage the selected city, and `F8` to destroy current enemies.

## Project layout

- `game/Main.gd`: explicit run phases, waves, economy, UI, saving, and orchestration
- `game/Balance.gd`: centralized tuning and ten data-driven wave definitions
- `game/City.gd`: city health states and shield damage routing
- `game/Weapon.gd`: runtime weapon state, heat, and behavioral upgrades
- `game/Enemy.gd`: reusable Basic, Fast, MIRV, child, and boss threat behavior
- `game/Projectile.gd`: interception missiles, bullets, explosions, clusters, and ricochets
- `tests/smoke_test.gd`: headless end-to-end state and combat smoke coverage

No audio assets are bundled. `Main.gd` emits `audio_cue_requested` hooks for launches, firing, explosions, destruction, purchases, wave starts, and run results.
