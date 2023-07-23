// Copied from godot-cpp/test/src and modified.

#include "godot_cpp/classes/global_constants.hpp"
#include "godot_cpp/classes/label.hpp"
#include "godot_cpp/core/class_db.hpp"
#include "godot_cpp/variant/utility_functions.hpp"
#include <stdio.h>
#include <map>

extern "C" {
    #include <tzo.h>
    #include <questvm.h>
    #include <json_ez.h>
}

#include "QuestVM.h"

char* _copy(const char* orig) {
    char *res = new char[strlen(orig)+1];
    strcpy_s(res, sizeof res, orig);
    return res;
}

// Instance map to store mapping of TzoVM to QuestVM instance
std::map<TzoVM *, QuestVM *> QuestVM::instanceMap;

// Free function to act as wrapper for emit foreign function
void QuestVM::emitWrapper(TzoVM *vm) {
    QuestVM *instance = instanceMap[vm];
    instance->emit();
}

void QuestVM::getresponseWrapper(TzoVM *vm) {
    QuestVM *instance = instanceMap[vm];
    instance->getresponse();
}

// Used to mark unused parameters to indicate intent and suppress warnings.
#define UNUSED( expr ) (void)( expr )

//// QuestVM

QuestVM::QuestVM()
{
    godot::UtilityFunctions::print( "Constructor." );
}

QuestVM::~QuestVM()
{
    godot::UtilityFunctions::print( "Destructor." );
}

// Methods.
void QuestVM::simpleFunc()
{
    godot::UtilityFunctions::print( "  Simple func called." );
}

void QuestVM::emit() {
    char *str = asString(_pop(vm));
    emit_signal("questvm_emit", godot::String(str));
}

void QuestVM::getresponse() {
    ::pause(vm);

    emit_signal("questvm_getresponse_start");

    struct hashmap_s responseMap = getResponseMap();
    int size = hashmap_num_entries(&responseMap);
    for (int i = 1; i <= size; i++)
    {
        char *k = toString(i);
        Answer* ans = (Answer*)hashmap_get(&responseMap, k, (int)strlen(k));
        if (ans != NULL)
        {
            emit_signal("questvm_getresponse_item", i, ans->pc, godot::String(ans->response));
        }
    }

    emit_signal("questvm_getresponse_end");

    //emit_signal("questvm_getresponse", godot::String(str));
}

void QuestVM::initTzoVM()
{
    vm = createTzoVM();
    instanceMap[vm] = this;
    struct json_value_s *root = loadFileGetJSON(vm, const_cast<char*>(filepath.ascii().get_data()));
    ::initRuntime(vm);
    registerForeignFunction(vm, "emit", &QuestVM::emitWrapper);
    registerForeignFunction(vm, "getResponse", &QuestVM::getresponseWrapper);
    registerForeignFunction(vm, "response", &response);
    struct json_object_s *rootObj = json_value_as_object(root);
    struct json_array_s *inputProgram = get_object_key_as_array(rootObj, "programList");
    struct json_object_s *labelMap = get_object_key_as_object(rootObj, "labelMap");
    if (labelMap != NULL) {
        initLabelMapFromJSONObject(vm, labelMap);
    }
    initProgramListFromJSONArray(vm, inputProgram);
    ::initQuestVM();
}

void QuestVM::run()
{
    ::run(vm);
}

void QuestVM::pushNumber(float num)
{
    _push(vm, *makeNumber(num));
}

void QuestVM::pushString(godot::String str)
{
    _push(vm, *makeString(_copy(str.ascii().get_data())));
}

void QuestVM::clearResponseMap() {
    ::clearResponseMap();
}

void QuestVM::set_file_path(godot::String str) {
    filepath = str;
}

godot::String QuestVM::get_file_path() {
    return filepath;
}


void QuestVM::_bind_methods()
{
    // Methods.
    godot::ClassDB::bind_method( godot::D_METHOD( "pushNumber", "num" ), &QuestVM::pushNumber );
    godot::ClassDB::bind_method( godot::D_METHOD( "pushString", "str" ), &QuestVM::pushString );
    godot::ClassDB::bind_method( godot::D_METHOD( "clearResponseMap" ), &QuestVM::clearResponseMap );
    godot::ClassDB::bind_method( godot::D_METHOD( "initTzoVM" ), &QuestVM::initTzoVM );
    godot::ClassDB::bind_method( godot::D_METHOD( "run" ), &QuestVM::run );

    // Properties.
	godot::ClassDB::bind_method(godot::D_METHOD("get_file_path"), &QuestVM::get_file_path);
	godot::ClassDB::bind_method(godot::D_METHOD("set_file_path", "path"), &QuestVM::set_file_path);
    ADD_PROPERTY(godot::PropertyInfo(godot::Variant::STRING, "file_path"), "set_file_path", "get_file_path");

    // Signals.
    ADD_SIGNAL( godot::MethodInfo( "questvm_emit",
                                   godot::PropertyInfo( godot::Variant::STRING, "string" ) ) );
    ADD_SIGNAL( godot::MethodInfo( "questvm_getresponse_start" ) );
    ADD_SIGNAL( godot::MethodInfo( "questvm_getresponse_item", godot::PropertyInfo( godot::Variant::INT, "id" ),  godot::PropertyInfo( godot::Variant::INT, "pc" ), godot::PropertyInfo( godot::Variant::STRING, "responseText" ) ) );
    ADD_SIGNAL( godot::MethodInfo( "questvm_getresponse_end" ) );

    // Constants.
}

