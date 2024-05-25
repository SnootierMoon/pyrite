extern void zig_nk_assert(int);
extern double zig_nk_strtod(const char*, const char**);
extern char* zig_nk_dtoa(char*, double);

#define NK_INCLUDE_DEFAULT_FONT
#define NK_INCLUDE_FIXED_TYPES
#define NK_INCLUDE_FONT_BAKING
#define NK_INCLUDE_STANDARD_BOOL
#define NK_INCLUDE_VERTEX_BUFFER_OUTPUT
#define NK_ASSERT(x) zig_nk_assert((x) != 0)
#define NK_STRTOD zig_nk_strtod
#define NK_DTOA zig_nk_dtoa

#include "nuklear.h"
