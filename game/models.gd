class_name Models
extends RefCounted
## Every model in the game, generated from MeshKit primitives. Units: one tile
## is 1.0; y is up; models stand on y = 0 centred on the origin.

const BARK := Color("5a4030")
const LEAF_PINE := Color("2f5a3a")
const LEAF_OAK := Color("4f7a34")
const LEAF_MAPLE := Color("c2502a")
const LEAF_IRON := Color("8a4a2a")
const STONE := Color("7b766c")
const STONE_DARK := Color("4e4a44")
const EMBER := Color("ff7a30")
const GOLD := Color("e8c060")
const SKIN := Color("d8a986")
const CLOTH := Color("6b3a2a")
const CLOTH_DARK := Color("3a2a22")
const LEATHER := Color("6a4a30")
const RUNE := Color("ffcf7a")

const WOOD_COLORS := {
	"pine": Color("c9a66b"), "oak": Color("8a5a32"), "maple": Color("a04a30"),
	"ironwood": Color("3f3a38"), "elderheart": Color("efe2b8"),
}
const METAL_COLORS := {
	"copper": Color("c26b3c"), "iron": Color("9a9ca0"), "duskiron": Color("4d4c68"),
	"emberite": Color("2e2624"), "sunsteel": Color("e6c35a"),
}
const ORE_FLECK := {
	"copper": Color("d9793a"), "iron": Color("a2553a"), "duskiron": Color("7a6ab0"),
	"emberite": Color("ff6a2a"), "sunsteel": Color("ffd970"),
}

static var _cache := {}

static func material_color(res_id: String) -> Color:
	if WOOD_COLORS.has(res_id):
		return WOOD_COLORS[res_id]
	return METAL_COLORS.get(res_id, Color.GRAY)

static func glows(res_id: String) -> bool:
	return res_id in ["emberite", "sunsteel", "elderheart"]

static func mi(kit: MeshKit) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = kit.build()
	return m

static func cached(key: String, f: Callable) -> Mesh:
	if not _cache.has(key):
		_cache[key] = f.call()
	return _cache[key]

static func mesh_node(key: String, f: Callable) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = cached(key, f)
	return m

# ================================================================ trees

static func tree(res: String, variant: int) -> Node3D:
	var root := Node3D.new()
	var standing := mesh_node("tree_%s_%d" % [res, variant % 3], func(): return _tree_mesh(res, variant % 3))
	standing.name = "Standing"
	root.add_child(standing)
	var stump := mesh_node("stump_%s" % res, func(): return _stump_mesh(res))
	stump.name = "Stump"
	stump.visible = false
	root.add_child(stump)
	root.rotation.y = variant * 1.7
	return root

static func _stump_mesh(res: String) -> Mesh:
	var k := MeshKit.new(7)
	var c: Color = WOOD_COLORS[res]
	k.prism(Vector3.ZERO, 0.28, 0.24, 0.2, 7, BARK)
	k.prism(Vector3(0, 0.28, 0), 0.01, 0.2, 0.2, 7, c.lightened(0.2))
	return k.build()

static func _tree_mesh(res: String, v: int) -> Mesh:
	var k := MeshKit.new(13 + v * 7)
	var s := 1.0 + v * 0.12
	match res:
		"pine":
			k.prism(Vector3.ZERO, 1.2 * s, 0.14, 0.08, 6, BARK)
			for i in 4:
				var y := (0.55 + i * 0.5) * s
				var r := (0.78 - i * 0.16) * s
				k.jitter = 0.04
				k.prism(Vector3(0, y, 0), 0.75 * s, r, 0.0, 7, LEAF_PINE.darkened(0.05 * i).lerp(LEAF_PINE.lightened(0.1), float(i) / 4))
				k.jitter = 0.0
		"oak":
			k.prism(Vector3.ZERO, 1.1 * s, 0.22, 0.16, 7, BARK)
			k.with(Transform3D(Basis(Vector3.FORWARD, 0.6), Vector3(0.1, 0.9 * s, 0)), func(): k.prism(Vector3.ZERO, 0.6, 0.09, 0.05, 5, BARK))
			k.with(Transform3D(Basis(Vector3.FORWARD, -0.7), Vector3(-0.1, 0.8 * s, 0)), func(): k.prism(Vector3.ZERO, 0.55, 0.09, 0.05, 5, BARK))
			k.jitter = 0.06
			for p in [Vector3(0, 1.65, 0), Vector3(0.45, 1.4, 0.15), Vector3(-0.45, 1.45, -0.1), Vector3(0.1, 1.5, 0.45), Vector3(-0.1, 1.35, -0.45)]:
				k.sphere(p * s, Vector3(0.55, 0.45, 0.55) * s, LEAF_OAK.darkened(0.12 * absf(p.x)), 7, 4)
		"maple":
			k.prism(Vector3.ZERO, 1.3 * s, 0.18, 0.12, 7, BARK.darkened(0.1))
			k.jitter = 0.07
			for p in [Vector3(0, 1.9, 0), Vector3(0.42, 1.55, 0.2), Vector3(-0.42, 1.6, -0.15), Vector3(0, 1.5, -0.45), Vector3(-0.1, 1.45, 0.45)]:
				k.sphere(p * s, Vector3(0.5, 0.48, 0.5) * s, LEAF_MAPLE.lerp(Color("e0782e"), 0.3 * (p.y - 1.4)), 7, 4)
		"ironwood":
			k.prism(Vector3.ZERO, 1.6 * s, 0.26, 0.12, 6, Color("2e2a28"), true, true, 0.6)
			for y in [0.4, 0.9]:
				k.prism(Vector3(0, y, 0), 0.1, 0.25, 0.23, 6, Color("6a6e74"))
			k.jitter = 0.08
			for p in [Vector3(0, 2.0, 0), Vector3(0.5, 1.7, 0.1), Vector3(-0.45, 1.75, -0.2)]:
				k.sphere(p * s, Vector3(0.52, 0.36, 0.52) * s, LEAF_IRON.darkened(0.1 * p.x), 6, 3)
		"elderheart":
			# Ancient, broad, carved with runes that burn pale gold.
			k.jitter = 0.05
			k.prism(Vector3.ZERO, 2.6, 0.62, 0.34, 9, Color("cfc3a0"), true, true, 0.5)
			for a in 5:
				var ang := a * TAU / 5
				k.with(Transform3D(Basis(Vector3.UP, ang) * Basis(Vector3.FORWARD, 1.1), Vector3(cos(ang) * 0.4, 0.15, sin(ang) * 0.4)),
					func(): k.prism(Vector3.ZERO, 0.8, 0.18, 0.04, 5, Color("bfb08a")))
			k.jitter = 0.0
			for i in 6:
				var ang := i * TAU / 6
				k.box(Vector3(cos(ang) * 0.52, 0.6 + (i % 3) * 0.55, sin(ang) * 0.52), Vector3(0.08, 0.3, 0.08), RUNE, true)
			k.jitter = 0.1
			for p in [Vector3(0, 3.3, 0), Vector3(0.9, 2.9, 0.3), Vector3(-0.9, 3.0, -0.2), Vector3(0.2, 2.8, 0.95), Vector3(-0.3, 2.9, -0.9)]:
				k.sphere(p, Vector3(1.0, 0.7, 1.0), Color("e9e0b0").darkened(0.15 + 0.1 * absf(p.x)), 8, 4)
			k.jitter = 0.0
			for p in [Vector3(0.6, 2.2, 0.8), Vector3(-0.9, 2.4, 0.1), Vector3(0.3, 2.5, -1.0)]:
				k.sphere(p, Vector3(0.07, 0.07, 0.07), RUNE, 4, 2, true)
	return k.build()

