extends RefCounted

const QuestVM := preload("res://addons/tzo/quest_vm.gd")

const HELLO := "res://tests/data/hello.json"
const CHOICES := "res://tests/data/choices.json"
const ECHO := "res://tests/data/echo.json"
const CHOICE_A := "res://tests/data/choice_a.json"
const CHOICE_B := "res://tests/data/choice_b.json"


func run(t) -> void:
	_test_backend_selection(t)
	_test_emit(t)
	_test_responses(t)
	_test_push_helpers(t)
	_test_instance_isolation(t)
	_test_clear_response_map(t)
	_test_missing_file(t)
	_test_collected_text(t)
	_test_native_parity(t)
	_test_native_isolation(t)


# --- Helpers ---------------------------------------------------------------

func _new_script_vm(path: String) -> QuestVM:
	var vm := QuestVM.new()
	vm.prefer_native = false
	vm.file_path = path
	return vm


func _new_native_vm(path: String) -> QuestVM:
	var vm := QuestVM.new()
	vm.prefer_native = true
	vm.file_path = path
	return vm


func _collect(vm: QuestVM) -> Dictionary:
	var result := {"emitted": [], "items": [], "starts": 0, "ends": 0}
	vm.questvm_emit.connect(func(text: String) -> void: result["emitted"].append(text))
	vm.questvm_getresponse_start.connect(func() -> void: result["starts"] += 1)
	vm.questvm_getresponse_end.connect(func() -> void: result["ends"] += 1)
	vm.questvm_getresponse_item.connect(
		func(id: int, pc: int, text: String) -> void: result["items"].append([id, pc, text])
	)
	vm.initTzoVM()
	vm.run()
	return result


# --- Tests -----------------------------------------------------------------

func _test_backend_selection(t) -> void:
	var auto := QuestVM.new()
	auto.file_path = HELLO
	auto.initTzoVM()
	var expected := "native" if ClassDB.class_exists("TzoVMNative") else "script"
	t.eq(auto.backend, expected, "auto backend matches available native class")
	auto.free()

	var forced := _new_script_vm(HELLO)
	forced.initTzoVM()
	t.eq(forced.backend, "script", "prefer_native=false forces the script backend")
	forced.free()


func _test_emit(t) -> void:
	var vm := _new_script_vm(HELLO)
	var emitted: Array = []
	vm.questvm_emit.connect(func(text: String) -> void: emitted.append(text))
	vm.initTzoVM()
	vm.run()
	t.eq(emitted, ["Hello World"], "questvm_emit fires with the concatenated text")
	t.eq(vm.collected_text, "Hello World", "collected text accumulates emitted text")
	vm.free()


func _test_responses(t) -> void:
	var vm := _new_script_vm(CHOICES)
	var starts := [0]
	var ends := [0]
	var items: Array = []
	vm.questvm_getresponse_start.connect(func() -> void: starts[0] += 1)
	vm.questvm_getresponse_end.connect(func() -> void: ends[0] += 1)
	vm.questvm_getresponse_item.connect(
		func(id: int, pc: int, text: String) -> void: items.append([id, pc, text])
	)
	vm.initTzoVM()
	vm.run()
	t.eq(starts[0], 1, "getresponse_start fires once")
	t.eq(ends[0], 1, "getresponse_end fires once")
	t.eq(items, [[1, 10, "Option A"], [2, 20, "Option B"]], "responses are emitted in order")
	t.eq(vm.getResponseMap().size(), 2, "response map holds both responses")
	vm.free()


func _test_push_helpers(t) -> void:
	var vm := _new_script_vm(ECHO)
	var emitted: Array = []
	vm.questvm_emit.connect(func(text: String) -> void: emitted.append(text))
	vm.initTzoVM()
	vm.pushString("hello")
	vm.run()
	t.eq(emitted, ["hello"], "pushString feeds the VM stack")
	vm.free()

	var vm2 := _new_script_vm(ECHO)
	var emitted2: Array = []
	vm2.questvm_emit.connect(func(text: String) -> void: emitted2.append(text))
	vm2.initTzoVM()
	vm2.pushNumber(3.0)
	vm2.run()
	t.eq(emitted2, ["3"], "pushNumber feeds the VM stack")
	vm2.free()


