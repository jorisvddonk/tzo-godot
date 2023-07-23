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

#include "Example.h"

char* _copy(const char* orig) {
    char *res = new char[strlen(orig)+1];
    strcpy_s(res, sizeof res, orig);
    return res;
}

// Instance map to store mapping of TzoVM to Example instance
std::map<TzoVM *, Example *> Example::instanceMap;

// Free function to act as wrapper for emit foreign function
void Example::emitWrapper(TzoVM *vm) {
    Example *instance = instanceMap[vm];
    instance->emit();
}

void Example::getresponseWrapper(TzoVM *vm) {
    Example *instance = instanceMap[vm];
    instance->getresponse();
}

// Used to mark unused parameters to indicate intent and suppress warnings.
#define UNUSED( expr ) (void)( expr )

//// Example

Example::Example()
{
    godot::UtilityFunctions::print( "Constructor." );
}

Example::~Example()
{
    godot::UtilityFunctions::print( "Destructor." );
}

// Methods.
void Example::simpleFunc()
{
    godot::UtilityFunctions::print( "  Simple func called." );
}

void Example::emit() {
    char *str = asString(_pop(vm));
    emit_signal("questvm_emit", godot::String(str));
}

void Example::getresponse() {
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

void Example::initTzoVM()
{
    vm = createTzoVM();
    instanceMap[vm] = this;
    struct json_value_s *root = loadFileGetJSON(vm, const_cast<char*>(filepath.ascii().get_data()));
    ::initRuntime(vm);
    registerForeignFunction(vm, "emit", &Example::emitWrapper);
    registerForeignFunction(vm, "getResponse", &Example::getresponseWrapper);
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

void Example::run()
{
    ::run(vm);
}

void Example::pushNumber(float num)
{
    _push(vm, *makeNumber(num));
}

void Example::pushString(godot::String str)
{
    _push(vm, *makeString(_copy(str.ascii().get_data())));
}

void Example::clearResponseMap() {
    ::clearResponseMap();
}

void Example::set_file_path(godot::String str) {
    filepath = str;
}

godot::String Example::get_file_path() {
    return filepath;
}


void Example::_bind_methods()
{
    // Methods.
    godot::ClassDB::bind_method( godot::D_METHOD( "pushNumber", "num" ), &Example::pushNumber );
    godot::ClassDB::bind_method( godot::D_METHOD( "pushString", "str" ), &Example::pushString );
    godot::ClassDB::bind_method( godot::D_METHOD( "clearResponseMap" ), &Example::clearResponseMap );
    godot::ClassDB::bind_method( godot::D_METHOD( "initTzoVM" ), &Example::initTzoVM );
    godot::ClassDB::bind_method( godot::D_METHOD( "run" ), &Example::run );

    // Properties.
	godot::ClassDB::bind_method(godot::D_METHOD("get_file_path"), &Example::get_file_path);
	godot::ClassDB::bind_method(godot::D_METHOD("set_file_path", "path"), &Example::set_file_path);
    ADD_PROPERTY(godot::PropertyInfo(godot::Variant::STRING, "file_path"), "set_file_path", "get_file_path");

    // Signals.
    ADD_SIGNAL( godot::MethodInfo( "questvm_emit",
                                   godot::PropertyInfo( godot::Variant::STRING, "string" ) ) );
    ADD_SIGNAL( godot::MethodInfo( "questvm_getresponse_start" ) );
    ADD_SIGNAL( godot::MethodInfo( "questvm_getresponse_item", godot::PropertyInfo( godot::Variant::INT, "id" ),  godot::PropertyInfo( godot::Variant::INT, "pc" ), godot::PropertyInfo( godot::Variant::STRING, "responseText" ) ) );
    ADD_SIGNAL( godot::MethodInfo( "questvm_getresponse_end" ) );

    // Constants.
}

