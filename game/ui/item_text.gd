class_name ItemText
extends RefCounted
## BBCode descriptions for tooltips. Every line says where a number came from.

const LETTERS := ["A", "B", "C", "D", "E", "F"]

static func c(col: Color, text: String) -> String:
	return "[color=#%s]%s[/color]" % [UIKit.hex(col), text]

static func tier(t: int) -> String:
	return Defs.TIER_NUMERALS[clampi(t, 0, 6)]

static func title(item: Dictionary) -> String:
	var r := int(item.get("rarity", 1)) if item.kind != "reagent" else 5
	return "[font_size=17][b]%s[/b][/font_size]" % c(UIKit.rarity_color(r), Items.item_name(item))

static func describe(item: Dictionary, world: World) -> String:
	match item.kind:
		"component":
			return _component(item)
		"gear":
			return _gear(item, world)
		"reagent":
			return "%s\n%s\n%s" % [title(item), c(UIKit.ASH, "Reagent · %d held" % int(item.qty)),
				"Raises one modifier on crafted gear by a tier, up to the lower of its ingredient's ceiling and your gathering skill's."]
	return ""

static func _component(item: Dictionary) -> String:
	var res: Dictionary = Defs.RESOURCES[item.res]
	var lines := [title(item)]
	lines.append(c(UIKit.ASH, "%s · tiers up to %s" % [Defs.RARITIES[item.rarity], tier(item.ceiling)]))
	if item.mods.is_empty():
		lines.append(c(UIKit.DIM, "No modifiers."))
	for m in item.mods:
		lines.append("%s %s" % [Defs.MODS[m.id].name, c(UIKit.GOLD, tier(m.tier))])
	return "\n".join(lines)

static func _gear(item: Dictionary, world: World) -> String:
	var rec: Dictionary = Defs.RECIPES[item.recipe]
	var perks: Dictionary = world.player.perks if world else {}
	var s := Items.gear_stats(item, perks)
	var lines := [title(item)]
	var kind := Defs.SLOT_NAMES[item.slot]
	if item.has("style"):
		kind = "%s · %d ticks · range %d" % [Defs.SKILL_NAMES[item.style], item.speed, item.range]
	lines.append(c(UIKit.ASH, "%s · quality %d" % [kind, item.quality]))
	var base := []
	for k in ["accuracy", "power", "armour"]:
		if int(item.base[k]) > 0:
			base.append("%s %d" % [k.capitalize(), int(item.base[k])])
	if not base.is_empty():
		lines.append(c(UIKit.ASH, "Base: ") + ", ".join(base))
	# Group instances by modifier; list which ingredient each came from.
	var totals := Items.mod_totals(item.mods, perks)
	for id in Defs.MOD_ORDER:
		if not totals.has(id):
			continue
		var parts := []
		for m in item.mods:
			if m.id != id:
				continue
			var src: Dictionary = item.sources[int(m.src)]
			var letter := c(UIKit.rarity_color(int(src.rarity)), LETTERS[int(m.src)])
			var t := tier(int(m.tier))
			if int(m.get("tempered", 0)) > 0:
				t = c(UIKit.EMBER, t)
			parts.append("%s %s" % [letter, t])
		var res_note := ""
		if perks.has("resonance") and int(totals[id].count) >= 3:
			res_note = c(UIKit.EMBER, " +I")
		lines.append("%s %s   %s%s" % [c(UIKit.INK, "[b]%s[/b]" % Defs.MODS[id].name),
			c(UIKit.GOLD, Defs.mod_value_text(id, int(totals[id].tiers))), c(UIKit.DIM, "·").join(parts), res_note])
	var src_names := []
	for i in item.sources.size():
		var src: Dictionary = item.sources[i]
		src_names.append(c(UIKit.rarity_color(int(src.rarity)), "%s %s" % [LETTERS[i], Defs.RARITIES[int(src.rarity)]]))
	var prov := "From %s %s." % [", ".join(src_names), Defs.component_name(item.res) + "s"]
	if int(item.tempers) > 0:
		prov += " Tempered %s." % ("once" if int(item.tempers) == 1 else "%d times" % int(item.tempers))
	lines.append(c(UIKit.DIM, prov))
	return "\n".join(lines)

static func stats_summary(world: World) -> String:
	var s := world.stats()
	var lines := []
	lines.append("%s %s" % [c(UIKit.ASH, "Style"), Defs.SKILL_NAMES[s.style]])
	lines.append("%s %d   %s %d" % [c(UIKit.ASH, "Max hit"), s.max_hit, c(UIKit.ASH, "Speed"), s.speed])
	lines.append("%s %d   %s %d" % [c(UIKit.ASH, "Accuracy"), s.accuracy, c(UIKit.ASH, "Power"), s.power])
	lines.append("%s %d   %s %d" % [c(UIKit.ASH, "Armour"), s.armour, c(UIKit.ASH, "Hitpoints"), world.max_hp()])
	if s.echo > 0:
		lines.append("%s %s" % [c(UIKit.ASH, "Echo"), Defs.mod_value_text("echo", s.echo)])
	return "\n".join(lines)
