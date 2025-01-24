const std = @import("std");

const GlfwLinkMode = enum { static, system };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const wayland = b.option(
        bool,
        "wayland",
        "Enable Wayland support when building for Linux",
    ) orelse true;
    const x11 = b.option(
        bool,
        "x11",
        "Enable X11 support when building for Linux",
    ) orelse true;

    const glfw_mode = b.option(
        GlfwLinkMode,
        "glfw_link",
        "Whether to compile & link GLFW statically, or link to a system installation",
    ) orelse .static;

    const exe = b.addExecutable(.{
        .name = "pyrite",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const cdeps = CDeps.init(b, .{
        .target = target,
        .optimize = optimize,
        .wayland = wayland,
        .x11 = x11,
        .glfw_mode = glfw_mode,
    });
    cdeps.link(exe);
}

const CDeps = struct {
    b: *std.Build,
    o: Options,

    glfw: ?Glfw,
    glad: Glad,
    nk: Nk,

    const Glfw = struct {
        dep: *std.Build.Dependency,
        lib: *std.Build.Step.Compile,
    };

    const Glad = struct {
        dep: *std.Build.Dependency,
        gl_dir: std.Build.LazyPath,
        gl_lib: *std.Build.Step.Compile,
    };

    const Nk = struct {
        dep: *std.Build.Dependency,
        lib: *std.Build.Step.Compile,
    };

    const Options = struct {
        target: std.Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        x11: bool,
        wayland: bool,
        glfw_mode: GlfwLinkMode,
    };

    fn init(b: *std.Build, o: Options) CDeps {
        const glfw = switch (o.glfw_mode) {
            .static => blk: {
                const dep = b.dependency("glfw", .{});
                const lib = b.addStaticLibrary(.{
                    .name = "glfw",
                    .target = o.target,
                    .optimize = o.optimize,
                    .link_libc = true,
                });
                lib.addCSourceFiles(.{
                    .root = dep.path("src"),
                    .files = &glfw_srcs_common,
                });
                lib.installHeadersDirectory(dep.path("include"), ".", .{});
                switch (o.target.result.os.tag) {
                    .windows => {
                        lib.root_module.addCMacro("_GLFW_WIN32", "");
                        lib.addCSourceFiles(.{
                            .root = dep.path("src"),
                            .files = &glfw_srcs_win32,
                        });
                    },
                    .macos => {
                        lib.root_module.addCMacro("_GLFW_COCOA", "");
                        lib.addCSourceFiles(.{
                            .root = dep.path("src"),
                            .files = &glfw_srcs_cocoa,
                        });
                    },
                    .linux => {
                        lib.addIncludePath(.{ .cwd_relative = "/usr/include" });
                        if (!(o.wayland or o.x11)) {
                            @panic("you must enable either Wayland or X11 on Linux");
                        }
                        lib.addCSourceFiles(.{
                            .root = dep.path("src"),
                            .files = &glfw_srcs_linux,
                        });
                        if (o.wayland) {
                            generateWaylandProtocols(b, dep, lib);

                            lib.root_module.addCMacro("_GLFW_WAYLAND", "");
                            lib.addCSourceFiles(.{
                                .root = dep.path("src"),
                                .files = &glfw_srcs_wayland,
                            });
                        }
                        if (o.x11) {
                            lib.root_module.addCMacro("_GLFW_X11", "");
                            lib.addCSourceFiles(.{
                                .root = dep.path("src"),
                                .files = &glfw_srcs_x11,
                            });
                        }
                    },
                    else => @panic("unsupported platform"),
                }
                break :blk Glfw{
                    .dep = dep,
                    .lib = lib,
                };
            },
            .system => null,
        };

        const glad_dep = b.dependency("glad", .{});
        const glad_install_step = std.Build.Step.Run.create(b, "glad-install");
        glad_install_step.addArgs(&.{ "python3", "-m", "pip", "install" });
        glad_install_step.addDirectoryArg(glad_dep.path("."));
        glad_install_step.addArgs(&.{"--target"});
        const glad_install_path = glad_install_step.addOutputFileArg(".");
        const glad_gen_step = std.Build.Step.Run.create(b, "glad-gen");
        glad_gen_step.setCwd(glad_install_path);
        glad_gen_step.addArgs(&.{ "python3", "-m", "glad" });
        glad_gen_step.addArgs(&.{ "--quiet", "--api=gl:core=3.3", "--extensions=GL_KHR_debug", "--out-path" });
        const glad_gl_dir = glad_gen_step.addOutputDirectoryArg(".");
        glad_gen_step.addArgs(&.{"c"});
        const glad_gl_lib = b.addStaticLibrary(.{
            .name = "glad",
            .target = o.target,
            .optimize = o.optimize,
            .link_libc = true,
        });

        glad_gl_lib.addIncludePath(glad_gl_dir.path(b, "include"));
        glad_gl_lib.addCSourceFile(.{ .file = glad_gl_dir.path(b, "src/gl.c") });

        const nk_dep = b.dependency("nuklear", .{});
        const nk_lib = b.addStaticLibrary(.{
            .name = "nuklear",
            .target = o.target,
            .optimize = o.optimize,
            .link_libc = true,
        });
        const nk_files = b.addWriteFiles();
        const nk_headers = std.Build.LazyPath{ .generated = .{
            .file = &nk_files.generated_directory,
            .sub_path = "include",
        } };
        _ = nk_files.addCopyFile(b.path("src/nk.h"), "include/nk.h");
        _ = nk_files.addCopyFile(nk_dep.path("nuklear.h"), "include/nuklear.h");
        _ = nk_files.addCopyFile(nk_dep.path("src/stb_truetype.h"), "include/stb_truetype.h");
        _ = nk_files.addCopyFile(nk_dep.path("src/stb_rect_pack.h"), "include/stb_rect_pack.h");
        nk_lib.addCSourceFile(.{ .file = nk_files.add("src/nk.c", "#define NK_IMPLEMENTATION\n#include \"nk.h\"") });
        nk_lib.addIncludePath(nk_headers);
        nk_lib.installHeadersDirectory(nk_headers, ".", .{});

        const cdeps = CDeps{
            .b = b,
            .o = o,
            .glfw = glfw,
            .glad = .{
                .dep = glad_dep,
                .gl_dir = glad_gl_dir,
                .gl_lib = glad_gl_lib,
            },
            .nk = .{
                .dep = nk_dep,
                .lib = nk_lib,
            },
        };

        return cdeps;
    }

    fn link(cdeps: CDeps, x: *std.Build.Step.Compile) void {
        switch (cdeps.o.glfw_mode) {
            .static => {
                x.linkLibrary(cdeps.glfw.?.lib);
                switch (cdeps.o.target.result.os.tag) {
                    .windows => {
                        x.linkSystemLibrary("gdi32");
                    },
                    .macos => {
                        x.linkFramework("Cocoa");
                        x.linkFramework("IOKit");
                        x.linkFramework("CoreFoundation");
                    },
                    .linux => {
                        x.linkSystemLibrary("wayland-client");
                    },
                    else => @panic("unsupported platform"),
                }
            },
            .system => {
                x.linkSystemLibrary("glfw3");
            },
        }

        x.addIncludePath(cdeps.glad.gl_dir.path(x.step.owner, "include"));
        x.linkLibrary(cdeps.glad.gl_lib);

        x.linkLibrary(cdeps.nk.lib);
    }

    fn generateWaylandProtocols(
        b: *std.Build,
        glfw_dep: *std.Build.Dependency,
        glfw_lib: *std.Build.Step.Compile,
    ) void {
        const protos = [_][]const u8{
            "wayland",
            "viewporter",
            "xdg-shell",
            "idle-inhibit-unstable-v1",
            "pointer-constraints-unstable-v1",
            "relative-pointer-unstable-v1",
            "fractional-scale-v1",
            "xdg-activation-v1",
            "xdg-decoration-unstable-v1",
        };

        for (protos) |proto| {
            const run_header = std.Build.Step.Run.create(b, b.fmt("gen-wl-protos.header.{s}", .{proto}));
            run_header.addArgs(&.{ "wayland-scanner", "client-header" });
            run_header.addFileArg(glfw_dep.path(b.fmt("deps/wayland/{s}.xml", .{proto})));
            const header = run_header.addOutputFileArg(b.fmt("{s}-client-protocol.h", .{proto}));
            glfw_lib.addIncludePath(header.dirname());

            const run_code = std.Build.Step.Run.create(b, b.fmt("gen-wl-protos.code.{s}", .{proto}));
            run_code.addArgs(&.{ "wayland-scanner", "private-code" });
            run_code.addFileArg(glfw_dep.path(b.fmt("deps/wayland/{s}.xml", .{proto})));
            const code = run_code.addOutputFileArg(b.fmt("{s}-client-protocol-code.h", .{proto}));
            glfw_lib.addIncludePath(code.dirname());
        }
    }

    const glfw_srcs_common = .{
        "context.c",       "init.c",         "input.c",
        "monitor.c",       "platform.c",     "vulkan.c",
        "window.c",        "egl_context.c",  "osmesa_context.c",
        "null_init.c",     "null_monitor.c", "null_window.c",
        "null_joystick.c",
    };

    const glfw_srcs_win32 = .{
        "win32_module.c",   "win32_time.c",
        "win32_thread.c",   "win32_init.c",
        "win32_joystick.c", "win32_monitor.c",
        "win32_window.c",   "wgl_context.c",
    };

    const glfw_srcs_cocoa = .{
        "cocoa_time.c",     "posix_module.c",
        "posix_thread.c",   "cocoa_init.m",
        "cocoa_joystick.m", "cocoa_monitor.m",
        "cocoa_window.m",   "nsgl_context.m",
    };

    const glfw_srcs_linux = .{
        "posix_time.c",   "posix_module.c",
        "posix_thread.c", "linux_joystick.c",
        "posix_poll.c",
    };

    const glfw_srcs_x11 = .{
        "x11_init.c",    "x11_monitor.c",
        "x11_window.c",  "xkb_unicode.c",
        "glx_context.c",
    };

    const glfw_srcs_wayland = .{
        "wl_init.c",   "wl_monitor.c",
        "wl_window.c", "xkb_unicode.c",
    };
};
