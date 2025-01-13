const std = @import("std");
const Build = std.Build;
const builtin = @import("builtin");

const tyrian_srcs = [_][]const u8{
    "src/lib/arg_parse.c",
    "src/lib/config.c",
    "src/lib/config_file.c",
    "src/lib/destruct.c",
    "src/lib/file.c",
    "src/lib/fonthand.c",
    "src/lib/helptext.c",
    "src/lib/keyboard.c",
    "src/lib/lds_play.c",
    "src/lib/loudness.c",
    "src/lib/mtrand.c",
    "src/lib/network.c",
    "src/lib/nortsong.c",
    "src/lib/opentyr.c",
    "src/lib/opl.c",
    "src/lib/palette.c",
    "src/lib/params.c",
    "src/lib/pcxmast.c",
    "src/lib/picload.c",
    "src/lib/sprite.c",
    "src/lib/vga256d.c",
    "src/lib/vga_palette.c",
    "src/lib/video.c",
    "src/lib/video_scale.c",
    "src/lib/video_scale_hqNx.c",
};

const c_flags: []const []const u8 = &.{
    "-std=gnu99",
    "-pedantic",
    "-Wall",
    "-Wextra",
    "-Wno-format-truncation",
    "-Wno-missing-field-initializers",
    "-O2",
    "-MMD",
    "-DNDEBUG",
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Setup sysroot with Emscripten so dependencies know where the system include files are
    const resolved_target = if (target.result.os.tag == .emscripten) blk: {
        const emsdk_sysroot = b.pathJoin(&.{ emSdkPath(b), "upstream", "emscripten", "cache", "sysroot" });
        b.sysroot = emsdk_sysroot;

        var target_query = target.query;
        for (target.result.cpu.arch.allFeaturesList(), 0..) |feature, index_usize| {
            const index = @as(std.Target.Cpu.Feature.Set.Index, @intCast(index_usize));
            if (feature.llvm_name) |llvm_name| {
                if (std.mem.eql(u8, llvm_name, "atomics") or std.mem.eql(u8, llvm_name, "bulk-memory")) {
                    target_query.cpu_features_add.addFeature(index);
                }
            }
        }

        const new_target = b.resolveTargetQuery(std.Target.Query{
            .cpu_arch = target_query.cpu_arch,
            .cpu_model = target_query.cpu_model,
            .cpu_features_add = target_query.cpu_features_add,
            .cpu_features_sub = target_query.cpu_features_sub,
            .os_tag = .emscripten,
            .os_version_min = target_query.os_version_min,
            .os_version_max = target_query.os_version_max,
            .glibc_version = target_query.glibc_version,
            .abi = target_query.abi,
            .dynamic_linker = target_query.dynamic_linker,
            .ofmt = target_query.ofmt,
        });

        break :blk new_target;
    } else blk: {
        break :blk target;
    };

    std.log.info("resolved target: arch {s}, cpu_model {s}, os {s}", .{
        resolved_target.result.cpu.arch.genericName(),
        resolved_target.result.cpu.model.name,
        @tagName(resolved_target.result.os.tag),
    });
    for (resolved_target.result.cpu.arch.allFeaturesList(), 0..) |feature, index_usize| {
        const index = @as(std.Target.Cpu.Feature.Set.Index, @intCast(index_usize));
        const is_enabled = resolved_target.result.cpu.features.isEnabled(index);
        if (feature.llvm_name) |llvm_name| {
            std.log.info("    feature {s} {s}", .{ llvm_name, if (is_enabled) "enabled" else "disabled" });
        } else {
            std.log.info("    feature (unnamed) {s}", .{if (is_enabled) "enabled" else "disabled"});
        }
    }

    const exe = if (resolved_target.result.os.tag == .emscripten) try compileEmscripten(
        b,
        "destruct",
        "src/main.zig",
        resolved_target,
        optimize,
    ) else b.addExecutable(.{
        .name = "destruct",
        .root_source_file = b.path("src/main.zig"),
        .target = resolved_target,
        .optimize = optimize,
    });
    exe.addCSourceFiles(.{ .files = &tyrian_srcs, .flags = c_flags });
    exe.root_module.addIncludePath(b.path("src/lib/"));

    const assets = b.dependency("assets", .{});
    exe.root_module.addImport("assets", assets.module("root"));
    exe.step.dependOn(&assets.artifact("assets").step); // force the "assets" module to build

    {
        const sdl_dep = b.dependency("sdl", .{
            .optimize = .ReleaseFast,
            .target = resolved_target,
            .c_flags = c_flags,
        });
        if (resolved_target.query.isNativeOs() and resolved_target.result.os.tag == .linux) {
            // The SDL package doesn't work for Linux yet, so we rely on system
            // packages for now.
            exe.linkSystemLibrary("SDL2");
            exe.linkLibC();
        } else {
            exe.linkLibrary(sdl_dep.artifact("SDL2"));
        }
        exe.root_module.addImport("sdl2", sdl_dep.module("sdl"));
        exe.root_module.addIncludePath(sdl_dep.path("include/"));
    }

    if (resolved_target.result.os.tag == .emscripten) {
        const link_step = try emLinkStep(b, .{
            .lib_main = exe,
            .target = resolved_target,
            .optimize = optimize,
        });

        // ...and a special run step to run the build result via emrun
        var run = emRunStep(b, .{ .name = "destruct" });
        run.step.dependOn(&link_step.step);

        const run_cmd = b.step("run", "Run the demo for web via emrun");
        run_cmd.dependOn(&run.step);
    } else {
        b.installArtifact(exe);

        const run = b.step("run", "Run the demo for desktop");
        const run_cmd = b.addRunArtifact(exe);
        run.dependOn(&run_cmd.step);
    }
}

