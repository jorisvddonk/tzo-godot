extends SceneTree

const TestTzoVM := preload("res://tests/test_tzo_vm.gd")
const TestQuestVM := preload("res://tests/test_quest_vm.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	print("Running tzo-godot tests...")
	TestTzoVM.new().run(self)
	TestQuestVM.new().run(self)
	print("")
	print("Checks: %d, Failures: %d" % [checks, failures])
	if failures > 0:
		print("TESTS FAILED")
		quit(1)
	else:
		print("All tests passed.")
		quit(0)


func ok(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("  FAIL: %s" % message)


func eq(actual, expected, message: String) -> void:
	checks += 1
	if actual != expected:
		failures += 1
		print("  FAIL: %s\n    expected: %s\n    actual:   %s" % [message, str(expected), str(actual)])
