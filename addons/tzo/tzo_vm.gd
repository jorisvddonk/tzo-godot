## Pure-GDScript port of the Tzo stack VM.
##
## This is a behaviour-compatible port of tzo-c's `tzo.c` so that the same
## compiled program JSON can run either on this VM or on the native
## GDExtension. It intentionally reproduces the original semantics (including
## operand order quirks and error behaviour) so both backends stay in sync.
##
## Unlike the C implementation, all state here is per-instance: no globals are
## shared between VMs.
class_name TzoVM
extends RefCounted

# Instruction types (mirrors tzo.h's InstructionType).
const PUSH_STRING := 0
const PUSH_NUMBER := 1
const INVOKE_FUNCTION := 2

const TZO_MAX_STACK_SIZE := 1000

var stack: Array = []
var program: Array = []
var stack_size: int = 0
var program_size: int = 0
var ppc: int = 0
var running: bool = false
var exited: bool = false

var label_map: Dictionary = {}
var context: Dictionary = {}
var foreign_functions: Dictionary = {}

## Error messages raised by opcodes (the C version prints and exits).
var errors: Array = []
## Text emitted by the `stdout` opcode.
var output: Array = []
## Optional sink invoked with every `stdout` string (useful for tests).
var stdout_sink := Callable()


# --- Lifetime --------------------------------------------------------------

func init_runtime() -> void:
	label_map = {}
	context = {}
	foreign_functions = {}


func register_foreign_function(function_name: String, function: Callable) -> void:
	foreign_functions[function_name] = function


# --- Program loading -------------------------------------------------------

