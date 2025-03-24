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

    const target_emscripten = (target.result.os.tag == .emscripten);
    const emsdk_dep = b.dependency("emsdk", .{});

    const exe = if (target_emscripten) try compileEmscripten(
        b,
        emsdk_dep,
        "destruct",
        "src/main.zig",
        target,
        optimize,
    ) else b.addExecutable(.{
        .name = "destruct",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.addCSourceFiles(.{ .files = &tyrian_srcs, .flags = c_flags });
    exe.addIncludePath(b.path("src/lib/"));

    const resolved_target = exe.root_module.resolved_target.?;

    const assets = b.dependency("assets", .{
        .target = resolved_target,
        .optimize = .ReleaseFast,
    });
    exe.root_module.addImport("assets", assets.module("root"));
    exe.step.dependOn(&assets.artifact("assets").step); // force the "assets" module to build

    {
        const sdl_dep = b.dependency("sdl", .{
            .target = resolved_target,
            .optimize = .ReleaseFast,
            // .c_flags = c_flags,
        });
        exe.linkLibrary(sdl_dep.artifact("SDL2"));
        exe.addIncludePath(sdl_dep.artifact("SDL2").getEmittedIncludeTree().path(b, "SDL2/"));
        exe.root_module.addImport("sdl2", sdl_dep.module("sdl"));
    }

    if (target_emscripten) {
        const link_step = try emLinkStep(b, emsdk_dep, .{
            .target = resolved_target,
            .optimize = optimize,
            .lib_main = exe,
            .shell_file_path = b.path("web_assets/shell_minimal.html"),
        });

        // ...and a special run step to run the build result via emrun
        var run = emRunStep(b, .{ .name = "index", .emsdk = emsdk_dep });
        run.step.dependOn(&link_step.step);

        const run_cmd = b.step("run", "Run the demo for web via emrun");
        run_cmd.dependOn(&run.step);
    } else {
        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());

        const run = b.step("run", "Run the demo for desktop");
        run.dependOn(&run_cmd.step);
    }
}

// Creates the static library to build a project for Emscripten.
fn compileEmscripten(
    b: *std.Build,
    emsdk: *std.Build.Dependency,
    name: []const u8,
    root_source_file: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Mode,
) !*std.Build.Step.Compile {
    // Setup sysroot with Emscripten so dependencies know where the system include files are
    const emsdk_sysroot = emSdkLazyPath(b, emsdk, &.{ "upstream", "emscripten", "cache", "sysroot" });
    b.sysroot = emsdk_sysroot.getPath(b);

    var target_query = target.query;
    for (target.result.cpu.arch.allFeaturesList(), 0..) |feature, index_usize| {
        const index = @as(std.Target.Cpu.Feature.Set.Index, @intCast(index_usize));
        if (feature.llvm_name) |llvm_name| {
            if (std.mem.eql(u8, llvm_name, "atomics") or std.mem.eql(u8, llvm_name, "bulk-memory")) {
                target_query.cpu_features_add.addFeature(index);
            }
        }
    }

    const resolved_target = b.resolveTargetQuery(std.Target.Query{
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

    // The project is built as a library and linked later.
    const exe_lib = b.addLibrary(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(root_source_file),
            .target = resolved_target,
            .optimize = optimize,
        }),
    });

    return exe_lib;
}

//== EMSCRIPTEN INTEGRATION ============================================================================================

fn emAddIncludes(b: *Build, emsdk: *std.Build.Dependency, main: *std.Build.Step.Compile) void {
    // one-time setup of Emscripten SDK
    const maybe_emsdk_setup = try emSdkSetupStep(b, emsdk);
    if (maybe_emsdk_setup) |emsdk_setup| {
        main.step.dependOn(&emsdk_setup.step);
    }

    // get sysroot include
    const sysroot_include_path = if (b.sysroot) |sysroot|
        b.pathJoin(&.{ sysroot, "include" })
    else
        @panic("unable to get sysroot path");

    // set the necessary include path for zig modules that lib_main imports (this looks hacky)
    const dependencies = main.root_module.getGraph();
    for (dependencies.modules) |dependency| {
        if (sysroot_include_path.len > 0) {
            // add emscripten system includes to each module, this ensures that any C-modules you import
            // will "just work", assuming it'll run under Emscripten
            dependency.addSystemIncludePath(.{ .cwd_relative = sysroot_include_path });
        }
    }

    // set the necessary include path for c/c++ libraries that lib_main depends on
    for (main.getCompileDependencies(false)) |item| {
        if (maybe_emsdk_setup) |emsdk_setup| {
            item.step.dependOn(&emsdk_setup.step);
        }
        if (sysroot_include_path.len > 0) {
            // add emscripten system includes to each module, this ensures that any C-modules you import
            // will "just work", assuming it'll run under Emscripten
            item.addSystemIncludePath(.{ .cwd_relative = sysroot_include_path });
        }
    }
}

