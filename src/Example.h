#pragma once
// Copied from godot-cpp/test/src and modified.

#include "godot_cpp/classes/control.hpp"
#include "godot_cpp/classes/node.hpp"
#include "godot_cpp/classes/global_constants.hpp"
#include "godot_cpp/classes/viewport.hpp"
#include "godot_cpp/core/binder_common.hpp"
#include <map>
extern "C" {
    #include <tzo.h>
}

class Example : public godot::Node
{
    GDCLASS( Example, godot::Node )

public:
    Example();
    ~Example() override;

    // Functions.
    void initTzoVM();
    void run();
    void simpleFunc();
    void emit();
    void getresponse();
    void clearResponseMap();
    void pushNumber(float num);
    void pushString(godot::String str);
    void Example::set_file_path(godot::String str);
    godot::String Example::get_file_path();

protected:
    static void _bind_methods();

private:
    TzoVM *vm;
    godot::String filepath;
    static void emitWrapper(TzoVM *vm);
    static void getresponseWrapper(TzoVM *vm);
    static std::map<TzoVM *, Example *> instanceMap;
};
