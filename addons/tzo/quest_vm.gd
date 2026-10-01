## QuestVM: the Tzo quest layer (emit / getResponse / response).
##
## This is the single implementation of the quest layer. It runs on top of a
## base VM, which is either the native [TzoVMNative] (when the GDExtension is
## loaded) or the pure-GDScript [TzoVM]. Both base VMs expose the same API, so
## this script contains no backend-specific code.
##
## All state (response map, collected text) is per-instance.
class_name QuestVM
extends Node

signal questvm_emit(text: String)
signal questvm_getresponse_start()
signal questvm_getresponse_item(id: int, pc: int, response_text: String)
signal questvm_getresponse_end()

const TzoVMScript := preload("res://addons/tzo/tzo_vm.gd")
const NATIVE_CLASS := "TzoVMNative"

@export_file("*.json") var file_path: String = ""
@export var prefer_native: bool = true

## Which base VM is in use: "native" or "script". Set after initTzoVM().
var backend: String = "script"
## Responses registered by the `response` opcode, keyed by insertion index.
var response_map: Dictionary = {}
## Text accumulated by the `emit` opcode.
var collected_text: String = ""

var _vm = null


# --- Public API ------------------------------------------------------------

func initTzoVM() -> void:
	_detect_backend()
	_vm = _make_base_vm()
	_vm.init_runtime()
	_vm.register_foreign_function("emit", _foreign_emit)
	_vm.register_foreign_function("getResponse", _foreign_get_response)
	_vm.register_foreign_function("response", _foreign_response)
	var root: Dictionary = _vm.load_file_get_json(file_path)
	_vm.init_label_map_from_json_object(root.get("labelMap", {}))
	_vm.init_program_list_from_json_array(root.get("programList", []))
	response_map.clear()
	collected_text = ""


func run() -> void:
	if _vm != null:
		_vm.run()


func pushNumber(num: float) -> void:
	if _vm != null:
		_vm.push_number(num)


func pushString(str: String) -> void:
	if _vm != null:
		_vm.push_string(str)


func clearResponseMap() -> void:
	response_map.clear()


func getResponseMap() -> Dictionary:
	return response_map


func getCollectedText() -> String:
	return collected_text


func clearCollectedText() -> void:
	collected_text = ""


func set_file_path(path: String) -> void:
	file_path = path


func get_file_path() -> String:
	return file_path


# --- Backend selection -----------------------------------------------------

func _detect_backend() -> void:
	backend = "script"
	if prefer_native and ClassDB.class_exists(NATIVE_CLASS):
		backend = "native"


func _make_base_vm():
	if backend == "native":
		var native = ClassDB.instantiate(NATIVE_CLASS)
		if native != null:
			return native
		backend = "script"
	return TzoVMScript.new()


# --- Quest layer foreign functions -----------------------------------------

func _foreign_emit(vm) -> void:
	var text: String = vm.as_string(vm.pop())
	collected_text += text
	questvm_emit.emit(text)


func _foreign_response(vm) -> void:
	var pc = vm.pop()
	var text = vm.pop()
	response_map[response_map.size() + 1] = {"pc": int(pc), "response": String(vm.as_string(text))}


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
