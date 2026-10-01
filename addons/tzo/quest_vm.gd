## QuestVM: GDScript implementation of the Tzo quest virtual machine.
##
## Runs on the pure-GDScript [TzoVM] by default, and transparently delegates to
## the native GDExtension class `QuestVMNative` when it is available (faster).
## Both backends expose the same methods and signals.
##
## All state (stack, context, response map, collected text) is per-instance.
class_name QuestVM
extends Node

signal questvm_emit(text: String)
signal questvm_getresponse_start()
signal questvm_getresponse_item(id: int, pc: int, response_text: String)
signal questvm_getresponse_end()

const TzoVMScript := preload("res://addons/tzo/tzo_vm.gd")
const NATIVE_CLASS := "QuestVMNative"

@export_file("*.json") var file_path: String = ""
@export var prefer_native: bool = true

## Which backend is actually in use: "native" or "script".
var backend: String = "script"
## Responses registered by the `response` opcode, keyed by insertion index.
var response_map: Dictionary = {}
## Text accumulated by the `emit` opcode.
var collected_text: String = ""

var _vm = null
var _native: Node = null
var _native_connected: bool = false


# --- Public API ------------------------------------------------------------

func initTzoVM() -> void:
	_detect_backend()
	if backend == "native":
		_init_native()
	else:
		_init_script()


func run() -> void:
	if backend == "native":
		_native.run()
	else:
		_vm.run()


func pushNumber(num: float) -> void:
	if backend == "native":
		_native.pushNumber(num)
	else:
		_vm._push(float(num))


func pushString(str: String) -> void:
	if backend == "native":
		_native.pushString(str)
	else:
		_vm._push(str)


func clearResponseMap() -> void:
	if backend == "native":
		_native.clearResponseMap()
	response_map.clear()


func getResponseMap() -> Dictionary:
	return response_map


func set_file_path(path: String) -> void:
	file_path = path


func get_file_path() -> String:
	return file_path


# --- Backend selection -----------------------------------------------------

func _detect_backend() -> void:
	backend = "script"
	if prefer_native and ClassDB.class_exists(NATIVE_CLASS):
		backend = "native"


func _init_script() -> void:
	_vm = TzoVMScript.new()
	_vm.init_runtime()
	_vm.register_foreign_function("emit", Callable(self, "_foreign_emit"))
	_vm.register_foreign_function("getResponse", Callable(self, "_foreign_get_response"))
	_vm.register_foreign_function("response", Callable(self, "_foreign_response"))
	var root: Dictionary = _vm.load_file_get_json(file_path)
	_vm.init_label_map_from_json_object(root.get("labelMap", {}))
	_vm.init_program_list_from_json_array(root.get("programList", []))
	response_map.clear()
	collected_text = ""


func _init_native() -> void:
	_native = ClassDB.instantiate(NATIVE_CLASS) as Node
	if _native == null:
		backend = "script"
		_init_script()
		return
	_native.file_path = file_path
	if not _native_connected:
		_native.questvm_emit.connect(_on_native_emit)
		_native.questvm_getresponse_start.connect(_on_native_get_response_start)
		_native.questvm_getresponse_item.connect(_on_native_get_response_item)
		_native.questvm_getresponse_end.connect(_on_native_get_response_end)
		_native_connected = true
	if is_inside_tree() and not _native.is_inside_tree():
		add_child(_native)
	_native.initTzoVM()


# --- Script backend foreign functions --------------------------------------

func _foreign_emit(vm) -> void:
	var text: String = vm.as_string(vm._pop())
	collected_text += text
	questvm_emit.emit(text)


func _foreign_response(vm) -> void:
	var pc = vm._pop()
	var text = vm._pop()
	var key := response_map.size() + 1
	response_map[key] = {"pc": int(pc), "response": vm.as_string(text)}


func _foreign_get_response(vm) -> void:
	vm.pause()
	questvm_getresponse_start.emit()
	var keys := response_map.keys()
	keys.sort()
	var id := 1
	for key in keys:
		var answer: Dictionary = response_map[key]
		questvm_getresponse_item.emit(id, int(answer["pc"]), String(answer["response"]))
		id += 1
	questvm_getresponse_end.emit()


# --- Native backend re-emitters --------------------------------------------

func _on_native_emit(text: String) -> void:
	collected_text += text
	questvm_emit.emit(text)


func _on_native_get_response_start() -> void:
	questvm_getresponse_start.emit()


func _on_native_get_response_item(id: int, pc: int, response_text: String) -> void:
	questvm_getresponse_item.emit(id, pc, response_text)


func _on_native_get_response_end() -> void:
	questvm_getresponse_end.emit()
