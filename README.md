# Thornreach

A single-player vertical slice of a tick-based frontier RPG, built in Godot 4.3
with GDScript. Combat, movement and enemy patterns all run on one 0.6-second
tick. Skills train by use. Gathered logs and ore roll modifiers that carry into
whatever you craft. Each skill family has a compact perk board. The slice ends
with the Cinder Warden, a three-phase boss that telegraphs every strike on the
floor before it lands.

Every model, animation and icon is generated in code. The only files in `assets/`
are two OFL fonts.

## Run

Open the folder in Godot 4.3 or later and press Play, or:

    godot --path .

## Play

- **Left-click** does the first option: walk, attack, chop, mine, or use a
  station. **Right-click** lists every option.
- **Arrow keys** or **middle-drag** turn the camera; the **wheel** zooms.
- **R** toggles run. **1–5** switch the side panel: Pack, Gear, Skills,
  Boards, Settings.
- To temper, click a Cinder Shard, then click a piece of gear.
- Settings has a Brisk ×3 XP rate for playtesting.

The camp holds the stash, anvil (Smithing), fletching bench, board shrine and
hearth. The forest is west, the mine east over the bridge, and the Warden's
hollow south through the ash pass.

## How items work

- A component's rarity sets its modifier count: Junk has none, and Mythic has six.
- A resource's level requirement sets its tier ceiling:
  `tier = 1 + level / 18`, capped at VI. Pine and copper roll only T1. A
  level-90 Elderheart log can roll T6.
- Levels above a resource's requirement improve both rarity and tier odds,
  so skills keep mattering after their board is full.
- A recipe carries every modifier from every ingredient. Duplicates stack.
  The tooltip labels each instance with the ingredient it came from (A, B, C...).
- A Cinder Shard raises one random modifier instance by one tier. The cap is
  the lower of that ingredient's ceiling and your gathering skill's ceiling.
- Echo is the one rhythm modifier: every Nth attack strikes twice. The tick
  strip marks that attack.

## Layout

    core/    rules only: data, items, map, world tick, Warden patterns (no nodes)
    game/    3D view, procedural models, animation, camera, interface
    data/    frontier.txt, the hand-authored map (tools/paint_map.py blocked it out)
    tests/   headless tests
    tools/   screenshot, parse-check and smoke scripts

## Test

    godot --headless --path . --import             # once, builds the class cache
    godot --headless --path . -s tests/run_tests.gd
    tools/smoke.sh                                 # plays the real scene headlessly
    tools/shot.sh fight out.png --seq=8            # screenshots via xvfb