# ================================================================ rocks

static func rock(res: String, variant: int) -> Node3D:
	var root := Node3D.new()
	var full := mesh_node("rock_%s_%d" % [res, variant % 3], func(): return _rock_mesh(res, variant % 3, false))
	full.name = "Standing"
	root.add_child(full)
	var empty := mesh_node("rock_empty_%d" % (variant % 3), func(): return _rock_mesh(res, variant % 3, true))
	empty.name = "Stump"
	empty.visible = false
	root.add_child(empty)
	root.rotation.y = variant * 2.1
	return root

static func _rock_mesh(res: String, v: int, depleted: bool) -> Mesh:
	var k := MeshKit.new(31 + v)
	k.jitter = 0.07
	var base := STONE_DARK if res in ["emberite", "duskiron", "sunsteel"] else STONE
	k.sphere(Vector3(0, 0.25, 0), Vector3(0.48, 0.42, 0.44), base, 6, 3)
	k.sphere(Vector3(0.22, 0.18, 0.2), Vector3(0.3, 0.26, 0.3), base.darkened(0.1), 5, 3)
	k.sphere(Vector3(-0.25, 0.15, -0.12), Vector3(0.26, 0.22, 0.26), base.lightened(0.05), 5, 3)
	k.jitter = 0.0
	if depleted:
		return k.build()
	var fleck: Color = ORE_FLECK[res]
	var glow := glows(res)
	var spots := [Vector3(0.15, 0.55, 0.1), Vector3(-0.2, 0.45, 0.2), Vector3(0.3, 0.3, -0.25), Vector3(-0.1, 0.5, -0.25), Vector3(0.35, 0.35, 0.25)]
	for i in spots.size():
		var p: Vector3 = spots[i]
		if res in ["duskiron", "emberite", "sunsteel"]:
			k.shard(p - Vector3(0, 0.08, 0), 0.26 + 0.06 * (i % 2), 0.07, fleck, glow and i % 2 == 0, p.normalized() * 0.1)
		else:
			k.box(p, Vector3(0.12, 0.08, 0.12), fleck)
	return k.build()

# ================================================================ humanoids

## Rig with pivots named Body, Head, ArmR, ArmL, LegR, LegL, HandR, HandL.
static func humanoid(opts: Dictionary) -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	var skin: Color = opts.get("skin", SKIN)
	var tunic: Color = opts.get("tunic", CLOTH)
	var legs_col: Color = opts.get("legs", CLOTH_DARK)
	var scale: float = opts.get("scale", 1.0)
	body.scale = Vector3.ONE * scale
	var hips := MeshKit.new(3)
	hips.box(Vector3(0, 0.66, 0), Vector3(0.36, 0.16, 0.22), legs_col.darkened(0.1))
	body.add_child(mi(hips))
	var torso := MeshKit.new(4)
	torso.prism(Vector3(0, 0.7, 0), 0.5, 0.19, 0.24, 6, tunic)
	torso.box(Vector3(0, 0.74, 0), Vector3(0.4, 0.05, 0.26), LEATHER)          # belt
	torso.box(Vector3(0.0, 0.74, -0.135), Vector3(0.08, 0.07, 0.02), GOLD)     # buckle
	var torso_mi := mi(torso)
	torso_mi.name = "Torso"
	body.add_child(torso_mi)
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.2, 0)
	body.add_child(head)
	var hk := MeshKit.new(5)
	hk.box(Vector3(0, 0.14, 0), Vector3(0.24, 0.26, 0.24), skin)
	hk.box(Vector3(0, 0.29, 0.02), Vector3(0.26, 0.07, 0.26), opts.get("hair", Color("3a2618")))
	hk.box(Vector3(0, 0.2, 0.1), Vector3(0.26, 0.16, 0.08), opts.get("hair", Color("3a2618")))
	hk.box(Vector3(-0.055, 0.16, -0.121), Vector3(0.04, 0.03, 0.01), Color("1a1410"))
	hk.box(Vector3(0.055, 0.16, -0.121), Vector3(0.04, 0.03, 0.01), Color("1a1410"))
	head.add_child(mi(hk))
	for side in [-1, 1]:
		var arm := Node3D.new()
		arm.name = "ArmR" if side > 0 else "ArmL"
		arm.position = Vector3(0.25 * side, 1.12, 0)
		body.add_child(arm)
		var ak := MeshKit.new(6)
		ak.box(Vector3(0, -0.12, 0), Vector3(0.12, 0.26, 0.13), tunic.darkened(0.08))
		ak.box(Vector3(0, -0.36, 0), Vector3(0.1, 0.24, 0.11), skin)
		arm.add_child(mi(ak))
		var hand := Node3D.new()
		hand.name = "HandR" if side > 0 else "HandL"
		hand.position = Vector3(0, -0.46, -0.02)
		arm.add_child(hand)
		var leg := Node3D.new()
		leg.name = "LegR" if side > 0 else "LegL"
		leg.position = Vector3(0.1 * side, 0.64, 0)
		body.add_child(leg)
		var lk := MeshKit.new(8)
		lk.box(Vector3(0, -0.3, 0), Vector3(0.14, 0.58, 0.16), legs_col)
		lk.box(Vector3(0, -0.58, -0.03), Vector3(0.15, 0.1, 0.22), LEATHER.darkened(0.2))
		leg.add_child(mi(lk))
	if opts.get("hood", false):
		var hood := MeshKit.new(10)
		var hc: Color = opts.get("cape_col", Color("7a2a22"))
		hood.prism(Vector3(0, 0.02, 0.03), 0.34, 0.2, 0.08, 6, hc.darkened(0.1))
		hood.box(Vector3(0, 0.16, 0.13), Vector3(0.28, 0.3, 0.06), hc.darkened(0.2))
		head.add_child(mi(hood))
	if opts.get("fantasy", false):
		var extra := MeshKit.new(11)
		extra.box(Vector3(0.12, 0.72, -0.14), Vector3(0.1, 0.12, 0.06), LEATHER.darkened(0.1))   # pouch
		extra.box(Vector3(0.12, 0.8, -0.17), Vector3(0.04, 0.03, 0.01), GOLD)
		extra.with(Transform3D(Basis(Vector3.BACK, 0.7), Vector3(0, 0.98, -0.13)), func(): extra.box(Vector3.ZERO, Vector3(0.05, 0.5, 0.02), LEATHER.darkened(0.25)))  # baldric
		extra.box(Vector3(0, 1.13, -0.12), Vector3(0.1, 0.05, 0.03), GOLD)                        # cloak clasp
		body.add_child(mi(extra))
		for side in [-1, 1]:
			var arm: Node3D = body.get_node("ArmR" if side > 0 else "ArmL")
			var pk := MeshKit.new(12)
			pk.sphere(Vector3(0.02 * side, 0.0, 0), Vector3(0.11, 0.07, 0.1), LEATHER.lightened(0.05), 6, 3)
			pk.box(Vector3(0, -0.33, 0), Vector3(0.12, 0.1, 0.13), LEATHER)                      # bracer
			arm.add_child(mi(pk))
			var leg: Node3D = body.get_node("LegR" if side > 0 else "LegL")
			var bk := MeshKit.new(13)
			bk.box(Vector3(0, -0.46, -0.01), Vector3(0.17, 0.08, 0.19), LEATHER.darkened(0.1))   # boot cuff
			leg.add_child(mi(bk))
	if opts.get("cape", true):
		var ck := MeshKit.new(9)
		ck.quad(Vector3(-0.2, 1.12, 0.13), Vector3(0.2, 1.12, 0.13), Vector3(0.26, 0.5, 0.26), Vector3(-0.26, 0.5, 0.26), opts.get("cape_col", Color("7a2a22")))
		ck.quad(Vector3(-0.26, 0.5, 0.265), Vector3(0.26, 0.5, 0.265), Vector3(0.2, 1.12, 0.135), Vector3(-0.2, 1.12, 0.135), opts.get("cape_col", Color("7a2a22")).darkened(0.3))
		var cape := mi(ck)
		cape.name = "Cape"
		body.add_child(cape)
	return root

