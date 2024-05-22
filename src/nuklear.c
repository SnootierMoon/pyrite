#define NK_IMPLEMENTATION
#define NK_INCLUDE_DEFAULT_FONT
#define NK_INCLUDE_FIXED_TYPES
#define NK_INCLUDE_FONT_BAKING
#define NK_INCLUDE_STANDARD_BOOL
#define NK_INCLUDE_VERTEX_BUFFER_OUTPUT
#define NK_ASSERT(x) zig_nk_assert((x) != 0)

extern void zig_nk_assert(int);

#include "nuklear.h"
