extends RefCounted

var t

func rng(s := 7) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

func test_xp_curve() -> void:
	for lv in range(2, 101):
		t.ok(Defs.xp_for_level(lv) > Defs.xp_for_level(lv - 1), "curve rises at %d" % lv)
	t.eq(Defs.level_for_xp(Defs.xp_for_level(40)), 40, "level 40 round trip")
	t.eq(Defs.level_for_xp(Defs.xp_for_level(40) - 1), 39, "just short of 40")
	t.eq(Defs.level_for_xp(1e12), 100, "capped at 100")

func test_tier_ceilings() -> void:
	t.eq(Defs.tier_ceiling(1), 1, "level 1")
	t.eq(Defs.tier_ceiling(15), 1, "level 15")
	t.eq(Defs.tier_ceiling(30), 2, "level 30")
	t.eq(Defs.tier_ceiling(40), 3, "level 40")
	t.eq(Defs.tier_ceiling(90), 6, "level 90")
	t.eq(Defs.tier_ceiling(100), 6, "level 100")

func test_rarity_sets_mod_count_and_tiers_respect_ceiling() -> void:
	var r := rng()
	for i in 400:
		var c := Items.roll_component(i, "maple", 60, {}, r)
		t.ok(c.mods.size() == c.rarity, "mod count equals rarity step")
		for m in c.mods:
			t.ok(m.tier >= 1 and m.tier <= 2, "maple tiers within II")
	var junk := 0
	for i in 400:
		var c := Items.roll_component(i, "pine", 1, {}, r)
		junk += 1 if c.rarity == 0 else 0
		for m in c.mods:
			t.eq(m.tier, 1, "pine is T1 only")
	t.ok(junk > 60, "junk is common at the gate")
	var six := false
	for i in 20000:
		var c := Items.roll_component(i, "elderheart", 100, {"keen_eye": true}, r)
		if c.rarity == 6:
			six = true
			t.eq(c.mods.size(), 6, "mythic carries six")
			break
	t.ok(six, "mythic is reachable")

func test_skill_level_improves_rolls_past_the_gate() -> void:
	var lo := 0.0
	var hi := 0.0
	var r := rng(3)
	for i in 3000:
		lo += Items.roll_component(i, "maple", 30, {}, r).rarity
		hi += Items.roll_component(i, "maple", 70, {}, r).rarity
	t.ok(hi > lo * 1.3, "level 70 rolls better maple than level 30 (%f vs %f)" % [hi, lo])

func make_comp(res: String, rarity: int, mods: Array) -> Dictionary:
	return {"uid": randi(), "kind": "component", "res": res, "rarity": rarity,
		"ceiling": Defs.tier_ceiling(Defs.RESOURCES[res].req), "mods": mods}

func test_craft_carries_every_modifier_and_stacks_duplicates() -> void:
	var a := make_comp("maple", 2, [{"id": "might", "tier": 1}, {"id": "vigor", "tier": 2}])
	var b := make_comp("maple", 1, [{"id": "might", "tier": 2}])
	var c := make_comp("maple", 0, [])
	var bow := Items.craft(1, "shortbow", [a, b, c], 30, {})
	t.eq(bow.mods.size(), 3, "all instances carried")
	t.eq(bow.mods[2].src, 1, "source index recorded")
	var totals := Items.mod_totals(bow.mods, {})
	t.eq(totals.might.tiers, 3, "might I + II")
	t.eq(totals.might.count, 2, "two might instances")
	var s := Items.gear_stats(bow, {})
	t.eq(s.power, Defs.base_stat(Defs.RECIPES.shortbow.power, 3) + 9, "power = base + 3 per tier")
	t.eq(s.max_hp, 4, "vigor II")
	t.eq(bow.style, "archery", "shortbow is archery")

func test_quality_rises_with_production_level() -> void:
	var comps := [make_comp("oak", 0, []), make_comp("oak", 0, []), make_comp("oak", 0, [])]
	var at_gate := Items.craft(1, "sword", [make_comp("iron", 0, []), make_comp("iron", 0, []), make_comp("iron", 0, [])], 15, {})
	var later := Items.craft(2, "sword", [make_comp("iron", 0, []), make_comp("iron", 0, []), make_comp("iron", 0, [])], 55, {})
	t.eq(at_gate.quality, 0, "no quality at the gate")
	t.eq(later.quality, 4, "quality 4 at forty levels over")
	t.ok(later.base.power > at_gate.base.power, "quality raises power")
	t.eq(Items.craft(3, "shortbow", comps, 15, {"masterwork": true}).quality, 1, "masterwork adds one")

func test_resonance_and_echo() -> void:
	var mods := [{"id": "echo", "tier": 1}, {"id": "echo", "tier": 1}, {"id": "echo", "tier": 1}]
	t.eq(Items.mod_totals(mods, {}).echo.tiers, 3, "three echoes")
	t.eq(Items.mod_totals(mods, {"resonance": true}).echo.tiers, 4, "resonance adds one")
	t.eq(Defs.echo_interval(1), 8, "echo I strikes every 8th")
	t.eq(Defs.echo_interval(20), 3, "echo floors at every 3rd")
	t.eq(Defs.echo_interval(0), 0, "no echo")

func test_temper_respects_both_ceilings() -> void:
	var r := rng()
	var a := make_comp("maple", 2, [{"id": "might", "tier": 1}, {"id": "guard", "tier": 2}])
	var bow := Items.craft(1, "shortbow", [a, make_comp("maple", 0, []), make_comp("maple", 0, [])], 30, {})
	# Woodcutting 17 caps at T1: nothing can rise.
	t.eq(Items.temper(bow, 17, r), -1, "skill ceiling blocks")
	# Woodcutting 40 caps at T3, maple at T2: only the T1 might can rise.
	t.eq(Items.temper(bow, 40, r), 0, "might rises")
	t.eq(bow.mods[0].tier, 2, "to II")
	t.eq(Items.temper(bow, 90, r), -1, "maple ceiling holds at II")
	t.eq(bow.tempers, 1, "one temper recorded")

func test_guided_temper_choice() -> void:
	var r := rng()
	var a := make_comp("ironwood", 2, [{"id": "might", "tier": 1}, {"id": "guard", "tier": 1}])
	var bow := Items.craft(1, "shortbow", [a, make_comp("ironwood", 0, []), make_comp("ironwood", 0, [])], 40, {})
	t.eq(Items.temper(bow, 40, r, 1), 1, "chosen instance")
	t.eq(bow.mods[1].tier, 2, "guard rose")

func test_hit_chance_bounds() -> void:
	t.ok(World.hit_chance(1000, 100) > 0.9, "strong attacker")
	t.ok(World.hit_chance(100, 1000) < 0.06, "weak attacker")
	t.ok(absf(World.hit_chance(500, 500) - 0.5) < 0.01, "even")