static func player() -> Node3D:
	return humanoid({"tunic": Color("4e5a3e"), "legs": Color("3a3228"), "cape_col": Color("8a2e22"), "hood": true, "fantasy": true})

# ---------------------------------------------------------------- gear on the body

static func gear_mesh(item: Dictionary) -> Mesh:
	var key := "gear_%s_%s" % [item.recipe, item.res]
	return cached(key, func(): return _gear_mesh(item.recipe, item.res))

static func _gear_mesh(recipe: String, res: String) -> Mesh:
	var k := MeshKit.new(41)
	var c := material_color(res)
	var glow := glows(res)
	var accent := EMBER if res == "emberite" else (RUNE if glow else c.lightened(0.3))
	match recipe:
		"sword":
			k.box(Vector3(0, -0.02, 0), Vector3(0.05, 0.16, 0.05), LEATHER)
			k.box(Vector3(0, 0.07, 0), Vector3(0.22, 0.04, 0.06), c.darkened(0.2))
			k.box(Vector3(0, 0.42, 0), Vector3(0.08, 0.66, 0.025), c.lightened(0.15))
			k.shard(Vector3(0, 0.75, 0), 0.12, 0.04, c.lightened(0.25))
			if glow:
				k.box(Vector3(0, 0.42, 0), Vector3(0.02, 0.6, 0.03), accent, true)
		"warhammer":
			k.box(Vector3(0, 0.25, 0), Vector3(0.05, 0.85, 0.05), LEATHER.darkened(0.2))
			k.box(Vector3(0, 0.7, 0), Vector3(0.36, 0.2, 0.2), c)
			k.box(Vector3(-0.2, 0.7, 0), Vector3(0.05, 0.24, 0.24), c.darkened(0.2))
			k.shard(Vector3(0.18, 0.7, 0), 0.14, 0.05, c.lightened(0.2), false, Vector3(0.12, -0.1, 0))
			if glow:
				k.box(Vector3(0, 0.7, -0.101), Vector3(0.2, 0.06, 0.01), accent, true)
		"shortbow", "longbow":
			var h := 0.55 if recipe == "shortbow" else 0.75
			for i in 6:
				var t0 := float(i) / 6.0
				var t1 := float(i + 1) / 6.0
				var y0 := lerpf(-h, h, t0)
				var y1 := lerpf(-h, h, t1)
				var z0 := -0.22 * (1.0 - pow(2 * t0 - 1, 2))
				var z1 := -0.22 * (1.0 - pow(2 * t1 - 1, 2))
				k.quad(Vector3(-0.03, y0, z0), Vector3(0.03, y0, z0), Vector3(0.03, y1, z1), Vector3(-0.03, y1, z1), c)
				k.quad(Vector3(0.03, y0, z0 + 0.04), Vector3(-0.03, y0, z0 + 0.04), Vector3(-0.03, y1, z1 + 0.04), Vector3(0.03, y1, z1 + 0.04), c.darkened(0.2))
			k.box(Vector3(0, 0, -0.2), Vector3(0.06, 0.14, 0.06), LEATHER)
			k.box(Vector3(0, 0, 0.02), Vector3(0.008, h * 2, 0.008), Color("ddd4c0"))
			if glow:
				k.box(Vector3(0, 0.0, -0.24), Vector3(0.03, 0.3, 0.02), accent, true)
		"buckler":
			k.prism(Vector3(0, 0, 0), 0.06, 0.26, 0.24, 8, c)
			k.prism(Vector3(0, 0.06, 0), 0.05, 0.08, 0.05, 6, Color("8a8a8a"))
			k.prism(Vector3(0, -0.005, 0), 0.07, 0.27, 0.27, 8, Color("5a5a5a"), false, false)
			if glow:
				k.prism(Vector3(0, 0.061, 0), 0.01, 0.2, 0.2, 8, accent, true)
		"helm":
			k.prism(Vector3(0, 0.12, 0), 0.2, 0.17, 0.12, 8, c)
			k.box(Vector3(0, 0.12, 0), Vector3(0.36, 0.05, 0.36), c.darkened(0.15))
			k.box(Vector3(0, 0.12, -0.16), Vector3(0.05, 0.16, 0.04), c.darkened(0.1))
			k.shard(Vector3(0, 0.31, 0), 0.1, 0.03, accent, glow)
		"cuirass":
			k.prism(Vector3(0, 0.7, 0), 0.5, 0.215, 0.265, 6, c)
			k.box(Vector3(0.26, 1.13, 0), Vector3(0.16, 0.1, 0.24), c.darkened(0.15))
			k.box(Vector3(-0.26, 1.13, 0), Vector3(0.16, 0.1, 0.24), c.darkened(0.15))
			k.box(Vector3(0, 0.95, -0.24), Vector3(0.12, 0.18, 0.03), accent, glow)
	return k.build()

