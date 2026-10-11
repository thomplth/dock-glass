// SPDX-License-Identifier: MIT
#include "DockGlassShims.h"

typedef void __attribute__((swiftcall)) (*BoolSetter)(bool, void *__attribute__((swift_context)));
typedef bool __attribute__((swiftcall)) (*BoolGetter)(void *__attribute__((swift_context)));

void dockglass_call_bool_setter(const void *setter, bool value, void *instance) {
    ((BoolSetter)setter)(value, instance);
}

bool dockglass_call_bool_getter(const void *getter, void *instance) {
    return ((BoolGetter)getter)(instance);
}

typedef void __attribute__((swiftcall)) (*IndirectStaticGetter)(void *__attribute__((swift_indirect_result)));

void dockglass_call_indirect_static_getter(const void *getter, void *result) {
    ((IndirectStaticGetter)getter)(result);
}
