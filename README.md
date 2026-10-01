# tzo-godot

This repository contains an experimental GDExtension extension for Godot that supports [Tzo](https://github.com/jorisvddonk/tzo) and QuestVM. In the future, QuestVM support may be separated out into a separate extension.

Under the hood, the native extension implements the base Tzo VM (`TzoVMNative`) on top of the [Tzo-c](https://github.com/jorisvddonk/tzo-c) implementation. It is entirely optional: the `addons/tzo` plugin ships a pure-GDScript port of the same base VM (`TzoVM`), and the `QuestVM` node runs on whichever base VM is available.

This repository structure is based on [GDExtensionTemplate](https://github.com/asmaloney/GDExtensionTemplate) and is currently set up to work with the **[Godot 4.5](https://github.com/godotengine/godot/releases/tag/4.5-stable)** release (via [godot-cpp](https://github.com/godotengine/godot-cpp) `godot-4.5-stable`).

## Repository layout

| Path              | Contents                                                                                     |
|-------------------|----------------------------------------------------------------------------------------------|
| `addons/tzo/`     | The Godot addon: GDScript `TzoVM` and `QuestVM`, plus an (empty) editor plugin.              |
| `src/`            | Native GDExtension: `TzoVMNative`, `GDExtensionTemplate`, and registration.                  |
| `templates/`      | `.gdextension` templates that CMake fills in and installs.                                    |
| `tests/`          | Headless Godot test suite plus `run_tests.sh`.                                               |
| `extern/`         | Submodules: `godot-cpp` and `tzo-c`.                                                         |
| `cmake/`          | CMake helper modules (warnings, ccache, clang-format, version info).                         |

## Backends

The quest layer (`QuestVM` / [quest_vm.gd](addons/tzo/quest_vm.gd)) is a single GDScript implementation with no backend-specific code. It runs on top of a **base VM**, which has two interchangeable implementations that share one API and keep **all state per-instance**:

| Base VM  | Class          | Notes                                                                              |
|----------|----------------|------------------------------------------------------------------------------------|
| Native   | `TzoVMNative`  | C++ GDExtension built on `tzo-c`. Faster. Loaded only when the extension is present. |
| GDScript | `TzoVM`        | Pure-GDScript port of the same VM. Always available; used as the fallback.          |

`QuestVM` auto-detects the native base VM at `initTzoVM()` time. Set `prefer_native = false` to force the GDScript backend (useful for testing or platforms without binaries). `backend` reports which one was chosen (`"native"` or `"script"`).

## Prerequisites

To use this locally on your machine, you will need the following:

- **[CMake](https://cmake.org/)** v3.22+
- C++ Compiler with at least **C++17** support (any recent compiler)
- (optional) **[ccache](https://ccache.dev/)** for faster rebuilds
- (optional) **[clang-format](https://clang.llvm.org/docs/ClangFormat.html)** for linting and automatic code formatting (CI uses clang-format version 15)

## Build & Install

Build the native extension only if you want the speedup; the addon works without it.

Here's an example of how to build & install a release version (use the terminal to run the following commands in the parent directory of this repo):

### Not MSVC

```sh
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=tzo-godot-install
cmake --build ./build --parallel 2
cmake --install ./build
```

### MSVC

```powershell
cmake -B build -S . -G "Visual Studio 17 2022" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=tzo-godot-install
cmake --build ./build --config Release
cmake --install ./build
```

This tells CMake to use `Visual Studio 2022`. There is a list of Visual Studio generators [on the CMake site](https://cmake.org/cmake/help/latest/manual/cmake-generators.7.html#visual-studio-generators) - pick the one you are using.

Install the GDScript addon by copying `addons/tzo/` into your project's `addons/` directory (or enable this repo as an asset). You can then enable **Tzo** under *Project → Project Settings → Plugins*; the runtime classes are registered as `TzoVM` and `QuestVM` even without enabling the plugin.

## Cmake Options

The following additional CMake options are available:

| Option                                                                   | Description                                      | Default                                                                                                 |
|--------------------------------------------------------------------------|--------------------------------------------------|---------------------------------------------------------------------------------------------------------|
| `CCACHE_PROGRAM`                                                         | Path to `ccache` for faster rebuilds             | This is automatically set **ON** if `ccache` is found. If you do not want to use it, set this to "".    |
| `CLANG_FORMAT_PROGRAM`                                                   | Path to `clang-format` for code formatting.      | This is automatically set **ON** if `clang-format` is on. If you do not want to use it, set this to "". |
| `${PROJECT_NAME_UPPERCASE}_WARN_EVERYTHING` (e.g. FOO_WARN_EVERYTHING)   | Turns on all warnings. (Not available for MSVC.) | **OFF** (too noisy, but can be useful sometimes)                                                        |
| `${PROJECT_NAME_UPPERCASE}_WARNING_AS_ERROR` (e.g. FOO_WARNING_AS_ERROR) | Turns warnings into errors.                      | **ON**                                                                                                  |

## Testing

The test suite covers both the GDScript VM and the `QuestVM` node, and (when the native extension has been built) runs parity and instance-isolation checks against the native backend. It needs a Godot binary on your `PATH` (or passed as the first argument):

```sh
tests/run_tests.sh
# or: tests/run_tests.sh /Applications/Godot.app/Contents/MacOS/Godot
```

Native tests require a build (see above); without one they are skipped automatically. Note that every piece of VM state is per-instance in both backends.

# Usage

The `addons/tzo` plugin provides a `QuestVM` node you can extend or instantiate. Set `file_path` to a compiled Tzo program (`.json`) before calling `initTzoVM()`, connect the signals you care about, then call `run()`.

```GDScript
extends QuestVM
@export var textBox: RichTextLabel
@export var buttonGroup: GridContainer

func _ready():
	textBox.text = ""
	self.questvm_emit.connect(_emit)
	self.questvm_getresponse_start.connect(_questvm_getresponse_start)
	self.questvm_getresponse_item.connect(_questvm_getresponse_item)
	self.questvm_getresponse_end.connect(_questvm_getresponse_end)
	self.initTzoVM()
	self.run()

func _emit(a):
	textBox.text += a

func clearButtonGroup():
	for child in buttonGroup.get_children():
		buttonGroup.remove_child(child)

func _questvm_getresponse_start():
	clearButtonGroup()

func _questvm_getresponse_item(id, pc, responseText):
	var button = Button.new()
	button.text = responseText
	var f = func foo():
		self.pushNumber(float(pc))
		self.clearResponseMap()
		clearButtonGroup()
		textBox.text = ""
		self.run()

	button.pressed.connect(f)
	buttonGroup.add_child(button)

func _questvm_getresponse_end():
	pass
```

## QuestVM API

### Properties

| Property          | Type       | Description                                                                    |
|-------------------|------------|--------------------------------------------------------------------------------|
| `file_path`       | `String`   | Path to the compiled program (`res://...` or an OS path). Exported as a file.  |
| `prefer_native`   | `bool`     | Use the native backend when available. Default `true`.                         |
| `backend`         | `String`   | Read-only. `"native"` or `"script"` after `initTzoVM()`.                        |
| `response_map`    | `Dictionary` | Read-only. Responses registered by the `response` opcode, keyed by 1-based id. |
| `collected_text`  | `String`   | Read-only. Text accumulated by `emit`.                                         |

### Methods

| Method                        | Description                                                                     |
|-------------------------------|---------------------------------------------------------------------------------|
| `initTzoVM()`                 | Loads `file_path`, registers foreign functions, and resets instance state.       |
| `run()`                       | Runs until the program pauses (`pause`/`getResponse`), exits, or ends.           |
| `pushNumber(num: float)`      | Pushes a number onto the VM stack.                                              |
| `pushString(str: String)`     | Pushes a string onto the VM stack.                                              |
| `clearResponseMap()`          | Empties `response_map`.                                                         |
| `getResponseMap() -> Dictionary` | Returns the response map.                                                    |
| `getCollectedText() -> String`   | Returns the text accumulated by `emit`.                                      |
| `clearCollectedText()`           | Clears the accumulated text.                                                 |
| `set_file_path(path)` / `get_file_path()` | Property accessors.                                                |

### Signals

| Signal                                                               | Description                                                     |
|----------------------------------------------------------------------|-----------------------------------------------------------------|
| `questvm_emit(text: String)`                                         | Fired by the `emit` opcode.                                     |
| `questvm_getresponse_start()`                                        | Fired before responses are reported by `getResponse`.           |
| `questvm_getresponse_item(id: int, pc: int, response_text: String)`  | Fired once per registered response.                             |
| `questvm_getresponse_end()`                                          | Fired after all responses have been reported.                   |

## TzoVM (base VM)

`TzoVM` (GDScript) and `TzoVMNative` (C++) are the base stack VM. You normally use them indirectly through `QuestVM`, but they are usable standalone. Both expose the same methods:

- `init_runtime()`, `register_foreign_function(name, Callable)`
- `load_file_get_json(path) -> Dictionary`, `init_label_map_from_json_object(obj)`, `init_program_list_from_json_array(array)`
- `run()`, `step()`, `pause()`, `resume()`
- `push_number(num)` / `push_string(str)`, `pop()`, `top()`
- `get_stack_size()`, `get_program_size()`, `get_ppc()` / `set_ppc(pc)`, `is_exited()`
- `as_string(value)`
- Output: `get_output()` / `clear_output()` / `set_stdout_sink(Callable)` (native), or the `output`/`stdout_sink` properties (GDScript)

Foreign functions are registered as `Callable`s and invoked with the VM instance. The GDScript class additionally exposes `stack`, `program`, `context`, `label_map`, and `errors` directly.

## Program format

A compiled program is a JSON object with a `programList` array of instructions and a `labelMap` mapping label names to instruction indices:

```json
{
	"programList": [
		{ "type": "push-string-instruction", "value": "Hello " },
		{ "type": "push-string-instruction", "value": "World" },
		{ "type": "invoke-function-instruction", "functionName": "rconcat" },
		{ "type": "invoke-function-instruction", "functionName": "emit" }
	],
	"labelMap": {}
}
```

Instructions may carry `type`, `value`, `label`, and `functionName`:

- `"push-number-instruction"` / `"push-string-instruction"` push `value`.
- `"invoke-function-instruction"` calls the opcode or foreign function named by `functionName`.
- `label` (on any instruction) registers that instruction's index under the given name.

## Opcodes

Built-in opcodes (with `functionName` aliases in parentheses). `top` is the value on top of the stack.

| Opcode                         | Description                                                                 |
|--------------------------------|-----------------------------------------------------------------------------|
| `nop`                          | Does nothing.                                                               |
| `plus` (`+`)                   | Pushes `top + second`.                                                      |
| `min` (`-`)                    | Pushes `top - second`.                                                      |
| `mul` (`*`)                    | Pushes `top * second`.                                                      |
| `pop`                          | Discards the top value.                                                     |
| `dup`                          | Duplicates the top value.                                                   |
| `stdout`                       | Writes the top value to `output` (and `stdout_sink` if set).                |
| `concat`                       | Pushes `top + second` as strings.                                           |
| `rconcat`                      | Pushes `second + top` as strings.                                           |
| `charCode`                     | Pops a number, pushes its UTF-8 character.                                  |
| `randInt`                      | Pops `n`, pushes `floor(rand() * n)` (integer, in `[0, n)`).                |
| `eq`                           | Pushes `1` if the two values have the same type and are equal, else `0`.    |
| `and` / `or` / `not`           | Boolean logic on numbers (`0`/`1`).                                         |
| `gt` / `lt`                    | Pushes `1` if `top > second` / `top < second`, else `0`.                    |
| `ppc`                          | Pushes the current instruction index.                                       |
| `stacksize`                    | Pushes the current stack size.                                              |
| `jz`                           | Pops a number; if `0`, skips the next instruction.                          |
| `jgz`                          | Pops a number; if `> 0`, skips the next instruction.                        |
| `{` / `}`                      | Block markers; `{` jumps past the matching `}`.                             |
| `goto`                         | Pops a label name or numeric index and jumps there.                         |
| `setContext` / `getContext`    | Store/read a value in the VM's context map (key is pushed on top).          |
| `hasContext` / `delContext`    | Test for / remove a context key.                                            |
| `pause` / `exit`               | Stop the run loop (`exit` also marks the VM exited).                        |

Foreign functions provided by the `QuestVM` layer:

| Function      | Description                                                                 |
|---------------|-----------------------------------------------------------------------------|
| `emit`        | Pops a value, appends it to the collected text, and emits `questvm_emit`.   |
| `response`    | Pops a `pc` (number) and response text, registering a selectable response.  |
| `getResponse` | Pauses the VM and emits the start/item/end response signals.                |