func load_file_get_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		_record_error("TzoVM: cannot open program file '%s'" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_record_error("TzoVM: cannot open program file '%s'" % path)
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_record_error("TzoVM: program file '%s' is not valid JSON" % path)
		return {}
	return parsed


func init_label_map_from_json_object(obj: Dictionary) -> void:
	for key in obj:
		var value = obj[key]
		if _is_number(value):
			label_map[key] = int(value)


func init_program_list_from_json_array(array: Array) -> void:
	program = []
	program_size = array.size()
	for i in array.size():
		var entry = array[i]
		var instruction := {"type": INVOKE_FUNCTION, "value": null, "op": "nop"}
		if typeof(entry) == TYPE_DICTIONARY:
			if entry.has("type"):
				match String(entry["type"]):
					"push-number-instruction":
						instruction["type"] = PUSH_NUMBER
					"push-string-instruction":
						instruction["type"] = PUSH_STRING
					"invoke-function-instruction":
						instruction["type"] = INVOKE_FUNCTION
			if entry.has("label"):
				label_map[String(entry["label"])] = i
			if entry.has("value"):
				instruction["value"] = entry["value"]
			if entry.has("functionName"):
				instruction["op"] = String(entry["functionName"])
		program.append(instruction)


# --- Stack -----------------------------------------------------------------

func _push(value) -> void:
	stack.append(value)
	stack_size += 1


func _top():
	return stack[stack_size - 1]


func _pop():
	stack_size -= 1
	return stack.pop_back()


# --- Value helpers ---------------------------------------------------------

static func _is_number(value) -> bool:
	return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT


static func _is_string(value) -> bool:
	return typeof(value) == TYPE_STRING


static func _type_of(value) -> int:
	return TYPE_STRING if _is_string(value) else TYPE_FLOAT


func as_string(value) -> String:
	if _is_string(value):
		return value
	var f := float(value)
	if absf(round(f) - f) <= 0.00001:
		return "%d" % int(f)
	return "%.6f" % f


func as_int_f(value) -> float:
	var f := float(value)
	if absf(round(f) - f) <= 0.00001:
		return round(f)
	return f


# --- Execution -------------------------------------------------------------

func step() -> void:
	if ppc < 0 or ppc >= program_size:
		return
	var instruction: Dictionary = program[ppc]
	match int(instruction["type"]):
		PUSH_STRING:
			_push(instruction["value"])
		PUSH_NUMBER:
			_push(float(instruction["value"]))
		INVOKE_FUNCTION:
			_invoke(String(instruction["op"]))
	ppc += 1


func run() -> void:
	running = true
	while running and ppc < program_size:
		step()
	running = false


func pause() -> void:
	running = false


func resume() -> void:
	running = true


func _invoke(function_name: String) -> void:
	if foreign_functions.has(function_name):
		foreign_functions[function_name].call(self)
		return
	match _canonical(function_name):
		"nop":
			_op_nop()
		"plus":
			_op_plus()
		"min":
			_op_min()
		"mul":
			_op_mul()
		"pop":
			_op_pop()
		"stdout":
			_op_stdout()
		"concat":
			_op_concat()
		"rconcat":
			_op_rconcat()
		"charCode":
			_op_char_code()
		"randInt":
			_op_rand_int()
		"eq":
			_op_eq()
		"and":
			_op_and()
		"dup":
			_op_dup()
		"gt":
			_op_gt()
		"lt":
			_op_lt()
		"not":
			_op_not()
		"or":
			_op_or()
		"ppc":
			_op_ppc()
		"stacksize":
			_op_stacksize()
		"jz":
			_op_jz()
		"jgz":
			_op_jgz()
		"br_open":
			_op_br_open()
		"br_close":
			_op_br_close()
		"pause":
			_op_pause()
		"exit":
			_op_exit()
		"goto":
			_op_goto()
		"setContext":
			_op_set_context()
		"getContext":
			_op_get_context()
		"hasContext":
			_op_has_context()
		"delContext":
			_op_del_context()
		_:
			_op_nop()


func _canonical(function_name: String) -> String:
	match function_name:
		"+":
			return "plus"
		"-":
			return "min"
		"*":
			return "mul"
		"{":
			return "br_open"
		"}":
			return "br_close"
		_:
			return function_name


func _record_error(message: String) -> void:
	errors.append(message)
	push_error(message)
	running = false
	exited = true


func _output(text: String) -> void:
	output.append(text)
	if stdout_sink.is_valid():
		stdout_sink.call(text)


# --- Opcodes ---------------------------------------------------------------

func _op_nop() -> void:
	pass


func _op_plus() -> void:
	var a = _pop()
	var b = _pop()
	if not (_is_number(a) and _is_number(b)):
		_record_error("+: operands must be numbers\n")
		return
	_push(float(a) + float(b))


func _op_min() -> void:
	var a = _pop()
	var b = _pop()
	if not (_is_number(a) and _is_number(b)):
		_record_error("-: operands must be numbers\n")
		return
	_push(float(a) - float(b))


func _op_mul() -> void:
	var a = _pop()
	var b = _pop()
	if not (_is_number(a) and _is_number(b)):
		_record_error("*: operands must be numbers\n")
		return
	_push(float(a) * float(b))


func _op_pop() -> void:
	_pop()


func _op_stdout() -> void:
	if stack_size == 0:
		_output("undefined")
		return
	var a = _pop()
	if _is_number(a):
		var f := float(a)
		if f == float(int(f)) and absf(f) < 1.0e15:
			_output("%d" % int(f))
		else:
			_output(_format_g(f))
	elif _is_string(a):
		_output(a)


func _op_concat() -> void:
	var a = _pop()
	var b = _pop()
	_push(as_string(a) + as_string(b))


func _op_rconcat() -> void:
	var a = _pop()
	var b = _pop()
	_push(as_string(b) + as_string(a))


func _op_char_code() -> void:
	var a = _pop()
	if not _is_number(a):
		_record_error("charCode: operand must be a number\n")
		return
	_push(String.chr(int(a) & 0xFFFF))


func _op_rand_int() -> void:
	var a = _pop()
	if not _is_number(a):
		_record_error("randInt: operand must be a number\n")
		return
	_push(float(int(floor(randf() * float(a)))))


func _op_eq() -> void:
	var a = _pop()
	var b = _pop()
	if _type_of(a) != _type_of(b):
		_push(0.0)
	elif _is_string(a):
		_push(1.0 if a == b else 0.0)
	else:
		_push(1.0 if float(a) == float(b) else 0.0)


func _op_and() -> void:
	var a = _pop()
	var b = _pop()
	if _is_number(a) and _is_number(b):
		_push(0.0 if (float(a) == 0.0 or float(b) == 0.0) else 1.0)
	else:
		_push(0.0)


func _op_dup() -> void:
	var a = _pop()
	_push(a)
	_push(a)


func _op_gt() -> void:
	var a = _pop()
	var b = _pop()
	if _is_number(a) and _is_number(b):
		_push(1.0 if float(a) > float(b) else 0.0)
	else:
		_push(0.0)


func _op_lt() -> void:
	var a = _pop()
	var b = _pop()
	if _is_number(a) and _is_number(b):
		_push(1.0 if float(a) < float(b) else 0.0)
	else:
		_push(0.0)


func _op_not() -> void:
	var a = _pop()
	if _is_number(a):
		_push(1.0 if float(a) == 0.0 else 0.0)
	else:
		_push(0.0)


func _op_or() -> void:
	var a = _pop()
	var b = _pop()
	if _is_number(a) and _is_number(b):
		_push(0.0 if (float(a) == 0.0 and float(b) == 0.0) else 1.0)
	else:
		_push(0.0)


func _op_ppc() -> void:
	_push(float(ppc))


func _op_stacksize() -> void:
	_push(float(stack_size))


func _op_jz() -> void:
	var a = _pop()
	if not _is_number(a):
		_record_error("jz: value must be a number\n")
		return
	if float(a) == 0.0:
		ppc += 1


func _op_jgz() -> void:
	var a = _pop()
	if not _is_number(a):
		_record_error("jgz: value must be a number\n")
		return
	if float(a) > 0.0:
		ppc += 1


func _op_br_open() -> void:
	var depth := 1
	var pc := ppc + 1
	while pc < program_size:
		if int(program[pc]["type"]) == INVOKE_FUNCTION:
			var op := _canonical(String(program[pc]["op"]))
			if op == "br_open":
				depth += 1
			elif op == "br_close":
				depth -= 1
				if depth == 0:
					ppc = pc
					return
		pc += 1


func _op_br_close() -> void:
	pass


func _op_pause() -> void:
	running = false


func _op_exit() -> void:
	running = false
	exited = true


func _op_goto() -> void:
	var a = _pop()
	if _is_number(a):
		ppc = int(a) - 1
	elif _is_string(a):
		ppc = int(label_map.get(a, 0)) - 1
	else:
		_record_error("goto: target must be a string or number\n")


func _op_set_context() -> void:
	var a = _pop()
	var b = _pop()
	if not _is_string(a):
		_record_error("setContext: key must be a string\n")
		return
	var key: String = a
	if _is_string(b):
		context[key] = b
	elif _is_number(b):
		context[key] = float(b)


func _op_get_context() -> void:
	var a = _pop()
	if not _is_string(a):
		_record_error("getContext: key must be a string\n")
		return
	if not context.has(a):
		_record_error("getContext: key not found\n")
		return
	_push(context[a])


func _op_has_context() -> void:
	var a = _pop()
	if not _is_string(a):
		_record_error("hasContext: key must be a string\n")
		return
	_push(1.0 if context.has(a) else 0.0)


func _op_del_context() -> void:
	var a = _pop()
	if not _is_string(a):
		_record_error("delContext: key must be a string\n")
		return
	context.erase(a)


# --- C-style "%g"/asString helpers -----------------------------------------

func _format_g(f: float) -> String:
	if f == 0.0:
		return "0"
	var negative := f < 0.0
	var a := absf(f)
	var exponent := int(floor(log(a) / log(10.0)))
	var text: String
	if exponent < -4 or exponent >= 6:
		var scientific := "%.5e" % a
		var split := scientific.split("e")
		text = _trim_zeros(split[0])
		if split.size() > 1:
			text += "e" + split[1]
	else:
		var precision := 5 - exponent
		if precision < 0:
			precision = 0
		text = _trim_zeros(String.num(a, precision))
	return ("-" if negative else "") + text


static func _trim_zeros(text: String) -> String:
	if not text.contains("."):
		return text
	text = text.rstrip("0")
	if text.ends_with("."):
		text = text.substr(0, text.length() - 1)
	return text
