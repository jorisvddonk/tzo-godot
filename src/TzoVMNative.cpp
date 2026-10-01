// Native (tzo-c backed) counterpart to the GDScript TzoVM.

#include "TzoVMNative.h"

#include "godot_cpp/classes/file_access.hpp"
#include "godot_cpp/classes/json.hpp"
#include "godot_cpp/core/class_db.hpp"
#include "godot_cpp/variant/char_string.hpp"
#include "godot_cpp/variant/utility_functions.hpp"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <set>
#include <string>

std::map<::TzoVM *, TzoVMNative *> TzoVMNative::instance_map;

namespace
{
char *_copy( const char *orig )
{
    char *res = new char[strlen( orig ) + 1];
    strcpy( res, orig );
    return res;
}

godot::Variant value_to_variant( Value value )
{
    if ( value.type == String )
    {
        return godot::String( value.string_value );
    }
    return value.number_value;
}

struct json_value_s *parse_variant( const godot::Variant &value )
{
    godot::String text = godot::JSON::stringify( value, "", true, true );
    godot::CharString utf8 = text.utf8();
    return json_parse( utf8.get_data(), (size_t)utf8.length() );
}

// Opcodes resolved by initProgramListFromJSONArray itself. Everything else is
// either stdout (captured) or a foreign function (dispatched through a
// trampoline so any instruction can be bound to a Callable at runtime).
const std::set<std::string> &builtin_opcodes()
{
    static const std::set<std::string> builtins = {
        "nop", "plus", "+", "min", "-", "mul", "*", "pop", "stdout", "concat",
        "rconcat", "charCode", "randInt", "eq", "and", "dup", "gt", "lt",
        "not", "or", "ppc", "stacksize", "jz", "jgz", "{", "}", "pause",
        "exit", "goto", "setContext", "getContext", "hasContext", "delContext"
    };
    return builtins;
}
} // namespace

TzoVMNative::TzoVMNative()
{
    vm = createTzoVM();
    runtime_initialized = false;
    instance_map[vm] = this;
}

TzoVMNative::~TzoVMNative()
{
    instance_map.erase( vm );
    ::free( vm->stack );
    ::free( vm->program );
    ::free( vm );
}

//// Runtime & loading

void TzoVMNative::init_runtime()
{
    if ( runtime_initialized )
    {
        return;
    }
    ::initRuntime( vm );
    runtime_initialized = true;
}

void TzoVMNative::register_foreign_function( godot::String name, godot::Callable function )
{
    foreign_callables[std::string( name.utf8().get_data() )] = function;
}

godot::Dictionary TzoVMNative::load_file_get_json( godot::String path )
{
    godot::Ref<godot::FileAccess> file = godot::FileAccess::open( path, godot::FileAccess::READ );
    if ( !file.is_valid() )
    {
        godot::UtilityFunctions::push_error( "TzoVMNative: cannot open program file '" + path + "'" );
        return godot::Dictionary();
    }

    godot::Variant parsed = godot::JSON::parse_string( file->get_as_text() );
    if ( parsed.get_type() != godot::Variant::DICTIONARY )
    {
        godot::UtilityFunctions::push_error( "TzoVMNative: program file '" + path + "' is not valid JSON" );
        return godot::Dictionary();
    }
    return parsed;
}

void TzoVMNative::init_label_map_from_json_object( godot::Dictionary obj )
{
    struct json_value_s *root = parse_variant( obj );
    if ( root == nullptr )
    {
        return;
    }
    struct json_object_s *object = json_value_as_object( root );
    if ( object != nullptr )
    {
        initLabelMapFromJSONObject( vm, object );
    }
}

void TzoVMNative::init_program_list_from_json_array( godot::Array array )
{
    struct json_value_s *root = parse_variant( array );
    if ( root == nullptr )
    {
        return;
    }
    struct json_array_s *json_array = json_value_as_array( root );
    if ( json_array == nullptr )
    {
        return;
    }

    initProgramListFromJSONArray( vm, json_array );

    // Rebind stdout and foreign functions on top of the tzo-c resolved program.
    foreign_names_by_pc.clear();
    for ( int i = 0; i < array.size() && i < vm->programSize; i++ )
    {
        godot::Variant entry = array[i];
        if ( entry.get_type() != godot::Variant::DICTIONARY )
        {
            continue;
        }
        godot::Dictionary dict = entry;
        if ( !dict.has( "functionName" ) )
        {
            continue;
        }
        std::string name( godot::String( dict["functionName"] ).utf8().get_data() );
        if ( name == "stdout" )
        {
            vm->program[i].function_pointer = &TzoVMNative::stdout_trampoline;
        }
        else if ( builtin_opcodes().count( name ) == 0 )
        {
            vm->program[i].function_pointer = &TzoVMNative::foreign_trampoline;
            foreign_names_by_pc[i] = name;
        }
    }
}

//// Execution

void TzoVMNative::run()
{
    ::run( vm );
}

void TzoVMNative::step()
{
    ::step( vm );
}

void TzoVMNative::pause()
{
    ::pause( vm );
}

void TzoVMNative::resume()
{
    ::resume( vm );
}

//// Stack

void TzoVMNative::push_number( double num )
{
    _push( vm, *makeNumber( num ) );
}

void TzoVMNative::push_string( godot::String str )
{
    _push( vm, *makeString( _copy( str.utf8().get_data() ) ) );
}

godot::Variant TzoVMNative::pop()
{
    if ( vm->stackSize == 0 )
    {
        return godot::Variant();
    }
    return value_to_variant( _pop( vm ) );
}

