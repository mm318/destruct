const std = @import("std");
const SDL = @import("sdl2");
const target_os = @import("builtin").os;

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
    @cInclude("varz.h");
    @cInclude("video.h");
});

pub fn main() u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const exe_path = std.fs.selfExePathAlloc(allocator) catch @panic("oom");
    defer allocator.free(exe_path);
    const exe_dir = std.fs.selfExeDirPathAlloc(allocator) catch @panic("oom");
    defer allocator.free(exe_dir);

    const arg0 = std.fmt.allocPrintZ(allocator, "{s}", .{exe_path}) catch @panic("oom");
    defer allocator.free(arg0);
    const arg1 = std.fmt.allocPrintZ(allocator, "--data={s}", .{exe_dir}) catch @panic("oom");
    defer allocator.free(arg1);

    const args_ptr: [*c][*c]u8 = @constCast(@ptrCast(&.{ arg0.ptr, arg1.ptr }));

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

    // Note for this reorganization:
    // Tyrian 2000 requires help text to be loaded before the configuration,
    // because the default high score names are stored in help text

    c.JE_paramCheck(2, args_ptr);

    c.JE_loadHelpText();

    c.JE_loadConfiguration();

    c.init_video();
    c.init_keyboard();
    std.log.debug("assuming mouse detected", .{});  // SDL can't tell us if there isn't one

    c.JE_loadPals();
    c.JE_loadMainShapeTables("tyrian.shp");

    std.log.debug("initializing SDL audio...", .{});
    _ = c.init_audio();
    c.load_music();
    c.loadSndFile(false);   // xmas = false

    c.JE_destructGame();

    c.JE_tyrianHalt(0);

    return 0;
}