// for wasm32-emscripten, need to run the Emscripten linker from the Emscripten SDK
// NOTE: ideally this would go into a separate emsdk-zig package
const EmLinkOptions = struct {
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
    shell_file_path: ?std.Build.LazyPath,
};
fn emLinkStep(b: *Build, emsdk: *std.Build.Dependency, options: EmLinkOptions) !*Build.Step.Run {
    const emcc_path = emSdkLazyPath(b, emsdk, &.{ "upstream", "emscripten", "emcc" }).getPath(b);
    const emcc = b.addSystemCommand(&.{emcc_path});
    emcc.setName("emcc"); // hide emcc path

    if (options.optimize == .Debug) {
        emcc.addArgs(&.{ "-Og", "-sASSERTIONS=1", "-sSAFE_HEAP=1", "-sSTACK_OVERFLOW_CHECK=1" });
        emcc.addArg("-gsource-map"); // NOTE(jae): debug sourcemaps in browser, so you can see the stack of crashes
        emcc.addArg("--emrun"); // NOTE(jae): This flag injects code into the generated Module object to enable capture of stdout, stderr and exit(), ie. outputs it in the terminal
    } else {
        emcc.addArg("-sASSERTIONS=0");
        if (options.optimize == .ReleaseSmall) {
            emcc.addArg("-Oz");
        } else {
            emcc.addArg("-O3");
        }
        if (options.release_use_lto) {
            emcc.addArgs(&.{ "-flto", "-Wl,-u,_emscripten_run_callback_on_thread" });
        }
        if (options.release_use_closure) {
            emcc.addArgs(&.{ "--closure", "1" });
        }
    }
    if (options.use_emmalloc) {
        emcc.addArg("-sMALLOC='emmalloc'");
    }
    if (options.use_pthreads) {
        emcc.addArgs(&.{ "-pthread", "-sUSE_PTHREADS=1", "-sPTHREAD_POOL_SIZE=navigator.hardwareConcurrency" });
    }
    if (options.use_webgl2) {
        emcc.addArg("-sUSE_WEBGL2=1");
    }
    if (options.use_webgpu) {
        emcc.addArg("-sUSE_WEBGPU=1");
    }
    if (!options.use_filesystem) {
        emcc.addArgs(&.{ "-sFILESYSTEM=0", "-sNO_FILESYSTEM=1" });
    }
    if (options.shell_file_path) |shell_file_path| {
        emcc.addPrefixedFileArg("--shell-file=", shell_file_path);
    }

    // NOTE(jae): 0224-02-22
    // Need to fix this linker issue
    // linker: Undefined symbol: eglGetProcAddress(). Please pass -sGL_ENABLE_GET_PROC_ADDRESS at link time to link in eglGetProcAddress().
    emcc.addArg("-sGL_ENABLE_GET_PROC_ADDRESS=1");
    emcc.addArg("-sINITIAL_MEMORY=64Mb");
    emcc.addArg("-sSTACK_SIZE=16Mb");

    // NOTE(jae): 2024-02-24
    // Needed or zig crashes with "Aborted(Cannot use convertFrameToPC (needed by __builtin_return_address) without -sUSE_OFFSET_CONVERTER)"
    // for os_tag == .emscripten.
    // However currently then it crashes when trying to call "std.debug.captureStackTrace"
    emcc.addArg("-sUSE_OFFSET_CONVERTER=1");
    emcc.addArg("-sFULL_ES3=1");
    emcc.addArg("-sUSE_GLFW=3");

    if (options.use_asyncify) {
        emcc.addArg("-sASYNCIFY");
    }

    // add the main lib, and then scan for library dependencies and add those too
    emcc.addArtifactArg(options.lib_main);
    for (options.lib_main.getCompileDependencies(false)) |item| {
        if (item.kind == .lib) {
            emcc.addArtifactArg(item);
        }
    }
    emcc.addArg("-o");
    const out_file = emcc.addOutputFileArg(b.fmt("{s}.html", .{options.lib_main.name}));

    emAddIncludes(b, emsdk, options.lib_main);

    // the emcc linker creates 3 output files (.html, .wasm and .js)
    const install_wasm = b.addInstallDirectory(.{
        .source_dir = out_file.dirname(),
        .install_dir = .prefix,
        .install_subdir = "web",
    });
    install_wasm.step.dependOn(&emcc.step);

    const install_coi = b.addInstallFile(b.path("web_assets/coi-serviceworker.js"), "web/coi-serviceworker.js");

    const install_index = b.addSystemCommand(&.{
        "mv",
        b.fmt("{s}/{s}.html", .{ b.getInstallPath(.prefix, "web"), options.lib_main.name }),
        b.fmt("{s}/index.html", .{b.getInstallPath(.prefix, "web")}),
    });
    install_index.step.dependOn(&install_wasm.step);
    install_index.step.dependOn(&install_coi.step);
    b.getInstallStep().dependOn(&install_index.step);

    return install_index;
}