func _test_instance_isolation(t) -> void:
	var first := _new_script_vm(HELLO)
	var second := _new_script_vm(CHOICES)
	var emitted: Array = []
	second.questvm_emit.connect(func(text: String) -> void: emitted.append(text))
	first.initTzoVM()
	second.initTzoVM()
	first.run()
	second.run()
	t.eq(first.getResponseMap().size(), 0, "first instance response map is untouched")
	t.eq(second.getResponseMap().size(), 2, "second instance keeps its own responses")
	t.eq(first.collected_text, "Hello World", "first instance collected its own text")
	first.free()
	second.free()


func _test_clear_response_map(t) -> void:
	var vm := _new_script_vm(CHOICES)
	vm.initTzoVM()
	vm.run()
	t.eq(vm.getResponseMap().size(), 2, "responses registered")
	vm.clearResponseMap()
	t.eq(vm.getResponseMap().size(), 0, "clearResponseMap empties the map")
	vm.free()


func _test_missing_file(t) -> void:
	var vm := _new_script_vm("res://tests/data/does_not_exist.json")
	vm.initTzoVM()
	vm.run()
	t.eq(vm.getResponseMap().size(), 0, "missing file does not crash")
	t.eq(vm.collected_text, "", "missing file emits nothing")
	vm.free()


func _test_collected_text(t) -> void:
	var vm := _new_script_vm(HELLO)
	vm.initTzoVM()
	vm.run()
	t.eq(vm.getCollectedText(), "Hello World", "getCollectedText returns emitted text")
	vm.clearCollectedText()
	t.eq(vm.getCollectedText(), "", "clearCollectedText empties collected text")
	vm.free()


func _test_native_parity(t) -> void:
	if not ClassDB.class_exists("TzoVMNative"):
		print("  (skipping native parity tests: native extension not loaded)")
		return

	for path in [HELLO, CHOICES]:
		var script_vm := _new_script_vm(path)
		var native_vm := _new_native_vm(path)
		var script_result := _collect(script_vm)
		var native_result := _collect(native_vm)
		t.eq(native_result["emitted"], script_result["emitted"], "native emit matches script for %s" % path)
		t.eq(native_result["items"], script_result["items"], "native responses match script for %s" % path)
		t.eq(native_result["starts"], script_result["starts"], "native getresponse_start matches script")
		t.eq(native_result["ends"], script_result["ends"], "native getresponse_end matches script")
		t.eq(native_vm.getCollectedText(), script_vm.getCollectedText(), "native collected text matches script")
		script_vm.free()
		native_vm.free()


func _test_native_isolation(t) -> void:
	if not ClassDB.class_exists("TzoVMNative"):
		print("  (skipping native isolation tests: native extension not loaded)")
		return

	# Interleave two native instances; state must not leak between them.
	var first := _new_native_vm(CHOICE_A)
	var second := _new_native_vm(CHOICE_B)
	first.initTzoVM()
	second.initTzoVM()
	# _collect calls init/run, so connect manually to keep the interleaving.
	var first_items: Array = []
	var second_items: Array = []
	first.questvm_getresponse_item.connect(
		func(id: int, pc: int, text: String) -> void: first_items.append([id, pc, text])
	)
	second.questvm_getresponse_item.connect(
		func(id: int, pc: int, text: String) -> void: second_items.append([id, pc, text])
	)
	first.run()
	second.run()
	t.eq(first_items, [[1, 1, "A"]], "native first instance sees only its own response")
	t.eq(second_items, [[1, 2, "B"]], "native second instance sees only its own response")
	first.free()
	second.free()
