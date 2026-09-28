# Thornreach

Godot 4.3, GDScript. A tick-based frontier RPG slice. See README.md.

- `godot --headless --path . --import` once, then
  `godot --headless --path . -s tests/run_tests.gd` for the rules tests.
- `tools/check.sh` parses every script. `tools/smoke.sh` drives the real scene
  through every screen headlessly. `tools/shot.sh <scene> <out.png>` takes
  screenshots under xvfb; scenes are listed in `tools/shots.gd`.

## Boundaries

- `core/` holds every rule and touches no nodes. `game/` draws and animates
  and encodes no rules: it asks the World and reads its events.
- The World changes only in `step()` and the `cmd_*`/inventory calls. The view
  reacts to `world.events` after each tick.
- Every tunable number lives in `core/defs.gd`.
- Every model is generated through `MeshKit` in `game/models.gd`. Nothing is
  imported except fonts.
- Every action gets an animation. A new action needs an event from the World
  and a response in `WorldView.handle_event` or `Actor`.
- No sound.

## Encounter rules

- Every Warden strike is marked on the floor before it lands, and every death
  names its tick, attack and cause in the recap. A new attack needs both.
- `tests/test_warden.gd` must still show that a mark-reading bot wins and a
  bot that ignores the marks dies.

## Interface and copy

- Dark warm panels, hairline borders, corners of 2px or less, no gradients, no
  emoji. Ember orange is the one accent; rarity colours are for items only.
- Display type is Cinzel; body text is Alegreya Sans.
- Every sentence must tell the player something they can't already see. The
  log records events; it does not narrate. Buttons are labels, not sentences.