# ================================================================ creatures

## Returns a rig; animators look for Body, ArmR/ArmL, LegR/LegL, Head.
static func creature(kind: String) -> Node3D:
	match kind:
		"thornling": return _thornling()
		"wolf": return _wolf()
		"crawler": return _crawler()
		"golem": return _golem()
		"revenant": return _revenant()
		"imp": return _imp()
		"warden": return _warden()
	return humanoid({})

static func _rig() -> Array:
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	return [root, body]

static func _limb(parent: Node3D, name: String, pos: Vector3, kit: MeshKit) -> Node3D:
	var p := Node3D.new()
	p.name = name
	p.position = pos
	parent.add_child(p)
	p.add_child(mi(kit))
	return p

static func _thornling() -> Node3D:
	var r := _rig()
	var body: Node3D = r[1]
	var k := MeshKit.new(51)
	k.jitter = 0.04
	var green := Color("4a5a2a")
	k.sphere(Vector3(0, 0.45, 0), Vector3(0.3, 0.34, 0.28), green, 6, 4)
	k.sphere(Vector3(0, 0.82, -0.02), Vector3(0.2, 0.18, 0.2), green.lightened(0.05), 6, 3)
	k.jitter = 0.0
	for i in 9:
		var a := i * 2.4
		var y := 0.3 + (i % 3) * 0.2
		var dir := Vector3(cos(a), 0.4, sin(a)).normalized()
		k.shard(Vector3(cos(a) * 0.24, y, sin(a) * 0.24), 0.2, 0.035, Color("8a7a4a"), false, dir * 0.12)
	k.box(Vector3(-0.07, 0.85, -0.18), Vector3(0.05, 0.04, 0.02), Color("ffe070"), true)
	k.box(Vector3(0.07, 0.85, -0.18), Vector3(0.05, 0.04, 0.02), Color("ffe070"), true)
	body.add_child(mi(k))
	for side in [-1, 1]:
		var lk := MeshKit.new(52)
		lk.prism(Vector3(0, -0.3, 0), 0.3, 0.04, 0.06, 4, Color("3a4a22"))
		_limb(body, "LegR" if side > 0 else "LegL", Vector3(0.14 * side, 0.3, 0), lk)
		var ak := MeshKit.new(53)
		ak.prism(Vector3(0, -0.35, 0), 0.35, 0.02, 0.05, 4, Color("3a4a22"))
		ak.shard(Vector3(0, -0.4, 0), 0.08, 0.03, Color("8a7a4a"), false, Vector3(0, -0.12, -0.05))
		_limb(body, "ArmR" if side > 0 else "ArmL", Vector3(0.3 * side, 0.6, 0), ak)
	return r[0]

static func _wolf() -> Node3D:
	var r := _rig()
	var body: Node3D = r[1]
	var fur := Color("6e6a64")
	var k := MeshKit.new(61)
	k.jitter = 0.03
	k.box(Vector3(0, 0.62, 0.05), Vector3(0.36, 0.34, 0.8), fur, false, fur.lightened(0.1))
	k.box(Vector3(0, 0.7, -0.3), Vector3(0.42, 0.4, 0.3), fur.darkened(0.1))          # ruff
	k.jitter = 0.0
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.82, -0.48)
	body.add_child(head)
	var hk := MeshKit.new(62)
	hk.box(Vector3(0, 0, 0), Vector3(0.28, 0.26, 0.26), fur)
	hk.box(Vector3(0, -0.05, -0.2), Vector3(0.16, 0.13, 0.22), fur.lightened(0.08))
	hk.box(Vector3(0, -0.02, -0.32), Vector3(0.06, 0.05, 0.03), Color("1a1614"))
	hk.shard(Vector3(-0.09, 0.12, 0.05), 0.14, 0.04, fur.darkened(0.2))
	hk.shard(Vector3(0.09, 0.12, 0.05), 0.14, 0.04, fur.darkened(0.2))
	hk.box(Vector3(-0.07, 0.04, -0.131), Vector3(0.04, 0.03, 0.01), Color("ffd060"), true)
	hk.box(Vector3(0.07, 0.04, -0.131), Vector3(0.04, 0.03, 0.01), Color("ffd060"), true)
	head.add_child(mi(hk))
	var tk := MeshKit.new(63)
	tk.with(Transform3D(Basis(Vector3.RIGHT, 1.0), Vector3(0, 0.66, 0.45)), func(): tk.prism(Vector3.ZERO, 0.4, 0.07, 0.02, 5, fur.darkened(0.15)))
	body.add_child(mi(tk))
	var legs := {"LegR": Vector3(0.12, 0.45, -0.25), "LegL": Vector3(-0.12, 0.45, -0.25), "ArmR": Vector3(0.12, 0.45, 0.3), "ArmL": Vector3(-0.12, 0.45, 0.3)}
	for n in legs:
		var lk := MeshKit.new(64)
		lk.box(Vector3(0, -0.22, 0), Vector3(0.1, 0.46, 0.12), fur.darkened(0.15))
		_limb(body, n, legs[n], lk)
	return r[0]

static func _crawler() -> Node3D:
	var r := _rig()
	var body: Node3D = r[1]
	var shell := Color("3e3a4a")
	var k := MeshKit.new(71)
	k.jitter = 0.03
	k.sphere(Vector3(0, 0.35, 0.1), Vector3(0.42, 0.26, 0.5), shell, 8, 4)
	k.box(Vector3(0, 0.52, 0.1), Vector3(0.05, 0.08, 0.8), shell.lightened(0.15))
	k.sphere(Vector3(0, 0.3, -0.42), Vector3(0.24, 0.18, 0.2), shell.darkened(0.15), 6, 3)
	k.jitter = 0.0
	k.shard(Vector3(-0.1, 0.25, -0.55), 0.22, 0.03, Color("c8b890"), false, Vector3(0.1, -0.1, -0.18))
	k.shard(Vector3(0.1, 0.25, -0.55), 0.22, 0.03, Color("c8b890"), false, Vector3(-0.1, -0.1, -0.18))
	for x in [-0.09, 0.09]:
		k.box(Vector3(x, 0.36, -0.6), Vector3(0.05, 0.05, 0.02), Color("b0ff70").lerp(Color("ffd060"), 0.6), true)
	body.add_child(mi(k))
	var i := 0
	for z in [-0.2, 0.1, 0.4]:
		for side in [-1, 1]:
			var lk := MeshKit.new(72)
			lk.with(Transform3D(Basis(Vector3.FORWARD, -0.9 * side), Vector3.ZERO), func(): lk.box(Vector3(0, -0.2, 0), Vector3(0.05, 0.4, 0.05), shell.darkened(0.3)))
			var names := ["LegR", "LegL", "ArmR", "ArmL", "Leg5", "Leg6"]
			_limb(body, names[i], Vector3(0.36 * side, 0.3, z), lk)
			i += 1
	return r[0]

