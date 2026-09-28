extends SceneTree
## Headless test runner: godot --headless --path . -s tests/run_tests.gd

var failures := 0
var passes := 0
var current := ""

func _init() -> void:
	var suites := [
		preload("res://tests/test_rules.gd").new(),
		preload("res://tests/test_world.gd").new(),
		preload("res://tests/test_warden.gd").new(),
	]
	for suite in suites:
		suite.t = self
		for m in suite.get_method_list():
			if m.name.begins_with("test_"):
				current = m.name
				suite.call(m.name)
	print("\n%d passed, %d failed" % [passes, failures])
	quit(1 if failures > 0 else 0)

func ok(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
	else:
		failures += 1
		printerr("FAIL %s: %s" % [current, msg])

func eq(a, b, msg: String) -> void:
	ok(a == b, "%s (got %s, want %s)" % [msg, str(a), str(b)])
