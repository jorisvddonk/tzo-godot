// Copied from godot-cpp/test/src and modified.

#pragma once

#include "godot_cpp/classes/global_constants.hpp"
#include "godot_cpp/classes/node.hpp"
#include "godot_cpp/core/binder_common.hpp"

#include <map>
#include <string>

extern "C" {
#include <tzo.h>
}

class QuestVMNative : public godot::Node
{
    GDCLASS( QuestVMNative, godot::Node )

public:
    QuestVMNative();
    ~QuestVMNative() override;

    // Functions.
    void initTzoVM();
    void run();
    void simpleFunc();
    void emit();
    void getresponse();
    void response();
    void clearResponseMap();
    void pushNumber(double num);
    void pushString(godot::String str);
    void set_file_path(godot::String str);
    godot::String get_file_path();
    godot::String getCollectedText();
    void clearCollectedText();

protected:
    static void _bind_methods();

private:
    struct Answer
    {
        int pc;
        std::string response;
    };

    // Per-instance state. Unlike tzo-c's questvm.c, nothing here is global, so
    // multiple QuestVMNative instances never share responses or emitted text.
    TzoVM *vm;
    godot::String filepath;
    std::map<int, Answer> responseMap;
    std::string collectedText;

    static void emitWrapper(TzoVM *vm);
    static void getresponseWrapper(TzoVM *vm);
    static void responseWrapper(TzoVM *vm);
    static std::map<TzoVM *, QuestVMNative *> instanceMap;
};
