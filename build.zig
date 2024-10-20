const std = @import("std");
const sdl = @import("SDLzig");

const tyrian_srcs = [_][]const u8{
    "src/lib/animlib.c",
    "src/lib/arg_parse.c",
    "src/lib/backgrnd.c",
    "src/lib/config.c",
    "src/lib/config_file.c",
    "src/lib/destruct.c",
    "src/lib/editship.c",
    "src/lib/episodes.c",
    "src/lib/file.c",
    "src/lib/font.c",
    "src/lib/fonthand.c",
    "src/lib/game_menu.c",
    "src/lib/helptext.c",
    "src/lib/joystick.c",
    "src/lib/jukebox.c",
    "src/lib/keyboard.c",
    "src/lib/lds_play.c",
    "src/lib/loudness.c",
    "src/lib/lvllib.c",
    "src/lib/lvlmast.c",
    "src/lib/mainint.c",
    "src/lib/menus.c",
    "src/lib/mouse.c",
    "src/lib/mtrand.c",
    "src/lib/musmast.c",
    "src/lib/network.c",
    "src/lib/nortsong.c",
    "src/lib/nortvars.c",
    "src/lib/opentyr.c",
    "src/lib/opl.c",
    "src/lib/palette.c",
    "src/lib/params.c",
    "src/lib/pcxload.c",
    "src/lib/pcxmast.c",
    "src/lib/picload.c",
    "src/lib/player.c",
    "src/lib/shots.c",
    "src/lib/sizebuf.c",
    "src/lib/sndmast.c",
    "src/lib/sprite.c",
    "src/lib/starlib.c",
    "src/lib/tyrian2.c",
    "src/lib/varz.c",
    "src/lib/vga256d.c",
    "src/lib/vga_palette.c",
    "src/lib/video.c",
    "src/lib/video_scale.c",
    "src/lib/video_scale_hqNx.c",
    "src/lib/xmas.c",
};

const c_flags = [_][]const u8{
    "-std=iso9899:1999",
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

    // Add "sdl2" package that exposes the SDL2 api (like SDL_Init or SDL_CreateWindow)
    exe.root_module.addImport("sdl2", sdk.getNativeModule());
    exe.root_module.addIncludePath(b.path("src/lib/"));

    sdk.link(exe, .dynamic, sdl.Library.SDL2); // link SDL2 as a shared library

    // Install the executable into the prefix when invoking "zig build"
    b.installArtifact(exe);
}
