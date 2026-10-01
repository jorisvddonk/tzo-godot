// Copied from godot-cpp/test/src and modified.

#include "godot_cpp/classes/file_access.hpp"
#include "godot_cpp/classes/global_constants.hpp"
#include "godot_cpp/core/class_db.hpp"
#include "godot_cpp/variant/char_string.hpp"
#include "godot_cpp/variant/utility_functions.hpp"

#include <cstring>
#include <map>
#include <string>

extern "C" {
#include <json_ez.h>
#include <tzo.h>
}

#include "QuestVM.h"

char *_copy(const char *orig)
{
    char *res = new char[strlen(orig) + 1];
    strcpy(res, orig);
    return res;
}

// Instance map to store mapping of TzoVM to QuestVMNative instance
std::map<TzoVM *, QuestVMNative *> QuestVMNative::instanceMap;

// Free functions to act as wrappers for the foreign functions.
void QuestVMNative::emitWrapper(TzoVM *vm)
{
    QuestVMNative *instance = instanceMap[vm];
    instance->emit();
}

void QuestVMNative::getresponseWrapper(TzoVM *vm)
{
    QuestVMNative *instance = instanceMap[vm];
    instance->getresponse();
}

void QuestVMNative::responseWrapper(TzoVM *vm)
{
    QuestVMNative *instance = instanceMap[vm];
    instance->response();
}

// Used to mark unused parameters to indicate intent and suppress warnings.
#define UNUSED( expr ) (void)( expr )

//// QuestVMNative

QuestVMNative::QuestVMNative()
{
    godot::UtilityFunctions::print( "Constructor." );
}

QuestVMNative::~QuestVMNative()
{
    godot::UtilityFunctions::print( "Destructor." );
}

// Methods.
void QuestVMNative::simpleFunc()
{
    godot::UtilityFunctions::print( "  Simple func called." );
}

void QuestVMNative::emit()
{
    char *str = asString(_pop(vm));
    collectedText += str;
    emit_signal("questvm_emit", godot::String(str));
}

void QuestVMNative::response()
{
    Value a = _pop(vm); // number (pc)
    Value b = _pop(vm); // string
    int pc = (int)a.number_value;
    char *str = asString(b);

    int key = (int)responseMap.size() + 1;
    Answer ans;
    ans.pc = pc;
    ans.response = std::string(str);
    responseMap[key] = ans;
}

void QuestVMNative::getresponse()
{
    ::pause(vm);

    emit_signal("questvm_getresponse_start");

    int id = 1;
    for (const auto &entry : responseMap)
    {
        emit_signal("questvm_getresponse_item", id, entry.second.pc,
                    godot::String(entry.second.response.c_str()));
        id += 1;
    }

    emit_signal("questvm_getresponse_end");
}

void QuestVMNative::clearResponseMap()
{
    responseMap.clear();
}

void QuestVMNative::initTzoVM()
{
    vm = createTzoVM();
    instanceMap[vm] = this;
    // This instance starts with no responses; unlike tzo-c's questvm.c, this
    // state lives on the instance rather than in a process-global map.
    responseMap.clear();
    collectedText.clear();

    // Load the program through Godot so res:// and user:// paths work, and so
    // a missing/unparseable file cannot crash on a NULL FILE* (tzo-c's
    // loadFileGetJSON does not null-check fopen/fseek).
    struct json_value_s *root = nullptr;
    godot::Ref<godot::FileAccess> file = godot::FileAccess::open(filepath, godot::FileAccess::READ);
    if (file.is_valid())
    {
        godot::CharString utf8 = file->get_as_text().utf8();
        root = json_parse(utf8.get_data(), (size_t)utf8.length());
    }

    ::initRuntime(vm);
    registerForeignFunction(vm, const_cast<char*>("emit"), (void*)&QuestVMNative::emitWrapper);
    registerForeignFunction(vm, const_cast<char*>("getResponse"), (void*)&QuestVMNative::getresponseWrapper);
    registerForeignFunction(vm, const_cast<char*>("response"), (void*)&QuestVMNative::responseWrapper);

    if (root == nullptr)
    {
        return;
    }

    struct json_object_s *rootObj = json_value_as_object(root);
    if (rootObj == nullptr)
    {
        return;
    }

    struct json_array_s *inputProgram = get_object_key_as_array(rootObj, const_cast<char*>("programList"));
    struct json_object_s *labelMap = get_object_key_as_object(rootObj, const_cast<char*>("labelMap"));
    if (labelMap != NULL)
    {
        initLabelMapFromJSONObject(vm, labelMap);
    }
    if (inputProgram != NULL)
    {
        initProgramListFromJSONArray(vm, inputProgram);
    }
}

void QuestVMNative::run()
{
    ::run(vm);
}

void QuestVMNative::pushNumber(double num)
{
    _push(vm, *makeNumber(num));
}

void QuestVMNative::pushString(godot::String str)
{
    _push(vm, *makeString(_copy(str.ascii().get_data())));
}

void QuestVMNative::set_file_path(godot::String str)
{
    filepath = str;
}

godot::String QuestVMNative::get_file_path()
{
    return filepath;
}


void QuestVMNative::_bind_methods()
{
    // Methods.
    godot::ClassDB::bind_method( godot::D_METHOD( "pushNumber", "num" ), &QuestVMNative::pushNumber );
    godot::ClassDB::bind_method( godot::D_METHOD( "pushString", "str" ), &QuestVMNative::pushString );
    godot::ClassDB::bind_method( godot::D_METHOD( "clearResponseMap" ), &QuestVMNative::clearResponseMap );
    godot::ClassDB::bind_method( godot::D_METHOD( "initTzoVM" ), &QuestVMNative::initTzoVM );
    godot::ClassDB::bind_method( godot::D_METHOD( "run" ), &QuestVMNative::run );

    // Properties.
    godot::ClassDB::bind_method( godot::D_METHOD( "get_file_path" ), &QuestVMNative::get_file_path );
    godot::ClassDB::bind_method( godot::D_METHOD( "set_file_path", "path" ), &QuestVMNative::set_file_path );
    ADD_PROPERTY( godot::PropertyInfo( godot::Variant::STRING, "file_path" ), "set_file_path", "get_file_path" );

    // Signals.
    ADD_SIGNAL( godot::MethodInfo( "questvm_emit",
                                   godot::PropertyInfo( godot::Variant::STRING, "string" ) ) );
    ADD_SIGNAL( godot::MethodInfo( "questvm_getresponse_start" ) );
    ADD_SIGNAL( godot::MethodInfo( "questvm_getresponse_item", godot::PropertyInfo( godot::Variant::INT, "id" ), godot::PropertyInfo( godot::Variant::INT, "pc" ), godot::PropertyInfo( godot::Variant::STRING, "responseText" ) ) );
    ADD_SIGNAL( godot::MethodInfo( "questvm_getresponse_end" ) );

    // Constants.
}
