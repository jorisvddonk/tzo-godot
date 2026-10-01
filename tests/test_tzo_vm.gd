extends RefCounted

const TzoVM := preload("res://addons/tzo/tzo_vm.gd")


func run(t) -> void:
	_test_arithmetic(t)
	_test_concat(t)
	_test_comparisons(t)
	_test_logic(t)
	_test_stack_ops(t)
	_test_ppc_and_stacksize(t)
	_test_goto(t)
	_test_conditional_skip(t)
	_test_blocks(t)
	_test_control_flow(t)
	_test_context(t)
	_test_char_code(t)
	_test_rand_int(t)
	_test_as_string(t)
	_test_stdout(t)
	_test_errors(t)


# --- Helpers ---------------------------------------------------------------

func _n(value) -> Dictionary:
	return {"type": "push-number-instruction", "value": value}


func _s(value: String) -> Dictionary:
	return {"type": "push-string-instruction", "value": value}


func _f(function_name: String) -> Dictionary:
	return {"type": "invoke-function-instruction", "functionName": function_name}


func _make(program: Array, labels := {}) -> TzoVM:
	var vm = TzoVM.new()
	vm.init_runtime()
	vm.init_label_map_from_json_object(labels)
	vm.init_program_list_from_json_array(program)
	return vm


# --- Tests -----------------------------------------------------------------

func _test_arithmetic(t) -> void:
	var vm = _make([_n(2), _n(3), _f("+")])
	vm.run()
	t.eq(vm._top(), 5.0, "2 3 + == 5")

	vm = _make([_n(10), _n(4), _f("-")])
	vm.run()
	t.eq(vm._top(), -6.0, "10 4 - == -6 (top minus second, tzo order)")

	vm = _make([_n(3), _n(7), _f("*")])
	vm.run()
	t.eq(vm._top(), 21.0, "3 7 * == 21")

	vm = _make([_n(2), _n(3), _f("+"), _n(4), _f("*")])
	vm.run()
	t.eq(vm._top(), 20.0, "2 3 + 4 * == 20")


func _test_concat(t) -> void:
	var vm = _make([_s("Hello "), _s("World"), _f("rconcat")])
	vm.run()
	t.eq(vm._top(), "Hello World", "rconcat preserves order")

	vm = _make([_s("Hello "), _s("World"), _f("concat")])
	vm.run()
	t.eq(vm._top(), "WorldHello ", "concat places top first (reversed)")

	vm = _make([_n(3), _s("x"), _f("rconcat")])
	vm.run()
	t.eq(vm._top(), "3x", "rconcat stringifies numbers")


func _test_comparisons(t) -> void:
	t.eq(_one([_n(2), _n(2), _f("eq")]), 1.0, "2 == 2")
	t.eq(_one([_n(2), _n(3), _f("eq")]), 0.0, "2 == 3 is false")
	t.eq(_one([_s("a"), _s("a"), _f("eq")]), 1.0, "a == a")
	t.eq(_one([_s("a"), _s("b"), _f("eq")]), 0.0, "a == b is false")
	t.eq(_one([_s("a"), _n(1), _f("eq")]), 0.0, "type mismatch is false")

	t.eq(_one([_n(1), _n(2), _f("gt")]), 1.0, "gt: top(2) > 1")
	t.eq(_one([_n(2), _n(1), _f("gt")]), 0.0, "gt: top(1) > 2 is false")
	t.eq(_one([_n(2), _n(1), _f("lt")]), 1.0, "lt: top(1) < 2")
	t.eq(_one([_n(1), _n(2), _f("lt")]), 0.0, "lt: top(2) < 1 is false")


func _test_logic(t) -> void:
	t.eq(_one([_n(1), _n(1), _f("and")]), 1.0, "1 and 1")
	t.eq(_one([_n(1), _n(0), _f("and")]), 0.0, "1 and 0")
	t.eq(_one([_n(0), _n(1), _f("or")]), 1.0, "0 or 1")
	t.eq(_one([_n(0), _n(0), _f("or")]), 0.0, "0 or 0")
	t.eq(_one([_n(0), _f("not")]), 1.0, "not 0")
	t.eq(_one([_n(5), _f("not")]), 0.0, "not 5")
	t.eq(_one([_s("a"), _s("a"), _f("and")]), 0.0, "and on strings is 0")


func _test_stack_ops(t) -> void:
	var vm = _make([_n(7), _f("dup")])
	vm.run()
	t.eq(vm.stack_size, 2, "dup doubles the top")
	t.eq(vm._top(), 7.0, "dup preserves value")

	vm = _make([_n(7), _f("pop")])
	vm.run()
	t.eq(vm.stack_size, 0, "pop removes the top")

	vm = _make([_s("a"), _s("b"), _f("dup")])
	vm.run()
	t.eq(vm.stack_size, 3, "dup works on strings")


func _test_ppc_and_stacksize(t) -> void:
	t.eq(_one([_n(1), _f("stacksize")]), 1.0, "stacksize is 1")
	t.eq(_one([_n(1), _f("ppc")]), 1.0, "ppc is instruction index 1")
	t.eq(_one([_n(1), _f("nop"), _f("ppc")]), 2.0, "ppc is instruction index 2")


