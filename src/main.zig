const std = @import("std");
const SDL = @import("sdl2");
const target_os = @import("builtin").os;

const opentyr = @cImport({
    @cInclude("opentyr.h");
});

pub fn main() u8 {
    var buffer: [1024]u8 = undefined;
    const path = std.fs.selfExePath(&buffer) catch return 255;
    std.log.info("exe: {s}", .{path});
    const cwd = std.fs.cwd().realpath(".", &buffer) catch return 255;
    std.log.info("cwd: {s}", .{cwd});

    const argv = std.os.argv;
    const c_ptr: [*c][*c]u8 = @ptrCast(argv.ptr);
    return @intCast(opentyr.opentyrian_main(@intCast(argv.len), c_ptr));
}
