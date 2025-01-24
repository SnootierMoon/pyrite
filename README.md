Done so far
 - ported `nuklear_font.c` into a working state

TODO:
 - get rid of `merge_mode` logic, replace with something like `addFont: Atlas -> Font` and `Font.addTTF: (Font, TTF) -> ()`. then determine what should be per font and what is per ttf