func _test_goto(t) -> void:
	# Numeric goto: target is the 0-based instruction index.
	var vm = _make([_n(4), _f("goto"), _n(111), _n(222), _n(42)])
	vm.run()
	t.eq(vm._top(), 42.0, "numeric goto jumps to index 4")
	t.eq(vm.stack_size, 1, "numeric goto consumed the target and skipped two pushes")

	# Label goto via labelMap.
	vm = _make([_s("end"), _f("goto"), _n(111), _n(42)], {"end": 3})
	vm.run()
	t.eq(vm._top(), 42.0, "label goto uses labelMap")
	t.eq(vm.stack_size, 1, "label goto consumed the target and skipped the push")

	# Label embedded on an instruction.
	vm = _make(
		[
			_s("target"),
			_f("goto"),
			_n(999),
			{"type": "push-number-instruction", "value": 5, "label": "target"},
		]
	)
	vm.run()
	t.eq(vm._top(), 5.0, "embedded label jumps to its instruction")
	t.eq(vm.stack_size, 1, "embedded label skipped the intermediate push")


func _test_conditional_skip(t) -> void:
	var vm = _make([_n(0), _f("jz"), _n(111), _n(42)])
	vm.run()
	t.eq(vm.stack_size, 1, "jz skips the next push when zero")
	t.eq(vm._top(), 42.0, "jz skips next when zero")

	vm = _make([_n(1), _f("jz"), _n(111), _n(42)])
	vm.run()
	t.eq(vm.stack_size, 2, "jz does not skip when set")

	vm = _make([_n(5), _f("jgz"), _n(111), _n(42)])
	vm.run()
	t.eq(vm.stack_size, 1, "jgz skips the next push when positive")
	t.eq(vm._top(), 42.0, "jgz skips next when positive")

	vm = _make([_n(0), _f("jgz"), _n(111), _n(42)])
	vm.run()
	t.eq(vm.stack_size, 2, "jgz does not skip on zero")


func _test_blocks(t) -> void:
	# br_open jumps to the matching br_close.
	var vm = _make([_f("{"), _n(111), _f("}"), _n(42)])
	vm.run()
	t.eq(vm._top(), 42.0, "block body is skipped")
	t.eq(vm.stack_size, 1, "block did not push")

	# Nested blocks.
	vm = _make([_f("{"), _f("{"), _n(111), _f("}"), _n(222), _f("}"), _n(42)])
	vm.run()
	t.eq(vm._top(), 42.0, "nested block is skipped")


func _test_control_flow(t) -> void:
	# pause stops the run loop; run() resumes from where it left off.
	var vm = _make([_n(1), _f("pause"), _n(2)])
	vm.run()
	t.eq(vm.stack_size, 1, "pause halts execution")
	t.eq(vm._top(), 1.0, "value before pause is on the stack")
	vm.run()
	t.eq(vm.stack_size, 2, "run() resumes after pause")
	t.eq(vm._top(), 2.0, "resumed execution continues")

	# exit stops execution and marks the VM exited.
	vm = _make([_n(1), _f("exit"), _n(2)])
	vm.run()
	t.eq(vm.stack_size, 1, "exit halts execution")
	t.ok(vm.exited, "exit marks the VM as exited")


func _test_context(t) -> void:
	var vm = _make(
		[
			_n(10),
			_s("k"),
			_f("setContext"),
			_s("k"),
			_f("getContext"),  # -> 10
			_s("missing"),
			_f("hasContext"),  # -> 0
			_s("k"),
			_f("delContext"),
			_s("k"),
			_f("hasContext"),  # -> 0
		]
	)
	vm.run()
	t.eq(vm.stack_size, 3, "context program leaves three values")
	t.eq(vm._pop(), 0.0, "hasContext false after delete")
	t.eq(vm._pop(), 0.0, "hasContext false for missing key")
	t.eq(vm._pop(), 10.0, "getContext returned the stored value")
	t.eq(vm.context.has("k"), false, "delContext removed the key")


func _test_char_code(t) -> void:
	t.eq(_one([_n(65), _f("charCode")]), "A", "charCode 65")
	t.eq(_one([_n(8364), _f("charCode")]), "\u20ac", "charCode 8364 is euro sign")
	t.eq(_one([_n(10), _f("charCode")]), "\n", "charCode 10 is newline")


func _test_rand_int(t) -> void:
	for i in 50:
		var vm = _make([_n(10), _f("randInt")])
		vm.run()
		var value := float(vm._top())
		t.ok(value >= 0.0 and value < 10.0, "randInt in [0,10)")
		t.eq(value, floor(value), "randInt returns an integer")


func _test_as_string(t) -> void:
	var vm = TzoVM.new()
	t.eq(vm.as_string(3), "3", "as_string integer")
	t.eq(vm.as_string(3.5), "3.500000", "as_string float")
	t.eq(vm.as_string("x"), "x", "as_string string")


func _test_stdout(t) -> void:
	t.eq(_stdout([_n(3), _f("stdout")]), ["3"], "stdout prints integer")
	t.eq(_stdout([_n(0.5), _f("stdout")]), ["0.5"], "stdout prints 0.5")
	t.eq(_stdout([_n(3.14159), _f("stdout")]), ["3.14159"], "stdout prints float")
	t.eq(_stdout([_s("hi"), _f("stdout")]), ["hi"], "stdout prints string")
	t.eq(_stdout([_f("stdout")]), ["undefined"], "stdout with empty stack")


func _test_errors(t) -> void:
	var vm = _make([_n(1), _s("x"), _f("+")])
	vm.run()
	t.ok(vm.errors.size() == 1, "type error is recorded")
	t.eq(vm.running, false, "type error halts the VM")


# --- Small utilities -------------------------------------------------------

func _one(program: Array, labels := {}):
	var vm = _make(program, labels)
	vm.run()
	return vm._top()


func _stdout(program: Array) -> Array:
	var vm = _make(program)
	vm.stdout_sink = func(_text: String) -> void:
		pass
	vm.run()
	return vm.output
