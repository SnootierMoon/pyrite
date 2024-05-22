# Pyrite

My WIP Voxel Art Editor!

## Feature Plan

Features are ranked by priority: from T1 (highest priority) to T5 (lowest
priority). Priorities have possibly been assigned without much thought and are
subject to change.

This feature list is not at all exhaustive. I maintain this list so that I can
write down my exciting ideas as to organize my thoughts and not continuously
overwhelm myself. These features may range from small things to large-scale
design ideas.

#### Saving/Loading Objects
 - voxel art file format [**(T1)** MVP]
   - **(T2)** data specification: palette, voxels
   - **(T4)** optimization for space
   - **(T4)** expressitivity, convert from other formats
 - remote access [**(T1)** MVP]
   - **(T2)** objects loaded in client can be marked for remote storage
 - drag & drop / file explorer **(T2)**
#### Edit/Interface
 - multiple objects open at a time, with shared state [**(T1)** MVP]
   - user can copy voxels from one to the other, for example
 - edit commands [**(T2)** MVP]
   - **(T3)** FP language (designed for scriptable proc gen)
   - **(T3)** commands can be saved alongside objects (i.e. on servers or local filesystem)
   - **(T3)** mirror functionality of W/E (FAWE and others)
   - **(T4)** fast!!!
#### Platform/Rendering
 - multiple rendering backends/platforms
   - **(T1)** OpenGL on GLFW
   - **(T3)** Vulkan on GLFW
   - **(T4)** DirectX on GLFW or WinAPI
   - **(T5)** Metal on GLFW or Cocoa
   - **(T3)** WebGPU on Wasm (server hosts wasm & objects perhaps)
   - **(T5)** Vulkan on ??? without linking libc (for fun)
 - **(T3)** headless rendering
 - **(T4)** multiple rendering strategies (rasterization, raymarching)
 - **(T4)** optimization for real-time performance (memory & speed)
#### Network Functionality
 - remote access, as described in [Saving/Loading Objects](#savingloading-objects)
   - **(T1)** server program with basic load/save functionality (MVP)
 - **(T4)** collaboration
   - **(T4)** real-time updates sync with server
   - **(T4)** interaction: chat; sharing objects, waypoints, and commands
#### UI/Design
 - **(T3)** clean, organized UI with coherent style
 - **(T5)** full customizability (tryna make some Emacs type  shit)
 - **(T5)** client/voxel API separation: perhaps the client is one user-orienteed program out of many (is this too much?)
 - **(T2)** create a logo
#### Misc
 - **(T5)** correct cross-compilation support
