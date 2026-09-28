class_name Items
extends RefCounted
## Component rolls, crafting, tempering and item stats. Items are plain
## Dictionaries so they save to JSON unchanged.

# ---------------------------------------------------------------- components

## Levels above a resource's requirement shift rarity and tier odds upward.
static func luck_for(skill_level: int, req: int, perks: Dictionary) -> float:
	var over := skill_level - req
	if perks.has("keen_eye"):
		over += 10
	return maxf(0.0, over) * 0.025

static func rarity_weights(luck: float) -> Array:
	var w := []
	for i in Defs.RARITIES.size():
		var base: float = Defs.RARITY_WEIGHTS[i]
		if i == 0:
			w.append(base / (1.0 + luck))
		else:
			w.append(base * pow(1.0 + luck, i))
	return w

static func tier_weights(ceiling: int, luck: float, tier_sense: bool) -> Array:
	var w := []
	for t in range(1, ceiling + 1):
		var x := pow(0.45 * (1.0 + luck * 0.6), t - 1)
		if tier_sense:
			x *= pow(1.8, t - 1)
		w.append(x)
	return w

static func weighted_index(weights: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for x in weights:
		total += x
	var r := rng.randf() * total
	for i in weights.size():
		r -= weights[i]
		if r <= 0.0:
			return i
	return weights.size() - 1

static func roll_mod_id(rng: RandomNumberGenerator) -> String:
	var w := []
	for id in Defs.MOD_ORDER:
		w.append(Defs.MODS[id].weight)
	return Defs.MOD_ORDER[weighted_index(w, rng)]

static func roll_component(uid: int, res_id: String, skill_level: int, perks: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var res: Dictionary = Defs.RESOURCES[res_id]
	var luck := luck_for(skill_level, res.req, perks)
	var rarity := weighted_index(rarity_weights(luck), rng)
	var ceiling := Defs.tier_ceiling(res.req)
	var tw := tier_weights(ceiling, luck, perks.has("tier_sense"))
	var mods := []
	for i in rarity:
		mods.append({"id": roll_mod_id(rng), "tier": 1 + weighted_index(tw, rng)})
	return {"uid": uid, "kind": "component", "res": res_id, "rarity": rarity, "ceiling": ceiling, "mods": mods}

## Sort key: more modifiers first, then higher tiers.
static func component_score(c: Dictionary) -> int:
	var s := 0
	for m in c.mods:
		s += 10 + int(m.tier) * 3
	return s

# ---------------------------------------------------------------- crafting

static func quality_for(skill_level: int, req: int, perks: Dictionary) -> int:
	return maxi(0, (skill_level - req) / 10) + (1 if perks.has("masterwork") else 0)

static func craft(uid: int, recipe_id: String, ingredients: Array, skill_level: int, perks: Dictionary) -> Dictionary:
	var rec: Dictionary = Defs.RECIPES[recipe_id]
	var res_id: String = ingredients[0].res
	var res: Dictionary = Defs.RESOURCES[res_id]
	var req := Defs.recipe_req(recipe_id, res_id)
	var q := quality_for(skill_level, req, perks)
	var mat: int = res.mat
	var base := {
		"accuracy": Defs.base_stat(rec.acc, mat),
		"power": Defs.base_stat(rec.power, mat),
		"armour": Defs.base_stat(rec.armour, mat),
	}
	if base.accuracy > 0: base.accuracy += 2 * q
	if base.power > 0: base.power += q
	if base.armour > 0: base.armour += 2 * q
	var mods := []
	var sources := []
	var rarity_sum := 0
	for i in ingredients.size():
		var ing: Dictionary = ingredients[i]
		rarity_sum += int(ing.rarity)
		sources.append({"rarity": ing.rarity, "mods": ing.mods.duplicate(true)})
		for m in ing.mods:
			mods.append({"id": m.id, "tier": m.tier, "src": i, "ceiling": ing.ceiling})
	var item := {
		"uid": uid, "kind": "gear", "recipe": recipe_id, "res": res_id,
		"family": res.family, "slot": rec.slot, "quality": q, "base": base,
		"rarity": int(round(float(rarity_sum) / ingredients.size())),
		"mods": mods, "sources": sources, "tempers": 0,
	}
	if rec.has("style"):
		item.style = rec.style
		item.speed = rec.speed
		item.range = rec.range
	return item

static func item_name(item: Dictionary) -> String:
	match item.kind:
		"component":
			return Defs.component_name(item.res)
		"gear":
			return "%s %s" % [Defs.RESOURCES[item.res].name, Defs.RECIPES[item.recipe].name]
		"reagent":
			return Defs.REAGENT_NAME
	return "?"

# ---------------------------------------------------------------- tempering

## Instances a shard may raise: below both the ingredient's ceiling and the
## tier ceiling of the player's gathering skill for that family.
static func temper_candidates(item: Dictionary, skill_level: int) -> Array:
	var cap_skill := Defs.tier_ceiling(skill_level)
	var out := []
	for i in item.mods.size():
		var m: Dictionary = item.mods[i]
		if int(m.tier) < mini(int(m.ceiling), cap_skill):
			out.append(i)
	return out

## Returns the upgraded instance index, or -1 if nothing can be raised.
static func temper(item: Dictionary, skill_level: int, rng: RandomNumberGenerator, choice := -1) -> int:
	var cands := temper_candidates(item, skill_level)
	if cands.is_empty():
		return -1
	var idx: int = choice if choice in cands else cands[rng.randi_range(0, cands.size() - 1)]
	item.mods[idx].tier = int(item.mods[idx].tier) + 1
	item.tempers = int(item.tempers) + 1
	return idx

static func salvage_yield(item: Dictionary) -> int:
	return item.mods.size() / 3

# ---------------------------------------------------------------- stats

## {mod_id: {"tiers": int, "count": int}} with Resonance applied to tiers.
static func mod_totals(mods: Array, perks: Dictionary) -> Dictionary:
	var out := {}
	for m in mods:
		if not out.has(m.id):
			out[m.id] = {"tiers": 0, "count": 0}
		out[m.id].tiers += int(m.tier)
		out[m.id].count += 1
	if perks.has("resonance"):
		for id in out:
			if out[id].count >= 3:
				out[id].tiers += 1
	return out

static func gear_stats(item: Dictionary, perks: Dictionary) -> Dictionary:
	var s := {"accuracy": int(item.base.accuracy), "power": int(item.base.power),
		"armour": int(item.base.armour), "max_hp": 0, "echo": 0}
	var totals := mod_totals(item.mods, perks)
	for id in totals:
		var def: Dictionary = Defs.MODS[id]
		s[def.stat] += int(totals[id].tiers) * int(def.per_tier)
	return s