static func _golem() -> Node3D:
	var r := _rig()
	var body: Node3D = r[1]
	body.scale = Vector3.ONE * 1.15
	var k := MeshKit.new(81)
	k.jitter = 0.05
	k.box(Vector3(0, 0.95, 0), Vector3(0.8, 0.7, 0.55), STONE_DARK)
	k.box(Vector3(0, 0.55, 0), Vector3(0.55, 0.3, 0.45), STONE_DARK.darkened(0.1))
	k.box(Vector3(0, 1.45, -0.05), Vector3(0.36, 0.3, 0.34), STONE)
	k.jitter = 0.0
	# Jagged magma seams across the chest.
	var seam := [Vector3(-0.3, 1.2, 0), Vector3(-0.12, 1.05, 0), Vector3(-0.18, 0.9, 0), Vector3(0.05, 0.78, 0), Vector3(0.0, 0.66, 0)]
	var branch := [Vector3(-0.12, 1.05, 0), Vector3(0.12, 1.12, 0), Vector3(0.28, 1.0, 0)]
	for line in [seam, branch]:
		for i in line.size() - 1:
			var a: Vector3 = line[i]
			var b: Vector3 = line[i + 1]
			var mid := (a + b) * 0.5 + Vector3(0, 0, -0.28)
			var ang := atan2(b.y - a.y, b.x - a.x)
			k.with(Transform3D(Basis(Vector3.BACK, ang), mid), func(): k.box(Vector3.ZERO, Vector3(a.distance_to(b) + 0.03, 0.045, 0.02), EMBER, true))
	k.box(Vector3(-0.08, 1.48, -0.23), Vector3(0.06, 0.05, 0.02), EMBER, true)
	k.box(Vector3(0.08, 1.48, -0.23), Vector3(0.06, 0.05, 0.02), EMBER, true)
	body.add_child(mi(k))
	for side in [-1, 1]:
		var ak := MeshKit.new(82)
		ak.jitter = 0.04
		ak.box(Vector3(0, -0.2, 0), Vector3(0.28, 0.45, 0.3), STONE)
		ak.box(Vector3(0, -0.6, 0), Vector3(0.34, 0.4, 0.34), STONE_DARK)
		_limb(body, "ArmR" if side > 0 else "ArmL", Vector3(0.55 * side, 1.2, 0), ak)
		var lk := MeshKit.new(83)
		lk.jitter = 0.04
		lk.box(Vector3(0, -0.22, 0), Vector3(0.28, 0.46, 0.3), STONE_DARK)
		_limb(body, "LegR" if side > 0 else "LegL", Vector3(0.2 * side, 0.45, 0), lk)
	return r[0]

static func _revenant() -> Node3D:
	var r := _rig()
	var body: Node3D = r[1]
	var ash := Color("5a5650")
	var k := MeshKit.new(91)
	k.jitter = 0.04
	k.prism(Vector3(0, 0.15, 0), 1.0, 0.36, 0.16, 7, ash.darkened(0.2))
	k.prism(Vector3(0, 0.95, 0), 0.4, 0.2, 0.05, 6, ash)
	k.jitter = 0.0
	k.box(Vector3(0, 1.1, -0.11), Vector3(0.16, 0.14, 0.04), Color("141210"))
	k.box(Vector3(-0.04, 1.12, -0.135), Vector3(0.035, 0.025, 0.01), Color("9ad0ff").lerp(Color("ffffff"), 0.4), true)
	k.box(Vector3(0.04, 1.12, -0.135), Vector3(0.035, 0.025, 0.01), Color("9ad0ff").lerp(Color("ffffff"), 0.4), true)
	for i in 7:
		var a := i * TAU / 7
		k.shard(Vector3(cos(a) * 0.3, 0.2, sin(a) * 0.3), -0.18, 0.05, ash.darkened(0.3))
	body.add_child(mi(k))
	for side in [-1, 1]:
		var ak := MeshKit.new(92)
		ak.box(Vector3(0, -0.2, 0), Vector3(0.1, 0.42, 0.1), ash.darkened(0.1))
		ak.box(Vector3(0, -0.43, 0), Vector3(0.06, 0.1, 0.06), Color("bdb6a6"))
		var arm := _limb(body, "ArmR" if side > 0 else "ArmL", Vector3(0.24 * side, 0.95, 0), ak)
		if side < 0:
			var bow := MeshInstance3D.new()
			bow.mesh = gear_mesh({"recipe": "longbow", "res": "elderheart"})
			bow.position = Vector3(0, -0.45, -0.05)
			bow.rotation = Vector3(0, PI / 2, 0)
			arm.add_child(bow)
	return r[0]

static func _imp() -> Node3D:
	var r := _rig()
	var body: Node3D = r[1]
	var k := MeshKit.new(101)
	var skin := Color("3a2420")
	k.sphere(Vector3(0, 0.4, 0), Vector3(0.2, 0.24, 0.18), skin, 6, 3)
	k.sphere(Vector3(0, 0.72, 0), Vector3(0.16, 0.15, 0.15), skin.lightened(0.05), 6, 3)
	k.shard(Vector3(-0.1, 0.8, 0), 0.16, 0.03, Color("d8c8a0"), false, Vector3(-0.08, 0, 0.04))
	k.shard(Vector3(0.1, 0.8, 0), 0.16, 0.03, Color("d8c8a0"), false, Vector3(0.08, 0, 0.04))
	k.sphere(Vector3(0, 0.42, -0.1), Vector3(0.1, 0.12, 0.08), EMBER, 5, 3, true)
	k.box(Vector3(-0.05, 0.74, -0.14), Vector3(0.04, 0.03, 0.01), Color("ffe070"), true)
	k.box(Vector3(0.05, 0.74, -0.14), Vector3(0.04, 0.03, 0.01), Color("ffe070"), true)
	body.add_child(mi(k))
	for side in [-1, 1]:
		var lk := MeshKit.new(102)
		lk.box(Vector3(0, -0.12, 0), Vector3(0.07, 0.24, 0.07), skin)
		_limb(body, "LegR" if side > 0 else "LegL", Vector3(0.08 * side, 0.22, 0), lk)
		var ak := MeshKit.new(103)
		ak.box(Vector3(0, -0.12, 0), Vector3(0.06, 0.24, 0.06), skin)
		_limb(body, "ArmR" if side > 0 else "ArmL", Vector3(0.2 * side, 0.5, 0), ak)
	return r[0]

