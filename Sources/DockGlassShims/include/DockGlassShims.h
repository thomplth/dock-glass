// SPDX-License-Identifier: MIT
#ifndef DOCKGLASS_SHIMS_H
#define DOCKGLASS_SHIMS_H

#include <stdbool.h>

/// Calls a Swift property setter of type `Bool` on the struct at `instance`.
///
/// Swift passes `self` to a mutating accessor in the `swiftself` register, which Swift source
/// cannot target through a raw function pointer; clang's `swiftcall` convention with a
/// `swift_context` parameter lowers to exactly that register.
void dockglass_call_bool_setter(const void *setter, bool value, void *instance);

/// Calls a Swift property getter of type `Bool` on the struct at `instance`.
bool dockglass_call_bool_getter(const void *getter, void *instance);

/// Calls a Swift static property getter that takes no `self` (a struct's thin metatype) and
/// returns its value indirectly, writing it into the uninitialised memory at `result`.
void dockglass_call_indirect_static_getter(const void *getter, void *result);

#endif