// Creates the static library to build a project for Emscripten.
pub fn compileEmscripten(
    b: *std.Build,
    name: []const u8,
    root_source_file: []const u8,
    resolved_target: std.Build.ResolvedTarget,
    optimize: std.builtin.Mode,
) !*std.Build.Step.Compile {
    // The project is built as a library and linked later.
    const exe_lib = b.addStaticLibrary(.{
        .name = name,
        .root_source_file = b.path(root_source_file),
        .target = resolved_target,
        .optimize = optimize,
    });

    const emsdk_sysroot = b.pathJoin(&.{ emSdkPath(b), "upstream", "emscripten", "cache", "sysroot" });
    const include_path = b.pathJoin(&.{ emsdk_sysroot, "include" });
    exe_lib.addSystemIncludePath(.{ .cwd_relative = include_path });

    if (resolved_target.query.os_tag == .wasi) {
        const webhack_c =
            \\// Zig adds '__stack_chk_guard', '__stack_chk_fail', and 'errno',
            \\// which emscripten doesn't actually support.
            \\// Seems that zig ignores disabling stack checking,
            \\// and I honestly don't know why emscripten doesn't have errno.
            \\// TODO: when the updateTargetForWeb workaround gets removed, see if those are nessesary anymore
            \\#include <stdint.h>
            \\uintptr_t __stack_chk_guard;
            \\//I'm not certain if this means buffer overflows won't be detected,
            \\// However, zig is pretty safe from those, so don't worry about it too much.
            \\void __stack_chk_fail(void){}
            \\int errno;
        ;

        // There are some symbols that need to be defined in C.
        const webhack_c_file_step = b.addWriteFiles();
        const webhack_c_file = webhack_c_file_step.add("webhack.c", webhack_c);
        exe_lib.addCSourceFile(.{ .file = webhack_c_file, .flags = &[_][]u8{} });
        // Since it's creating a static library, the symbols raylib uses to webgl
        // and glfw don't need to be linked by emscripten yet.
        exe_lib.step.dependOn(&webhack_c_file_step.step);
    }

    return exe_lib;
}

