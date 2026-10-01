// Native (tzo-c backed) counterpart to the GDScript TzoVM.
//
// Mirrors the public surface of addons/tzo/tzo_vm.gd: program loading, opcode
// execution, context, output capture, and Callable-based foreign functions.

#pragma once

#include "godot_cpp/classes/global_constants.hpp"
#include "godot_cpp/classes/ref_counted.hpp"
#include "godot_cpp/core/binder_common.hpp"
#include "godot_cpp/variant/array.hpp"
#include "godot_cpp/variant/callable.hpp"
#include "godot_cpp/variant/dictionary.hpp"
#include "godot_cpp/variant/packed_string_array.hpp"
#include "godot_cpp/variant/variant.hpp"

#include <map>
#include <string>

extern "C" {
#include <tzo.h>
}

class TzoVMNative : public godot::RefCounted
{
    GDCLASS( TzoVMNative, godot::RefCounted )

public:
    TzoVMNative();
    ~TzoVMNative() override;

    void init_runtime();
    void register_foreign_function(godot::String name, godot::Callable function);

    godot::Dictionary load_file_get_json(godot::String path);
    void init_label_map_from_json_object(godot::Dictionary obj);
    void init_program_list_from_json_array(godot::Array array);

    void run();
    void step();
    void pause();
    void resume();

    void push_number(double num);
    void push_string(godot::String str);
    godot::Variant pop();
    godot::Variant top();

    int get_stack_size() const;
    int get_program_size() const;
    int get_ppc() const;
    void set_ppc(int pc);
    bool is_exited() const;

    godot::String as_string(godot::Variant value);

    godot::PackedStringArray get_output() const;
    void clear_output();
    void set_stdout_sink(godot::Callable sink);

protected:
    static void _bind_methods();

private:
    ::TzoVM *vm;
    bool runtime_initialized;
    std::map<std::string, godot::Callable> foreign_callables;
    std::map<int, std::string> foreign_names_by_pc;
    godot::PackedStringArray output;
    godot::Callable stdout_sink;

    static std::map<::TzoVM *, TzoVMNative *> instance_map;
    static void foreign_trampoline(::TzoVM *vm);
    static void stdout_trampoline(::TzoVM *vm);
    void stdout_value();
    void append_output(const godot::String &text);
};
