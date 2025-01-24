const std = @import("std");
const log_glfw = std.log.scoped(.glfw);
const log_gl = std.log.scoped(.gl);
pub const c = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", "");
    @cInclude("GLFW/glfw3.h");

    @cInclude("glad/gl.h");

    @cInclude("nk.h");
    @cInclude("stb_rect_pack.h");
    @cInclude("stb_truetype.h");
});

const ui = @import("ui.zig");
const Camera = @import("Camera.zig");
const ChunkCoord = @import("voxel/coord.zig").ChunkCoord;
const Dir = @import("voxel/coord.zig").Dir;
const Object = @import("voxel/Object.zig");
const Sphere = @import("voxel/Sphere.zig");
const Voxel = @import("voxel.zig").Voxel;
const lm = @import("linmath.zig");

var f: *ui.Font = undefined;

const NkVertex = extern struct {
    position: [2]f32,
    uv: [2]f32,
    col: [4]u8,
};
pub var AAA: *c.nk_allocator = undefined;

var value: f32 = 0.5;
pub const Platform = struct {
    allocator: std.mem.Allocator,

    fb_width: c_int,
    fb_height: c_int,
    window: *c.GLFWwindow,

    camera: Camera,
    object: Object,

    meshes: std.AutoHashMapUnmanaged(ChunkCoord, Mesh),

    input_mode: InputMode,
    cursor_pos: ?lm.Vec(2, f64),

    voxel_prog: c.GLuint,
    voxel_prog_transform: c.GLint,

    crosshair_prog: c.GLuint,
    crosshair_prog_frame_size: c.GLint,

    atlas: *ui.FontAtlas,

    nk_alloc: c.nk_allocator,
    nk_ctx: c.nk_context,
    nk_tex_null: c.nk_draw_null_texture,
    ui_font_tex: c.GLuint,

    ui_prog: c.GLuint,
    ui_prog_tex: c.GLint,
    ui_prog_transform: c.GLint,

    ui_vao: c.GLuint,
    ui_vbo: c.GLuint,
    ui_ebo: c.GLuint,
    nk_vbuffer: c.nk_buffer,
    nk_ebuffer: c.nk_buffer,
    nk_cmd_buffer: c.nk_buffer,

    const Mesh = struct {
        vao: c.GLuint,
        vbo: c.GLuint,
        count: usize,
    };

    const InputMode = enum {
        camera_input,
        cursor_input,
    };

    const InitOptions = struct {
        width: u16,
        height: u16,
    };

    pub fn init(allocator: std.mem.Allocator, options: InitOptions) !*Platform {
        var platform = try allocator.create(Platform);
        errdefer allocator.destroy(platform);
        platform.allocator = allocator;

        const glfw_allocator: c.GLFWallocator = .{
            .allocate = &glfwAllocate,
            .reallocate = &glfwReallocate,
            .deallocate = &glfwDeallocate,
            .user = platform,
        };

        platform.fb_width = options.width;
        platform.fb_height = options.height;
        _ = c.glfwSetErrorCallback(errorCallback);
        c.glfwInitAllocator(&glfw_allocator);
        if (c.glfwInit() == c.GLFW_FALSE) {
            return error.GlfwInit;
        }
        errdefer c.glfwTerminate();

        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
        c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
        c.glfwWindowHint(c.GLFW_OPENGL_FORWARD_COMPAT, c.GLFW_TRUE);
        c.glfwWindowHint(c.GLFW_OPENGL_DEBUG_CONTEXT, c.GLFW_TRUE);
        platform.window = c.glfwCreateWindow(options.width, options.height, "Pyrite", null, null) orelse {
            return error.GlfwCreateWindow;
        };
        errdefer c.glfwDestroyWindow(platform.window);

        c.glfwSetWindowUserPointer(platform.window, platform);
        _ = c.glfwSetWindowFocusCallback(platform.window, windowFocusCallback);
        _ = c.glfwSetFramebufferSizeCallback(platform.window, framebufferSizeCallback);
        _ = c.glfwSetKeyCallback(platform.window, keyCallback);
        _ = c.glfwSetCharCallback(platform.window, charCallback);
        _ = c.glfwSetMouseButtonCallback(platform.window, mouseButtonCallback);
        _ = c.glfwSetCursorPosCallback(platform.window, cursorPosCallback);
        _ = c.glfwSetScrollCallback(platform.window, scrollCallback);

        c.glfwMakeContextCurrent(platform.window);
        const gl_ver = c.gladLoadGL(c.glfwGetProcAddress);
        log_gl.info("version {}.{}", .{ c.GLAD_VERSION_MAJOR(gl_ver), c.GLAD_VERSION_MINOR(gl_ver) });

        var context_flags: c.GLint = undefined;
        c.glGetIntegerv(c.GL_CONTEXT_FLAGS, &context_flags);
        if (context_flags & c.GL_CONTEXT_FLAG_DEBUG_BIT != 0) {
            log_gl.info("debug context available", .{});
            c.glEnable(c.GL_DEBUG_OUTPUT);
            c.glEnable(c.GL_DEBUG_OUTPUT_SYNCHRONOUS);
            c.glDebugMessageCallback(&glDebugCallback, platform);
            c.glDebugMessageControl(c.GL_DONT_CARE, c.GL_DONT_CARE, c.GL_DONT_CARE, 0, null, c.GL_TRUE);
        }

        c.glViewport(0, 0, options.width, options.height);

        platform.camera = Camera.init(lm.Vec3F{ -20.0, 0.0, 0.0 }, 0.0, 0.0);
        platform.object = Object.init();
        errdefer platform.object.deinit(allocator);

        const sphere = Sphere{ .radius = 15.0, .center = lm.vec3d.zero };
        var sphere_it = sphere.iterator();
        while (sphere_it.next()) |posn| {
            (try platform.object.getPtr(allocator, posn)).* = @enumFromInt(1);
        }

        platform.meshes = .{};
        errdefer platform.meshes.deinit(allocator);
        errdefer platform.cleanupMeshes();

        var it = platform.object.chunks.keyIterator();
        while (it.next()) |ccoord| {
            try platform.updateMesh(ccoord.*);
        }

        platform.input_mode = .cursor_input;
        platform.cursor_pos = null;

        platform.voxel_prog = try makeProgram(
            @embedFile("shaders/voxel_vert.glsl"),
            @embedFile("shaders/voxel_frag.glsl"),
        );
        errdefer c.glDeleteProgram(platform.voxel_prog);
        platform.voxel_prog_transform = c.glGetUniformLocation(platform.voxel_prog, "transform");

        platform.crosshair_prog = try makeProgram(
            @embedFile("shaders/crosshair_vert.glsl"),
            @embedFile("shaders/crosshair_frag.glsl"),
        );
        errdefer c.glDeleteProgram(platform.crosshair_prog);
        c.glUseProgram(platform.crosshair_prog);
        platform.crosshair_prog_frame_size = c.glGetUniformLocation(platform.crosshair_prog, "frame_size");
        c.glUniform2f(platform.crosshair_prog_frame_size, @floatFromInt(options.width), @floatFromInt(options.height));

        platform.nk_alloc = platform.nkAllocator();
        AAA = &platform.nk_alloc;

        platform.ui_prog = try makeProgram(
            @embedFile("shaders/nuklear_vert.glsl"),
            @embedFile("shaders/nuklear_frag.glsl"),
        );
        errdefer c.glDeleteProgram(platform.ui_prog);
        platform.ui_prog_tex = c.glGetUniformLocation(platform.ui_prog, "tex");
        platform.ui_prog_transform = c.glGetUniformLocation(platform.ui_prog, "transform");

        c.glGenVertexArrays(1, &platform.ui_vao);
        errdefer c.glDeleteVertexArrays(1, &platform.ui_vao);
        c.glGenBuffers(1, &platform.ui_vbo);
        errdefer c.glDeleteBuffers(1, &platform.ui_vbo);
        c.glGenBuffers(1, &platform.ui_ebo);
        errdefer c.glDeleteBuffers(1, &platform.ui_ebo);

        c.glBindVertexArray(platform.ui_vao);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, platform.ui_vbo);
        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, platform.ui_ebo);

        c.nk_buffer_init(&platform.nk_vbuffer, &platform.nk_alloc, 4096);
        errdefer c.nk_buffer_free(&platform.nk_vbuffer);
        c.nk_buffer_init(&platform.nk_ebuffer, &platform.nk_alloc, 4096);
        errdefer c.nk_buffer_free(&platform.nk_ebuffer);
        c.nk_buffer_init(&platform.nk_cmd_buffer, &platform.nk_alloc, 4096);
        errdefer c.nk_buffer_free(&platform.nk_cmd_buffer);

        c.glEnableVertexAttribArray(0);
        c.glEnableVertexAttribArray(1);
        c.glEnableVertexAttribArray(2);

        c.glVertexAttribPointer(0, 2, c.GL_FLOAT, c.GL_FALSE, @sizeOf(NkVertex), @ptrFromInt(@offsetOf(NkVertex, "position")));
        c.glVertexAttribPointer(1, 2, c.GL_FLOAT, c.GL_FALSE, @sizeOf(NkVertex), @ptrFromInt(@offsetOf(NkVertex, "uv")));
        c.glVertexAttribPointer(2, 4, c.GL_UNSIGNED_BYTE, c.GL_TRUE, @sizeOf(NkVertex), @ptrFromInt(@offsetOf(NkVertex, "col")));

        platform.atlas = try .init(allocator);
        errdefer platform.atlas.deinit(platform.allocator);
        f = try platform.atlas.addTTF(allocator, .{
            .ttf = @embedFile("yeet.ttf"),
            .height = 13,
        });
        const result = try platform.atlas.bake(allocator, .r8g8b8a8_unorm);
        defer allocator.free(result.pixels);

        c.glGenTextures(1, &platform.ui_font_tex);
        errdefer c.glDeleteTextures(1, &platform.ui_font_tex);
        c.glBindTexture(c.GL_TEXTURE_2D, platform.ui_font_tex);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_LINEAR);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_LINEAR);
        c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGBA, @intCast(result.width), @intCast(result.height), 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, result.pixels.ptr);
        platform.atlas.end(@ptrFromInt(platform.ui_font_tex), &platform.nk_tex_null);

        _ = c.nk_init(&platform.nk_ctx, &platform.nk_alloc, &f.nkuf);

        return platform;
    }

    pub fn deinit(platform: *Platform) void {
        const allocator = platform.allocator;

        c.glDeleteTextures(1, &platform.ui_font_tex);
        platform.atlas.deinit(platform.allocator);
        // c.nk_font_atlas_clear(&platform.nk_atlas);
        c.nk_free(&platform.nk_ctx);
        c.nk_buffer_free(&platform.nk_cmd_buffer);
        c.nk_buffer_free(&platform.nk_ebuffer);
        c.nk_buffer_free(&platform.nk_vbuffer);
        c.glDeleteBuffers(1, &platform.ui_ebo);
        c.glDeleteBuffers(1, &platform.ui_vbo);
        c.glDeleteVertexArrays(1, &platform.ui_vao);
        c.glDeleteProgram(platform.ui_prog);
        c.glDeleteProgram(platform.crosshair_prog);
        c.glDeleteProgram(platform.voxel_prog);
        platform.cleanupMeshes();
        platform.meshes.deinit(allocator);
        platform.object.deinit(platform.allocator);
        c.glfwDestroyWindow(platform.window);
        c.glfwTerminate();
        allocator.destroy(platform);
    }

    pub fn run(platform: *Platform) !void {
        while (c.glfwWindowShouldClose(platform.window) == c.GLFW_FALSE) {
            try platform.events();
            try platform.draw();

            c.nk_clear(&platform.nk_ctx);
        }
    }

    fn events(platform: *Platform) !void {
        c.nk_input_begin(&platform.nk_ctx);
        c.glfwPollEvents();
        c.nk_input_end(&platform.nk_ctx);

        c.nk_style_show_cursor(&platform.nk_ctx);
        if (c.nk_begin(&platform.nk_ctx, "Show", c.nk_rect(50, 50, 220, 220), c.NK_WINDOW_BORDER | c.NK_WINDOW_MOVABLE | c.NK_WINDOW_CLOSABLE)) {}
        c.nk_end(&platform.nk_ctx);

        switch (platform.input_mode) {
            .camera_input => {
                var v_rel = lm.Vec3F{ 0, 0, 0 };
                if (c.glfwGetKey(platform.window, c.GLFW_KEY_W) == c.GLFW_PRESS) {
                    v_rel[0] += 1;
                }
                if (c.glfwGetKey(platform.window, c.GLFW_KEY_A) == c.GLFW_PRESS) {
                    v_rel[1] += 1;
                }
                if (c.glfwGetKey(platform.window, c.GLFW_KEY_S) == c.GLFW_PRESS) {
                    v_rel[0] -= 1;
                }
                if (c.glfwGetKey(platform.window, c.GLFW_KEY_D) == c.GLFW_PRESS) {
                    v_rel[1] -= 1;
                }
                if (c.glfwGetKey(platform.window, c.GLFW_KEY_SPACE) == c.GLFW_PRESS) {
                    v_rel[2] += 1;
                }
                if (c.glfwGetKey(platform.window, c.GLFW_KEY_LEFT_SHIFT) == c.GLFW_PRESS) {
                    v_rel[2] -= 1;
                }
                if (lm.vec3f.scaleTo(v_rel, 0.2, 0.001)) |v_rel_scaled| {
                    platform.camera.move(v_rel_scaled);
                }
            },
            else => {},
        }
    }

    fn draw(platform: *Platform) !void {
        c.glClearColor(0, 0, 0, 255);
        c.glClear(c.GL_DEPTH_BUFFER_BIT | c.GL_COLOR_BUFFER_BIT);

        c.glEnable(c.GL_CULL_FACE);
        c.glEnable(c.GL_DEPTH_TEST);
        c.glUseProgram(platform.voxel_prog);
        const view_proj = platform.camera.viewProj(
            0.1,
            std.math.pi / 2.0,
            @as(f32, @floatFromInt(platform.fb_width)) / @as(f32, @floatFromInt(platform.fb_height)),
        );
        var it = platform.meshes.iterator();
        while (it.next()) |entry| {
            const model = platform.camera.model(entry.key_ptr.*);
            c.glUniformMatrix4fv(platform.voxel_prog_transform, 1, c.GL_TRUE, &lm.mat4f.rowMajorArray(lm.mat4f.mul(view_proj, model)));
            c.glBindVertexArray(entry.value_ptr.vao);
            c.glDrawArraysInstanced(c.GL_TRIANGLES, 0, 6, @intCast(entry.value_ptr.count));
        }

        c.glDisable(c.GL_DEPTH_TEST);
        c.glUseProgram(platform.crosshair_prog);
        c.glDrawArrays(c.GL_TRIANGLES, 0, 12);

        const convert_config: c.nk_convert_config = .{
            .global_alpha = 1.0,
            .line_AA = c.NK_ANTI_ALIASING_ON,
            .shape_AA = c.NK_ANTI_ALIASING_ON,
            .circle_segment_count = 22,
            .arc_segment_count = 22,
            .curve_segment_count = 22,
            .tex_null = platform.nk_tex_null,
            .vertex_layout = &[4]c.nk_draw_vertex_layout_element{
                .{ .attribute = c.NK_VERTEX_POSITION, .format = c.NK_FORMAT_FLOAT, .offset = @offsetOf(NkVertex, "position") },
                .{ .attribute = c.NK_VERTEX_TEXCOORD, .format = c.NK_FORMAT_FLOAT, .offset = @offsetOf(NkVertex, "uv") },
                .{ .attribute = c.NK_VERTEX_COLOR, .format = c.NK_FORMAT_R8G8B8A8, .offset = @offsetOf(NkVertex, "col") },
                .{ .attribute = c.NK_VERTEX_ATTRIBUTE_COUNT, .format = c.NK_FORMAT_COUNT, .offset = 0 },
            },
            .vertex_size = @sizeOf(NkVertex),
            .vertex_alignment = @alignOf(NkVertex),
        };

        const ortho = lm.transform.ortho(@floatFromInt(platform.fb_width), @floatFromInt(platform.fb_height));

        c.glEnable(c.GL_BLEND);
        c.glBlendEquation(c.GL_FUNC_ADD);
        c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
        c.glDisable(c.GL_CULL_FACE);
        c.glDisable(c.GL_DEPTH_TEST);
        c.glEnable(c.GL_SCISSOR_TEST);
        c.glActiveTexture(c.GL_TEXTURE0);

        c.glUseProgram(platform.ui_prog);
        c.glUniform1i(platform.ui_prog_tex, 0);
        c.glUniformMatrix4fv(platform.ui_prog_transform, 1, c.GL_TRUE, &lm.mat4f.rowMajorArray(ortho));

        c.glBindVertexArray(platform.ui_vao);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, platform.ui_vbo);
        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, platform.ui_ebo);

        c.nk_buffer_clear(&platform.nk_vbuffer);
        c.nk_buffer_clear(&platform.nk_ebuffer);
        c.nk_buffer_clear(&platform.nk_cmd_buffer);
        _ = c.nk_convert(&platform.nk_ctx, &platform.nk_cmd_buffer, &platform.nk_vbuffer, &platform.nk_ebuffer, &convert_config);
        c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(platform.nk_vbuffer.allocated), c.nk_buffer_memory(&platform.nk_vbuffer), c.GL_STREAM_DRAW);
        c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, @intCast(platform.nk_ebuffer.allocated), c.nk_buffer_memory(&platform.nk_ebuffer), c.GL_STREAM_DRAW);

        var cmd_ = c.nk__draw_begin(&platform.nk_ctx, &platform.nk_cmd_buffer);
        var offset: [*]allowzero c.nk_draw_index = @ptrFromInt(0);
        while (@as(?*const c.nk_draw_command, cmd_)) |cmd| : (cmd_ = c.nk__draw_next(cmd_, &platform.nk_cmd_buffer, &platform.nk_ctx)) {
            if (cmd.elem_count == 0) continue;
            c.glBindTexture(c.GL_TEXTURE_2D, @intCast(cmd.texture.id));
            c.glScissor(
                @intFromFloat(cmd.clip_rect.x),
                platform.fb_height - @as(c_int, @intFromFloat(cmd.clip_rect.y + cmd.clip_rect.h)),
                @intFromFloat(cmd.clip_rect.w),
                @intFromFloat(cmd.clip_rect.h),
            );
            c.glDrawElements(c.GL_TRIANGLES, @intCast(cmd.elem_count), c.GL_UNSIGNED_SHORT, @ptrCast(offset));
            offset += cmd.elem_count;
        }

        c.glfwSwapBuffers(platform.window);
    }

    fn updateMesh(platform: *Platform, ccoord: ChunkCoord) !void {
        const allocator = platform.allocator;
        if (platform.meshes.fetchRemove(ccoord)) |kv| {
            c.glDeleteBuffers(1, &kv.value.vbo);
            c.glDeleteVertexArrays(1, &kv.value.vao);
        }

        var buffer = std.ArrayList(u32).init(allocator);
        defer buffer.deinit();

        if (try platform.object.generateMesh(ccoord, &buffer)) {
            var vao: c.GLuint = undefined;
            var vbo: c.GLuint = undefined;

            c.glGenVertexArrays(1, &vao);
            c.glGenBuffers(1, &vbo);

            c.glBindVertexArray(vao);
            c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);

            c.glVertexAttribIPointer(0, 1, c.GL_UNSIGNED_INT, @sizeOf(u32), null);
            c.glEnableVertexAttribArray(0);
            c.glVertexAttribDivisor(0, 1);
            c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(buffer.items.len * @sizeOf(u32)), buffer.items.ptr, c.GL_STATIC_DRAW);

            try platform.meshes.put(allocator, ccoord, .{
                .vao = vao,
                .vbo = vbo,
                .count = buffer.items.len,
            });
        }
    }

    fn cleanupMeshes(platform: *Platform) void {
        var it = platform.meshes.valueIterator();
        while (it.next()) |mesh| {
            c.glDeleteBuffers(1, &mesh.vbo);
            c.glDeleteVertexArrays(1, &mesh.vao);
        }
    }

    fn setInputMode(platform: *Platform, input_mode: InputMode) void {
        if (platform.input_mode != input_mode) {
            platform.input_mode = input_mode;
            switch (input_mode) {
                .camera_input => {
                    c.glfwSetInputMode(platform.window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);
                    c.glfwSetInputMode(platform.window, c.GLFW_RAW_MOUSE_MOTION, 1);
                },
                .cursor_input => {
                    c.glfwSetInputMode(platform.window, c.GLFW_RAW_MOUSE_MOTION, 0);
                    c.glfwSetInputMode(platform.window, c.GLFW_CURSOR, c.GLFW_CURSOR_NORMAL);
                },
            }
        }
    }

    fn windowFocusCallback(window: ?*c.GLFWwindow, focused: c_int) callconv(.C) void {
        const platform = platformFromWindow(window);

        switch (platform.input_mode) {
            .camera_input => {
                if (focused == c.GLFW_FALSE) {
                    platform.setInputMode(.cursor_input);
                }
            },
            else => {},
        }
        if (focused == c.GLFW_FALSE) {
            platform.cursor_pos = null;
        }
    }

    fn framebufferSizeCallback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
        const platform = platformFromWindow(window);
        platform.fb_width = width;
        platform.fb_height = height;
        c.glViewport(0, 0, width, height);
        c.glUseProgram(platform.crosshair_prog);
        c.glUniform2f(platform.crosshair_prog_frame_size, @floatFromInt(width), @floatFromInt(height));
    }

    fn keyCallback(window: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
        _ = .{ scancode, mods };
        const platform = platformFromWindow(window);

        switch (platform.input_mode) {
            .cursor_input => {
                const nk_key: ?c.nk_keys = switch (key) {
                    c.GLFW_KEY_LEFT_SHIFT, c.GLFW_KEY_RIGHT_SHIFT => c.NK_KEY_SHIFT,
                    c.GLFW_KEY_LEFT_CONTROL, c.GLFW_KEY_RIGHT_CONTROL => c.NK_KEY_CTRL,
                    c.GLFW_KEY_DELETE => c.NK_KEY_DEL,
                    c.GLFW_KEY_ENTER => c.NK_KEY_ENTER,
                    c.GLFW_KEY_TAB => c.NK_KEY_TAB,
                    c.GLFW_KEY_BACKSPACE => c.NK_KEY_BACKSPACE,
                    c.GLFW_KEY_C => c.NK_KEY_COPY,
                    c.GLFW_KEY_X => c.NK_KEY_CUT,
                    c.GLFW_KEY_V => c.NK_KEY_PASTE,
                    c.GLFW_KEY_UP => c.NK_KEY_UP,
                    c.GLFW_KEY_DOWN => c.NK_KEY_DOWN,
                    c.GLFW_KEY_LEFT => c.NK_KEY_LEFT,
                    c.GLFW_KEY_RIGHT => c.NK_KEY_RIGHT,
                    // => NK_KEY_TEXT_INSERT_MODE,
                    // => NK_KEY_TEXT_REPLACE_MODE,
                    // => NK_KEY_TEXT_RESET_MODE,
                    // => NK_KEY_TEXT_LINE_START,
                    // => NK_KEY_TEXT_LINE_END,
                    // => NK_KEY_TEXT_START,
                    // => NK_KEY_TEXT_END,
                    // => NK_KEY_TEXT_UNDO,
                    // => NK_KEY_TEXT_REDO,
                    // => NK_KEY_TEXT_SELECT_ALL,
                    // => NK_KEY_TEXT_WORD_LEFT,
                    // => NK_KEY_TEXT_WORD_RIGHT,
                    // => NK_KEY_SCROLL_START,
                    // => NK_KEY_SCROLL_END,
                    // => NK_KEY_SCROLL_DOWN,
                    // => NK_KEY_SCROLL_UP,

                    else => null,
                };
                if (nk_key) |k| {
                    c.nk_input_key(&platform.nk_ctx, k, action == c.GLFW_PRESS);
                }
            },
            .camera_input => {
                if (key == c.GLFW_KEY_ESCAPE and action == c.GLFW_PRESS) {
                    platform.setInputMode(.cursor_input);
                }
            },
        }
    }

    fn charCallback(window: ?*c.GLFWwindow, codepoint: c_uint) callconv(.C) void {
        const platform = platformFromWindow(window);

        if (platform.input_mode == .cursor_input) {
            c.nk_input_unicode(&platform.nk_ctx, codepoint);
        }
    }

    fn mouseButtonCallback(window: ?*c.GLFWwindow, button: c_int, action: c_int, mods: c_int) callconv(.C) void {
        _ = mods;
        const platform = platformFromWindow(window);

        switch (platform.input_mode) {
            .cursor_input => {
                if (button == c.GLFW_MOUSE_BUTTON_LEFT and action == c.GLFW_PRESS and !c.nk_window_is_any_hovered(&platform.nk_ctx)) {
                    platform.setInputMode(.camera_input);
                } else {
                    const nk_button: ?c.nk_buttons = switch (button) {
                        c.GLFW_MOUSE_BUTTON_LEFT => c.NK_BUTTON_LEFT,
                        c.GLFW_MOUSE_BUTTON_MIDDLE => c.NK_BUTTON_MIDDLE,
                        c.GLFW_MOUSE_BUTTON_RIGHT => c.NK_BUTTON_RIGHT,
                        // => c.NK_BUTTON_DOUBLE,
                        else => null,
                    };
                    if (nk_button) |b| {
                        if (platform.cursor_pos) |pos| {
                            c.nk_input_button(&platform.nk_ctx, @intCast(b), @intFromFloat(pos[0]), @intFromFloat(pos[1]), action == c.GLFW_PRESS);
                        }
                    }
                }
            },
            .camera_input => {
                if (button == c.GLFW_MOUSE_BUTTON_LEFT and action == c.GLFW_PRESS) {
                    if (platform.object.rayMarchNonAir(platform.camera.pos, platform.camera.forward(), 25.0)) |hit| {
                        const sphere = Sphere{ .radius = 5.0, .center = hit.center() };
                        var sphere_it = sphere.iterator();
                        while (sphere_it.next()) |posn| {
                            (platform.object.getPtr(platform.allocator, posn) catch @panic("")).* = @enumFromInt(@as(u32, @intCast(0)));
                        }
                        var it = platform.object.chunks.keyIterator();
                        while (it.next()) |ccoord| {
                            platform.updateMesh(ccoord.*) catch @panic("");
                        }
                    }
                }
            },
        }
    }

    fn cursorPosCallback(window: ?*c.GLFWwindow, xpos: f64, ypos: f64) callconv(.C) void {
        const platform = platformFromWindow(window);

        switch (platform.input_mode) {
            .cursor_input => {
                const x: c_int = @intFromFloat(xpos);
                const y: c_int = @intFromFloat(ypos);
                c.nk_input_motion(&platform.nk_ctx, x, y);
            },
            .camera_input => {
                if (platform.cursor_pos) |pos| {
                    const del_yaw = 0.01 * (pos[0] - xpos);
                    const del_pitch = 0.01 * (pos[1] - ypos);

                    platform.camera.adjustOrientation(@floatCast(del_yaw), @floatCast(del_pitch));
                }
            },
        }
        platform.cursor_pos = .{ xpos, ypos };
    }

    fn scrollCallback(window: ?*c.GLFWwindow, x_offset: f64, y_offset: f64) callconv(.C) void {
        const platform = platformFromWindow(window);

        switch (platform.input_mode) {
            .cursor_input => {
                c.nk_input_scroll(&platform.nk_ctx, c.nk_vec2(@floatCast(x_offset), @floatCast(y_offset)));
            },
            else => {},
        }
    }

    fn errorCallback(error_code: c_int, description: ?[*:0]const u8) callconv(.C) void {
        log_glfw.err("(0x{x}): {?s}", .{ error_code, description });
    }

    fn platformFromWindow(window: ?*c.GLFWwindow) *Platform {
        return @ptrCast(@alignCast(c.glfwGetWindowUserPointer(window).?));
    }

    fn makeProgram(vs_src: []const u8, fs_src: []const u8) !c.GLuint {
        const vs_shader = try makeShader(c.GL_VERTEX_SHADER, vs_src);
        defer c.glDeleteShader(vs_shader);
        const fs_shader = try makeShader(c.GL_FRAGMENT_SHADER, fs_src);
        defer c.glDeleteShader(fs_shader);
        const program = c.glCreateProgram();
        errdefer c.glDeleteProgram(program);

        c.glAttachShader(program, vs_shader);
        c.glAttachShader(program, fs_shader);
        c.glLinkProgram(program);

        var status: c.GLint = undefined;
        c.glGetProgramiv(program, c.GL_LINK_STATUS, &status);
        if (status == 0) {
            var buf: [512]u8 = undefined;
            c.glGetProgramInfoLog(program, 512, null, &buf);
            log_glfw.err("GL link program: {s}", .{std.mem.sliceTo(&buf, 0)});
            return error.GlLinkProgram;
        }

        return program;
    }

    fn makeShader(kind: c.GLenum, src: []const u8) !c.GLuint {
        const shader = c.glCreateShader(kind);
        errdefer c.glDeleteShader(shader);

        c.glShaderSource(shader, 1, &src.ptr, &@as(c.GLint, @intCast(src.len)));
        c.glCompileShader(shader);

        var status: c.GLint = undefined;
        c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &status);
        if (status == 0) {
            var buf: [512]u8 = undefined;
            c.glGetShaderInfoLog(shader, 512, null, &buf);
            log_glfw.err("GL compile shader: {s}", .{std.mem.sliceTo(&buf, 0)});
            return error.GlCompileShader;
        }

        return shader;
    }

    fn glDebugCallback(
        source: c.GLenum,
        type_: c.GLenum,
        id: c.GLuint,
        severity: c.GLenum,
        length: c.GLsizei,
        message: ?[*:0]const c.GLchar,
        userParam: ?*const anyopaque,
    ) callconv(if (@import("builtin").target.os.tag == .windows) std.os.windows.WINAPI else .C) void {
        _ = .{ source, type_, id, severity, length, userParam };

        switch (severity) {
            c.GL_DEBUG_SEVERITY_HIGH => log_gl.err("(0x{x}) {?s}", .{ id, message }),
            c.GL_DEBUG_SEVERITY_MEDIUM => log_gl.warn("(0x{x}) {?s}", .{ id, message }),
            else => log_gl.info("(0x{x}) {?s}", .{ id, message }),
        }
    }

    const max_c_align = 32;

    fn glfwAllocate(size: usize, user: ?*anyopaque) callconv(.C) ?*anyopaque {
        const platform: *Platform = @ptrCast(@alignCast(user.?));
        const mem = platform.allocator.alignedAlloc(u8, max_c_align, max_c_align + size) catch return null;
        mem[0..@sizeOf(usize)].* = @bitCast(size);
        return mem.ptr + max_c_align;
    }

    fn glfwReallocate(block: ?*anyopaque, size: usize, user: ?*anyopaque) callconv(.C) ?*anyopaque {
        const platform: *Platform = @ptrCast(@alignCast(user.?));
        const old_mem_ptr: [*]align(max_c_align) u8 = @alignCast(@as([*]u8, @ptrCast(block orelse return null)) - max_c_align);
        const len: usize = @bitCast(old_mem_ptr[0..@sizeOf(usize)].*);
        const old_mem = old_mem_ptr[0 .. len + max_c_align];
        const new_mem = platform.allocator.realloc(old_mem, max_c_align + size) catch return null;
        new_mem[0..@sizeOf(usize)].* = @bitCast(size);
        return new_mem.ptr + max_c_align;
    }

    fn glfwDeallocate(block: ?*anyopaque, user: ?*anyopaque) callconv(.C) void {
        const platform: *Platform = @ptrCast(@alignCast(user.?));
        const mem_ptr: [*]align(max_c_align) u8 = @alignCast(@as([*]u8, @ptrCast(block orelse return)) - max_c_align);
        const len: usize = @bitCast(mem_ptr[0..@sizeOf(usize)].*);
        const mem = mem_ptr[0 .. len + max_c_align];
        platform.allocator.free(mem);
    }

    pub fn nkAllocator(platform: *const Platform) c.nk_allocator {
        return .{
            .userdata = c.nk_handle_ptr(@constCast(platform)),
            .alloc = nkAlloc,
            .free = nkFree,
        };
    }

    fn nkAlloc(userdata: c.nk_handle, old: ?*anyopaque, size: usize) callconv(.C) ?*anyopaque {
        const platform: *Platform = @ptrCast(@alignCast(userdata.ptr.?));
        _ = old;
        // if (old) |p| {
        //     const old_mem_ptr: [*]align(max_c_align) u8 = @alignCast(@as([*]u8, @ptrCast(p)) - max_c_align);
        //     const len: usize = @bitCast(old_mem_ptr[0..@sizeOf(usize)].*);
        //     const old_mem = old_mem_ptr[0 .. len + max_c_align];
        //     const new_mem = platform.allocator.realloc(old_mem, max_c_align + size) catch return null;
        //     new_mem[0..@sizeOf(usize)].* = @bitCast(size);
        //     return new_mem.ptr + max_c_align;
        // } else {
        const mem = platform.allocator.alignedAlloc(u8, max_c_align, max_c_align + size) catch return null;
        mem[0..@sizeOf(usize)].* = @bitCast(size);
        return mem.ptr + max_c_align;
        // }
    }

    fn nkFree(userdata: c.nk_handle, old: ?*anyopaque) callconv(.C) void {
        const platform: *Platform = @ptrCast(@alignCast(userdata.ptr.?));
        const mem_ptr: [*]align(max_c_align) u8 = @alignCast(@as([*]u8, @ptrCast(old orelse return)) - max_c_align);
        const len: usize = @bitCast(mem_ptr[0..@sizeOf(usize)].*);
        const mem = mem_ptr[0 .. len + max_c_align];
        platform.allocator.free(mem);
    }
};