// build a run step which uses the emsdk emrun command to run a build target in the browser
// NOTE: ideally this would go into a separate emsdk-zig package
const EmRunOptions = struct {
    name: []const u8,
    emsdk: *Build.Dependency,
};
fn emRunStep(b: *Build, options: EmRunOptions) *Build.Step.Run {
    const emrun_path = b.findProgram(&.{"emrun"}, &.{}) catch emSdkLazyPath(b, options.emsdk, &.{ "upstream", "emscripten", "emrun" }).getPath(b);
    const emrun = b.addSystemCommand(&.{ emrun_path, b.fmt("{s}/web/{s}.html", .{ b.install_path, options.name }) });
    return emrun;
}

// helper function to build a LazyPath from the emsdk root and provided path components
fn emSdkLazyPath(b: *Build, emsdk: *Build.Dependency, subPaths: []const []const u8) Build.LazyPath {
    return emsdk.path(b.pathJoin(subPaths));
}

fn createEmsdkStep(b: *Build, emsdk: *Build.Dependency) *Build.Step.Run {
    if (builtin.os.tag == .windows) {
        return b.addSystemCommand(&.{emSdkLazyPath(b, emsdk, &.{"emsdk.bat"}).getPath(b)});
    } else {
        const step = b.addSystemCommand(&.{"bash"});
        step.addArg(emSdkLazyPath(b, emsdk, &.{"emsdk"}).getPath(b));
        return step;
    }
}

// One-time setup of the Emscripten SDK (runs 'emsdk install + activate'). If the
// SDK had to be setup, a run step will be returned which should be added
// as dependency to the sokol library (since this needs the emsdk in place),
// if the emsdk was already setup, null will be returned.
// NOTE: ideally this would go into a separate emsdk-zig package
// NOTE 2: the file exists check is a bit hacky, it would be cleaner
// to build an on-the-fly helper tool which takes care of the SDK
// setup and just does nothing if it already happened
// NOTE 3: this code works just fine when the SDK version is updated in build.zig.zon
// since this will be cloned into a new zig cache directory which doesn't have
// an .emscripten file yet until the one-time setup.
fn emSdkSetupStep(b: *Build, emsdk: *Build.Dependency) !?*Build.Step.Run {
    const dot_emsc_path = emSdkLazyPath(b, emsdk, &.{".emscripten"}).getPath(b);
    const dot_emsc_exists = !std.meta.isError(std.fs.accessAbsolute(dot_emsc_path, .{}));
    if (!dot_emsc_exists) {
        const emsdk_install = createEmsdkStep(b, emsdk);
        emsdk_install.addArgs(&.{ "install", "latest" });
        const emsdk_activate = createEmsdkStep(b, emsdk);
        emsdk_activate.addArgs(&.{ "activate", "latest" });
        emsdk_activate.step.dependOn(&emsdk_install.step);
        return emsdk_activate;
    } else {
        return null;
    }
}

//== END EMSCRIPTEN INTEGRATION ========================================================================================
