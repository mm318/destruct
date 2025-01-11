const std = @import("std");
const sdl = @import("SDLzig");

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
    "-O2",
    "-MMD",
    "-DNDEBUG",
};

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Determine compilation target
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // const assets_cmd = ExtractAssetsStep.create(b, b.path("assets/tyrian2000.zip"), b.path("assets/"));
    const assets = b.dependency("assets", .{});

    // Create a new instance of the SDL2 Sdk
    // Specifiy dependency name explicitly if necessary (use sdl by default)
    const sdk = sdl.init(b, .{ .dep_name = "SDLzig" });

    // Create executable for our example
    const exe = b.addExecutable(.{
        .name = "destruct",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.addCSourceFiles(.{ .files = &tyrian_srcs, .flags = &c_flags });
    exe.root_module.addImport("assets", assets.module("root"));
    exe.root_module.addImport("sdl2", sdk.getNativeModule()); // Add "sdl2" package that exposes the SDL2 api (like SDL_Init or SDL_CreateWindow)
    exe.root_module.addIncludePath(b.path("src/lib/"));
    sdk.link(exe, .dynamic, sdl.Library.SDL2); // link SDL2 as a shared library
    exe.step.dependOn(&assets.artifact("assets").step); // force the "assets" module to build

    // Install the executable into the prefix when invoking "zig build"
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