static func _warden() -> Node3D:
	# A furnace-hearted giant in blackened plate; stands on a 2x2 footprint.
	var r := _rig()
	var body: Node3D = r[1]
	var plate := Color("2e2a28")
	var trim := Color("8a6a3a")
	var k := MeshKit.new(111)
	k.prism(Vector3(0, 1.3, 0), 1.2, 0.62, 0.8, 8, plate)                    # chest
	k.prism(Vector3(0, 1.0, 0), 0.32, 0.5, 0.6, 8, plate.darkened(0.2))      # waist
	k.prism(Vector3(0, 1.36, -0.02), 0.05, 0.64, 0.64, 8, trim, false, false)
	k.prism(Vector3(0, 2.44, 0), 0.06, 0.8, 0.8, 8, trim, false, false)
	# Furnace core behind a grille.
	k.sphere(Vector3(0, 1.85, -0.58), Vector3(0.28, 0.3, 0.12), EMBER, 6, 3, true)
	for x in [-0.14, 0.0, 0.14]:
		k.box(Vector3(x, 1.85, -0.7), Vector3(0.04, 0.6, 0.04), plate.darkened(0.3))
	for side in [-1, 1]:
		k.sphere(Vector3(0.82 * side, 2.35, 0), Vector3(0.36, 0.26, 0.4), plate.lightened(0.05), 6, 3)
		for i in 3:
			k.shard(Vector3(0.82 * side + 0.1 * side * i, 2.5, -0.15 + 0.15 * i), 0.35, 0.05, trim.darkened(0.2), false, Vector3(0.15 * side, 0, 0))
	k.box(Vector3(0, 0.55, 0), Vector3(1.0, 0.5, 0.7), plate.darkened(0.1))
	k.box(Vector3(0, 0.55, -0.36), Vector3(0.5, 0.6, 0.04), Color("5a2a1e"))    # tabard
	body.add_child(mi(k))
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 2.55, 0)
	body.add_child(head)
	var hk := MeshKit.new(112)
	hk.prism(Vector3(0, 0, 0), 0.5, 0.3, 0.22, 6, plate)
	hk.box(Vector3(0, 0.22, -0.2), Vector3(0.34, 0.05, 0.08), EMBER, true)       # visor slit
	for side in [-1, 1]:
		hk.with(Transform3D(Basis(Vector3.FORWARD, -0.7 * side), Vector3(0.25 * side, 0.35, 0)),
			func(): hk.prism(Vector3.ZERO, 0.6, 0.08, 0.0, 5, Color("d8cfb8")))
	head.add_child(mi(hk))
	for side in [-1, 1]:
		var ak := MeshKit.new(113)
		ak.box(Vector3(0, -0.35, 0), Vector3(0.36, 0.7, 0.38), plate)
		ak.box(Vector3(0, -0.95, 0), Vector3(0.32, 0.55, 0.34), plate.lightened(0.05))
		ak.box(Vector3(0, -0.72, 0), Vector3(0.38, 0.08, 0.4), trim)
		var arm := _limb(body, "ArmR" if side > 0 else "ArmL", Vector3(1.0 * side, 2.2, 0), ak)
		if side > 0:
			var hammer := MeshKit.new(114)
			hammer.box(Vector3(0, -0.4, 0), Vector3(0.1, 2.0, 0.1), LEATHER.darkened(0.3))
			hammer.box(Vector3(0, -1.5, 0), Vector3(0.7, 0.5, 0.5), Color("3a3432"))
			hammer.box(Vector3(0, -1.5, -0.26), Vector3(0.5, 0.3, 0.02), EMBER, true)
			hammer.box(Vector3(0, -1.5, 0.26), Vector3(0.5, 0.3, 0.02), EMBER, true)
			var h := mi(hammer)
			h.position = Vector3(0, -1.1, -0.1)
			h.rotation = Vector3(-PI / 2, 0, 0)
			h.name = "Hammer"
			arm.add_child(h)
		var lk := MeshKit.new(115)
		lk.box(Vector3(0, -0.3, 0), Vector3(0.4, 0.6, 0.44), plate)
		lk.box(Vector3(0, -0.55, -0.06), Vector3(0.44, 0.2, 0.56), plate.darkened(0.2))
		_limb(body, "LegR" if side > 0 else "LegL", Vector3(0.32 * side, 0.6, 0), lk)
	var light := OmniLight3D.new()
	light.light_color = EMBER
	light.light_energy = 1.4
	light.omni_range = 4.0
	light.position = Vector3(0, 1.9, -1.0)
	body.add_child(light)
	return r[0]

# ================================================================ stations & props

static func flame(scale_: float) -> Node3D:
	var f := mesh_node("flame", func():
		var k := MeshKit.new(77)
		k.shard(Vector3.ZERO, 0.5, 0.13, EMBER, true)
		k.shard(Vector3(0.04, 0, 0.03), 0.34, 0.09, Color("ffc060"), true)
		k.shard(Vector3(-0.05, 0, -0.02), 0.28, 0.07, Color("ff9a40"), true, Vector3(-0.04, 0, 0))
		return k.build())
	f.name = "Flame"
	f.scale = Vector3.ONE * scale_
	var holder := Node3D.new()
	holder.add_child(f)
	holder.scale = Vector3.ONE * scale_
	f.scale = Vector3.ONE
	return holder

## Slow rising sparks over a fire.
static func embers(amount: int, spread: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.035
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.6, 0.7, 0.25)
	bm.material = mat
	p.mesh = bm
	p.amount = amount
	p.lifetime = 1.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = spread
	p.direction = Vector3.UP
	p.spread = 15.0
	p.gravity = Vector3(0, 0.6, 0)
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.8
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	return p