// One-time setup of the Emscripten SDK (runs 'emsdk install + activate'). If the
// SDK had to be setup, a run step will be returned which should be added
// as dependency to the sokol library (since this needs the emsdk in place),
// if the emsdk was already setup, null will be returned.
// NOTE: ideally this would go into a separate emsdk-zig package
fn emSdkSetupStep(b: *std.Build) !?*std.Build.Step.Run {
    const emsdk_path = emSdkPath(b);
    const dot_emsc_path = b.pathJoin(&.{ emsdk_path, ".emscripten" });
    const dot_emsc_exists = !std.meta.isError(std.fs.accessAbsolute(dot_emsc_path, .{}));
    if (!dot_emsc_exists) {
        var cmd = std.ArrayList([]const u8).init(b.allocator);
        defer cmd.deinit();
        if (builtin.os.tag == .windows)
            try cmd.append(b.pathJoin(&.{ emsdk_path, "emsdk.bat" }))
        else {
            try cmd.append("bash"); // or try chmod
            try cmd.append(b.pathJoin(&.{ emsdk_path, "emsdk" }));
        }
        const emsdk_install = b.addSystemCommand(cmd.items);
        emsdk_install.addArgs(&.{ "install", "latest" });
        const emsdk_activate = b.addSystemCommand(cmd.items);
        emsdk_activate.addArgs(&.{ "activate", "latest" });
        emsdk_activate.step.dependOn(&emsdk_install.step);
        return emsdk_activate;
    } else {
        return null;
    }
}

// for wasm32-emscripten, need to run the Emscripten linker from the Emscripten SDK
pub const EmLinkOptions = struct {
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    lib_main: *Build.Step.Compile, // the actual Zig code must be compiled to a static link library
    release_use_closure: bool = true,
    release_use_lto: bool = true,
    use_emmalloc: bool = true,
    use_pthreads: bool = true,
    use_webgl2: bool = false,
    use_webgpu: bool = false,
    use_filesystem: bool = false,
    use_asyncify: bool = true,
    shell_file_path: ?[]const u8 = null,
    extra_args: []const []const u8 = &.{},
};