export fn zig_nk_assert(x: c_int) callconv(.C) void {
    std.debug.assert(x != 0);
}

export fn zig_nk_strtod(_start: [*:0]const u8, endptr: ?*[*:0]const u8) callconv(.C) f64 {
    // read ( )+[+-]?([0-9]+\.[0-9]*|\.[0-9]+)?([eE][+-]?)[0-9]+
    var start = _start;
    while (start[0] == ' ') start += 1;
    var len: usize = 0;
    if (start[len] == '+' or start[len] == '-') {
        len += 1;
    }
    var state: enum { int, dec, exp } = .int;
    if (std.ascii.isDigit(start[len])) {
        len += 1;
    } else if (start[len] == '.' and std.ascii.isDigit(start[len + 1])) {
        state = .dec;
        len += 2;
    } else {
        return 0.0;
    }
    while (true) : (len += 1) {
        if (state == .int and start[len] == '.') {
            state = .dec;
        } else if (state == .dec and (start[len] == 'e' or start[len] == 'E') and
            (std.ascii.isDigit(start[len + 1]) or
            (start[len + 1] == '+' or start[len + 1] == '-') and std.ascii.isDigit(start[len + 2])))
        {
            state = .exp;
        } else if (!std.ascii.isDigit(start[len])) {
            break;
        }
    }
    if (endptr) |eptr| {
        eptr.* = start + len;
    }
    return std.fmt.parseFloat(f64, start[0..len]) catch unreachable;
}

export fn zig_nk_dtoa(_s: ?[*:0]u8, n: f64) ?[*:0]u8 {
    if (_s) |s| {
        const buf = s[0..c.NK_MAX_NUMBER_BUFFER];
        _ = std.fmt.bufPrintZ(buf, "{d:.2}", .{n}) catch unreachable;
    }
    return _s;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var platform = try Platform.init(gpa.allocator(), .{ .width = 1280, .height = 800 });
    defer platform.deinit();

    try platform.run();
}