static func station(kind: String) -> Node3D:
	var root := Node3D.new()
	root.add_child(mesh_node("station_" + kind, func(): return _station_mesh(kind)))
	match kind:
		"hearth":
			var f := flame(1.0)
			f.position = Vector3(0, 0.05, 0)
			root.add_child(f)
			var e := embers(14, 0.15)
			e.position = Vector3(0, 0.4, 0)
			root.add_child(e)
		"anvil":
			var f := flame(0.6)
			f.position = Vector3(0, 0.48, 0.55)
			root.add_child(f)
		"stash":
			var lid := Node3D.new()
			lid.name = "Lid"
			lid.position = Vector3(0, 0.5, 0.275)
			var lk := MeshKit.new(122)
			lk.box(Vector3(0, 0.07, -0.275), Vector3(0.84, 0.14, 0.59), Color("5a3a22"), false, Color("6a4428"))
			for x in [-0.3, 0.3]:
				lk.box(Vector3(x, 0.08, -0.275), Vector3(0.06, 0.15, 0.6), Color("4a4a4c"))
			lid.add_child(mi(lk))
			root.add_child(lid)
	if kind == "hearth" or kind == "anvil":
		var l := OmniLight3D.new()
		l.light_color = Color("ff9a50")
		l.light_energy = 1.6 if kind == "hearth" else 0.9
		l.omni_range = 5.0 if kind == "hearth" else 3.0
		l.position = Vector3(0, 0.8, 0)
		l.name = "Flicker"
		root.add_child(l)
	if kind == "shrine":
		var l := OmniLight3D.new()
		l.light_color = RUNE
		l.light_energy = 0.8
		l.omni_range = 3.5
		l.position = Vector3(0, 1.4, 0)
		root.add_child(l)
		var crystal := MeshInstance3D.new()
		crystal.name = "Spin"
		var ck := MeshKit.new(5)
		ck.shard(Vector3(0, 0, 0), 0.34, 0.1, RUNE, true)
		ck.shard(Vector3(0, 0, 0), -0.24, 0.1, RUNE.darkened(0.2), true)
		crystal.mesh = ck.build()
		crystal.position = Vector3(0, 1.25, 0)
		root.add_child(crystal)
	return root

static func _station_mesh(kind: String) -> Mesh:
	var k := MeshKit.new(121)
	match kind:
		"stash":
			k.box(Vector3(0, 0.25, 0), Vector3(0.8, 0.5, 0.55), Color("6a4428"), false, Color("7a5230"))
			for x in [-0.3, 0.3]:
				k.box(Vector3(x, 0.26, 0), Vector3(0.06, 0.52, 0.6), Color("4a4a4c"))
			k.box(Vector3(0, 0.42, -0.29), Vector3(0.12, 0.14, 0.03), GOLD)
			k.box(Vector3(0, 0.46, 0), Vector3(0.74, 0.04, 0.5), Color("1a1410"))
		"anvil":
			k.prism(Vector3(0, 0, 0), 0.35, 0.3, 0.26, 7, BARK)
			k.box(Vector3(0, 0.45, 0), Vector3(0.22, 0.2, 0.18), Color("3a3a3e"))
			k.box(Vector3(0, 0.6, 0), Vector3(0.6, 0.12, 0.24), Color("4a4a50"), false, Color("6a6a70"))
			k.shard(Vector3(0.3, 0.6, 0), 0.2, 0.06, Color("4a4a50"), false, Vector3(0.18, -0.12, 0))
			# Forge brazier behind.
			k.prism(Vector3(0, 0, 0.55), 0.5, 0.3, 0.36, 8, STONE_DARK)
			k.sphere(Vector3(0, 0.46, 0.55), Vector3(0.26, 0.08, 0.26), Color("ff5a20"), 6, 2, true)
		"bench":
			k.box(Vector3(0, 0.5, 0), Vector3(0.9, 0.08, 0.5), Color("8a5a32"), false, Color("9a6a3a"))
			for x in [-0.38, 0.38]:
				for z in [-0.18, 0.18]:
					k.box(Vector3(x, 0.24, z), Vector3(0.07, 0.48, 0.07), Color("6a4428"))
			k.box(Vector3(-0.1, 0.57, 0), Vector3(0.55, 0.05, 0.06), WOOD_COLORS.pine)
			k.box(Vector3(0.25, 0.56, 0.1), Vector3(0.06, 0.04, 0.3), Color("ddd4c0"))
			for i in 4:
				k.shard(Vector3(0.3 + i * 0.03, 0.56, -0.12), 0.1, 0.015, Color("c04a2a"))
		"shrine":
			for i in 5:
				var a := i * TAU / 5
				var h := 1.0 + 0.25 * (i % 2)
				k.jitter = 0.03
				k.box(Vector3(cos(a) * 0.38, h * 0.5, sin(a) * 0.38), Vector3(0.14, h, 0.1), STONE.darkened(0.1))
				k.jitter = 0.0
				k.box(Vector3(cos(a) * 0.31, h * 0.6, sin(a) * 0.31), Vector3(0.05, 0.18, 0.05), RUNE, true)
			k.prism(Vector3(0, 0, 0), 0.08, 0.5, 0.48, 10, STONE_DARK)
		"hearth":
			for i in 8:
				var a := i * TAU / 8
				k.jitter = 0.03
				k.sphere(Vector3(cos(a) * 0.35, 0.08, sin(a) * 0.35), Vector3(0.12, 0.1, 0.12), STONE, 5, 2)
				k.jitter = 0.0
			for i in 4:
				k.with(Transform3D(Basis(Vector3.UP, i * PI / 4) * Basis(Vector3.FORWARD, PI / 2 - 0.25), Vector3(0, 0.08, 0)),
					func(): k.prism(Vector3(0, -0.3, 0), 0.6, 0.05, 0.05, 5, BARK))
			k.sphere(Vector3(0, 0.06, 0), Vector3(0.2, 0.05, 0.2), Color("ff5a20"), 6, 2, true)
	return k.build()

static func prop(kind: String, variant: int) -> Node3D:
	var root := Node3D.new()
	root.add_child(mesh_node("prop_%s_%d" % [kind, variant % 2], func(): return _prop_mesh(kind, variant % 2)))
	if kind == "brazier":
		var f := flame(0.9)
		f.position = Vector3(0, 0.95, 0)
		root.add_child(f)
		var e := embers(10, 0.12)
		e.position = Vector3(0, 1.3, 0)
		root.add_child(e)
	if kind == "brazier" or kind == "lantern":
		var l := OmniLight3D.new()
		l.light_color = Color("ff9a50")
		l.light_energy = 1.3 if kind == "brazier" else 0.8
		l.omni_range = 4.5 if kind == "brazier" else 3.5
		l.position = Vector3(0, 1.2 if kind == "brazier" else 1.5, 0)
		l.name = "Flicker"
		root.add_child(l)
	root.rotation.y = variant * 1.3
	return root