fn emLinkStep(b: *Build, options: EmLinkOptions) !*Build.Step.Run {
    const emcc_path = b.pathJoin(&.{ emSdkPath(b), "upstream", "emscripten", "emcc" });

    // create a separate output directory zig-out/web
    try std.fs.cwd().makePath(b.fmt("{s}/web", .{b.install_path}));

    var emcc_cmd = std.ArrayList([]const u8).init(b.allocator);
    defer emcc_cmd.deinit();

    try emcc_cmd.append(emcc_path);
    if (options.optimize == .Debug) {
        try emcc_cmd.append("-Og");
        try emcc_cmd.append("-sASSERTIONS=1");
        try emcc_cmd.append("-sSAFE_HEAP=1");
        try emcc_cmd.append("-sSTACK_OVERFLOW_CHECK=1");
        try emcc_cmd.append("-gsource-map"); // NOTE(jae): debug sourcemaps in browser, so you can see the stack of crashes
        try emcc_cmd.append("--emrun"); // NOTE(jae): This flag injects code into the generated Module object to enable capture of stdout, stderr and exit(), ie. outputs it in the terminal
    } else {
        try emcc_cmd.append("-sASSERTIONS=0");
        if (options.optimize == .ReleaseSmall) {
            try emcc_cmd.append("-Oz");
        } else {
            try emcc_cmd.append("-O3");
        }
        if (options.release_use_lto) {
            try emcc_cmd.append("-flto");
            try emcc_cmd.append("-Wl,-u,_emscripten_run_callback_on_thread");
        }
        if (options.release_use_closure) {
            try emcc_cmd.append("--closure 1");
        }
    }
    if (options.use_emmalloc) {
        try emcc_cmd.append("-sMALLOC='emmalloc'");
    }
    if (options.use_pthreads) {
        try emcc_cmd.append("-pthread");
        try emcc_cmd.append("-sUSE_PTHREADS=1");
        try emcc_cmd.append("-sPTHREAD_POOL_SIZE=navigator.hardwareConcurrency");
    }
    if (options.use_webgl2) {
        try emcc_cmd.append("-sUSE_WEBGL2=1");
    }
    if (options.use_webgpu) {
        try emcc_cmd.append("-sUSE_WEBGPU=1");
    }
    if (!options.use_filesystem) {
        try emcc_cmd.append("-sFILESYSTEM=0");
        try emcc_cmd.append("-sNO_FILESYSTEM=1");
    }
    if (options.shell_file_path) |shell_file_path| {
        try emcc_cmd.append(b.fmt("--shell-file={s}", .{shell_file_path}));
    }
    // NOTE(jae): 0224-02-22
    // Need to fix this linker issue
    // linker: Undefined symbol: eglGetProcAddress(). Please pass -sGL_ENABLE_GET_PROC_ADDRESS at link time to link in eglGetProcAddress().
    try emcc_cmd.append("-sGL_ENABLE_GET_PROC_ADDRESS=1");
    try emcc_cmd.append("-sINITIAL_MEMORY=64Mb");
    try emcc_cmd.append("-sSTACK_SIZE=16Mb");

    // NOTE(jae): 2024-02-24
    // Needed or zig crashes with "Aborted(Cannot use convertFrameToPC (needed by __builtin_return_address) without -sUSE_OFFSET_CONVERTER)"
    // for os_tag == .emscripten.
    // However currently then it crashes when trying to call "std.debug.captureStackTrace"
    try emcc_cmd.append("-sUSE_OFFSET_CONVERTER=1");
    try emcc_cmd.append("-sFULL_ES3=1");
    try emcc_cmd.append("-sUSE_GLFW=3");
    if (options.use_asyncify) {
        try emcc_cmd.append("-sASYNCIFY");
    }

    // try emcc_cmd.append("--embed-file");
    // try emcc_cmd.append("assets@/wasm_data");

    try emcc_cmd.append(b.fmt("-o{s}/web/{s}.html", .{ b.install_path, options.lib_main.name }));
    for (options.extra_args) |arg| {
        try emcc_cmd.append(arg);
    }

    const emcc = b.addSystemCommand(emcc_cmd.items);
    emcc.setName("emcc"); // hide emcc path

    // one-time setup of Emscripten SDK
    const maybe_emsdk_setup = try emSdkSetupStep(b);
    if (maybe_emsdk_setup) |emsdk_setup| {
        options.lib_main.step.dependOn(&emsdk_setup.step);
    }

    // get sysroot include
    const sysroot_include_path = if (b.sysroot) |sysroot| b.pathJoin(&.{ sysroot, "include" }) else @panic("unable to get sysroot path");

    // add the main lib, and then scan for library dependencies and add those too
    emcc.addArtifactArg(options.lib_main);
    var it = options.lib_main.root_module.iterateDependencies(options.lib_main, false);
    while (it.next()) |item| {
        if (maybe_emsdk_setup) |emsdk_setup| {
            item.compile.?.step.dependOn(&emsdk_setup.step);
        }
        if (sysroot_include_path.len > 0) {
            // add emscripten system includes to each module, this ensures that any C-modules you import
            // will "just work", assuming it'll run under Emscripten
            item.module.addSystemIncludePath(.{ .cwd_relative = sysroot_include_path });
        }
        for (item.module.link_objects.items) |link_object| {
            switch (link_object) {
                .other_step => |compile_step| {
                    switch (compile_step.kind) {
                        .lib => {
                            emcc.addArtifactArg(compile_step);
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }
    }
    b.getInstallStep().dependOn(&emcc.step);
    return emcc;
}

// build a run step which uses the emsdk emrun command to run a build target in the browser
pub const EmRunOptions = struct {
    name: []const u8,
};

fn emRunStep(b: *std.Build, options: EmRunOptions) *std.Build.Step.Run {
    const emrun_path = b.pathJoin(&.{ emSdkPath(b), "upstream", "emscripten", "emrun" });
    const web_path = b.pathJoin(&.{ ".", "zig-out", "web", options.name });
    // NOTE(jae): 2024-02-24
    // Default browser to chrome as it has the better WASM debugging tools / UX
    const emrun = b.addSystemCommand(&.{ emrun_path, "--serve_after_exit", "--serve_after_close", "--browser=chrome", b.fmt("{s}.html", .{web_path}) });
    return emrun;
}

fn emSdkPath(b: *std.Build) []const u8 {
    const emsdk = b.dependency("emsdk", .{});
    const emsdk_path = emsdk.path("").getPath(b);
    return emsdk_path;
}
