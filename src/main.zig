const std = @import("std");
const SDL = @import("sdl2");
const target_os = @import("builtin").os;

const opentyr = @cImport({
    @cInclude("opentyr.h");
});

pub fn main() u8 {
    const argv = std.os.argv;
    const c_ptr: [*c][*c]u8 = @ptrCast(argv.ptr);
    return @intCast(opentyr.opentyrian_main(@intCast(argv.len), c_ptr));
}