godot::Variant TzoVMNative::top()
{
    if ( vm->stackSize == 0 )
    {
        return godot::Variant();
    }
    return value_to_variant( _top( vm ) );
}

int TzoVMNative::get_stack_size() const
{
    return vm->stackSize;
}

int TzoVMNative::get_program_size() const
{
    return vm->programSize;
}

int TzoVMNative::get_ppc() const
{
    return vm->ppc;
}

void TzoVMNative::set_ppc( int pc )
{
    vm->ppc = pc;
}

bool TzoVMNative::is_exited() const
{
    return vm->exited;
}

godot::String TzoVMNative::as_string( godot::Variant value )
{
    if ( value.get_type() == godot::Variant::STRING )
    {
        return value;
    }
    Value number;
    number.type = Number;
    number.number_value = (double)value;
    char *text = asString( number );
    godot::String result( text );
    ::free( text );
    return result;
}

//// Output

godot::PackedStringArray TzoVMNative::get_output() const
{
    return output;
}

void TzoVMNative::clear_output()
{
    output.clear();
}

void TzoVMNative::set_stdout_sink( godot::Callable sink )
{
    stdout_sink = sink;
}

void TzoVMNative::append_output( const godot::String &text )
{
    output.push_back( text );
    if ( stdout_sink.is_valid() )
    {
        stdout_sink.call( text );
    }
}

void TzoVMNative::stdout_value()
{
    if ( vm->stackSize == 0 )
    {
        append_output( "undefined" );
        return;
    }
    Value value = _pop( vm );
    if ( value.type == Number )
    {
        char buffer[64];
        double number = value.number_value;
        if ( number == (double)(long)number && std::fabs( number ) < 1.0e15 )
        {
            snprintf( buffer, sizeof( buffer ), "%ld", (long)number );
        }
        else
        {
            snprintf( buffer, sizeof( buffer ), "%g", number );
        }
        append_output( godot::String( buffer ) );
    }
    else
    {
        append_output( godot::String( value.string_value ) );
    }
}

//// Trampolines

void TzoVMNative::foreign_trampoline( ::TzoVM *p_vm )
{
    auto instance = instance_map.find( p_vm );
    if ( instance == instance_map.end() )
    {
        return;
    }
    TzoVMNative *self = instance->second;
    auto name = self->foreign_names_by_pc.find( p_vm->ppc );
    if ( name == self->foreign_names_by_pc.end() )
    {
        return;
    }
    auto callable = self->foreign_callables.find( name->second );
    if ( callable == self->foreign_callables.end() )
    {
        return;
    }
    if ( callable->second.is_valid() )
    {
        callable->second.call( self );
    }
}

void TzoVMNative::stdout_trampoline( ::TzoVM *p_vm )
{
    auto instance = instance_map.find( p_vm );
    if ( instance != instance_map.end() )
    {
        instance->second->stdout_value();
    }
}

//// Bindings

void TzoVMNative::_bind_methods()
{
    godot::ClassDB::bind_method( godot::D_METHOD( "init_runtime" ), &TzoVMNative::init_runtime );
    godot::ClassDB::bind_method( godot::D_METHOD( "register_foreign_function", "name", "function" ), &TzoVMNative::register_foreign_function );
    godot::ClassDB::bind_method( godot::D_METHOD( "load_file_get_json", "path" ), &TzoVMNative::load_file_get_json );
    godot::ClassDB::bind_method( godot::D_METHOD( "init_label_map_from_json_object", "obj" ), &TzoVMNative::init_label_map_from_json_object );
    godot::ClassDB::bind_method( godot::D_METHOD( "init_program_list_from_json_array", "array" ), &TzoVMNative::init_program_list_from_json_array );

    godot::ClassDB::bind_method( godot::D_METHOD( "run" ), &TzoVMNative::run );
    godot::ClassDB::bind_method( godot::D_METHOD( "step" ), &TzoVMNative::step );
    godot::ClassDB::bind_method( godot::D_METHOD( "pause" ), &TzoVMNative::pause );
    godot::ClassDB::bind_method( godot::D_METHOD( "resume" ), &TzoVMNative::resume );

    godot::ClassDB::bind_method( godot::D_METHOD( "push_number", "num" ), &TzoVMNative::push_number );
    godot::ClassDB::bind_method( godot::D_METHOD( "push_string", "str" ), &TzoVMNative::push_string );
    godot::ClassDB::bind_method( godot::D_METHOD( "pop" ), &TzoVMNative::pop );
    godot::ClassDB::bind_method( godot::D_METHOD( "top" ), &TzoVMNative::top );

    godot::ClassDB::bind_method( godot::D_METHOD( "get_stack_size" ), &TzoVMNative::get_stack_size );
    godot::ClassDB::bind_method( godot::D_METHOD( "get_program_size" ), &TzoVMNative::get_program_size );
    godot::ClassDB::bind_method( godot::D_METHOD( "get_ppc" ), &TzoVMNative::get_ppc );
    godot::ClassDB::bind_method( godot::D_METHOD( "set_ppc", "pc" ), &TzoVMNative::set_ppc );
    godot::ClassDB::bind_method( godot::D_METHOD( "is_exited" ), &TzoVMNative::is_exited );

    godot::ClassDB::bind_method( godot::D_METHOD( "as_string", "value" ), &TzoVMNative::as_string );

    godot::ClassDB::bind_method( godot::D_METHOD( "get_output" ), &TzoVMNative::get_output );
    godot::ClassDB::bind_method( godot::D_METHOD( "clear_output" ), &TzoVMNative::clear_output );
    godot::ClassDB::bind_method( godot::D_METHOD( "set_stdout_sink", "sink" ), &TzoVMNative::set_stdout_sink );
}
