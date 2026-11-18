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

const c_flags = [_][]const u8{
    "-std=gnu99",
    "-pedantic",
    "-Wall",
    "-Wextra",
    "-Wno-format-truncation",
    "-Wno-missing-field-initializers",
    // Keep the HQNx scaler practical to compile even in Debug builds.
    "-O2",
    // Preserve the original C build behavior: the loader intentionally truncates
    // some bundled Tyrian 2000 strings to fit its text buffers.
    "-DNDEBUG",
};

pub fn build(b: *Build) !void {
    var target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const target_emscripten = target.result.os.tag == .emscripten;
    const emsdk = b.dependency("emsdk", .{});

    // Install the SDK explicitly before building for the web, as in sokol-zig.
    b.step("install-emsdk", "Install Emscripten SDK in zig-pkg").dependOn(emSdkInstallStep(b, emsdk));

    if (target_emscripten) {
        var query = target.query;
        query.cpu_features_add.addFeature(@backingInt(std.Target.wasm.Feature.atomics));
        query.cpu_features_add.addFeature(@backingInt(std.Target.wasm.Feature.bulk_memory));
        target = b.resolveTargetQuery(query);
    }

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addCSourceFiles(.{
        .files = &tyrian_srcs,
        // Match sokol-zig's Emscripten C compilation flags.
        .flags = if (target_emscripten) &(c_flags ++ .{"-fno-sanitize=undefined"}) else &c_flags,
    });
    mod.addIncludePath(b.path("src/lib"));

    const assets = b.dependency("assets", .{ .target = target, .optimize = .fast });
    mod.addImport("assets", assets.module("root"));

    const sdl = if (target_emscripten)
        b.dependency("sdl", .{
            .target = target,
            .optimize = .fast,
            .emscripten_include = emsdk.path("upstream/emscripten/cache/sysroot/include"),
        })
    else
        b.dependency("sdl", .{ .target = target, .optimize = .fast });
    mod.linkLibrary(sdl.artifact("SDL2"));
    mod.addIncludePath(sdl.artifact("SDL2").getEmittedIncludeTree().path(b, "SDL2"));
    mod.addImport("sdl2", sdl.module("sdl"));

    const bindings = b.addTranslateC(.{
        .root_source_file = b.path("src/lib/bindings.h"),
        .target = target,
        .optimize = optimize,
    });
    bindings.addIncludePath(b.path("src/lib"));
    bindings.addIncludePath(sdl.artifact("SDL2").getEmittedIncludeTree().path(b, "SDL2"));
    mod.addImport("c", bindings.createModule());

    if (target_emscripten) {
        const sysroot_include = emsdk.path("upstream/emscripten/cache/sysroot/include");
        // C imports and the bundled SDL library need the Emscripten headers.
        for (mod.getGraph().modules) |dependency| {
            dependency.addSystemIncludePath(sysroot_include);
        }
        bindings.addSystemIncludePath(sysroot_include);

        const lib = b.addLibrary(.{ .name = "destruct", .root_module = mod });
        const install = emLinkStep(b, emsdk, lib, optimize);
        b.getInstallStep().dependOn(&install.step);
        b.installFile("web_assets/coi-serviceworker.js", "web/coi-serviceworker.js");

        const run = b.addRunFile(emTool(b, emsdk, "emrun"));
        run.addFileArg(.{ .relative = .{ .base = .install_prefix, .sub_path = "web/index.html" } });
        run.step.dependOn(b.getInstallStep());
        b.step("run", "Run Destruct in a browser via emrun").dependOn(&run.step);
    } else {
        const exe = b.addExecutable(.{ .name = "destruct", .root_module = mod });
        b.installArtifact(exe);
        const run = b.addRunArtifact(exe);
        b.step("run", "Run Destruct on the desktop").dependOn(&run.step);
    }
}

// Emscripten links the Zig static library and its C library dependencies.
fn emLinkStep(b: *Build, emsdk: *Build.Dependency, lib: *Build.Step.Compile, optimize: std.builtin.Optimize) *Build.Step.InstallDir {
    const emcc = b.addRunFile(emTool(b, emsdk, "emcc"));
    emcc.setName("emcc");
    if (optimize == .debug) {
        emcc.addArgs(&.{ "-g", "-Og", "-sSAFE_HEAP=1", "-sSTACK_OVERFLOW_CHECK=1" });
        emcc.addArg("-gsource-map");
        emcc.addArg("--emrun");
    } else {
        emcc.addArg("-sASSERTIONS=0");
        emcc.addArg(if (optimize == .small) "-Oz" else "-O3");
        emcc.addArgs(&.{ "-flto", "--closure", "1" });
    }
    emcc.addArgs(&.{
        "-sMALLOC=emmalloc",
        "-pthread",
        "-sPTHREAD_POOL_SIZE=navigator.hardwareConcurrency",
        // Zig's Debug runtime references filesystem and socket support.
        "-sFILESYSTEM=1",
        "-sGL_ENABLE_GET_PROC_ADDRESS=1",
        "-sINITIAL_MEMORY=64MB",
        "-sSTACK_SIZE=16MB",
        "-sFULL_ES3=1",
        "-sASYNCIFY=1",
    });
    emcc.addPrefixedFileArg("--shell-file=", b.path("web_assets/shell_minimal.html"));
    emcc.addArtifactArg(lib);
    for (lib.getCompileDependencies(false)) |dependency| {
        if (dependency != lib and dependency.kind == .lib) emcc.addArtifactArg(dependency);
    }
    emcc.addArg("-o");
    const output = emcc.addOutputFileArg("index.html");
    return b.addInstallDirectory(.{
        .source_dir = output.dirname(),
        .install_dir = .prefix,
        .install_subdir = "web",
    });
}

fn emTool(b: *Build, emsdk: *Build.Dependency, tool: []const u8) Build.LazyPath {
    const filename = if (builtin.os.tag == .windows) b.fmt("{s}.exe", .{tool}) else tool;
    return emsdk.path(b.pathJoin(&.{ "upstream", "emscripten", filename }));
}

fn createEmsdkStep(b: *Build, emsdk: *Build.Dependency) *Build.Step.Run {
    if (builtin.os.tag == .windows) {
        return b.addRunFile(emsdk.path("emsdk.bat"));
    } else {
        const run = b.addSystemCommand(&.{"bash"});
        run.addFileArg(emsdk.path("emsdk"));
        return run;
    }
}

fn emSdkInstallStep(b: *Build, emsdk: *Build.Dependency) *Build.Step {
    const install = createEmsdkStep(b, emsdk);
    install.addArgs(&.{ "install", "7.0.0" });
    const activate = createEmsdkStep(b, emsdk);
    activate.addArgs(&.{ "activate", "7.0.0" });
    activate.step.dependOn(&install.step);
    return &activate.step;
}
