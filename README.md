Done so far
 - ported `nuklear_font.c` into a working state

TODO:
 - get rid of `merge_mode` logic, replace with something like `addFont: Atlas -> Font` and `Font.addTTF: (Font, TTF) -> ()`. then determine what should be per font and what is per ttf
 - port the rest of `nuklear.c`, whatever is used for this version of pyrite
   - need basic input, UI, and vertex buffer output
