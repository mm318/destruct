const std = @import("std");
const builtin = @import("builtin");

const SDL = @import("sdl2");

const c = @cImport({
    @cInclude("time.h");
    @cInclude("destruct.h");
    @cInclude("config.h");
    @cInclude("helptext.h");
    @cInclude("keyboard.h");
    @cInclude("loudness.h");
    @cInclude("mtrand.h");
    @cInclude("nortsong.h");
    @cInclude("palette.h");
    @cInclude("params.h");
    @cInclude("sprite.h");
    @cInclude("video.h");
});

const destruct = @import("destruct.zig");

pub fn logFn(
    comptime _: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const prefix2 = if (scope == .default) "" else "(" ++ @tagName(scope) ++ "): ";

    var buffer: [128]u8 = undefined;
    const c_string = std.fmt.bufPrintZ(&buffer, prefix2 ++ format ++ "\n", args) catch &buffer;
    _ = c.printf(c_string.ptr);
}

pub const std_options: std.Options = .{
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        else => .info,
    },

    // Overwrite default log handler
    .logFn = logFn,
};

pub fn main() u8 {
    c.mt_srand(@intCast(c.time(0)));

    std.log.info("Welcome to... >> {s} {s} <<\n", .{ c.opentyrian_str, c.opentyrian_version });

    std.log.info("Copyright (C) 2022 The OpenTyrian Development Team", .{});
    std.log.info("Copyright (C) 2022 Kaito Sinclaire\n", .{});

    std.log.info("This program comes with ABSOLUTELY NO WARRANTY.", .{});
    std.log.info("This is free software, and you are welcome to redistribute it", .{});
    std.log.info("under certain conditions.  See the file COPYING for details.\n", .{});

    if (SDL.SDL_Init(0) != 0) {
        std.log.err("Failed to initialize SDL: {s}", .{SDL.SDL_GetError()});
        return 0xFF;
    }
    defer c.SDL_Quit();

    // Note for this reorganization:
    // Tyrian 2000 requires help text to be loaded before the configuration,
    // because the default high score names are stored in help text

    c.JE_paramCheck(0, null);

    c.JE_loadHelpText(destruct.assets.texts.ptr, destruct.assets.texts.len);

    c.JE_loadConfiguration();
    defer {
        // TODO?
        // JE_drawANSI("exitmsg.bin");
        // JE_gotoXY(1,22);
        c.JE_saveConfiguration();
    }

    c.init_video("destruct");
    defer c.deinit_video();

    c.init_keyboard();
    std.log.debug("assuming mouse detected", .{}); // SDL can't tell us if there isn't one

    c.JE_loadPals(destruct.assets.palettes.ptr, destruct.assets.palettes.len);
    c.JE_loadMainShapeTables(destruct.assets.fonts.ptr, destruct.assets.fonts.len);
    defer c.free_main_shape_tables();

    std.log.debug("initializing SDL audio...", .{});
    _ = c.init_audio();
    defer c.deinit_audio();

    c.load_music(destruct.assets.music.ptr, destruct.assets.music.len); // leaks memory of song_offset
    c.loadSndFile(
        destruct.assets.sounds.ptr,
        destruct.assets.sounds.len,
        destruct.assets.voice_samples.ptr,
        destruct.assets.voice_samples.len,
    );
    defer {
        for (0..c.SOUND_COUNT) |i| {
            c.free(c.soundSamples[i]);
        }
    }

    destruct.JE_destructGame();

    return 0;
}
