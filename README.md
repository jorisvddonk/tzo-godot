# tzo-godot

This repository contains an experimental GDExtension extension for Godot that supports [Tzo](https://github.com/jorisvddonk/tzo) and QuestVM. In the future, QuestVM support may be separated out into a separate extension.

Under the hood, this uses the [Tzo-c](https://github.com/jorisvddonk/tzo-c) implementation.

This repository structure is based on [GDExtensionTemplate](https://github.com/asmaloney/GDExtensionTemplate) and is currently set up to work with the **[Godot 4.1](https://github.com/godotengine/godot/releases/tag/4.1-stable)** release.

## Prerequisites

To use this locally on your machine, you will need the following:

- **[CMake](https://cmake.org/)** v3.22+
- C++ Compiler with at least **C++17** support (any recent compiler)
- (optional) **[ccache](https://ccache.dev/)** for faster rebuilds
- (optional) **[clang-format](https://clang.llvm.org/docs/ClangFormat.html)** for linting and automatic code formatting (CI uses clang-format version 15)

The GitHub actions (CI) are set up to include all of these tools. To see how to download them on your platform, take a look at the [workflow](.github/workflows/main.yml) file.

## Build & Install

Here's an example of how to build & install a release version (use the terminal to run the following commands in the parent directory of this repo):

### Not MSVC

```sh
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=tzo-godot-install
cmake --build ./build --parallel
cmake --install ./build
```

### MSVC

```powershell
cmake -B build -S . -G "Visual Studio 17 2022" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=tzo-godot-install
cmake --build ./build --config Release
cmake --install ./build
```

This tells CMake to use `Visual Studio 2022`. There is a list of Visual Studio generators [on the CMake site](https://cmake.org/cmake/help/latest/manual/cmake-generators.7.html#visual-studio-generators) - pick the one you are using.

## Cmake Options

The following additional CMake options are available:

| Option                                                                   | Description                                      | Default                                                                                                 |
|--------------------------------------------------------------------------|--------------------------------------------------|---------------------------------------------------------------------------------------------------------|
| `CCACHE_PROGRAM`                                                         | Path to `ccache` for faster rebuilds             | This is automatically set **ON** if `ccache` is found. If you do not want to use it, set this to "".    |
| `CLANG_FORMAT_PROGRAM`                                                   | Path to `clang-format` for code formatting.      | This is automatically set **ON** if `clang-format` is on. If you do not want to use it, set this to "". |
| `${PROJECT_NAME_UPPERCASE}_WARN_EVERYTHING` (e.g. FOO_WARN_EVERYTHING)   | Turns on all warnings. (Not available for MSVC.) | **OFF** (too noisy, but can be useful sometimes)                                                        |
| `${PROJECT_NAME_UPPERCASE}_WARNING_AS_ERROR` (e.g. FOO_WARNING_AS_ERROR) | Turns warnings into errors.                      | **ON**                                                                                                  |

# Usage

More usage information and documentation follows later.
For now, consider the following code example:

```GDScript
extends Example
@export var textBox: RichTextLabel
@export var buttonGroup: GridContainer

func _ready():
	textBox.text = ""
	if self.has_signal('questvm_emit'):
		print("binding..")
		self.questvm_emit.connect(_emit.bind())
		self.questvm_getresponse_start.connect(_questvm_getresponse_start.bind())
		self.questvm_getresponse_item.connect(_questvm_getresponse_item.bind())
		self.questvm_getresponse_end.connect(_questvm_getresponse_end.bind())
	else:
		push_error("Could not find `questvm_emit` signal...")
	self.initTzoVM()
	print("running...")
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