static func _prop_mesh(kind: String, v: int) -> Mesh:
	var k := MeshKit.new(131 + v)
	match kind:
		"boulder":
			k.jitter = 0.1
			k.sphere(Vector3(0, 0.3, 0), Vector3(0.5, 0.45, 0.45), STONE, 7, 3)
			k.sphere(Vector3(0.3, 0.2, 0.25), Vector3(0.25, 0.22, 0.25), STONE.darkened(0.1), 5, 3)
		"brazier":
			k.prism(Vector3.ZERO, 0.8, 0.18, 0.12, 6, Color("2a2624"))
			k.prism(Vector3(0, 0.8, 0), 0.25, 0.2, 0.36, 8, Color("3a3432"))
			k.sphere(Vector3(0, 0.96, 0), Vector3(0.16, 0.05, 0.16), Color("ff5a20"), 6, 2, true)
		"lantern":
			k.prism(Vector3.ZERO, 1.4, 0.06, 0.05, 5, BARK.darkened(0.2))
			k.box(Vector3(0.15, 1.35, 0), Vector3(0.32, 0.05, 0.05), BARK.darkened(0.2))
			k.box(Vector3(0.28, 1.18, 0), Vector3(0.16, 0.2, 0.16), Color("2a2624"))
			k.box(Vector3(0.28, 1.18, 0), Vector3(0.12, 0.14, 0.17), Color("ffc060"), true)
	return k.build()

# ================================================================ buildings

## A timber-framed hall over a w x d footprint, roof ridge along the long side.
static func hall(w: int, d: int, seed_value: int) -> MeshInstance3D:
	var k := MeshKit.new(seed_value)
	var hw := w * 0.5 - 0.05
	var hd := d * 0.5 - 0.05
	var wall_h := 1.5
	k.box(Vector3(0, 0.15, 0), Vector3(w, 0.3, d), STONE.darkened(0.05))
	k.box(Vector3(0, 0.3 + wall_h * 0.5, 0), Vector3(hw * 2, wall_h, hd * 2), Color("cdbf9e"))
	# Dark timber frame.
	var beam := Color("3e2a1c")
	for x in [-hw, hw]:
		for z in [-hd, hd]:
			k.box(Vector3(x, 0.3 + wall_h * 0.5, z), Vector3(0.14, wall_h, 0.14), beam)
	for z in [-hd - 0.01, hd + 0.01]:
		k.box(Vector3(0, 0.3 + wall_h, z), Vector3(hw * 2, 0.12, 0.06), beam)
		k.box(Vector3(0, 0.95, z), Vector3(hw * 2, 0.1, 0.06), beam)
		for i in range(1, w):
			k.box(Vector3(-hw + i * (2 * hw / w), 0.3 + wall_h * 0.5, z), Vector3(0.1, wall_h, 0.06), beam)
	for x in [-hw - 0.01, hw + 0.01]:
		k.box(Vector3(x, 0.3 + wall_h, 0), Vector3(0.06, 0.12, hd * 2), beam)
	# Door and a lit window on the long south face.
	k.box(Vector3(0, 0.75, hd + 0.02), Vector3(0.5, 0.9, 0.04), Color("4a3020"))
	k.box(Vector3(-hw * 0.55, 1.3, hd + 0.03), Vector3(0.3, 0.26, 0.03), Color("ffc070"), true)
	k.box(Vector3(hw * 0.55, 1.3, hd + 0.03), Vector3(0.3, 0.26, 0.03), Color("ffc070"), true)
	# Steep gable roof with overhang.
	var y0 := 0.3 + wall_h
	var ridge := y0 + 1.3
	var ox := hw + 0.25
	var oz := hd + 0.3
	var roof := Color("5a3a2e")
	k.quad(Vector3(-ox, y0 - 0.1, -oz), Vector3(ox, y0 - 0.1, -oz), Vector3(ox, ridge, 0), Vector3(-ox, ridge, 0), roof)
	k.quad(Vector3(ox, y0 - 0.1, oz), Vector3(-ox, y0 - 0.1, oz), Vector3(-ox, ridge, 0), Vector3(ox, ridge, 0), roof.darkened(0.15))
	for x in [-hw, hw]:
		var s := signf(x)
		if s > 0:
			k.tri(Vector3(x, y0, -hd), Vector3(x, ridge - 0.1, 0), Vector3(x, y0, hd), Color("b8a888"))
		else:
			k.tri(Vector3(x, y0, hd), Vector3(x, ridge - 0.1, 0), Vector3(x, y0, -hd), Color("b8a888"))
	k.box(Vector3(0, ridge + 0.03, 0), Vector3(ox * 2 + 0.1, 0.1, 0.14), beam)
	# Shingle rows.
	for i in 4:
		var t := (i + 0.5) / 4.0
		var y := lerpf(y0 - 0.1, ridge, t)
		for sz in [-1, 1]:
			k.box(Vector3(0, y + 0.02, sz * lerpf(oz, 0, t)), Vector3(ox * 2, 0.04, 0.08), roof.darkened(0.25))
	# Chimney.
	k.box(Vector3(hw * 0.5, ridge, -hd * 0.3), Vector3(0.35, 1.2, 0.35), STONE_DARK)
	var m := MeshInstance3D.new()
	m.mesh = k.build()
	return m

# ================================================================ items for icons

static func item_mesh(item: Dictionary) -> Mesh:
	match item.kind:
		"component":
			return cached("icon_comp_" + item.res, func(): return _component_mesh(item.res))
		"reagent":
			return cached("icon_shard", func(): return _shard_mesh())
		"gear":
			return gear_mesh(item)
	return null

static func _component_mesh(res: String) -> Mesh:
	var k := MeshKit.new(141)
	var fam: String = Defs.RESOURCES[res].family
	var c := material_color(res)
	if fam == "log":
		k.with(Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(0.35, 0, 0)), func():
			k.prism(Vector3.ZERO, 0.7, 0.16, 0.16, 7, BARK.lerp(c, 0.35)))
		k.with(Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(-0.351, 0, 0)), func():
			k.prism(Vector3.ZERO, 0.001, 0.15, 0.15, 7, c.lightened(0.25)))
		if glows(res):
			k.box(Vector3(0, 0.15, 0), Vector3(0.3, 0.03, 0.06), RUNE, true)
	else:
		k.jitter = 0.05
		k.sphere(Vector3.ZERO, Vector3(0.28, 0.22, 0.25), STONE_DARK, 6, 3)
		k.jitter = 0.0
		k.shard(Vector3(0.05, 0.05, 0), 0.22, 0.07, ORE_FLECK[res], glows(res), Vector3(0.05, 0, 0))
		k.box(Vector3(-0.12, 0.12, -0.1), Vector3(0.1, 0.08, 0.1), ORE_FLECK[res])
	return k.build()

static func _shard_mesh() -> Mesh:
	var k := MeshKit.new(151)
	k.shard(Vector3(0, -0.25, 0), 0.5, 0.12, EMBER, true)
	k.shard(Vector3(0.12, -0.25, 0.05), 0.3, 0.07, Color("ffc060"), true, Vector3(0.08, 0, 0))
	k.shard(Vector3(-0.12, -0.25, -0.03), 0.26, 0.06, Color("d8402a"), true, Vector3(-0.07, 0, 0))
	return k.build()
